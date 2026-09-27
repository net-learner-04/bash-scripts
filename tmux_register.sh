#!/bin/bash

# If you continue to encounter errors even though the parameters you entered are correct, 
# you need to modify the SELinux label for the tmux binary.
# [ The command below is used to edit a label. ]
# sudo semanage fcontext -a -t bin_t /usr/bin/tmux
# sudo restorecon -v /usr/bin/tmux

if [ "$EUID" -ne 0 ]; then
    echo "Run as root."
    exit 1
fi

clear; echo

cat << "EOF"
 ______  ___ ___  __ __  __ __                                
|      ||   |   ||  |  ||  |  |                               
|      || _   _ ||  |  ||  |  |                               
|_|  |_||  \_/  ||  |  ||_   _|                               
  |  |  |   |   ||  :  ||     |                               
  |  |  |   |   ||     ||  |  |                               
  |__|  |___|___| \__,_||__|__|                               
                                                              
         ____     ___   ____  ____ _____ ______    ___  ____  
        |    \   /  _] /    ||    / ___/|      |  /  _]|    \ 
        |  D  ) /  [_ |   __| |  (   \_ |      | /  [_ |  D  )
        |    / |    _]|  |  | |  |\__  ||_|  |_||    _]|    / 
        |    \ |   [_ |  |_ | |  |/  \ |  |  |  |   [_ |    \ 
        |  .  \|     ||     | |  |\    |  |  |  |     ||  .  \
        |__|\_||_____||___,_||____|\___|  |__|  |_____||__|\_|
                                                              
EOF

sleep 2

read -r -p "Enter the absolute path of the script to be executed: " FILE_PATH; echo

read -r -p "Does the command you want to run require root privileges? (y/n): " USER_CHECK; echo

# When checking the user account to be registered, if it is “root,” store “root” in the variable; 
# otherwise, automatically set it to the currently logged-in user.
if [ "$USER_CHECK" = "y" ]; then
    LOGIN_USER="root"
else
    LOGIN_USER=${SUDO_USER:-$LOGNAME}
fi

# If the file the user wants to run does not exist, terminate the process.
if [ ! -f "$FILE_PATH" ]; then
    echo "File not found. Please check the path."
    exit 1
fi

# Ask which interpreter/program should run the file. (e.g. python3)
read -r -p "Please enter the name of the program to run the file (example -> python3): " COMMAND_NAME; echo

# Locate the tmux binary and resolve its absolute path.
TMUX_PATH=$(which tmux 2>/dev/null)

if [ -n "$TMUX_PATH" ]; then
    TMUX_PATH=$(realpath "$TMUX_PATH")
fi

# Confirm tmux exists and is executable; exit if not.
if [ -z "$TMUX_PATH" ] || [ ! -x "$TMUX_PATH" ]; then
    echo "tmux is not installed."
    exit 1
fi

# Resolve COMMAND_NAME to an absolute path:
# - if not already an absolute path, check /usr/bin first, then fall back to `which`
# - if already absolute, just normalize it with realpath.
if [[ "$COMMAND_NAME" != /* ]]; then
    if [ -x "/usr/bin/$COMMAND_NAME" ]; then
        COMMAND_NAME="/usr/bin/$COMMAND_NAME"
    else
        RESOLVED_CMD=$(which "$COMMAND_NAME" 2>/dev/null)
        if [ -n "$RESOLVED_CMD" ]; then
            COMMAND_NAME=$(realpath "$RESOLVED_CMD")
        fi
    fi
else
    COMMAND_NAME=$(realpath "$COMMAND_NAME")
fi

# Ask for a name to use for the tmux session. (also used as the service name)
read -r -p "Enter a tmux session name: " SESSION_NAME; echo

# Build the path for the new systemd unit file.
SYSTEMD_FILE_PATH="/etc/systemd/system/${SESSION_NAME}.service"

# A variable that dynamically stores the WorkingDirectory for each script.
WORKING_DIR=$(dirname "$(realpath "$FILE_PATH")")

# Generate the systemd service file that starts a tmux session running the command on boot.
cat << EOF > "$SYSTEMD_FILE_PATH"
[Unit]
Description=Auto Start Tmux Session on Boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=$LOGIN_USER
WorkingDirectory=$WORKING_DIR
ExecStart=$TMUX_PATH new-session -d -s "$SESSION_NAME" "$COMMAND_NAME $FILE_PATH"
ExecStop=$TMUX_PATH kill-session -t "$SESSION_NAME"

[Install]
WantedBy=multi-user.target
EOF

echo "Restart the systemd daemon to save the settings."
systemctl daemon-reload

echo "The service you created will be applied permanently."
systemctl enable --now "${SESSION_NAME}.service"

if [ $? -eq 0 ]; then
    echo "Service registration is complete."
    exit 0
else
    echo "Service registration failed."
    
    read -r -p "Would you like to delete the .service file you created? (y/n): " SELECT

    if [ "$SELECT" = "y" ]; then
        echo "Delete the .service file."
        rm -f "$SYSTEMD_FILE_PATH"
        exit 1
    else
        exit 1
    fi
fi
