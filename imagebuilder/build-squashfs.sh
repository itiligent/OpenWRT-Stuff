#!/bin/bash
#######################################################################################################################
# Enlarge default SquashFS partitions for OpenWRT x86 builds and convert new raw images to vmdk
# FOR x86 BUILDS TO HDD/VM/MMC ONLY! (Not for use with router flash memory - you've been warned!!)
# David Harrop
# April 2023
#######################################################################################################################

clear

# Prepare text output colours
LYELLOW='\033[0;93m'
LRED='\033[0;91m'
NC='\033[0m' #No Colour

if ! [[ $(id -u) = 0 ]]; then
    echo
    echo -e "${LRED}Please run this script as sudo or root${NC}" 1>&2
    echo
    exit 1
fi

#######################################################################################################################
# User input variables
#######################################################################################################################
# Select the OWRT version to build
    BUILDER="https://downloads.openwrt.org/releases/23.05.0/targets/x86/64/openwrt-imagebuilder-23.05.0-x86-64.Linux-x86_64.tar.xz"
    #BUILDER="https://downloads.openwrt.org/snapshots/targets/x86/64/openwrt-imagebuilder-x86-64.Linux-x86_64.tar.xz" # Current snapshot

# Select the desired SquashFS partition sizes in MB
    MODIFY_SQUASH=""   # true/false
    KERNEL_PARTSIZE="" # variable set in MB
    ROOTFS_PARTSIZE="" # variable set in MB (values over 8192 may give memory exhaustion errors)
    IMAGE_TAG=""       # This ID tag will be added to the completed image filename
    CREATE_VMDK=""     # Create VMware images of the final build true/false

# Provide your specific recipe of custom OWRT packages to add to the base installation here. (Below is an example)
CUSTOM_PACKAGES="blockd block-mount kmod-fs-ext4 kmod-usb2 kmod-usb3 kmod-usb-storage kmod-usb-core usbutils \
    -dnsmasq dnsmasq-full luci luci-app-ddns luci-app-mwan3 mwan3 luci-app-openvpn openvpn-openssl \
    luci-app-samba4 luci-app-sqm sqm-scripts sqm-scripts-extra luci-app-attendedsysupgrade auc \
    curl nano socat tcpdump python3-light python3-netifaces wsdd2 igmpproxy iptables-mod-ipopt \
    usbmuxd libimobiledevice kmod-usb-net kmod-usb-net-asix-ax88179 kmod-mt7921u kmod-usb-net-rndis kmod-usb-net-ipheth"
    #luci-app-advanced-reboot

#######################################################################################################################
# Setup the image builder working environment 
#######################################################################################################################
    SOURCE_FILE="${BUILDER##*/}" # Separate the tar.xz file name from the source download link
    SOURCE_DIR="${SOURCE_FILE%%.tar.xz}" # Get the uncompressed tar.xz directory name to set as the build source dir
    BUILD_ROOT="$(pwd)/build_output"
    OUTPUT="${BUILD_ROOT}/firmware_images"
    VMDK="${BUILD_ROOT}/vmdk"
    INJECT_FILES="$(pwd)/inject_files"
    BUILD_LOG="${BUILD_ROOT}/build.log"

#######################################################################################################################
# Script user prompts 
#######################################################################################################################
echo -e ${LYELLOW}
echo "Image Builder activity will be logged to ${BUILD_LOG}"
echo

echo -e "SquashFS:${NC}"
if [[ -z ${MODIFY_SQUASH} ]]; then
    echo -e -n "    Modify SquashFS partitions? [ n = no change (default) | y = resize ] [N/y]: "
    read PROMPT
    if [[ ${PROMPT} =~ ^[Yy]$ ]]; then
        MODIFY_SQUASH=true
    else
        MODIFY_SQUASH=false
    fi
fi

# Set custom partition sizes
if [[ ${MODIFY_SQUASH} = true ]]; then
    [[ -z ${KERNEL_PARTSIZE} ]] &&
        read -p "    Enter SquashFS KERNEL partition size in MB [Hit enter for 32MB, or enter custom size]: " KERNEL_PARTSIZE
    [[ -z ${ROOTFS_PARTSIZE} ]] &&
        read -p "    Enter SquashFS ROOT partition size in MB [Hit enter for 2048MB, or enter custom size]: " ROOTFS_PARTSIZE
fi

# If no kernel partition size value given, create a default value
if [[ -z ${KERNEL_PARTSIZE} ]]; then
    KERNEL_PARTSIZE=32
   fi
   # If no root partition size value given, create a default value
   if [[ -z ${ROOTFS_PARTSIZE} ]]; then
    ROOTFS_PARTSIZE=2048
fi

