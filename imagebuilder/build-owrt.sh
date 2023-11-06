#!/bin/bash
#######################################################################################################################
# Build custom OpenWRT images
# DO NOT RESIZE ROUTER FLASH PARTITONS, x86 only!!)
# Use partition resize and conversion to vmdk virtual with x86 builds only!!!
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
    echo -e "${LRED}Please run this script as sudo.${NC}" 1>&2
    echo
    exit 1
fi

#######################################################################################################################
# User input variables
#######################################################################################################################

# Mandatory static user input
    SNAPSHOT="false"         # true/false
    VERSION="23.05.0"        # If snapshot = true version value is ignored
    TARGET="x86"             # x86, mvebu  etc
    ARCH="64"                # 64, cortexa9 etc
    IMAGE_PROFILE="generic"  # x86 = generic, linksys_wrt1900acs etc. For profile options run $SOURCE_DIR/make info

# Provide your specific recipe of custom OWRT packages to add to the base installation here. (Below is just an example)
    CUSTOM_PACKAGES="blockd block-mount kmod-fs-ext4 kmod-usb2 kmod-usb3 kmod-usb-storage kmod-usb-core usbutils \
    -dnsmasq dnsmasq-full luci luci-app-ddns luci-app-mwan3 mwan3 luci-app-openvpn openvpn-openssl \
    luci-app-samba4 luci-app-sqm sqm-scripts sqm-scripts-extra luci-app-attendedsysupgrade auc \
    curl nano socat tcpdump python3-light python3-netifaces wsdd2 igmpproxy iptables-mod-ipopt \
    usbmuxd libimobiledevice kmod-usb-net kmod-usb-net-asix-ax88179 kmod-mt7921u kmod-usb-net-rndis kmod-usb-net-ipheth"

#######################################################################################################################
# Setup the image builder working environment
#######################################################################################################################

# Select the OWRT version to build.
if [[ ${SNAPSHOT} = false ]]; then
    BUILDER="https://downloads.openwrt.org/releases/${VERSION}/targets/${TARGET}/${ARCH}/openwrt-imagebuilder-${VERSION}-${TARGET}-${ARCH}.Linux-x86_64.tar.xz"
else
    BUILDER="https://downloads.openwrt.org/snapshots/targets/${TARGET}/${ARCH}/openwrt-imagebuilder-${TARGET}-${ARCH}.Linux-x86_64.tar.xz" # Current snapshot
fi

# Configure the build path and logging
    SOURCE_FILE="${BUILDER##*/}" # Separate the tar.xz file name from the source download link
    SOURCE_DIR="${SOURCE_FILE%%.tar.xz}" # Get the uncompressed tar.xz directory name and set as the source dir
    BUILD_ROOT="$(pwd)/owrt_build_output"
    OUTPUT="${BUILD_ROOT}/firmware_images"
    VMDK="${BUILD_ROOT}/vmdk"
    INJECT_FILES="$(pwd)/owrt_inject_files"
    BUILD_LOG="${BUILD_ROOT}/build.log"

#######################################################################################################################
# Script user prompts
#######################################################################################################################

# Initialise prompt variables and set script defaults. If values are added here user prompts will be skipped
    MOD_PARTSIZE=""          # true/false
    KERNEL_PARTSIZE=""       # variable set in MB
    ROOT_PARTSIZE=""         # variable set in MB (values over 8192 may give memory exhaustion errors)
    KERNEL_RESIZE_DEF="32" # Default increased partition size in MB
    ROOT_RESIZE_DEF="2048" # Default increased partition size in MB
    IMAGE_TAG=""             # This ID tag will be added to the completed image filename
    CREATE_VMDK=""           # Create VMware images of the final build true/false

echo -e ${LYELLOW}
echo "Image Builder activity will be logged to ${BUILD_LOG}"
echo

if [[ -z ${MOD_PARTSIZE} ]] && [[ ${IMAGE_PROFILE} = "generic" ]]; then
echo -e "Modify OpenWRT Partitions (x86 ONLY):${NC}"
    echo -e -n "    Modify partition sizes? [ n = no changes (default) | y = resize ] [N/y]: "
    read PROMPT
    if [[ ${PROMPT} =~ ^[Yy]$ ]]; then
        MOD_PARTSIZE=true
    else
        MOD_PARTSIZE=false
    fi
