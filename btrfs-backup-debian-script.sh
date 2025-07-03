#!/bin/bash

# Load keys
source .env

readonly DATA_FILE="config.yaml"

# Check if API keys are set
if [[ -z "$TELEGRAM_BOT_KEY" ]]; then
  echo "ERROR: API key is not set. Exiting."
  exit 1
fi

# Check if DATA_FILE exists
if [[ ! -f "$DATA_FILE" ]]; then
  echo "ERROR: Data file $DATA_FILE not found. Exiting."
  exit 1
fi

# Function to log messages
log() {
  local level=$1 message=$2
  case "$level" in
  DEBUG) syslog_level="debug" ;; INFO) syslog_level="info" ;;
  WARNING) syslog_level="warning" ;; ERROR) syslog_level="err" ;;
  *) syslog_level="notice" ;; # Default level
  esac
  logger -p user.$syslog_level -t brtfs-backup "$message"
}

# Main function
main() {
    1. Montar cada particiones para hacer backup
    
    2. 

}

# Entry point
main
