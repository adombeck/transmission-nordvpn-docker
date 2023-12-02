# transmission-nordvpn

Run nordvpn and transmission-daemon in Docker containers to download torrents via NordVPN.

## Requirements

* transmission-remote-gtk (if you want to use the GUI)
* Docker

## Installation

Run the `install.sh` script.

## Usage

Start the "Transmission Nordvpn" app. This will start the containers in
the background and open transmission-remote-gtk once the containers are
ready.

The app should automatically connect to the transmission daemon running
in the container.

When you close the app, the containers are automatically stopped.

To just start the containers and not use transmission-remote-gtk, run:

```bash
systemctl --user start transmission-nordvpn-containers.service
```
