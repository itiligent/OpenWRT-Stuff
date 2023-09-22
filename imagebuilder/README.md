# Build OpenWRT x86 images (with options for SquashFS resize & vmdk conversion).

- **THIS SCRIPT IS FOR x86 DISK SYSTEMS ONLY**

OpenWRT with SquashFS offers numerous advantages such as easier backups, factory reset to a known good config, no flash memory wear and config management simplicity. However, all this comes with a huge drawback for x86 systems that could better utilise their extra capacity if not for ***a default 100MB SquashFS root partition limitation.*** To work around this limitation, typically EXT4 filesystems are used, but this sacrifices all the convenience, immutability and flash wear protection that SquashFS provides.


## Prerequisites
Any recent Debian flavoured OS should work fine.

## Script Overview

This script presents the following build option prompts:

- Modify SquashFS sizing or keep OpenWRT SqaushFS defaults?
- Add a custom image filename identifier?
- Convert finished OpenWRT images to VMware VMDK?
- Include extra config files to bake into the new image?

## Instructions

To utilise the script, edit the below script variables as needed:

1. Choose your preferred version or snapshot of the OWRT x86 Image Builder source:
   ```
   BUILDER="https://downloads.openwrt.org/releases/22.03.5/targets/x86/64/openwrt-imagebuilder-22.03.5-x86-64.Linux-x86_64.tar.xz"
   or for a snapshot build...
   BUILDER="https://downloads.openwrt.org/snapshots/targets/x86/64/openwrt-imagebuilder-x86-64.Linux-x86_64.tar.xz"
   ```

2. Customise the list of packages you want in your new image. (Script contents and below are just examples):
   ```
   CUSTOM_PACKAGES="blockd block-mount curl dnsmasq dnsmasq-full kmod-fs-ext4 kmod-usb2 kmod-usb3 kmod-usb-storage kmod-usb-core \
   usbutils nano socat tcpdump luci luci-app-ddns luci-app-mwan3 mwan3 luci-app-openvpn openvpn-openssl luci-app-samba4 open-vm-tools"
   ```

3. When the script prompts, copy any customised OWRT config files to `$(pwd)/inject_files` to bake these into images.

## Further hybrid filesystem expansion

It is also possible to combine SquashFS with a third **and pesistent** EXT4 data partition after image installation. Simply add a new EXT4 partition and add its PART-UUID details to the fstab file. Take the updated fstab file and inject this into a new OpenWRT image, then re-flash with the new image.
