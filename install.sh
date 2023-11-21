#!/bin/bash

set -eu

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

CONFIG_FILE="$HOME/.config/transmission-nordvpn.conf"
TRANSMISSION_REMOTE_CONFIG_FILE="$HOME/.config/transmission-remote-gtk/config.json"

mkdir -p "$HOME/bin"
ln -sf "${SCRIPT_DIR}/bin/"* "$HOME/bin/"
ln -sf "${SCRIPT_DIR}/data/"*.desktop "$HOME/.local/share/applications/"

# Create the config file
touch "${CONFIG_FILE}"
chmod 600 "${CONFIG_FILE}"

read -p "Enter NordVPN token: " token
echo "NORDVPN_TOKEN=${token}" > "${CONFIG_FILE}"

# Generate a random password for the transmission user
echo "Generating random password for transmission user"
TRANSMISSION_PASSWORD=$(base64 < /dev/urandom | head -c32)

# Store the transmission password in the config file
echo "Storing transmission password in ${CONFIG_FILE}"
echo "TRANSMISSION_PASSWORD=${TRANSMISSION_PASSWORD}" >> "${CONFIG_FILE}"

echo "Creating transmission-remote-gtk config file"
# Check if a transmission-remote-gtk config file exists
if [ -f "${TRANSMISSION_REMOTE_CONFIG_FILE}" ]; then
    echo "A transmission-remote-gtk config file already exists. You can
          keep it and configure the password manually, or overwrite it
          with a new config file that has the password already set.
          Please make sure that transmission-remote-gtk isn't running
          when you choose to overwrite the config file."
    read -p "Overwrite existing config file? [y/N] " overwrite
    if [ "${overwrite}" != "y" ]; then
        exit
    fi
fi

# Create a transmission-remote-gtk config file with the password
cat > "${TRANSMISSION_REMOTE_CONFIG_FILE}" << EOF
{
  "profiles" : [
    {
      "profile-name" : "Default",
      "hostname" : "localhost",
      "port" : 9091,
      "username" : "user",
      "password" : "${TRANSMISSION_PASSWORD}",
      "auto-connect" : true
    }
  ]
}
EOF
