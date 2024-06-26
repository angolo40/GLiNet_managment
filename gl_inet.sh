#!/bin/bash

# Initial Variables
username='root'
password='password'
host='192.168.8.1'

# Determine the log file path based on an environment variable
log_file="${GL_INET_LOG_FILE:-/config/scripts/log_glinet.txt}"

# Create the log directory if it doesn't exist
mkdir -p "$(dirname "$log_file")"

# Logging function
log() {
  echo "$(date) - $1" >> $log_file
}

log "Script started with arguments: $@"

# Function to trim whitespace
trim() {
  echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Initial crypto function
response=$(curl -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"challenge","params": {"username": "'$username'"},"id": 0}' http://$host/rpc -s)

# Extract relevant details from json
alg=$(jq -n "$response" | jq '.result.alg' | tr -d '"')
salt=$(jq -n "$response" | jq '.result.salt' | tr -d '"')
nonce=$(jq -n "$response" | jq '.result.nonce' | tr -d '"')

# Create cipherPassword
cipherpassword=$(mkpasswd -m md5 -S "$salt" "$password")

# Construct hash
hash=$(echo -n "$username:$cipherpassword:$nonce" | md5sum | cut -d' ' -f1)

# Get SID to run API commands
sid=$(curl -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"login","params": {"username": "'$username'", "hash": "'$hash'"},"id": 0}' http://$host/rpc -s | jq '.result.sid' | tr -d '"')

# Function to make RPC calls
rpc_call() {
  log "Calling RPC with data: $2"
  curl -X POST -H 'Content-Type: application/json' -d "$2" http://$host/rpc -s
}

# Function to control VPN
control_vpn() {
  local action=$1 vpn_type=$2 group_id=$3 client_id=$4 peer_key=$5
  rpc_call "$vpn_type" '{
    "jsonrpc": "2.0",
    "method": "call",
    "params": ["'"$sid"'","'"$vpn_type"'-client","'"$action"'",{"group_id": '"$group_id"',"'"$peer_key"'": '"$client_id"'}],
    "id": 1
  }'
}

# Function to stop all VPNs
stop_all_vpns() {
  log "Stopping all VPNs"
  for vpn_type in ovpn wg; do
    status=$(get_vpn_status "$vpn_type")
    status_value=$(echo $status | jq '.result.status')
    if [ "$status_value" == "1" ]; then
      group_id=$(echo $status | jq '.result.group_id')
      peer_key=$( [ "$vpn_type" == "wg" ] && echo 'peer_id' || echo 'client_id' )
      client_id=$(echo $status | jq ".result.$peer_key")
      control_vpn "stop" "$vpn_type" "$group_id" "$client_id" "$peer_key"
      log "Stopped $vpn_type with group_id: $group_id, client_id: $client_id"
    fi
  done
}

# Function to get VPN status
get_vpn_status() {
  log "Getting VPN status for: $1"
  curl -X POST -H 'Content-Type: application/json' -d '{"jsonrpc": "2.0", "method": "call", "params": ["'"$sid"'","'"$1"'-client","get_status",{}], "id": 1}' http://$host/rpc -s
}

# Function to print active VPN
print_active_vpn() {
  log "Printing active VPN"
  for vpn_type in ovpn wg; do
    status=$(get_vpn_status "$vpn_type")
    status_value=$(echo $status | jq '.result.status')
    [ "$status_value" == "1" ] && echo $status | jq ".result" && return
  done
  echo '{"status": 0, "group_id": null, "client_id": null, "peer_id": null, "rx_bytes": null, "tx_bytes": null, "name": null, "ipv4": null, "domain": null}'
}

# Function to call system-related RPCs
system_call() {
  curl -X POST -H 'Content-Type: application/json' -d '{"jsonrpc": "2.0", "method": "call", "params": ["'"$sid"'","system","'"$1"'",{}], "id": 1}' http://$host/rpc -s | jq ".result"
}

get_system_status() { log "Getting system status"; system_call "get_status"; }

get_system_info() { log "Getting system info"; system_call "get_info"; }

get_system_reboot() { log "Rebooting system"; system_call "reboot"; }

get_disk_info() { log "Getting disk info"; system_call "disk_info"; }

check_firmware_online() { log "Checking firmware online"; system_call "check_firmware_online"; }

# Function to get all VPN configurations
get_all_config() {
  log "Getting all $1 configs"
  rpc_call "$1" '{"jsonrpc": "2.0", "method": "call", "params": ["'"$sid"'","'"$1"'-client","get_all_config_list",{}], "id": 1}' | jq .
}