fi

# Set custom partition sizes
if [[ ${MOD_PARTSIZE} = true ]] && [[ ${IMAGE_PROFILE} = "generic" ]]; then
    [[ -z ${KERNEL_PARTSIZE} ]] &&
        read -p "    x86 ONLY!: Enter KERNEL partition size in MB [Hit enter for ${KERNEL_RESIZE_DEF}, or enter custom size]: " KERNEL_PARTSIZE
    [[ -z ${ROOT_PARTSIZE} ]] &&
        read -p "    x86 ONLY!: Enter ROOT partition size in MB [Hit enter for ${ROOT_RESIZE_DEF}, or enter custom size]: " ROOT_PARTSIZE
fi

# If no kernel partition size value given, create a default value
if [[ ${MOD_PARTSIZE} = true ]] && [[ -z ${KERNEL_PARTSIZE} ]] && [[ ${IMAGE_PROFILE} = "generic" ]]; then
    KERNEL_PARTSIZE=$KERNEL_RESIZE_DEF
   fi
   # If no root partition size value given, create a default value
   if [[ ${MOD_PARTSIZE} = true ]] && [[ -z ${ROOT_PARTSIZE} ]] && [[ ${IMAGE_PROFILE} = "generic" ]]; then
    ROOT_PARTSIZE=$ROOT_RESIZE_DEF
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
if [[ -z ${CREATE_VMDK} ]] && [[ ${IMAGE_PROFILE} = "generic" ]]; then
echo
    echo -e "${LYELLOW}Virtual machine image conversion:${NC}"
    echo -e -n "x86 ONLY!: Convert OpenWRT images to VMware VMDK images? [default = n] [N/y]: "
    read PROMPT
    if [[ ${PROMPT} =~ ^[Yy]$ ]]; then
        CREATE_VMDK=true
    else
        CREATE_VMDK=false
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
    mkdir -p "${INJECT_FILES}"
    if [[ ${CREATE_VMDK} = true ]] && [[ ${IMAGE_PROFILE} = "generic" ]]; then mkdir -p "${VMDK}" ; fi
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

# Uncompress if the source tar.xz exists but there is no uncompressed source directory (was cleared for a fresh build).
if [ -n "${SOURCE_DIR}" ]; then
    tar xJvf "${BUILDER##*/}" --checkpoint=.100 2>&1 | tee -a ${BUILD_LOG}
fi

# Reconfigure the partition sizing source files (for x86 build only)
if [[ ${MOD_PARTSIZE} = true ]] && [[ ${IMAGE_PROFILE} = "generic" ]]; then
    # Patch the source partition size config settings
    sed -i "s/CONFIG_TARGET_KERNEL_PARTSIZE=.*/CONFIG_TARGET_KERNEL_PARTSIZE=$KERNEL_PARTSIZE/g" "$PWD/$SOURCE_DIR/.config"
    sed -i "s/CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=$ROOT_PARTSIZE/g" "$PWD/$SOURCE_DIR/.config"
    # Patch for source partition size config settings giving errors https://forum.openwrt.org/t/22-03-3-image-builder-issues/154168
    sed -i '/\$(CONFIG_TARGET_ROOTFS_PARTSIZE) \$(IMAGE_ROOTFS)/,/256/ s/256/'"$ROOT_PARTSIZE"'/' "$PWD/$SOURCE_DIR/target/linux/x86/image/Makefile"
fi

# Start a clean image build with the selected packages
    cd $(pwd)/"${SOURCE_DIR}"/
    make clean 2>&1 | tee -a ${BUILD_LOG}
    make image PROFILE="${IMAGE_PROFILE}" PACKAGES="${CUSTOM_PACKAGES}" EXTRA_IMAGE_NAME="${IMAGE_TAG}" FILES="${INJECT_FILES}" BIN_DIR="${OUTPUT}" 2>&1 | tee -a ${BUILD_LOG}


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
    rm -f $VMDK/*.img
fi

# Remove sudo access limits from output
    cd ..
    chown -R $SUDO_USER $SOURCE_FILE
    chown -R $SUDO_USER $SOURCE_DIR
    chown -R $SUDO_USER $BUILD_ROOT

