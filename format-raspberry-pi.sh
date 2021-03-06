# Calculate boot and rootfs partitions
BOOT_PART="${device}${FIRST_PARTITION}"
ROOT_PART="${device}${SECOND_PARTITION}"

umount_if_mounted $BOOT_PART
umount_if_mounted $ROOT_PART

# mountpoints
BOOT_MNT="$(mktemp -d --suffix=-boot)"
ROOT_MNT="$(mktemp -d --suffix=-root)"
echo "Using mount points: "
echo "...Boot MNT: $BOOT_MNT"
echo "...Root MNT: $ROOT_MNT"

if ! $skip_format; then
    echo "Creating partition table on ${device}..."
    # to create the partitions programatically (rather than manually)
    # we're going to simulate the manual input to fdisk
    # The sed script strips off all the comments so that we can
    # document what we're doing in-line with the actual commands
    # Note that a blank line (commented as "default" will send a empty
    # line terminated with a newline to take the fdisk default.
    sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk ${device}
      o # clear the in memory partition table
      n # new partition
      p # primary partition
      1 # partition number 1
        # default - start at beginning of disk
      +110M # boot parttion
      t # change the type (1st partition will be selected automatically)
      c # Changed type of partition 'Linux' to 'W95 FAT32 (LBA)', mandatory for RaspberryPi
      n # new partition
      p # primary partition
      2 # partion number 2
        # default, start immediately after preceding partition
        # default, extend partition to end of disk
      a # make a partition bootable
      1 # bootable partition is partition 1 -- /dev/sda1
      p # print the in-memory partition table
      w # write the partition table
      q # and we're done
EOF


    echo "Creating filesystem on device partitions..."
    echo_green "...creating FAT for BOOT_PART ($BOOT_PART)"
    mkfs.vfat ${BOOT_PART}

    # ext4 filesystem is problematic on Raspbian Jessie, so
    # stick with ext3 for now
    fstype="ext3"
    echo_green "...creating $fstype for ROOT_PART ($ROOT_PART)"
    mkfs.$fstype ${ROOT_PART}
fi

require_device $BOOT_PART
require_device $ROOT_PART

echo_green "Restoring files from source to device..."
echo "...mounting partitions"
mount ${BOOT_PART} ${BOOT_MNT}
mount ${ROOT_PART} ${ROOT_MNT}

echo "...restoring files from source ($(get_relative $PWD $src)) (this may take a while...)"
set +e # do not exit on error because some transfer errors are not important
error=false
rsync --info=progress2 -rltD -HAXh "${src}/boot/" ${BOOT_MNT}
[[ $? == 0 ]] || error=true
rsync --info=progress2 -aHAXh --exclude "boot" "${src}/" ${ROOT_MNT}
[[ $? == 0 ]] || error=true
mkdir -p "${ROOT_MNT}/boot"

if $error; then
    if prompt_yes_no "Should we ignore above errors?"; then
        echo_yellow "OK, we are ignoring above errors."
    else
        echo_red "Performing final cleanup."
    fi
fi

if ! $error; then
    echo "...setting /etc/resolv.conf attributes to make it immutable"
    chattr +i $ROOT_MNT/etc/resolv.conf

    echo "...syncing"
    sync
fi

echo "...unmounting devices"
umount ${BOOT_PART}
umount ${ROOT_PART}

echo "...removing mountpoints"
rmdir ${BOOT_MNT}
rmdir ${ROOT_MNT}

if ! $error; then
    echo_yellow "Do not forget to check the following files on target: "
    echo_yellow " * /boot/cmdline.txt"
    echo_yellow " * /etc/fstab"
    echo_yellow " * /etc/network/interfaces"
fi