# Function to initialize VPN configurations
initialize_vpn_configs() {
  local wg_configs=$(rpc_call "wg" '{"jsonrpc": "2.0", "method": "call", "params": ["'"$sid"'","wg-client","get_all_config_list",{}], "id": 1}')
  local ovpn_configs=$(rpc_call "ovpn" '{"jsonrpc": "2.0", "method": "call", "params": ["'"$sid"'","ovpn-client","get_all_config_list",{}], "id": 1}')

  vpn_names=() group_ids=() client_ids=() vpn_types=()

  log "WireGuard configurations: $wg_configs"
  log "OpenVPN configurations: $ovpn_configs"

  # Read WireGuard configurations
  for row in $(echo "${wg_configs}" | jq -r '.result.config_list[] | @base64'); do
    group_name=$(echo "${row}" | base64 -d | jq -r '.group_name')
    group_id=$(echo "${row}" | base64 -d | jq -r '.group_id')
    for peer in $(echo "${row}" | base64 -d | jq -r '.peers[] | @base64'); do
      vpn_name=$(echo "${peer}" | base64 -d | jq -r '.name')
      peer_id=$(echo "${peer}" | base64 -d | jq -r '.peer_id')
      vpn_names+=("$vpn_name (WireGuard)")
      group_ids+=("$group_id")
      client_ids+=("$peer_id")
      vpn_types+=("wg")
      log "Added WireGuard VPN: $vpn_name, Group ID: $group_id, Peer ID: $peer_id"
    done
  done

  # Read OpenVPN configurations
  for row in $(echo "${ovpn_configs}" | jq -r '.result.config_list[] | @base64'); do
    group_name=$(echo "${row}" | base64 -d | jq -r '.group_name')
    group_id=$(echo "${row}" | base64 -d | jq -r '.group_id')
    for client in $(echo "${row}" | base64 -d | jq -r '.clients[] | @base64'); do
      vpn_name=$(echo "${client}" | base64 -d | jq -r '.name')
      client_id=$(echo "${client}" | base64 -d | jq -r '.client_id')
      vpn_names+=("$vpn_name (OpenVPN)")
      group_ids+=("$group_id")
      client_ids+=("$client_id")
      vpn_types+=("ovpn")
      log "Added OpenVPN: $vpn_name, Group ID: $group_id, Client ID: $client_id"
    done
  done
}

# Function to display dynamic menu
dynamic_menu() {
  initialize_vpn_configs
  while true; do
    clear
    echo "======= MENU ======="
    echo "Select an option:"
    echo "1) Status"
    echo "2) Stop all VPNs"
    echo "3) Get all WG Config"
    echo "4) Get all OVPN Config"
    echo "5) System Status"
    echo "6) System Info"
    echo "7) Reboot System"
    echo "8) Disk Info"
    echo "9) Check Firmware"
    echo "0) Exit"

    idx=1
    for name in "${vpn_names[@]}"; do
      echo "$((idx+9))) Start $name"
      ((idx++))
    done

    active_vpn=$(print_active_vpn | jq -r '.name')
    [ "$active_vpn" != "null" ] && echo "$((idx+9))) Stop $active_vpn" && active_vpn_option=$((idx+9))

    read -rp "Enter your choice: " choice
    choice=$(trim "$choice")
    [ -z "$choice" ] && log "Invalid option. Please select a valid number." && echo "Invalid option. Please select a valid number." && read -n 1 -s -r -p "Press any key to continue..." && continue

    case $choice in
      1) clear; echo "===== VPN Status ====="; print_active_vpn | jq .; read -n 1 -s -r -p "Press any key to continue...";;
      2) clear; echo "Stopping all VPNs..."; stop_all_vpns; echo "All VPNs stopped."; read -n 1 -s -r -p "Press any key to continue...";;
      3) clear; echo "===== WireGuard Configurations ====="; get_all_config wg; read -n 1 -s -r -p "Press any key to continue...";;
      4) clear; echo "===== OpenVPN Configurations ====="; get_all_config ovpn; read -n 1 -s -r -p "Press any key to continue...";;
      5) clear; echo "===== System Status ====="; get_system_status; read -n 1 -s -r -p "Press any key to continue...";;
      6) clear; echo "===== System Info ====="; get_system_info; read -n 1 -s -r -p "Press any key to continue...";;
      7) clear; echo "===== Rebooting System ====="; get_system_reboot; read -n 1 -s -r -p "Press any key to continue...";;
      8) clear; echo "===== Disk Info ====="; get_disk_info; read -n 1 -s -r -p "Press any key to continue...";;
      9) clear; echo "===== Checking Firmware ====="; check_firmware_online; read -n 1 -s -r -p "Press any key to continue...";;
      0) log "Exiting menu."; echo "Exiting..."; exit 0;;
      *)
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 10 ] && [ "$choice" -lt "$((10 + ${#vpn_names[@]}))" ]; then
          idx=$((choice - 9))
          stop_all_vpns
          control_vpn "start" "${vpn_types[$idx-1]}" "${group_ids[$idx-1]}" "${client_ids[$idx-1]}" "peer_id"
          log "VPN ${vpn_names[$idx-1]} started."; echo "VPN ${vpn_names[$idx-1]} started."
          read -n 1 -s -r -p "Press any key to continue..."
        elif [ "$choice" == "$active_vpn_option" ]; then
          stop_all_vpns; log "VPN $active_vpn stopped."; echo "VPN $active_vpn stopped."
          read -n 1 -s -r -p "Press any key to continue..."
        else
          log "Invalid option selected: $choice"; echo "Invalid option. Please select a valid number."
          read -n 1 -s -r -p "Press any key to continue..."
        fi
        ;;
    esac
  done
}

