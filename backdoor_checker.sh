#!/bin/bash

# Verify Root Permissions.
if [ "$EUID" -ne 0 ]; then
    echo "Run as root."
    exit 1
fi

clear; echo

cat << "EOF"
  ____             _      _____                   
 |  _ \           | |    |  __ \                  
 | |_) | __ _  ___| | __ | |  | | ___   ___  _ __ 
 |  _ < / _` |/ __| |/ / | |  | |/ _ \ / _ \| '__|
 | |_) | (_| | (__|   <  | |__| | (_) | (_) | |   
 |____/ \__,_|\___|_|\_\ |_____/ \___/ \___/|_|   
           _____ _               _                
          / ____| |             | |               
         | |    | |__   ___  ___| | _____ _ __    
         | |    | '_ \ / _ \/ __| |/ / _ \ '__|   
         | |____| | | |  __/ (__|   <  __/ |      
          \_____|_| |_|\___|\___|_|\_\___|_|      
                                                  
EOF
echo; echo

sleep 2

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

EFI_LIST=$(ls -1a /boot/efi/EFI/)

# Check for suspicious EFI mount entries.
echo "$EFI_LIST" | while read -r line; do
    # Skip if the line is empty or is a base directory. (`.` and `..`)
    if [ "$line" = "." ] || [ "$line" = ".." ] || [ -z "$line" ]; then
        continue
    fi
    # Check for suspicious entries that do not match known legitimate EFI directories.
    if echo "$line" | grep -viE "(rocky|boot|ubuntu|debian|fedora|opensuse|arch|microsoft)"; then
        echo -e "${RED}A suspicious mount entry exists: $line${NC}"; echo
    else
        echo -e "${GREEN}No suspicious mount entries detected: $line${NC}"; echo
    fi
done
echo

# Check for suspicious EFI boot entries.
efibootmgr -v | grep -E '^Boot[0-9]{4}' | awk '{$1=""; sub(/^ /, ""); print}' | awk '{$NF=""; print}' | while read -r line; do
    # Check for suspicious entries that do not match known legitimate boot entries.
    if echo "$line" | grep -viE "(rocky|shim|grub|redhat|centos|fedora|windows boot manager|uefi os|hd\(|nvme|sata|usb)"; then
        echo -e "${RED}Potential backdoor or unauthorized entry found: $line${NC}"; echo
    else
        echo -e "${GREEN}No suspicious entries detected: $line${NC}"; echo
    fi
done
echo

# Check Secure Boot status.
SECURE_BOOT_STATE=$(mokutil --sb-state | grep -i "secureboot" | awk '{print $NF}')

# Check if Secure Boot is enabled or disabled and provide a warning if it is disabled.
if [ "$SECURE_BOOT_STATE" = "disabled" ]; then
    echo -e "${RED}Secure Boot is disabled. This may indicate a potential security risk.${NC}"; echo
else
    echo -e "${GREEN}Secure Boot is enabled.${NC}"; echo
fi
echo

# Save the list of currently bound items.
BIND_LIST=$(ss -tulpn | grep -oP 'users:\(\("\K[^"]+' | sort -u)

if [ -z "$BIND_LIST" ]; then
    echo -e "${GREEN}No active process bindings found via ss.${NC}"; echo 
else 
    echo "$BIND_LIST" | while read -r line; do
        # Check for suspicious network bindings that do not match known legitimate services.
        if [[ "$line" =~ systemd|sshd|nginx|apache|mysql|postgresql|docker|chronyd ]]; then
            echo -e "${GREEN}No suspicious network bindings detected: $line${NC}"; echo
        else
            echo -e "${RED}Suspicious network binding detected: $line${NC}"; echo
        fi
    done
fi
echo

# Install rkhunter and chkrootkit if not already installed.
echo "Installing rkhunter..."; echo

dnf install -qy epel-release
dnf install -qy rkhunter

# Update rkhunter database and perform rootkit checks.
echo "Updating rkhunter database..."; echo

rkhunter --update >/dev/null 2>&1
rkhunter --propupd >/dev/null 2>&1

# Perform rootkit checks using rkhunter and chkrootkit.
echo "Executing rkhunter check..."; echo

rkhunter --check --sk
