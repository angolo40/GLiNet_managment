<h1 align="center">Welcome to GL.iNet Router Management Script 👋</h1>
<p>
  <img alt="Version" src="https://img.shields.io/badge/version-1.0-blue.svg?cacheSeconds=2592000" />
  <a href="https://github.com/angolo40/GLiNet_managment" target="_blank">
    <img alt="License: MIT" src="https://img.shields.io/github/license/angolo40/GLiNet_managment" />
  </a>
</p>

## 📋 Introduction

This repository provides a script to manage GL.iNet routers, including controlling VPN connections, obtaining system status, and more. The script supports both WireGuard and OpenVPN configurations. It also provides the possibility to manage the router through Home Assistant.

**Note:** This script is based on the 4.x API of GL.iNet routers. At the time of writing, these APIs are offline and were retrieved using the Wayback Machine: [GL.iNet 4.x API](https://web.archive.org/web/20240106020516/https://dev.gl-inet.com/router-4.x-api/#wifi/get_status).

## 🚀 Installation

1. Set up a fresh environment with necessary dependencies:
   - Ensure you have `curl`, `jq`, and `mkpasswd` installed.
2. Download the script using `wget` and put in HomeAssistant folder /config/scripts/:
   <pre>wget https://raw.githubusercontent.com/angolo40/GLiNet_managment/main/gl_inet.sh -O /config/scripts/gl_inet.sh</pre>
3. Edit the script `gl_inet.sh` with your router's credentials and IP address:
   <pre>nano /config/scripts/gl_inet.sh</pre>
   Modify the following variables:
   <pre>username='root'
password='password'
host='192.168.8.1'</pre>
4. Ensure the script has executable permissions:
   <pre>chmod +x /config/scripts/gl_inet.sh</pre>

## 🛠️ Script Overview

The script supports the following commands:
- **status**: Prints the status of the active VPN.
- **stop**: Stops all active VPN connections.
- **get_all_config_wg**: Retrieves all WireGuard VPN configurations.
- **get_all_config_ovpn**: Retrieves all OpenVPN configurations.
- **get_system_status**: Gets the system status of the router.
- **get_system_info**: Gets detailed system information.
- **get_system_reboot**: Reboots the router.
- **get_disk_info**: Retrieves disk usage information.
- **check_firmware_online**: Checks if a firmware update is available.
- **start_vpn [VPN_NAME]**: Starts a specified VPN.
- **stop_vpn [VPN_NAME]**: Stops a specified VPN.

## 🏠 Home Assistant Integration

To integrate this script with Home Assistant, for example add the following configurations to your `configuration.yaml` file:

<pre>
shell_command:
  glinet_vpn_albania: "bash /config/scripts/gl_inet.sh start_vpn Albania_37_Tirana"
  glinet_vpn_italia: "bash /config/scripts/gl_inet.sh start_vpn Italy_223_Milan"
  glinet_vpn_svizzera: "bash /config/scripts/gl_inet.sh start_vpn Switzerland_373_Zurich"
  glinet_vpn_status: "bash /config/scripts/gl_inet.sh status"
  glinet_vpn_stop: "bash /config/scripts/gl_inet.sh stop"
  glinet_get_system_status: "bash /config/scripts/gl_inet.sh get_system_status"
  glinet_get_system_info: "bash /config/scripts/gl_inet.sh get_system_info"
  glinet_get_system_reboot: "bash /config/scripts/gl_inet.sh get_system_reboot"
  glinet_get_disk_info: "bash /config/scripts/gl_inet.sh get_disk_info"
  glinet_check_firmware_online: "bash /config/scripts/gl_inet.sh check_firmware_online"

command_line:
  - sensor:
      name: "VPN Status"
      command: "bash /config/scripts/gl_inet.sh status"
      scan_interval: 10
      value_template: >-
        {% if value_json.status == 1 %}
          Active
        {% else %}
          Not Active
        {% endif %}
      json_attributes:
        - group_id
        - client_id
        - peer_id
        - rx_bytes
        - tx_bytes
        - name
        - ipv4
        - domain

  - sensor:
      name: "System Status"
      command: "bash /config/scripts/gl_inet.sh get_system_status"
      scan_interval: 600
      value_template: "OK"
      json_attributes:
        - network
        - wifi
        - service
        - client
        - system

  - sensor:
      name: "Disk Info"
      command: "bash /config/scripts/gl_inet.sh get_disk_info"
      scan_interval: 600
      value_template: >-
        {% if value_json.root.free >= 1 %}
          OK
        {% else %}
          NOT OK
        {% endif %}
      json_attributes:
        - root
        - tmp


  - sensor:
      name: "System Info"
      command: "bash /config/scripts/gl_inet.sh get_system_info"
      scan_interval: 600
      value_template: "OK"
      json_attributes:
        - mac
        - disable_guest_during_scan_wifi
        - hardware_version
        - country_code
        - sn_bak
        - software_feature
        - vendor
        - hardware_feature
        - cpu_num
        - board_info
        - firmware_date
        - model
        - ddns
        - sn
        - firmware_type
        - firmware_version

switch:
  - platform: template
    switches:
      vpn_albania:
        friendly_name: "VPN Albania"
        value_template: "{{ state_attr('sensor.vpn_status', 'name') is not none and 'Albania_37_Tirana' in state_attr('sensor.vpn_status', 'name') }}"
        turn_on:
          service: shell_command.glinet_vpn_albania
        turn_off:
          service: shell_command.glinet_vpn_stop
      vpn_italia:
        friendly_name: "VPN Italia"
        value_template: "{{ state_attr('sensor.vpn_status', 'name') is not none and 'Italy_223_Milan' in state_attr('sensor.vpn_status', 'name') }}"
        turn_on:
          service: shell_command.glinet_vpn_italia
        turn_off:
          service: shell_command.glinet_vpn_stop
      vpn_svizzera:
        friendly_name: "VPN Svizzera"
        value_template: "{{ state_attr('sensor.vpn_status', 'name') is not none and 'Switzerland_373_Zurich' in state_attr('sensor.vpn_status', 'name') }}"
        turn_on:
          service: shell_command.glinet_vpn_svizzera
        turn_off:
          service: shell_command.glinet_vpn_stop

script:
  glinet_system_reboot:
    alias: "System Reboot"
    sequence:
      - service: shell_command.glinet_get_system_reboot
  glinet_system_info:
    alias: "System Info"
    sequence:
      - service: shell_command.glinet_get_system_info
  glinet_system_status:
    alias: "System Status"
    sequence:
      - service: shell_command.glinet_get_system_status
  glinet_disk_info:
    alias: "Disk Info"
    sequence:
      - service: shell_command.glinet_get_disk_info
  glinet_check_firmware_online:
    alias: "Check Firmware"
    sequence:
      - service: shell_command.glinet_check_firmware_online
</pre>

## 👤 Author

**Giuseppe Trifilio**

- [Website](https://github.com/angolo40/GLiNet_managment)
- [GitHub](https://github.com/angolo40)

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Check the [issues page](https://github.com/angolo40/GLiNet_managment/issues).

## 🌟 Show Your Support

Give a ⭐️ if this project helped you!

---

### 📝 Note

This README is a work in progress. More details and instructions will be added soon.
