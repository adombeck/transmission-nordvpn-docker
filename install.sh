#!/bin/bash

set -eu

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Support --system and --help
if [ "${1:-}" = "--system" ]; then
  SYSTEM_INSTALL=1
  shift
elif [ "${1:-}" = "--help" ]; then
  echo "Usage: $0 [--system]"
  echo
  echo "Options:"
  echo "  --system  Install the systemd service files as systemd units"
  echo "  --help    Show this help message"
  exit 0
fi

# Installing system-wide requires root privileges
if [ -n "${SYSTEM_INSTALL:-}" ] && [ "$(id -u)" != "0" ]; then
  echo "The --system option requires root privileges."
  exit 1
fi

# A user service should not be installed as root
if [ -z "${SYSTEM_INSTALL:-}" ] && [ "$(id -u)" = "0" ]; then
  echo "Run this script as a non-root user or use the --system option."
  exit 1
fi

cleanup() {
  if [ -n "${SKIP_CLEANUP:-}" ]; then
    return
  fi
  rm -rf "${BUILD_DIR}"
}

install_() {
  BUILD_DIR=$(mktemp -d -t transmission-nordvpn-XXXXXX)

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

  # Create the compose.yaml file from the template
  TEMPLATE="${SCRIPT_DIR}/data/compose.yaml.template"
  COMPOSE_FILE_SRC="${BUILD_DIR}/compose.yaml"
  sed \
    -e "s|{{CONFIG_DIR}}|${CONFIG_DIR}|g" \
    -e "s|{{DOWNLOADS_DIR}}|${DOWNLOADS_DIR}|g" \
    "${TEMPLATE}" > "${COMPOSE_FILE_SRC}"

  # Check if the docker socket is accessible. If it's not, we try with sudo.
  # If that works, we create a sudoers file to allow starting the containers
  # without a password.
  echo "Checking if the docker socket is accessible..."
  if docker info > /dev/null 2>&1; then
    echo "Docker socket is accessible."

    # Install the compose file to the user config dir, because the docker
    # socket is accessible without sudo so we don't need to create a sudoers
    # file and care about privilege escalation.
    install -d -m 700 "$(dirname "${COMPOSE_FILE}")"
    install -m 600 "${COMPOSE_FILE_SRC}" "${COMPOSE_FILE}"
  else
    # Don't try to use sudo if we're already root
    if [ "$(id -u)" = "0" ]; then
      echo "Docker socket not accessible."
      exit 1
    fi

    echo "Docker socket not accessible. Trying with sudo..."
    if ! sudo docker info > /dev/null 2>&1; then
      echo "Docker socket not accessible."
      exit 1
    fi

    echo "Docker socket is accessible with sudo. A sudoers file will be created to allow starting the containers without a password."

    # Create a sudoers file to allow starting the containers without a password
    TEMPLATE="${SCRIPT_DIR}/data/transmission-nordvpn.sudoers.template"
    SUDOERS_FILE_SRC="${BUILD_DIR}/transmission-nordvpn.sudoers"
    sed \
      -e "s|{{DOCKER_COMPOSE}}|${DOCKER_COMPOSE}|g" \
      -e "s|{{USER}}|${USER}|g" \
      "${TEMPLATE}" > "${SUDOERS_FILE_SRC}"

    # When we allow the non-root user to run docker-compose without a
    # password, we need to make sure that the compose file is only writable
    # by root.
    COMPOSE_FILE="/var/lib/transmission-nordvpn/compose.yaml"
    echo "Installing Docker compose file to ${COMPOSE_FILE}..."
    install -d -m 700 "$(dirname "${COMPOSE_FILE}")"
    sudo install -m 600 "${COMPOSE_FILE_SRC}" "${COMPOSE_FILE}"

    echo "Installing sudoers file to ${SUDOERS_FILE}..."
    # Create the /etc/sudoers.d directory if it doesn't exist
    if [ ! -d /etc/sudoers.d ]; then
      sudo install -d -m 700 /etc/sudoers.d
    fi
    # Install the sudoers file
    sudo install -m 440 "${SUDOERS_FILE_SRC}" "${SUDOERS_FILE}"

    # Update the DOCKER_COMPOSE variable to use sudo
    DOCKER_COMPOSE="sudo ${DOCKER_COMPOSE}"
  fi

  # Update the DOCKER_COMPOSE variable to use the compose file
  DOCKER_COMPOSE="${DOCKER_COMPOSE} --file ${COMPOSE_FILE}"
  
  # Create the systemd data dir
  mkdir -p "${SYSTEMD_DATA_DIR}"
  
  # Create the containers service file from the template
  DEST="${SYSTEMD_DATA_DIR}/transmission-nordvpn-containers.service"
  TEMPLATE="${SCRIPT_DIR}/data/transmission-nordvpn-containers.service.template"
  TMP_FILE="${BUILD_DIR}/transmission-nordvpn-containers.service"
  sed \
    -e "s|{{DOCKER_COMPOSE}}|${DOCKER_COMPOSE}|g" \
    -e "s|{{USER}}|${USER}|g" \
    "${TEMPLATE}" > "${TMP_FILE}"
  install -m 600 "${TMP_FILE}" "${DEST}"
  
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
  
  # Create the downloads dir
  install -d -m 700 "${DOWNLOADS_DIR}"
  
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
}


create_transmission_remote_config() {
  echo "Checking if transmission-remote-gtk config file exists..."

  TRANSMISSION_REMOTE_CONFIG_FILE="${CONFIG_DIR}/transmission-remote-gtk/config.json"
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
}

system_install() {
  echo "Installing system-wide..."

  DOWNLOADS_DIR="/var/lib/transmission-nordvpn/downloads"
  SYSTEMD_DATA_DIR="/usr/local/lib/systemd/system"
  APPLICATIONS_DIR="/usr/local/share/applications"
  CONFIG_DIR="/etc/transmission-nordvpn"
  NORDVPN_SECRETS_FILE="${CONFIG_DIR}/nordvpn-secrets.env"
  TRANSMISSION_SECRETS_FILE="${CONFIG_DIR}/transmission-secrets.env"
  COMPOSE_FILE="${CONFIG_DIR}/compose.yaml"

  install_

  echo "Reloading systemd unit files..."
  systemctl daemon-reload
}

user_install() {
  echo "Installing for the current user..."

  DOWNLOADS_DIR="${XDG_DOWNLOAD_DIR:-$HOME/Downloads}/transmission-nordvpn"
  SYSTEMD_DATA_DIR="$HOME/.local/share/systemd/user"
  APPLICATIONS_DIR="$HOME/.local/share/applications"
  CONFIG_DIR="$HOME/.config/transmission-nordvpn"
  NORDVPN_SECRETS_FILE="${CONFIG_DIR}/nordvpn-secrets.env"
  TRANSMISSION_SECRETS_FILE="${CONFIG_DIR}/transmission-secrets.env"
  COMPOSE_FILE="${CONFIG_DIR}/compose.yaml"
  SUDOERS_FILE="/etc/sudoers.d/transmission-nordvpn-containers"

  install_

  # Install the remote-gtk service file
  DEST="${SYSTEMD_DATA_DIR}/transmission-nordvpn-remote-gtk.service"
  SRC="${SCRIPT_DIR}/data/transmission-nordvpn-remote-gtk.service"
  install -m 600 "${SRC}" "${DEST}"

  echo "Reloading systemd user unit files..."
  systemctl --user daemon-reload

  create_transmission_remote_config
}

if [ -n "${SYSTEM_INSTALL:-}" ]; then
  system_install
else
  user_install
fi
