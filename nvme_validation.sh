#!/bin/bash

# Script Name: nvme_validation.sh 
# Description: This script is responsible for testing and validation all nvme drives and logging data in a structured format
# Author: Gurpreet Singh 

# =================
# Colors & Styles
# =================

NC=$'\033[0m'
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'

# =================
# Global Variables 
# =================

TOTAL_TESTS=0
PASSED=0
FAILED=0
WARNINGS=0
WIDTH=120
LOG_DIR="/var/tmp/hw-validation"
TIMESTAMP=$(date +"%m-%d-%y_%H:%M:%S")
SCRIPT_NAME=$(basename $0 .sh)
LOG_FILE="${SCRIPT_NAME}_${TIMESTAMP}.log"
LOG_FILE_PATH="${LOG_DIR}/${SCRIPT_NAME}_${TIMESTAMP}.log"

# =================
# Dependencies 
# =================

PACKAGES=("ipmitool" "nvme-cli" "smartmontools" "fio" "jq" "bc")

# ==================
# Safety Flags
# ==================

set -u pipefail

# ==================
# Helper Functions
# ==================

# Functions to print color coded statuses to the terminal 

function error()
{
    echo -e "${RED}$1${NC}"
}

function success()
{
    echo -e "${GREEN}$1${NC}"
}

function warn()
{
    echo -e "${YELLOW}$1${NC}"
}

function info()
{
    echo -e "${BLUE}$1${NC}"
}

function footer_space()
{
    echo -e "\n"
}

function get_product_name()
{
    echo `sudo dmidecode -t system |
          grep "Product Name" |
          cut -d ":" -f 2 |
          sed -e 's/^[ ]*//'`
}

# This function will generate the header and display to the console
function generate_header()
{
    TEST_NAME="NVMe Drive Validation"
    PADDING=$(( ($WIDTH - ${#TEST_NAME}) / 2 ))
    
    OS_RELEASE="/etc/os-release"
    source "$OS_RELEASE"

    KERNEL_VERSION=$(uname -r)
    HOSTNAME=$(hostname)
    DETECTED_PLATFORM=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n 1)
    BMC_FIRMWARE=$(ipmitool mc info 2>/dev/null | grep -i "Firmware Revision" | awk '{print $4}' || echo "N/A")
    BIOS_VERSION=$(dmidecode -s bios-version || echo "N/A")
    SERIAL_NUMBER=$(dmidecode -s system-serial-number || echo "N/A")
    PRODUCT_NAME=$(get_product_name)
    START_TIME=$(date +"%m/%d/%y %H:%M:%S")

    printf '%*s\n' "$WIDTH" '' | tr ' ' '='
    printf "%${PADDING}s%s\n" "" "$TEST_NAME"
    printf '%*s\n' "$WIDTH" '' | tr ' ' '='
    printf "%-15s : %s\n" "Product" "$PRODUCT_NAME"
    printf "%-15s : %s\n" "Platform" "$DETECTED_PLATFORM"
    printf "%-15s : %s\n" "Serial Number" "$SERIAL_NUMBER"
    printf "%-15s : %s\n" "OS" "$PRETTY_NAME (kernel $KERNEL_VERSION)"
    printf "%-15s : %s\n" "BMC FW" "$BMC_FIRMWARE"
    printf "%-15s : %s\n" "BIOS Version" "$BIOS_VERSION"
    printf "%-15s : %s\n" "Host" "$HOSTNAME"
    printf "%-15s : %s\n" "Start Time" "$START_TIME"
    printf '%*s\n' "$WIDTH" '' | tr ' ' '='
    echo
}

# This function will generate the test summary and display to the console

function generate_summary()
{    
    TEST_NAME="SUMMARY"
    PADDING=$(( ($WIDTH - ${#TEST_NAME}) / 2 ))
    
    RESULT=$([[ "$FAILED" -ne 0 ]] && echo "FAIL" || echo "PASS")
    END_TIME=$(date +"%m/%d/%y %H:%M:%S")

    printf '%*s\n' "$WIDTH" '' | tr ' ' '='
    printf "%${PADDING}s%s\n" "" "$TEST_NAME"
    printf '%*s\n' "$WIDTH" '' | tr ' ' '='
    printf "%-15s : %s\n" "Total Tests" "$TOTAL_TESTS"
    printf "%-15s : %s\n" "Passed" "$PASSED"
    printf "%-15s : %s\n" "Failed" "$FAILED"
    printf "%-15s : %s\n" "Result" "$RESULT"
    printf "%-15s : %s\n" "End Time" "$END_TIME"
    printf "%-15s : %s\n" "Log Location" "${LOG_FILE_PATH}"
    printf '%*s\n' "$WIDTH" '' | tr ' ' '='
}

# This function will color code the log entry 

function color_code_log_type()
{
    local TYPE="$1"
    case "$TYPE" in
        PASS) echo -e "${GREEN}${TYPE}${NC}" ;;
        FAIL) echo -e "${RED}${TYPE}${NC}" ;;
        WARN) echo -e "${YELLOW}${TYPE}${NC}" ;;
        INFO) echo -e "${BLUE}${TYPE}${NC}" ;;
    esac
}

function generate_divider()
{
    echo
    printf '%*s\n' "$WIDTH" '' | tr ' ' '-' 
    echo
}

# This function defines the structure of each log entry and increments variables related to test results
# Log Structure in comment below
# [TYPE] [TIMESTAMP] [MODULE] Message

function generate_log() 
{
    local TYPE=$1
    local COLORED_TYPE=$(color_code_log_type "$TYPE")
    local MODULE=$2
    local MSG=$3
    local TIMESTAMP=$(date +"%m/%d/%y %H:%M:%S")

    # This will keep track of PASS/FAIL for all tests
    case "$TYPE" in
    PASS) ((PASSED++)); ((TOTAL_TESTS++));;
    FAIL) ((FAILED++)); ((TOTAL_TESTS++));;
    WARN) ((WARNINGS++));;
    esac

    printf "[%s] [%s] [%s] %s\n" "$COLORED_TYPE" "$TIMESTAMP" "$MODULE" "$MSG"
}

