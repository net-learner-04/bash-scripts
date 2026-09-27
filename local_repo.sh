#!/bin/bash

# Verify Root Permissions.
if [ "$EUID" -ne 0 ]; then
    echo "Run the command with 'sudo'."
    exit 1
fi

clear; echo

cat << "EOF"
                        ______                 
                        | ___ \                
 _   _ _   _ _ __ ___   | |_/ /___ _ __   ___  
| | | | | | | '_ ` _ \  |    // _ \ '_ \ / _ \ 
| |_| | |_| | | | | | | | |\ \  __/ |_) | (_) |
 \__, |\__,_|_| |_| |_| \_| \_\___| .__/ \___/ 
  __/ |                           | |          
 |___/                            |_|          
                                                                                                                                                                                                                               
EOF

sleep 2

# Repository folder path
REPO_DIR="/srv/repo"

USER_NAME=$(logname)

# Display a list of currently automatically mounted devices.
ls /media/$USER_NAME/; echo

# USB Mount Point (Requires changes in an auto-mount environment.)
read -r -p "Enter the current USB mount point (absolute path): " USB_MOUNT; echo

# Check if the value is empty.
if [ -z "$USB_MOUNT" ]; then
    echo "No path was entered. The script is terminating."
    exit 1
fi

# Check if it is an absolute path. (whether it starts with ‘/’)
if [[ "$USB_MOUNT" != /* ]]; then
    echo "You must enter the absolute path. (ex: /media/user/USB)"
    exit 1
fi

# Verify that the directory actually exists.
if [ ! -d "$USB_MOUNT" ]; then
    echo "The path does not exist or is not a directory: $USB_MOUNT"
    exit 1
fi

# Verify that the drive is actually mounted.
if ! mountpoint -q "$USB_MOUNT"; then
    read -r -p "$USB_MOUNT does not appear to be a mount point. Do you want to continue? (y/n)" CONTINUE
    if [ "$CONTINUE" != 'y' ]; then
        exit 1
    fi
fi

# Check if the 'createrepo' command exists
if ! command -v createrepo &> /dev/null 
then
    echo "The 'createrepo' command is not installed."
    read -r -p "Would you like to install it? (y/n): " CREATEREPO_INST

    if [ "$CREATEREPO_INST" = 'y' ]; then
        echo "The 'createrepo' command is currently being installed..."; echo
        yum install createrepo -y
    else
        echo "Since the installation will not proceed, the system will shut down."
        exit 1
    fi
fi

# Create a repository folder
mkdir -p "$REPO_DIR"

# Use the 'find' command to filter and copy the '.rpm' 
# files in the mount path to the local repository.
find "$USB_MOUNT" -name "*.rpm" -exec cp {} "$REPO_DIR" +

if [ $? -ne 0 ]
then
    echo "Failed to copy RPM files. Please check USB mount status or disk space."
    exit 1
fi

if [ -z "$(ls -A "$REPO_DIR" 2>/dev/null | grep '\.rpm$')" ]
then
    echo "Failed to copy RPM files. No .rpm files found or USB is not mounted."
    exit 1
fi

# Check if it has been indexed before
if [ ! -d "$REPO_DIR/repodata" ]
then
    echo "Creating a Repository..."
    createrepo "$REPO_DIR"
    
    if [ $? -ne 0 ]
    then
        echo "Failed to create repository."
        exit 1
    fi
else
    echo "The repository already exists. Updating the index..."
    createrepo --update "$REPO_DIR"
    
    if [ $? -ne 0 ]
    then
        echo "Failed to update repository. "
        exit 1
    fi
fi

# Configuring the settings file to install programs
# using files on my computer (or USB drive) 
# without an internet connection
cat << EOF > /etc/yum.repos.d/local.repo
[local-repo]
name=Local Repository
baseurl=file://$REPO_DIR
enabled=1
gpgcheck=0
EOF

echo "The local repository setup is now complete."
