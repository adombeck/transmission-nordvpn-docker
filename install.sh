#!/bin/bash

set -eu

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

CONFIG_FILE="$HOME/.config/transmission-nordvpn.conf"

ln -s "${SCRIPT_DIR}/bin/"* "$HOME/bin/"
ln -s "${SCRIPT_DIR}/data/"*.desktop "$HOME/.local/share/applications/"

# Create the config file
touch "${CONFIG_FILE}"
chmod 600 "${CONFIG_FILE}"

read -p "Enter NordVPN Username/Email: " user
echo "NORDVPN_USER=${user}" > "${CONFIG_FILE}"

read -s -p "Enter NordVPN Password: " pass
echo "NORDVPN_PASS=${pass}" >> "${CONFIG_FILE}"