function generate_log_env()
{
    # Generating directory for log file 
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
        chmod 755 "$LOG_DIR"
    fi

    # Generating log file
    touch "$LOG_FILE_PATH"
}

function check_root()
{
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root${NC}"
        echo -e "Example: ${YELLOW} sudo $0${NC}"
        exit 1
    fi
}

function install_dependencies()
{
    # Check for packages prior to header being generated, do dependency check afterwards
    for PACKAGE in "${PACKAGES[@]}"; do 
        if ! dpkg -s "$PACKAGE" &>/dev/null; then
            echo "Package ${PACKAGE} not installed"
            read -p "Dependencies missing, would you like to install now? [yes/no]: " choice
            # if [[ "$CHOICE" = ]]
            
            
            # echo -e ": $PACKAGE"
            # if apt-get -y install "$PACKAGE" &>/dev/null; then
                # echo -e "Package ${PACKAGE} has been installed" 
                # generate_log "INFO" "env_check" "Package ${PACKAGE} has been installed"
            # else
            #     echo -e "Package ${PACKAGE} has not been installed, exiting...." 
            #     # generate_log "FAIL" "env_check" "Package ${PACKAGE} has not been installed, exiting..."
            #     return 1
            # fi
        # else
        #     echo -e "Package ${PACKAGE} is installed"
        #     # generate_log "INFO" "env_check" "Package $PACKAGE is installed" 
        fi
    done
    # generate_log "PASS" "env_check" "All packages have been installed"
}

# ==================
# Test Cases
# ==================

function env_checks()
{
    # This function will take care of environment checks
    # 1. Verify log directory and file has been created
    # 2. All packages have been installed 

    if [[ -d "$LOG_DIR" ]]; then
        generate_log "INFO" "env_check" "Log directory: ${LOG_DIR}"
    fi
    if [[ -f "$LOG_FILE_PATH" ]]; then
        generate_log "INFO" "env_check" "Log file: ${LOG_FILE}"
    fi
    generate_log "PASS" "env_check" "Environment Validation Passed"
    generate_divider
}

