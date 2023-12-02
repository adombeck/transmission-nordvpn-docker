#!/bin/bash

set -eu

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
DOWNLOADS_DIR="$HOME/torrents"
SYSTEMD_DATA_DIR="$HOME/.local/share/systemd/user"
APPLICATIONS_DIR="$HOME/.local/share/applications"
CONFIG_DIR="$HOME/.config/transmission-nordvpn"
NORDVPN_SECRETS_FILE="${CONFIG_DIR}/nordvpn-secrets.env"
TRANSMISSION_SECRETS_FILE="${CONFIG_DIR}/transmission-secrets.env"
COMPOSE_FILE="${CONFIG_DIR}/compose.yaml"
TRANSMISSION_REMOTE_CONFIG_FILE="$HOME/.config/transmission-remote-gtk/config.json"
SUDOERS_FILE="/etc/sudoers.d/transmission-nordvpn-containers"
BUILD_DIR=$(mktemp -d -t transmission-nordvpn-XXXXXX)

# Cleanup on exit
function cleanup {
  if [ -n "${SKIP_CLEANUP:-}" ]; then
    return
  fi
  rm -rf "${BUILD_DIR}"
}
trap cleanup EXIT

# Check if the docker-compose command is available
if command -v docker-compose > /dev/null 2>&1; then
  DOCKER_COMPOSE=$(command -v docker-compose)
elif docker compose version > /dev/null 2>&1; then
  DOCKER_COMPOSE="$(command -v docker) compose"
else
  echo "Neither 'docker-compose' nor 'docker compose' are available."
  exit 1
fi
DOCKER_COMPOSE="${DOCKER_COMPOSE} --file ${COMPOSE_FILE}"

echo "Checking if the docker socket is accessible..."
if docker info > /dev/null 2>&1; then
  echo "Docker socket is accessible."
else
  echo "Docker socket not accessible. Trying with sudo..."
  if ! sudo docker info > /dev/null 2>&1; then
    echo "Docker socket not accessible."
    exit 1
  fi

  echo "Docker socket is accessible with sudo. A sudoers file will be created to allow starting the containers without a password."

  # Create a sudoers file to allow starting the containers without a password
  TEMPLATE="${SCRIPT_DIR}/data/transmission-nordvpn.sudoers.template"
  TMP_PATH="${BUILD_DIR}/transmission-nordvpn.sudoers"
  sed \
    -e "s|{{DOCKER_COMPOSE}}|${DOCKER_COMPOSE}|g" \
    -e "s|{{USER}}|${USER}|g" \
    "${TEMPLATE}" > "${TMP_PATH}"

  echo "Installing sudoers file to ${SUDOERS_FILE}..."
  # Create the /etc/sudoers.d directory if it doesn't exist
  if [ ! -d /etc/sudoers.d ]; then
    sudo install -d -m 700 /etc/sudoers.d
  fi
  # Install the sudoers file
  sudo install -m 440 "${TMP_PATH}" "${SUDOERS_FILE}"

  # Update the DOCKER_COMPOSE variable to use sudo
  DOCKER_COMPOSE="sudo ${DOCKER_COMPOSE}"
fi

# Create the systemd data dir
mkdir -p "${SYSTEMD_DATA_DIR}"

# Create the containers service file from the template
DEST="${SYSTEMD_DATA_DIR}/transmission-nordvpn-containers.service"
TEMPLATE="${SCRIPT_DIR}/data/transmission-nordvpn-containers.service.template"
TMP_PATH="${BUILD_DIR}/transmission-nordvpn-containers.service"
sed \
  -e "s|{{DOCKER_COMPOSE}}|${DOCKER_COMPOSE}|g" \
  -e "s|{{USER}}|${USER}|g" \
  "${TEMPLATE}" > "${TMP_PATH}"
install -m 600 "${TMP_PATH}" "${DEST}"

# Install the remote-gtk service file
DEST="${SYSTEMD_DATA_DIR}/transmission-nordvpn-remote-gtk.service"
SRC="${SCRIPT_DIR}/data/transmission-nordvpn-remote-gtk.service"
install -m 600 "${SRC}" "${DEST}"

# Install the service files
for service_file in "${SCRIPT_DIR}/data/"*.service; do
  ln -sf "${service_file}" "${SYSTEMD_DATA_DIR}/"
done

echo "Reloading systemd user unit files..."
systemctl --user daemon-reload

# Install the desktop file
SRC="${SCRIPT_DIR}/data/transmission-nordvpn.desktop"
DEST="${APPLICATIONS_DIR}/transmission-nordvpn.desktop"
echo "Installing desktop file to ${DEST}..."
if [ ! -d "${APPLICATIONS_DIR}" ]; then
  install -d -m 700 "${APPLICATIONS_DIR}"
fi
install -m 600 "${SRC}" "${DEST}"

# Create the config dir
install -d -m 700 "${CONFIG_DIR}"

# Create the compose.yaml file from the template
TEMPLATE="${SCRIPT_DIR}/data/compose.yaml.template"
TMP_PATH="${BUILD_DIR}/compose.yaml"
sed \
  -e "s|{{CONFIG_DIR}}|${CONFIG_DIR}|g" \
  -e "s|{{DOWNLOADS_DIR}}|${DOWNLOADS_DIR}|g" \
  "${TEMPLATE}" > "${TMP_PATH}"
install -m 600 "${TMP_PATH}" "${COMPOSE_FILE}"

# Ask for the NordVPN token if it's not already stored
if ! grep -q "TOKEN=" "${NORDVPN_SECRETS_FILE}"; then
  read -r -p "Enter NordVPN token: " token
  echo "TOKEN=${token}" > "${NORDVPN_SECRETS_FILE}"
fi

# Try to read the transmission password from the config file
if grep -q "PASS=" "${TRANSMISSION_SECRETS_FILE}"; then
  TRANSMISSION_PASSWORD="$(grep "PASS=" "${TRANSMISSION_SECRETS_FILE}" | cut -d= -f2)"
else
  echo "Generating random password for transmission user"
  TRANSMISSION_PASSWORD="$(base64 < /dev/urandom | head -c32)"

  echo "Storing transmission password in ${TRANSMISSION_SECRETS_FILE}"
  echo "USER=user" >> "${TRANSMISSION_SECRETS_FILE}"
  echo "PASS=${TRANSMISSION_PASSWORD}" >> "${TRANSMISSION_SECRETS_FILE}"
fi

echo "Checking if transmission-remote-gtk config file exists..."
if [ -f "${TRANSMISSION_REMOTE_CONFIG_FILE}" ]; then
  echo "A transmission-remote-gtk config file already exists. You can keep it and configure the password manually, or overwrite it with a new config file that has the password already set.
Please make sure that transmission-remote-gtk isn't running when you choose to overwrite the config file."
  read -r -p "Overwrite existing config file? [y/N] " overwrite
  if [ "${overwrite}" != "y" ]; then
    exit
  fi
fi

# Create a transmission-remote-gtk config file with the password
echo "Creating transmission-remote-gtk config file..."
install -d -m 700 "$(dirname "${TRANSMISSION_REMOTE_CONFIG_FILE}")"
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
