#!/bin/bash
#######################################################################################################################
# OpenWRT Imagebuilder script for custom Linksys WRT1900acsv2 firmware creation
# David Harrop
# October 2023
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
   BUILDER="https://downloads.openwrt.org/releases/23.05.0/targets/mvebu/cortexa9/openwrt-imagebuilder-23.05.0-mvebu-cortexa9.Linux-x86_64.tar.xz"
   #BUILDER="https://downloads.openwrt.org/snapshots/targets/mvebu/cortexa9/openwrt-imagebuilder-mvebu-cortexa9.Linux-x86_64.tar.xz" #Current snapshot
   #BUILDER="https://downloads.openwrt.org/releases/22.03.5/targets/mvebu/cortexa9/openwrt-imagebuilder-22.03.5-mvebu-cortexa9.Linux-x86_64.tar.xz"

# Select the desired SquashFS partition sizes in MB
    IMAGE_TAG=""  # This tag will be added to the completed image filename

# Provide your specific recipe of custom OWRT packages to add to the base installation here. (Below is an example)
CUSTOM_PACKAGES="blockd block-mount kmod-fs-ext4 kmod-usb2 kmod-usb3 kmod-usb-storage kmod-usb-core usbutils \
    -dnsmasq dnsmasq-full luci luci-app-ddns luci-app-mwan3 mwan3 luci-app-openvpn openvpn-openssl \
    luci-app-samba4 luci-app-sqm sqm-scripts sqm-scripts-extra luci-app-attendedsysupgrade auc luci-app-advanced-reboot \
    curl nano socat tcpdump python3-light python3-netifaces wsdd2 igmpproxy iptables-mod-ipopt  \
    usbmuxd libimobiledevice kmod-usb-net kmod-usb-net-asix-ax88179 kmod-mt7921u kmod-usb-net-rndis kmod-usb-net-ipheth"
    
#######################################################################################################################
# Setup the image builder working environment
#######################################################################################################################
    SOURCE_FILE="${BUILDER##*/}" # Separate the tar.xz file name from the source download link
    SOURCE_DIR="${SOURCE_FILE%%.tar.xz}" # Get the uncompressed tar.xz directory name to set as the build source dir
    BUILD_ROOT="$(pwd)/build_output"
    OUTPUT="${BUILD_ROOT}/firmware_images"
    INJECT_FILES="$(pwd)/inject_files"
    BUILD_LOG="${BUILD_ROOT}/build.log"

#######################################################################################################################
# Script user prompts 
#######################################################################################################################
echo -e ${LYELLOW}
echo "Image Builder activity will be logged to ${BUILD_LOG}"
echo

echo -e "Linksys WRT1900acsv2 Image Builder:${NC}"
# Create a custom image name tag
if [[ -z ${IMAGE_TAG} ]]; then
echo
    while true; do
        read -p "    Enter text to include in the image filename [Enter for \"custom\"]: " IMAGE_TAG
        [[ "${IMAGE_TAG}" = "" ]] || [[ "${IMAGE_TAG}" != "" ]] && break
    done
fi
# If no image name tag is given, create a default value
if [[ -z ${IMAGE_TAG} ]]; then
    IMAGE_TAG="custom"
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
    chown -R $SUDO_USER $INJECT_FILES

# Option to pre-configure images with injected config files
    echo -e ${LYELLOW}
    read -p $"Copy optional config files to ${INJECT_FILES} now for inclusion into the new image. Enter to begin build..."
    echo -e ${NC}

# Install OWRT build system dependencies for recent Ubuntu/Debian.
# See here for other distro dependencies: https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem
    sudo apt-get update  2>&1 | tee -a ${BUILD_LOG}
    sudo apt-get install -y build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
    gettext git libncurses-dev libssl-dev python3-distutils rsync unzip zlib1g-dev file wget 2>&1 | tee -a ${BUILD_LOG}

# Download the image builder source if we haven't already
if [ ! -f "${BUILDER##*/}" ]; then
    wget -q --show-progress "$BUILDER"
    tar xJvf "${BUILDER##*/}" --checkpoint=.100 2>&1 | tee -a ${BUILD_LOG}
fi

# Uncompress if the source tar.xz exists but the uncompressed source directory was cleared for a fresh build.
if [ -n "${SOURCE_DIR}" ]; then
    tar xJvf "${BUILDER##*/}" --checkpoint=.100 2>&1 | tee -a ${BUILD_LOG}
fi

# Start a clean image build with the selected packages
    cd $(pwd)/"${SOURCE_DIR}"/
    make clean 2>&1 | tee -a ${BUILD_LOG}
    make image PROFILE="linksys_wrt1900acs" PACKAGES="${CUSTOM_PACKAGES}" EXTRA_IMAGE_NAME="${IMAGE_TAG}" FILES="${INJECT_FILES}" BIN_DIR="${OUTPUT}" 2>&1 | tee -a ${BUILD_LOG}

# Remove sudo access limits from output
    cd ..
    chown -R $SUDO_USER $SOURCE_FILE
    chown -R $SUDO_USER $SOURCE_DIR
    chown -R $SUDO_USER $BUILD_ROOT

