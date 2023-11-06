# OpenWRT custom image builder script

**This OWRT build script script presents the following option prompts:**

  1. Modify partition sizes or keep OpenWRT partition defaults? [y/n], y = enter custom sizing (x86 only)
  2. Add a custom image filename identifier [enter a filename tag]
  3. Convert finished OpenWRT images to VMware VMDK? [y/n] (x86 only)
  4. Add extra config files (to bake into the new images)? [provide custom config files]

**Note: Partition resize and VMDK conversion options only available with x86 targets**

## Prerequisites
Any recent Debian flavoured OS should work fine.

## Instructions

**To configure the script, edit the below script variables as needed:**

1. Set your preferred OWRT release version (or snapshot), target architecture and image profile name:
   ```
    SNAPSHOT="false"
    VERSION="23.05.0" # If snapshot = true then release value is ignored 
    TARGET="x86"
    ARCH="64"
    IMAGE_PROFILE="generic"  # x86 = generic. For available profile options run $SOURCE_DIR/make info
    ```

2. Customise the list of packages you want in your new image. (Script contents & below are just examples):
   ```
   CUSTOM_PACKAGES="blockd block-mount curl dnsmasq dnsmasq-full kmod-fs-ext4 kmod-usb2 kmod-usb3 kmod-usb-storage kmod-usb-core \
   usbutils nano socat tcpdump luci luci-app-ddns luci-app-mwan3 mwan3 luci-app-openvpn openvpn-openssl luci-app-samba4 open-vm-tools"
   ```

3. For baking custom settings into new images, when prompted copy custom OWRT config files to `$(pwd)/owrt_inject_files` 

## Further filesystem expansion

It is also possible to combine SquashFS with a third _**and pesistent after sysupgrade**_ EXT4 data partition. After image installation, simply add a new EXT4 partition and update its PART-UUID details in the OWRT fstab file. Next take a copy of the updated fstab file and inject this into a 2nd new OpenWRT image, then re-flash your device with this 2nd new image. Now the fstab and new EXT4 partition is permanent and won't be affected by sysupgrades.
