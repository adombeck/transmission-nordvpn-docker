#!/bin/bash

set -eu

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

SYSTEMD_DATA_DIR="$HOME/.local/share/systemd/user"
CONFIG_DIR="$HOME/.config/transmission-nordvpn"
NORDVPN_SECRETS_FILE="${CONFIG_DIR}/nordvpn-secrets.env"
TRANSMISSION_SECRETS_FILE="${CONFIG_DIR}/transmission-secrets.env"
TRANSMISSION_REMOTE_CONFIG_FILE="$HOME/.config/transmission-remote-gtk/config.json"

mkdir -p "$HOME/bin"
ln -sf "${SCRIPT_DIR}/bin/"* "$HOME/bin/"
ln -sf "${SCRIPT_DIR}/data/"*.desktop "$HOME/.local/share/applications/"

# Create the systemd data dir
mkdir -p "${SYSTEMD_DATA_DIR}"

# Create symlinks to the systemd service files
for service_file in "${SCRIPT_DIR}/data/"*.service; do
    ln -sf "${service_file}" "${SYSTEMD_DATA_DIR}/"
done

# Create the config dir
mkdir -p "${CONFIG_DIR}"
chmod 700 "${CONFIG_DIR}"

# Copy the compose.yaml file
cp "${SCRIPT_DIR}/data/compose.yaml" "${CONFIG_DIR}/"

read -r -p "Enter NordVPN token: " token
echo "TOKEN=${token}" > "${NORDVPN_SECRETS_FILE}"

# Generate a random password for the transmission user
echo "Generating random password for transmission user"
TRANSMISSION_PASSWORD=$(base64 < /dev/urandom | head -c32)

# Store the transmission password in the config file
echo "Storing transmission password in ${TRANSMISSION_SECRETS_FILE}"
echo "USER=user" >> "${TRANSMISSION_SECRETS_FILE}"
echo "PASS=${TRANSMISSION_PASSWORD}" >> "${TRANSMISSION_SECRETS_FILE}"

echo "Creating transmission-remote-gtk config file"
# Check if a transmission-remote-gtk config file exists
if [ -f "${TRANSMISSION_REMOTE_CONFIG_FILE}" ]; then
    echo "A transmission-remote-gtk config file already exists. You can
          keep it and configure the password manually, or overwrite it
          with a new config file that has the password already set.
          Please make sure that transmission-remote-gtk isn't running
          when you choose to overwrite the config file."
    read -r -p "Overwrite existing config file? [y/N] " overwrite
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