# Function to print valid options
print_valid_options() {
  echo "Invalid option: $1"
  echo "Valid options are:"
  echo "  status"
  echo "  stop"
  echo "  get_all_config_wg"
  echo "  get_all_config_ovpn"
  echo "  get_system_status"
  echo "  get_system_info"
  echo "  get_system_reboot"
  echo "  get_disk_info"
  echo "  check_firmware_online"
  echo "  start_vpn [VPN_NAME]"
  echo "  stop_vpn [VPN_NAME]"
}

# Handle input parameters
if [ $# -eq 0 ]; then
  dynamic_menu
else
  command=$(trim "$1")
  arg=$(trim "$2")
  case "$command" in
    "status") print_active_vpn ;;
    "stop") log "Stopping all VPNs..."; stop_all_vpns; log "All VPNs stopped." ;;
    "get_all_config_wg") echo "===== WireGuard Configurations ====="; get_all_config wg ;;
    "get_all_config_ovpn") echo "===== OpenVPN Configurations ====="; get_all_config ovpn ;;
    "get_system_status") get_system_status ;;
    "get_system_info") get_system_info ;;
    "get_system_reboot") log "===== Rebooting System ====="; get_system_reboot ;;
    "get_disk_info") get_disk_info ;;
    "check_firmware_online") check_firmware_online ;;
    "start_vpn")
      [ -z "$arg" ] && log "Please provide the VPN name to start." && echo "Please provide the VPN name to start." && exit 1
      initialize_vpn_configs
      vpn_name="$arg"
      log "Trying to start VPN with name: $vpn_name"
      idx=0
      found=false
      for name in "${vpn_names[@]}"; do
        log "Checking VPN name: $name"
        if [[ "$name" == *"$vpn_name"* ]]; then
          echo "${vpn_types[$idx]}" "${group_ids[$idx]}" "${client_ids[$idx]}" "peer_id"
          control_vpn "start" "${vpn_types[$idx]}" "${group_ids[$idx]}" "${client_ids[$idx]}" "peer_id"
          log "VPN $name started."; echo "VPN $name started."
          found=true; break
        fi
        ((idx++))
      done
      [ "$found" = false ] && log "VPN $vpn_name not found." && echo "VPN $vpn_name not found."
      ;;
    "stop_vpn")
      [ -z "$arg" ] && log "Please provide the VPN name to stop." && echo "Please provide the VPN name to stop." && exit 1
      vpn_name="$arg"
      log "Stopping VPN with name: $vpn_name"
      idx=0
      found=false
      for name in "${vpn_names[@]}"; do
        log "Checking VPN name: $name"
        if [[ "$name" == *"$vpn_name"* ]]; then
          control_vpn "stop" "${vpn_types[$idx]}" "${group_ids[$idx]}" "${client_ids[$idx]}" "peer_id"
          log "VPN $name stopped."; echo "VPN $name stopped."
          found=true; break
        fi
        ((idx++))
      done
      [ "$found" = false ] && log "VPN $vpn_name not found." && echo "VPN $vpn_name not found."
      ;;
    *) log "Unknown option: $command"; print_valid_options "$1" ;;
  esac
fi