# This function is responsible for checking links for the NVMe Drives
function link_checks()
{
    ALL_DRIVES=$(lsblk -dn -o NAME | grep "^nvme")
    NUM_DRIVES=$(echo "${ALL_DRIVES}" | wc -l)
    # echo "Value of NUM_DRIVES: $NUM_DRIVES"
    if [[ "$NUM_DRIVES" -eq 0 ]]; then
        generate_log "FAIL" "link_check" "No NVMe drives detected"
        return 1
    else
        generate_log "INFO" "link_check" "Drives discovered: ${NUM_DRIVES}"
    fi

    for drive in $ALL_DRIVES; do
        DEV="/dev/$drive"
        MODEL=$(lsblk -dn -o MODEL "$DEV")
        SIZE=$(lsblk -dnr -o SIZE "$DEV")
        SERIAL=$(lsblk -dn -o SERIAL "$DEV")

        # echo "This is the current drive: $drive"
        # SYMLINK_PATH="/sys/block/$drive"
        
        PCI_ADDR=$(cat /sys/block/${drive}/device/address || echo "N/A")
        # echo "Current PCI Address: ${PCI_ADDR}"
        LINK_WIDTH=$(cat /sys/block/${drive}/device/device/current_link_width 2>/dev/null || echo "N/A")
        LINK_SPEED=$(cat /sys/block/${drive}/device/device/current_link_speed 2>/dev/null|| echo "N/A")
        MAX_LINK_WIDTH=$(cat /sys/block/${drive}/device/device/max_link_width || echo "N/A")
        MAX_LINK_SPEED=$(cat /sys/block/${drive}/device/device/max_link_speed || echo "N/A")
        # echo "Current Link Width: ${LINK_WIDTH}"
        # echo "Current Link Speed: ${LINK_SPEED}"


        generate_log "INFO" "link_check" "Device: /dev/$drive (${SIZE})"
        generate_log "INFO" "link_check" "Model: ${MODEL}"
        generate_log "INFO" "link_check" "Serial Number: ${SERIAL}"
        generate_log "INFO" "link_check" "PCI Address: ${PCI_ADDR}"

        if [[ "$LINK_WIDTH" -ne "$MAX_LINK_WIDTH" ]]; then
            generate_log "WARN" "link check" "Link Drop Detected"
            generate_log "WARN" "link check" "Current Link Width: ${LINK_WIDTH}  Expected Link Width: ${MAX_LINK_WIDTH}"
        else
            generate_log "INFO" "link_check" "Current Link Width is equal to Maximum Link Width" 
        fi

        if [[ "$LINK_SPEED" != "$MAX_LINK_SPEED" ]]; then
            generate_log "WARN" "link check" "Current Link Speed: ${LINK_SPEED}  Expected Link Speed: ${MAX_LINK_SPEED}"
        else
            generate_log "INFO" "link_check" "Current Link Speed is equal to Maximum Link Speed" 
        fi
        generate_divider
    done
}

function read_write_checks
{
    ALL_DRIVES=($(lsblk -dn -o NAME | grep "^nvme"))
    
    root_src=$(findmnt -no SOURCE /)
    root_disk=$(lsblk -no PKNAME "$root_src") 
    
    for drive in "${ALL_DRIVES[@]}"; do
        DEV_PATH="/dev/${drive}"
        MODEL=$(lsblk -dn -o MODEL "$DEV_PATH")
        
        # OS Drive Safety Protection
        if [[ "$drive" == "$root_disk" ]]; then
            # generate_log "WARN" "read_write_check" "Skipping OS drive: $DEV_PATH"
            continue
        fi

        generate_log "INFO" "read_write_check" "Beginning Read/Write Validation for: $DEV_PATH ($MODEL)"

        # Profile format: Name|RW|BS|Jobs|Depth
        PROFILES=(
            "Seq_Read|read|128k|8|4"
            "Seq_Write|write|128k|8|32"
            "Rand_Read|randread|4k|16|16"
            "Rand_Write|randwrite|4k|16|16"
        )

        for profile in "${PROFILES[@]}"; do
            IFS="|" read -r NAME RW BS JOBS DEPTH <<< "$profile"
            JSON_OUT="${LOG_DIR}/${drive}_${NAME}.json"

            # Execute FIO silently
            fio --name="$NAME" --filename="$DEV_PATH" --rw="$RW" --bs="$BS" \
                --numjobs="$JOBS" --iodepth="$DEPTH" --direct=1 --runtime=10 \
                --time_based --group_reporting --size=10G \
                --output-format=json --output="$JSON_OUT" > /dev/null

            if [[ $? -eq 0 && -f "$JSON_OUT" ]]; then
                # 1. Extract raw values using JQ
                # Note: We add read+write bytes/iops so the logic works for any rw pattern
                BW_BYTES=$(jq '.jobs[0].read.bw_bytes + .jobs[0].write.bw_bytes' "$JSON_OUT")
                IOPS=$(jq '.jobs[0].read.iops + .jobs[0].write.iops' "$JSON_OUT")
                LAT_NS=$(jq '.jobs[0].read.clat_ns.percentile["99.000000"] // .jobs[0].write.clat_ns.percentile["99.000000"]' "$JSON_OUT")
                JOB_ERROR=$(jq '.jobs[0].error' "$JSON_OUT")


                # 2. Convert units using bc (scale=2 provides the .00 decimal precision)
                BW_MIB=$(echo "scale=2; $BW_BYTES / 1024 / 1024" | bc)
                LAT_US=$(echo "scale=2; $LAT_NS / 1000" | bc)

                # 3. Format the exact string you requested
                # %'d adds commas to the IOPS for better readability
                IOPS_INT=${IOPS%.*}
                FORMATTED_DATA=$(printf "%s MiB/s | %'d IOPS | Error Count: %s" "$BW_MIB" "$IOPS_INT" "$JOB_ERROR")

                # 4. Pass to your logging function
                generate_log "PASS" "read_write_check" "$NAME Result: $FORMATTED_DATA"
                
                # Cleanup temporary JSON
                rm "$JSON_OUT"
            else
                generate_log "FAIL" "read_write_check" "FIO failed during $NAME profile"
            fi
        done
        generate_divider
    done
}


