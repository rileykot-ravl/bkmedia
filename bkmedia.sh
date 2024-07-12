#!/bin/bash

# Load locations from file
if [ ! -f "locations.cfg" ]; then
  echo "Error: locations.cfg file not found"
  exit 1
fi
locations=($(tr -d '\r' < locations.cfg))

# Function to sync media to a server
sync_to_server() {
  host=$1
  path=$2
  echo "Syncing media to ${host}:${path}"
  scp -r ./media/* ${host}:${path}/
}

# Function to calculate checksum
calculate_checksum() {
  local file=$1
  sha256sum "$file" | cut -d' 'f1
}

# Function to write checksums to a file
write_checksums() {
  local dir=$1
  local checksum_file=$2

  > "$checksum_file"  # Clear the checksum file

  for file in "$dir"/*; do
    if [ -f "$file" ]; then
      checksum=$(calculate_checksum "$file")
      echo "$file:$checksum" >> "$checksum_file"
    fi
  done
}

# Function to display locations
display_locations() {
  for ((i=0; i<${#locations[@]}; i++)); do
    echo "$((i+1))) ${locations[$i]}"
  done
}

# Function to create a timestamped backup for a specific location
backup_specific() {
    if [ -z "$1" ]; then
        echo "Error: Location not specified"
        exit 1
    fi
    if [ -z "$2" ]; then
        timestamp=$(date +"%Y-%m-%d-%H:%M:%S")
    fi
    if [ $1 -lt 1 ] || [ $1 -gt ${#locations[@]} ]; then
        echo "Error: Invalid location index"
        exit 1
    fi

    index=$1
    location=${locations[$index-1]}
    host=${location%:*}
    path=${location#*:}
    backup_path="${path}/../backup/${timestamp}"
    
    local_checksum_file="./media/checksums.txt"
    log_file="phantom_log.txt"

    # Calculate checksums on local machine
    find ./media -type f -exec sha256sum {} \; > $local_checksum_file

    # Read server checksum file
    remote_checksums=$(ssh ${host} "cat ${path}/checksums.txt")

    # Loop through local checksum file
    while IFS= read -r line; do
        local_checksum=$(echo "$line" | awk '{print $1}')
        file=$(echo "$line" | awk '{print $2}')
        
        # Get the remote checksum for the file
        remote_checksum=$(grep "$file" <<< "$remote_checksums" | awk '{print $1}')
        
        if [ "$local_checksum" != "$remote_checksum" ]; then
            echo "Discrepancy found for $file"
            # Log the discrepancy in any case
            echo "File: $file" >> $log_file
            echo "Original Checksum: $remote_checksum" >> $log_file
            echo "New Checksum: $local_checksum" >> $log_file
            echo "---------------------------" >> $log_file
        else
            echo "Checksums match for $file"
        fi
    done < $local_checksum_file

    sync_to_server $host $path
    echo "Creating backup at ${host}:${backup_path}"
    ssh ${host} "mkdir -p ${backup_path}"
    ssh ${host} "cp -r ${path}/* ${backup_path}/"
}

# Function to create a timestamped backup on all servers
backup_all() {
    timestamp=$(date +"%Y-%m-%d-%H:%M:%S")

    for ((i=1; i<=${#locations[@]}; i++)); do
        backup_specific $i $timestamp
    done
}

# Function to fetch recent backups and remove duplicates
get_recent_backups() {
  backup_indices=()
  backup_hosts=()
  unique_backups=()

  for location in "${locations[@]}"; do
    host=${location%:*}
    path=${location#*:}

    recent_backups=$(ssh ${host} "ls -t ${path}/../backup | head -n 5 | sort -u -r")
    
    if [ -z "$recent_backups" ]; then
      echo "No backups found for ${host}:${path}"
    else
      while read -r backup; do
        if ! [[ " ${unique_backups[@]} " =~ " ${backup} " ]]; then
          unique_backups+=("$backup")
          backup_indices+=("$backup")
          backup_hosts+=("$host")
        fi
      done <<< "$recent_backups"
    fi
  done
  backup_indices=("${backup_indices[@]:0:5}")
  backup_hosts=("${backup_hosts[@]:0:5}")
}

# Function to display recent backups
display_recent_backups() {
  get_recent_backups
  for ((i=0; i<${#backup_indices[@]}; i++)); do
    echo "$((i+1))) ${backup_indices[$i]} (${backup_hosts[$i]})"
  done
}

# Function to display each server location and their backups
display_all_server_backups() {
  for location in "${locations[@]}"; do
    host=${location%:*}
    path=${location#*:}

    echo "Backups for ${host}:${path}"
    ssh ${host} "ls -t ${path}/../backup | sort -u -r" | nl -n ln -w2 -s') '
    echo
  done
}

# Function to restore a specific backup from the most recent backups
restore_backup() {
  if [ -z "$1" ]; then
    echo "Error: Backup ID not specified"
    exit 1
  fi
  if [ -z "$2" ]; then
    echo "Error: Location not specified"
    exit 1
  fi
  backup_id=$1
  location=$2

  host=${location%:*}
  path=${location#*:}
  restore_path="${path}/../backup/${backup_id}"
  local_path="./media"
  
  rm -rf ${local_path}/*  
  echo "Restoring backup ${backup_id} from ${host}:${restore_path} to ${local_path}"
  scp -r ${host}:${restore_path}/* ${local_path}/
  sync_to_server $host $path
}

# Main Script
if [ $# -eq 0 ]; then
  display_locations
  exit 1
else
  action=""
  location_arg=""
  backup_index=""
  restore_flag=false
  restore_arg=""
  location_flag=false
  location_arg=""
  
  while getopts "BRL" opt; do
    case $opt in
      B)
        action="backup"
        ;;
      R)
        action="restore"
        eval nextopt=\${$OPTIND}
        if [ -n "$nextopt" ] && [[ "$nextopt" != -* ]]; then
          OPTIND=$((OPTIND + 1))
          restore_flag=true
          restore_arg=$nextopt
        fi
        ;;
      L)
        location_flag=true
        eval nextopt=\${$OPTIND}
        if [ -n "$nextopt" ] && [[ "$nextopt" != -* ]]; then
          OPTIND=$((OPTIND + 1))
          location_arg=$nextopt
        fi
        ;;
      *)
        echo "Usage: $0 [-B] [-R [<backup_index>]] [-L <line_number>]"
        exit 1
        ;;
    esac
  done

  if [ "$action" = "backup" ]; then
    if [ -n "$location_arg" ]; then
      backup_specific "$location_arg"
    else
      backup_all
    fi
  elif [ "$action" = "restore" ]; then
    if [ "$restore_flag" = false ]; then
      display_recent_backups
    else
      if [ "$location_flag" = false ]; then
        get_recent_backups
        if [ "$restore_arg" -ge 1 ] && [ "$restore_arg" -le "${#backup_indices[@]}" ]; then
          backup_id=${backup_indices[$restore_arg-1]}
          host=${backup_hosts[$restore_arg-1]}
          
          for location in "${locations[@]}"; do
            if [[ "$location" == "$host"* ]]; then
              restore_backup "$backup_id" "$location"
              exit 0
            fi
          done
          echo "Error: Backup $restore_arg not found on any server"
          exit 1
        else
          echo "Error: Invalid backup index $restore_arg"
          exit 1
        fi
      else
        if [[ "$location_arg" =~ ^[0-9]+$ ]] && [ "$location_arg" -ge 1 ] && [ "$location_arg" -le "${#locations[@]}" ]; then
            location_index=$(($location_arg - 1))
            selected_location=${locations[$location_index]}
            
            get_recent_backups
            
            if [[ "$restore_arg" =~ ^[0-9]+$ ]] && [ "$restore_arg" -ge 1 ] && [ "$restore_arg" -le 5 ]; then
                backup_id=$(ssh ${selected_location%:*} "ls -t ${selected_location#*:}/../backup | sort -u -r | sed -n ${restore_arg}p")
                restore_backup "$backup_id" "$selected_location"
                exit 0
            else
                echo "Error: Invalid backup index $restore_arg"
                exit 1
            fi
        else
            display_all_server_backups
        fi
      fi
    fi
  fi
fi