#!/bin/bash

# Verify Root Permissions.
if [ "$EUID" -ne 0 ]; then
    echo "Run as root."
    exit 1
fi

clear; echo

cat << "EOF"
  ____  _     _                             
 |  _ \(_)___| | __                         
 | | | | / __| |/ /                         
 | |_| | \__ \   <                          
 |____/|_|___/_|\_\           _             
        / ___| |__   ___  ___| | _____ _ __ 
       | |   | '_ \ / _ \/ __| |/ / _ \ '__|
       | |___| | | |  __/ (__|   <  __/ |   
        \____|_| |_|\___|\___|_|\_\___|_|   
EOF
echo; echo

sleep 2

# Iterate over all NVMe/SATA disks detected by smartctl and check their SMART health attributes.
for dev in $(lsblk -n -d -o NAME | grep -E '^nvme|^sd|^hd' | sed 's#^#/dev/#'); do
    echo "  ===== $dev ====="; echo

    # Displaying the Model Name and Serial Number.
    MODEL=$(lsblk -n -d -o MODEL "$dev" 2>/dev/null | xargs)
    SERIAL=$(lsblk -n -d -o SERIAL "$dev" 2>/dev/null | xargs)
    
    echo "  Model : ${MODEL:-N/A}"; echo
    echo "  S/N : ${SERIAL:-N/A}"; echo

    # Variables contained in the raw smartctl execution output.
    INFO=$(smartctl -A "$dev")

    # Extract key SMART attributes from the output
    CRITICAL_WARNING=$(echo "$INFO" | grep -oP 'Critical Warning:\s*\K\S+')
    PERCENTAGE_USED=$(echo "$INFO" | grep -oP 'Percentage Used:\s*\K[0-9]+')
    SPARE=$(echo "$INFO" | grep -oP 'Available Spare:\s*\K[0-9]+')
    SPARE_THRESHOLD=$(echo "$INFO" | grep -oP 'Available Spare Threshold:\s*\K[0-9]+')
    INTEGRITY_ERRORS=$(echo "$INFO" | grep -oP 'Media and Data Integrity Errors:\s*\K[0-9,]+' | tr -d ',')
    ERROR_LOG=$(echo "$INFO" | grep -oP 'Error Information Log Entries:\s*\K[0-9,]+' | tr -d ',')

    # Extraction of Key Bad Sector Metrics for SATA SSD/HDD.
    REALLOCATED=$(echo "$INFO" | awk '/Reallocated_Sector_Ct/ {print $10}')
    PENDING=$(echo "$INFO" | awk '/Current_Pending_Sector/ {print $10}')
    UNCORRECTABLE=$(echo "$INFO" | awk '/Offline_Uncorrectable/ {print $10}')

    # Critical Warning should be 0x00; any other value indicates a problem.
    if [ "$CRITICAL_WARNING" != "0x00" ]; then
        echo "  Critical Warning: $CRITICAL_WARNING"
        echo
    fi

    # Percentage Used close to 100% means the drive is nearing end of life.
    if [ -n "$PERCENTAGE_USED" ] && [ "$PERCENTAGE_USED" -ge 80 ]; then
        echo "  Percentage Used is high: ${PERCENTAGE_USED}%"
        echo
    fi

    # If Available Spare has dropped to or below the threshold, replacement may be needed soon.
    if [ -n "$SPARE" ] && [ -n "$SPARE_THRESHOLD" ] && [ "$SPARE" -le "$SPARE_THRESHOLD" ]; then
        echo "  Available Spare is below the threshold: ${SPARE}% <= ${SPARE_THRESHOLD}%"
        echo
    fi

    # Any non-zero value here means actual data corruption/integrity issues have occurred.
    if [ -n "$INTEGRITY_ERRORS" ] && [ "$INTEGRITY_ERRORS" -gt 0 ]; then
        echo "  Data Integrity Errors Occur: $INTEGRITY_ERRORS"
        echo
    fi

    # Alert if reallocated sectors are found, indicating physical drive degradation or bad blocks.
    if [ -n "$REALLOCATED" ] && [ "$REALLOCATED" -gt 0 ]; then
        echo "  Reallocated Sector Count: $REALLOCATED"
        echo
    fi

    # Alert if unstable sectors are pending reallocation due to read errors.
    if [ -n "$PENDING" ] && [ "$PENDING" -gt 0 ]; then
        echo "  Current Pending Sector Count: $PENDING"
        echo
    fi

    echo "  Percentage Used: ${PERCENTAGE_USED}%"; echo
    echo "  Error Log Entries: $ERROR_LOG"; echo
done