function smart_checks()
{
    ALL_DRIVES=$(lsblk -dn -o NAME | grep "^nvme")
    for drive in $ALL_DRIVES; do
        
        RESULT=$(smartctl -a /dev/${drive})
        MODEL=$(lsblk -dn -o MODEL "/dev/${drive}")
        SMART_HEALTH_SCORE=$(echo "${RESULT}" | grep -i "self-assessment" | awk '{print $NF}')
        CRITICAL_WARNINGS=$(echo "$RESULT" | grep -i "Critical Warning:" | awk '{print $3}')
        DRIVE_TEMP=$(echo "$RESULT" | grep -i "^Temperature:" | awk '{print $2}')
        MEDIA_DATA_INTEGRITY_ERRORS=$(echo "$RESULT" | grep -i "Media and Data Integrity" | awk '{print $NF}')


        generate_log "INFO" "smart_check" "Device: /dev/${drive}"
        generate_log "INFO" "smart_check" "Model: ${MODEL}"

        
        # echo "SMART_HEALTH_SCORE: ${CRITICAL_WARNINGS}"
        if [[ "${SMART_HEALTH_SCORE}" = "PASSED" ]]; then
            generate_log "PASS" "smart_check" "Smart Health Self-Assessment: ${SMART_HEALTH_SCORE}"
        else
            generate_log "FAIL" "smart_check" "Smart Health Self-Assessment: ${SMART_HEALTH}"
        fi

        # echo "CRITIAL_WARNING: ${CRITICAL_WARNINGS}"
        if [[ "$CRITICAL_WARNINGS" = "0x00" ]]; then
            generate_log "PASS" "smart_check" "Critical Warnings Found: 0"
        else
            generate_log "FAIL" "smart_check" "Device: /dev/${drive} Critical Warning Found, Replace Drive"
        fi
       
        # echo "DRIVE_TEMP: ${DRIVE_TEMP}"
        generate_log "INFO" "smart_check" "Current Drive Temp: ${DRIVE_TEMP}°C"
        if [[ "$DRIVE_TEMP" -lt 70 ]]; then
            generate_log "PASS" "smart_check" "Drive temps don't exceed 70°C"
        else
            generate_log "FAIL" "smart_check" "Drive Temp Exceeds 70°C"
        fi

        # echo "MEDIA_DATA_INTEGRITY_ERRORS: ${MEDIA_DATA_INTEGRITY_ERRORS}"
        if [[ "$MEDIA_DATA_INTEGRITY_ERRORS" -eq 0 ]]; then
            generate_log "PASS" "smart_check" "Media or Data Integrity Errors: 0"
        else
            generate_log "FAIL" "smart_check" "This drive has ${MEDIA_DATA_INTEGRITY_ERRORS} Media or Data Integrity Errors"
        fi
        generate_divider
    done
}

function kernel_log_checks()
{
    generate_log "INFO" "kernel_log_check" "Scanning dmesg for NVMe-related error messages"
    DMESG=$(dmesg)
    IO_ERROR_COUNT=$(echo "${DMESG}" | grep -i "nvme" | grep -ic "i/o error")
    LINK_ERR_COUNT=$(echo "${DMESG}" | grep -i "nvme" | grep -ic "link down")
    
    if [[ "${IO_ERROR_COUNT}" -eq 0 ]]; then
        generate_log "PASS" "kernel_log_check" "No NVMe I/O errors detected in dmesg"
    else
        generate_log "FAIL" "kernel_log_check" "Found ${IO_ERROR_COUNT} NVMe I/O errors in kernel log!"
    fi

    if [[ "${LINK_ERR_COUNT}" -eq 0 ]]; then
        generate_log "PASS" "kernel_log_check" "No NVMe Link Down errors detected"
    else
        generate_log "FAIL" "kernel_log_check" "Found ${LINK_ERROR_COUNT} Link Down events"
    fi
}


# ==================
# Main Execution
# ==================

# 1. Check if the script is being run as root 
# 2. Check if all required packages are installed 
# 3. Generate log file and directory
# 4. Generate header with all required information and append to log file
# 5. Run environment checks
# 6. Run link checks
# 7. Run read_write_checks
# 8. Run smart_checks
# 9. Run kernel_log_checks
# 6. Generate summary with results and append to log file


check_root
install_dependencies
generate_log_env

{
    generate_header
    env_checks
    link_checks
    dmesg -C # Clearing Kernel Buffer Before Running Read & Write Tests
    read_write_checks
    smart_checks
    kernel_log_checks
    generate_summary
} > >(tee -a "$LOG_FILE_PATH")
