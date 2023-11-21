#!/bin/bash

set -eu

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

CONFIG_FILE="$HOME/.config/transmission-nordvpn.conf"

mkdir -p "$HOME/bin"
ln -sf "${SCRIPT_DIR}/bin/"* "$HOME/bin/"
ln -sf "${SCRIPT_DIR}/data/"*.desktop "$HOME/.local/share/applications/"

# Create the config file
touch "${CONFIG_FILE}"
chmod 600 "${CONFIG_FILE}"

read -p "Enter NordVPN token: " token
echo "NORDVPN_TOKEN=${token}" > "${CONFIG_FILE}"
