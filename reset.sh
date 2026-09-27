#!/bin/bash

# Verify Root Permissions.
if [ "$EUID" -ne 0 ]; then
    echo "Run as root."
    exit 1
fi

clear; echo

cat << "EOF"
 ______     ______     ______     ______     ______  
/\  == \   /\  ___\   /\  ___\   /\  ___\   /\__  _\ 
\ \  __<   \ \  __\   \ \___  \  \ \  __\   \/_/\ \/ 
 \ \_\ \_\  \ \_____\  \/\_____\  \ \_____\    \ \_\ 
  \/_/ /_/   \/_____/   \/_____/   \/_____/     \/_/ 
                                                     
EOF

sleep 2

# Show a list of currently connected block disks.
echo "=== List of disks on the current system ==="; echo
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
echo; echo "==========================================="; echo

# Receive Input for Target Disk.
read -r -p "Enter the name of the disk you want to initialize (ex: sdb, nvme1n1): " DISK_NAME
TARGET="/dev/$DISK_NAME"

# Check for the Presence and Type of a Disk.
if [ ! -b "$TARGET" ]
then
    echo "$TARGET The disk does not exist or is not a block device."
    exit 1
fi

# Check if It's Mounted.
if mount | grep -q "$TARGET"
then
    echo "$TARGET disk is currently mounted."
    read -r -p "Do you want to unmount the $TARGET disk? (y/n): " UNMOUNT_CHECK
    if [ "$UNMOUNT_CHECK" == 'y' ]
    then
        echo "Unmounting $TARGET..."
        umount -l "$TARGET"* 2>/dev/null

        if mount | grep -q "$TARGET"
        then
            echo "Unmount failed. Check to see if another process is using the disk."
            echo "Display the PID and process name of the process holding the disk."
            lsof "$TARGET"
            exit 1
        fi
    else
        echo "$TARGET disk is currently mounted."
        exit 1
    fi
fi

# Color setup.
RED='\033[0;31m'
NC='\033[0m'

# Final Warning Before Starting Work.
echo -e "${RED} All data in $TARGET will be permanently deleted.${NC}"
read -r -p "Are you sure you want to proceed? (Type 'YES' in all caps): " CONFIRM

if [ "$CONFIRM" != "YES" ]
then
    echo "It has been canceled."
    exit 1
fi

TRAN=$(lsblk -d -n -o TRAN "$TARGET") 

# Regular expression for identifying NVMe.
PATTERN="^nvme[0-9]+n[0-9]+"

# Performing a full SSD reset
echo "$TARGET Initialization Begins..."

STATUS=1

if [[ $DISK_NAME =~ $PATTERN && $TRAN == "nvme" ]]
then
    echo "NVMe Secure Erase in progress..."
    nvme format "$TARGET" -s 1 -f
    STATUS=$?
else
    echo "Initializing a general block disk (blkdiscard)..."
    blkdiscard -f "$TARGET"
    STATUS=$?
fi

if [ "$STATUS" -eq 0 ]
then
    echo "The $TARGET SSD has been completely initialized."
    read -r -p "Do you want to create a file system on the $TARGET disk? (y/n): " MAKE_FS
    if [ "$MAKE_FS" == 'y' ]
    then
        echo "Creating the 'xfs' file system on the $TARGET disk..."
        mkfs.xfs -f "$TARGET"
        # $? -> A special variable that returns the exit status of the most recently executed command.
        # Therefore, do not insert another command between the command and '$?'.
        if [ $? -ne 0 ]; then
            echo "Failed to create xfs file system. Canceled fstab registration."
            exit 1
        fi

        # Refresh the Kernel Partition Table.
        partprobe "$TARGET"

        UUID=$(blkid -s UUID -o value "$TARGET")

        if [ -z "$UUID" ]
        then
            echo "Failed to get UUID. Canceled fstab registration."
            exit 1
        fi

        read -r -p "Enter the path where you want to mount the disk (ex: /mnt/storage): " MP

        if [ ! -d "$MP" ]
        then
            echo "Creating mount directory: $MP"
            mkdir -p "$MP"
        fi

        # Backup of /etc/fstab Just in Case
        cp /etc/fstab "/etc/fstab.bak_$(date +%Y%m%d_%H%M%S)"
        echo "Backed up /etc/fstab."

        if grep -q "$UUID" /etc/fstab
        then
            echo "The UUID is already registered in /etc/fstab. Skipping insertion."
        else
            echo "UUID=$UUID $MP xfs defaults 0 0" >> /etc/fstab
            echo "Registered in /etc/fstab."
        fi

        echo "Testing the mount based on the /etc/fstab configuration..."
        mount -a

        if [ $? -eq 0 ]
        then
            echo "The $TARGET disk has been permanently mounted at $MP."
        else
            echo "An error occurred while testing the mount in /etc/fstab." 
            echo "Please check your configuration."
        fi
    else
        echo "Exit the initialization process."
        exit 1
    fi
else
    echo "An error occurred during initialization."
fi