# Create a custom image name tag
if [[ -z ${IMAGE_TAG} ]]; then
echo
    echo -e "${LYELLOW}Custom image filename identifier:${NC}"
    while true; do
        read -p "    Enter text to include in the image filename [Enter for \"custom\"]: " IMAGE_TAG
        [[ "${IMAGE_TAG}" = "" ]] || [[ "${IMAGE_TAG}" != "" ]] && break
    done
fi
# If no image name tag is given, create a default value
if [[ -z ${IMAGE_TAG} ]]; then
    IMAGE_TAG="custom"
fi

# Convert images for use in virtual environment?"
if [[ -z ${CREATE_VMDK} ]]; then
echo
    echo -e "${LYELLOW}Virtual machine image conversion:${NC}"
    echo -e -n "Convert OpenWRT images to VMware VMDK images? [default = y] [Y/n]: "
    read PROMPT
    if [[ ${PROMPT} =~ ^[Nn]$ ]]; then
        CREATE_VMDK=false
    else
        CREATE_VMDK=true
    fi
fi

#######################################################################################################################
# Begin script build actions 
#######################################################################################################################
# Clear out any previous builds
    rm -rf "${BUILD_ROOT}"
    rm -rf "${SOURCE_DIR}"

# Create the destination directories
    mkdir -p "${BUILD_ROOT}"
    mkdir -p "${OUTPUT}"
    mkdir -p "${VMDK}"
    mkdir -p "${INJECT_FILES}"
    chown -R $SUDO_USER $INJECT_FILES

# Option to pre-configure images with injected config files
    echo -e ${LYELLOW}
    read -p $"Copy optional config files to ${INJECT_FILES} now for inclusion into the new image. Enter to begin build..."
    echo -e ${NC}

# Install OWRT build system dependencies for recent Ubuntu/Debian.
# See here for other distro dependencies: https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem
    sudo apt-get update  2>&1 | tee -a ${BUILD_LOG}
    sudo apt-get install -y build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
    gettext git libncurses-dev libssl-dev python3-distutils rsync unzip zlib1g-dev file wget qemu-utils 2>&1 | tee -a ${BUILD_LOG}

# Download the image builder source if we haven't already
if [ ! -f "${BUILDER##*/}" ]; then
    wget -q --show-progress "$BUILDER"
    tar xJvf "${BUILDER##*/}" --checkpoint=.100 2>&1 | tee -a ${BUILD_LOG}
fi

# Uncompress if the source tar.xz exists but the uncompressed source directory was cleared for a fresh build.
if [ -n "${SOURCE_DIR}" ]; then
    tar xJvf "${BUILDER##*/}" --checkpoint=.100 2>&1 | tee -a ${BUILD_LOG}
fi

# Modify the SquashFS source configuration
if [[ ${MODIFY_SQUASH} = true ]]; then
    # Patch the source partition size config settings
    sed -i "s/CONFIG_TARGET_KERNEL_PARTSIZE=.*/CONFIG_TARGET_KERNEL_PARTSIZE=$KERNEL_PARTSIZE/g" "$PWD/$SOURCE_DIR/.config"
    sed -i "s/CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE/g" "$PWD/$SOURCE_DIR/.config"
    # Patch for source partition size config settings giving errors https://forum.openwrt.org/t/22-03-3-image-builder-issues/154168
    sed -i '/\$(CONFIG_TARGET_ROOTFS_PARTSIZE) \$(IMAGE_ROOTFS)/,/256/ s/256/'"$ROOTFS_PARTSIZE"'/' "$PWD/$SOURCE_DIR/target/linux/x86/image/Makefile"
fi

# Start a clean image build with the selected packages
    cd $(pwd)/"${SOURCE_DIR}"/
    make clean 2>&1 | tee -a ${BUILD_LOG}
    make image PROFILE="generic" PACKAGES="${CUSTOM_PACKAGES}" EXTRA_IMAGE_NAME="${IMAGE_TAG}" FILES="${INJECT_FILES}" BIN_DIR="${OUTPUT}" 2>&1 | tee -a ${BUILD_LOG}


if [[ ${CREATE_VMDK} = true ]]; then
    # Copy the new images to a separate directory for conversion to vmdk
    cp $OUTPUT/*.gz $VMDK
    # Create a list of new images to unzip
    for LIST in $VMDK/*img.gz
    do
    echo $LIST
    gunzip $LIST
    done
    # Convert the unzipped images to vmdk
    for LIST in $VMDK/*.img
    do
    echo $LIST
    qemu-img convert -f raw -O vmdk $LIST $LIST.vmdk 2>&1 | tee -a ${BUILD_LOG}
    done
    # Clean up
    rm $VMDK/*.img
fi

# Remove sudo access limits from output
    cd ..
    chown -R $SUDO_USER $SOURCE_FILE
    chown -R $SUDO_USER $SOURCE_DIR
    chown -R $SUDO_USER $BUILD_ROOT

