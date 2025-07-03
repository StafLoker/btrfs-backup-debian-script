#!/bin/bash

# Color Definitions
readonly RED='\033[31m'
readonly YELLOW='\033[33m'
readonly GREEN='\033[32m'
readonly PURPLE='\033[36m'
readonly RESET='\033[0m'

# Function to print INFO messages
log_info() {
    echo -e "${YELLOW}[INFO] $1${RESET}"
}

# Function to print SUCCESS messages
log_success() {
    echo -e "${GREEN}[SUCCESS] $1${RESET}"
}

# Function to print ERROR messages
log_error() {
    echo -e "${RED}[ERROR] $1${RESET}"
}

# Function to print WARNING messages
log_warning() {
    echo -e "${PURPLE}[WARNING] $1${RESET}"
}

check_dependencies() {
    for cmd in curl sed yq; do
        if ! command -v $cmd &>/dev/null; then
            log_error "$cmd is not installed. Please install it and try again."
            return 1
        fi
    done
    return 0
}

main() {
    if ! check_dependencies; then
        exit 1
    fi
    
    
}

main
