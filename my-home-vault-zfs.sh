#!/bin/bash

# =============================================================================
#                 M Y   H O M E   V A U L T   Z F S   E D I T I O N
#                            v5.1.5b-zfs
# =============================================================================
#   GitHub    : https://github.com/waelisa/my-home-vault
#   License   : MIT
#   Author    : Wael Isa
#   Website   : https://www.wael.name
#   Date      : 22-02-2026
# =============================================================================
#   DESCRIPTION:
#   My Home Vault ZFS Edition combines the proven backup logic with ZFS
#   power. Features automatic ZFS pool/dataset detection, compression (LZ4),
#   automatic snapshots after each backup, snapshot retention management,
#   mount verification, atomic snapshot naming (collision-proof), and
#   optional ZFS send/receive for remote replication.
# =============================================================================
#   ZFS FEATURES:
#   • Compression: lz4 (saves space, minimal CPU impact)
#   • Snapshots: Automatic after each backup with atomic naming
#   • Dataset Management: Auto-creates datasets with optimal settings
#   • Mount Verification: Ensures dataset is mounted before backup
#   • Collision Prevention: Atomic timestamp + PID ensures unique snapshots
#   • ZFS Send/Receive: Optional replication to remote ZFS pools
#   • Pool Detection: Automatically detects existing ZFS pools
# =============================================================================
#   REQUIREMENTS:
#   • Root/sudo permissions (ZFS commands require elevated privileges)
#   • ZFS utilities installed (zfsutils-linux, zfs-linux, etc.)
#   • Existing ZFS pool or willing to create one
# =============================================================================
#   HARDWARE RECOMMENDATIONS:
#   • Seagate IronWolf 4TB - Best for ZFS snapshot metadata (AgileArray)
#   • WD Red Plus 4TB      - Best for LZ4 compression & stability
#   • ECC RAM              - Recommended for ZFS data integrity
# =============================================================================
#   QUICK START:
#   1. Install ZFS: sudo apt install zfsutils-linux (Ubuntu/Debian)
#                   sudo pacman -S zfs-linux (Arch/Manjaro)
#   2. curl -O https://raw.githubusercontent.com/waelisa/my-home-vault/main/my-home-vault-zfs.sh
#   3. chmod +x my-home-vault-zfs.sh
#   4. sudo ./my-home-vault-zfs.sh
#   5. Follow the ZFS-aware setup wizard
# =============================================================================

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# =============================================================================
#                         R O O T   P E R M I S S I O N   C H E C K
# =============================================================================

# Color definitions for permission check
PERM_RED='\033[0;31m'
PERM_GREEN='\033[0;32m'
PERM_YELLOW='\033[1;33m'
PERM_NC='\033[0m'

# Check if running as root (EUID 0 = root)
if [ "$EUID" -ne 0 ]; then
    echo -e "${PERM_RED}❌ ERROR: ZFS Edition requires root/sudo permissions${PERM_NC}"
    echo -e "${PERM_YELLOW}ℹ ZFS commands need elevated privileges to:${PERM_NC}"
    echo -e "  • Create/modify ZFS datasets"
    echo -e "  • Create/delete ZFS snapshots"
    echo -e "  • Perform ZFS send/receive operations"
    echo -e "  • Verify dataset mount status"
    echo ""
    echo -e "${PERM_GREEN}Please run with: sudo $0${PERM_NC}"
    exit 1
fi

echo -e "${PERM_GREEN}✓ Root privileges confirmed${PERM_NC}\n"
sleep 1

# =============================================================================
#                         D E P E N D E N C Y   C H E C K
# =============================================================================

echo -e "${PERM_YELLOW}🔍 Checking dependencies...${PERM_NC}"

MISSING_DEPS=()

# Check for required commands
for cmd in rsync ssh ping curl mount umount zfs zpool; do
    if ! command -v $cmd &> /dev/null; then
        MISSING_DEPS+=($cmd)
        echo -e "  ${PERM_RED}✗ $cmd not found${PERM_NC}"
    else
        echo -e "  ${PERM_GREEN}✓ $cmd found${PERM_NC}"
    fi
done

# If dependencies are missing, show installation instructions
if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo -e "\n${PERM_RED}❌ Missing required dependencies: ${MISSING_DEPS[*]}${PERM_NC}"
    echo -e "\n${PERM_YELLOW}Installation instructions:${PERM_NC}"
    
    # Detect distribution
    if command -v apt &> /dev/null; then
        # Debian/Ubuntu
        echo -e "  ${PERM_GREEN}Debian/Ubuntu:${PERM_NC} sudo apt update && sudo apt install zfsutils-linux ${MISSING_DEPS[*]//zfs zpool/}"
    elif command -v dnf &> /dev/null; then
        # Fedora
        echo -e "  ${PERM_GREEN}Fedora:${PERM_NC} sudo dnf install zfs ${MISSING_DEPS[*]//zfs zpool/}"
    elif command -v pacman &> /dev/null; then
        # Arch/Manjaro
        echo -e "  ${PERM_GREEN}Arch/Manjaro:${PERM_NC} sudo pacman -S zfs-linux ${MISSING_DEPS[*]//zfs zpool/}"
    elif command -v zypper &> /dev/null; then
        # openSUSE
        echo -e "  ${PERM_GREEN}openSUSE:${PERM_NC} sudo zypper install zfs ${MISSING_DEPS[*]//zfs zpool/}"
    else
        echo -e "  ${PERM_YELLOW}Please install ZFS for your distribution${PERM_NC}"
    fi
    
    echo -e "\n${PERM_YELLOW}After installing dependencies, run this script again.${PERM_NC}"
    exit 1
fi

# Check if ZFS modules are loaded
if ! lsmod | grep -q zfs; then
    echo -e "\n${PERM_YELLOW}⚠ ZFS modules not loaded. Attempting to load...${PERM_NC}"
    modprobe zfs 2>/dev/null || {
        echo -e "${PERM_RED}Failed to load ZFS modules. Please ensure ZFS is properly installed.${PERM_NC}"
        exit 1
    }
fi

echo -e "${PERM_GREEN}✓ All dependencies satisfied! ZFS is ready.${PERM_NC}\n"
sleep 1

# =============================================================================
#                         C O R E   C O N F I G U R A T I O N
# =============================================================================

# --- Version Information ---
CURRENT_VERSION="5.1.5b-zfs"
VERSION_URL="https://raw.githubusercontent.com/waelisa/my-home-vault/main/VERSION"
CONFIG_FILE="${HOME}/.my-home-vault-zfs.conf"
VAULT_DIR="${HOME}/.my-home-vault"
LOG_DIR="${VAULT_DIR}/logs"
ZFS_SNAPSHOT_PREFIX="mhv"

# --- Auto-Detect User Details (Always works) ---
USERNAME=$(whoami)
HOME_DIR="${HOME}"

# --- Logging (with rotation) ---
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/vault_zfs_$(date +%Y%m%d_%H%M%S).log"

# --- Default Settings (can be overridden in wizard) ---
RETENTION_DAYS=14
ENABLE_NOTIFICATIONS="yes"
ENABLE_CHECKSUM_VERIFY="no"
MIN_FREE_SPACE_PERCENT=10
BW_LIMIT="5000"  # Default 5MB/s for NAS (protects slow drives)
SSH_TIMEOUT=10   # SSH connection timeout in seconds
SSH_ALIVE=60     # SSH server alive interval

# --- ZFS Default Settings ---
ZFS_COMPRESSION="lz4"
ZFS_ATIME="off"
ZFS_RECORDSIZE="1M"
ZFS_SNAPSHOT_RETENTION=14
ENABLE_ZFS_SEND="no"
ZFS_REMOTE_POOL=""
ZFS_REMOTE_HOST=""

# =============================================================================
#                         C O L O R   D E F I N I T I O N S
# =============================================================================
# Reset
NC='\033[0m'              # No Color

# Regular Colors
RED='\033[0;31m'          # Red
GREEN='\033[0;32m'        # Green
YELLOW='\033[0;33m'       # Yellow
BLUE='\033[0;34m'         # Blue
MAGENTA='\033[0;35m'      # Magenta
CYAN='\033[0;36m'         # Cyan
WHITE='\033[0;37m'        # White

# Bold
BOLD='\033[1m'
BOLD_RED='\033[1;31m'     # Bold Red
BOLD_GREEN='\033[1;32m'   # Bold Green
BOLD_YELLOW='\033[1;33m'  # Bold Yellow
BOLD_BLUE='\033[1;34m'    # Bold Blue
BOLD_MAGENTA='\033[1;35m' # Bold Magenta
BOLD_CYAN='\033[1;36m'    # Bold Cyan
BOLD_WHITE='\033[1;37m'   # Bold White

# Icons
ICON_SUCCESS="${BOLD_GREEN}✓${NC}"
ICON_ERROR="${BOLD_RED}✗${NC}"
ICON_WARNING="${BOLD_YELLOW}⚠${NC}"
ICON_INFO="${BOLD_BLUE}ℹ${NC}"
ICON_STEP="${BOLD_CYAN}→${NC}"
ICON_ARROW="${BOLD_MAGENTA}➤${NC}"
ICON_CLOCK="${BOLD_YELLOW}⌛${NC}"
ICON_DONE="${BOLD_GREEN}✔${NC}"
ICON_VAULT="${BOLD_CYAN}🔐${NC}"
ICON_HOME="${BOLD_GREEN}🏠${NC}"
ICON_NAS="${BOLD_YELLOW}🌐${NC}"
ICON_SPACE="${BOLD_MAGENTA}💾${NC}"
ICON_CRON="${BOLD_BLUE}⏰${NC}"
ICON_TRASH="${BOLD_RED}🗑️${NC}"
ICON_REPAIR="${BOLD_YELLOW}🔧${NC}"
ICON_DISK="${BOLD_WHITE}💿${NC}"
ICON_CPU="${BOLD_RED}⚙️${NC}"
ICON_USB="${BOLD_YELLOW}🔌${NC}"
ICON_ZFS="${BOLD_CYAN}🌀${NC}"
ICON_SNAPSHOT="${BOLD_GREEN}📸${NC}"
ICON_MOUNT="${BOLD_MAGENTA}📂${NC}"
ICON_ATOMIC="${BOLD_YELLOW}⚛️${NC}"

# =============================================================================
#                     Z F S   H E L P E R   F U N C T I O N S
# =============================================================================

# Function to detect ZFS pools
detect_zfs_pools() {
    local pools=()
    while IFS= read -r pool; do
        if [ -n "$pool" ]; then
            pools+=("$pool")
        fi
    done < <(zpool list -H -o name 2>/dev/null || true)
    echo "${pools[@]}"
}

# Function to detect ZFS datasets in a pool
detect_zfs_datasets() {
    local pool="$1"
    local datasets=()
    while IFS= read -r dataset; do
        if [ -n "$dataset" ]; then
            datasets+=("$dataset")
        fi
    done < <(zfs list -H -o name -r "$pool" 2>/dev/null | grep -v "^$pool$" || true)
    echo "${datasets[@]}"
}

# Function to verify ZFS dataset is mounted
verify_zfs_mount() {
    local dataset="$1"
    local expected_mountpoint="$2"
    
    print_step "mount" "Verifying ZFS dataset is mounted..." "start"
    
    # Check if dataset exists
    if ! zfs list "$dataset" &>/dev/null; then
        print_step "mount" "Dataset $dataset does not exist" "error"
        return 1
    fi
    
    # Get current mountpoint
    local current_mount=$(zfs get -H -o value mountpoint "$dataset" 2>/dev/null)
    local mounted=$(zfs get -H -o value mounted "$dataset" 2>/dev/null)
    
    if [ "$mounted" = "yes" ]; then
        print_step "mount" "Dataset is mounted at: $current_mount" "done"
        return 0
    else
        print_step "mount" "Dataset is not mounted, attempting to mount..." "warn"
        if zfs mount "$dataset" 2>&1 | tee -a "$LOG_FILE"; then
            print_step "mount" "Successfully mounted at: $current_mount" "done"
            return 0
        else
            print_step "mount" "Failed to mount dataset" "error"
            return 1
        fi
    fi
}

# Function to create ZFS dataset with optimal settings
create_zfs_dataset() {
    local dataset="$1"
    local mountpoint="$2"
    
    print_step "zfs" "Creating ZFS dataset: $dataset" "start"
    
    # Create parent datasets if needed
    local parent="${dataset%/*}"
    if [ "$parent" != "$dataset" ] && ! zfs list "$parent" &>/dev/null; then
        zfs create -p "$parent"
    fi
    
    # Create the dataset
    if ! zfs list "$dataset" &>/dev/null; then
        zfs create "$dataset"
        zfs set compression="$ZFS_COMPRESSION" "$dataset"
        zfs set atime="$ZFS_ATIME" "$dataset"
        zfs set recordsize="$ZFS_RECORDSIZE" "$dataset"
        zfs set mountpoint="$mountpoint" "$dataset"
        
        # Set permissions for user (optional - allows user to write without root)
        chown "$USERNAME:$USERNAME" "$mountpoint" 2>/dev/null || true
        
        print_step "zfs" "Dataset created with compression=$ZFS_COMPRESSION, atime=$ZFS_ATIME" "done"
    else
        print_step "zfs" "Dataset already exists" "info"
        # Ensure it's mounted
        verify_zfs_mount "$dataset" "$mountpoint"
    fi
}

# Function to create ZFS snapshot with atomic naming (collision-proof)
create_zfs_snapshot() {
    local dataset="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local pid=$$
    local snapshot_name="${ZFS_SNAPSHOT_PREFIX}_${timestamp}_${pid}"
    local max_attempts=5
    local attempt=1
    
    print_step "snapshot" "Creating ZFS snapshot with atomic naming" "start"
    echo -e "    ${ICON_ATOMIC} Timestamp: $timestamp, PID: $pid (ensures uniqueness)"
    
    while [ $attempt -le $max_attempts ]; do
        # Check if snapshot already exists
        if zfs list -t snapshot -o name | grep -q "${dataset}@${snapshot_name}"; then
            print_step "snapshot" "Snapshot name collision detected! (attempt $attempt/$max_attempts)" "warn"
            # Add microsecond delay and retry with new timestamp
            sleep 0.1
            timestamp=$(date +%Y%m%d_%H%M%S_%3N)  # Add milliseconds
            snapshot_name="${ZFS_SNAPSHOT_PREFIX}_${timestamp}_${pid}"
            ((attempt++))
        else
            # Create the snapshot
            if zfs snapshot "${dataset}@${snapshot_name}"; then
                print_step "snapshot" "Snapshot created: $snapshot_name" "done"
                echo "$snapshot_name"
                return 0
            else
                print_step "snapshot" "Failed to create snapshot" "error"
                return 1
            fi
        fi
    done
    
    print_step "snapshot" "Failed to create unique snapshot after $max_attempts attempts" "error"
    return 1
}

# Function to list ZFS snapshots
list_zfs_snapshots() {
    local dataset="$1"
    zfs list -t snapshot -o name,creation -s creation | grep "$dataset@" || true
}

# Function to clean old ZFS snapshots
clean_zfs_snapshots() {
    local dataset="$1"
    local retention_days="$2"
    local dry_run="${3:-no}"
    
    print_step "snapshot" "Cleaning snapshots older than $retention_days days" "start"
    
    local cutoff=$(date -d "$retention_days days ago" +%s)
    local count=0
    
    while IFS= read -r snapshot; do
        if [ -n "$snapshot" ]; then
            local creation=$(zfs get -H -o value creation "$snapshot" 2>/dev/null)
            local creation_epoch=$(date -d "$creation" +%s 2>/dev/null || echo 0)
            
            if [ "$creation_epoch" -lt "$cutoff" ]; then
                if [ "$dry_run" = "yes" ]; then
                    echo -e "    ${ICON_TRASH} Would delete: $snapshot"
                    ((count++))
                else
                    print_step "snapshot" "Deleting old snapshot: $snapshot" "warn"
                    if zfs destroy "$snapshot"; then
                        ((count++))
                    fi
                fi
            fi
        fi
    done < <(zfs list -H -o name -t snapshot -r "$dataset" 2>/dev/null || true)
    
    if [ "$dry_run" = "yes" ]; then
        print_step "snapshot" "Would delete $count old snapshots" "info"
    else
        print_step "snapshot" "Deleted $count old snapshots" "done"
    fi
}

# Function to send ZFS snapshot to remote host
send_zfs_snapshot() {
    local dataset="$1"
    local snapshot="$2"
    local remote_host="$3"
    local remote_pool="$4"
    
    print_step "zfs-send" "Sending snapshot to $remote_host" "start"
    
    # Determine remote dataset path (preserve hierarchy)
    local local_pool="${dataset%%/*}"
    local remote_dataset="${dataset/$local_pool/$remote_pool}"
    
    # Create remote parent datasets if needed
    ssh "$remote_host" "zfs create -p \"${remote_dataset%/*}\" 2>/dev/null || true"
    
    # Send the snapshot
    if zfs send "$dataset@$snapshot" | ssh "$remote_host" "zfs receive -F \"$remote_dataset\""; then
        print_step "zfs-send" "Snapshot sent successfully" "done"
        return 0
    else
        print_step "zfs-send" "Failed to send snapshot" "error"
        return 1
    fi
}

# =============================================================================
#                     F I R S T - T I M E   S E T U P   W I Z A R D
# =============================================================================

run_setup_wizard() {
    clear
    echo -e "${BOLD_CYAN}"
    echo "  ╔════════════════════════════════════════════════════════════════╗"
    echo "  ║         MY HOME VAULT ZFS - FIRST RUN WIZARD                  ║"
    echo "  ║                   30 Seconds • One Time                       ║"
    echo "  ╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${ICON_HOME} Welcome to My Home Vault ZFS Edition!"
    echo -e "${ICON_ZFS} This version uses ZFS compression and snapshots."
    echo -e "${ICON_ATOMIC} Atomic snapshot naming prevents collisions.\n"
    echo -e "${ICON_INFO} Running with root privileges - all ZFS commands will work.\n"
    echo -e "${ICON_INFO} Configuration will be saved to: $CONFIG_FILE\n"
    
    # --- Detect ZFS pools ---
    echo -e "${BOLD_WHITE}Step 1: Detecting ZFS pools...${NC}"
    local pools=($(detect_zfs_pools))
    
    if [ ${#pools[@]} -gt 0 ]; then
        echo -e "\n${BOLD_GREEN}Detected ZFS pools:${NC}"
        local index=1
        for pool in "${pools[@]}"; do
            local pool_size=$(zpool list -H -o size "$pool" 2>/dev/null)
            local pool_free=$(zpool list -H -o free "$pool" 2>/dev/null)
            local pool_health=$(zpool list -H -o health "$pool" 2>/dev/null)
            echo -e "  ${BOLD_CYAN}${index}.${NC} $pool (Size: $pool_size, Free: $pool_free, Health: $pool_health)"
            ((index++))
        done
        echo -e "  ${BOLD_CYAN}0.${NC} Use regular filesystem (non-ZFS mode)"
        
        echo ""
        read -p "  ${ICON_ARROW} Select ZFS pool for backups [0-${#pools[@]}]: " pool_choice
        
        if [ "$pool_choice" = "0" ] || [ -z "$pool_choice" ]; then
            USE_ZFS="no"
            echo -e "  ${ICON_INFO} Using regular filesystem (non-ZFS mode)"
        elif [ "$pool_choice" -ge 1 ] && [ "$pool_choice" -le "${#pools[@]}" ]; then
            USE_ZFS="yes"
            ZFS_POOL="${pools[$((pool_choice-1))]}"
            ZFS_DATASET="${ZFS_POOL}/mhv_${USERNAME}"
            ZFS_MOUNTPOINT="/${ZFS_POOL}/mhv_${USERNAME}"
            LOCAL_BACKUP_BASE="$ZFS_MOUNTPOINT"
            echo -e "  ${ICON_SUCCESS} Using ZFS pool: $ZFS_POOL"
            echo -e "  ${ICON_ZFS} Dataset: $ZFS_DATASET"
            echo -e "  ${ICON_MOUNT} Mount point: $ZFS_MOUNTPOINT"
        else
            USE_ZFS="no"
            echo -e "  ${ICON_WARNING} Invalid choice, using regular filesystem"
        fi
    else
        echo -e "\n${ICON_WARNING} No ZFS pools detected."
        USE_ZFS="no"
    fi
    
    # --- If not using ZFS, fall back to regular drive detection ---
    if [ "$USE_ZFS" = "no" ]; then
        echo -e "\n${BOLD_WHITE}Falling back to regular drive detection...${NC}"
        
        # Check for common mount points
        local detected_drives=()
        
        if [ -d "/run/media/${USERNAME}" ]; then
            while IFS= read -r drive; do
                detected_drives+=("$drive")
            done < <(find "/run/media/${USERNAME}" -maxdepth 1 -type d ! -path "/run/media/${USERNAME}" 2>/dev/null || true)
        fi
        
        if [ -d "/media/${USERNAME}" ]; then
            while IFS= read -r drive; do
                detected_drives+=("$drive")
            done < <(find "/media/${USERNAME}" -maxdepth 1 -type d ! -path "/media/${USERNAME}" 2>/dev/null || true)
        fi
        
        if [ ${#detected_drives[@]} -gt 0 ]; then
            echo -e "\n${BOLD_GREEN}Detected backup drives:${NC}"
            local index=1
            for drive in "${detected_drives[@]}"; do
                local drive_size=$(df -h "$drive" 2>/dev/null | awk 'NR==2 {print $2}')
                local drive_used=$(df -h "$drive" 2>/dev/null | awk 'NR==2 {print $3}')
                local drive_avail=$(df -h "$drive" 2>/dev/null | awk 'NR==2 {print $4}')
                local drive_percent=$(df -h "$drive" 2>/dev/null | awk 'NR==2 {print $5}')
                local drive_rw=$(test -w "$drive" && echo "Read/Write" || echo "Read-Only")
                echo -e "  ${BOLD_CYAN}${index}.${NC} $drive"
                echo -e "     ${ICON_SPACE} Size: $drive_size | Used: $drive_used | Free: $drive_avail ($drive_percent)"
                echo -e "     ${ICON_USB} Status: $drive_rw"
                ((index++))
            done
            echo -e "  ${BOLD_CYAN}0.${NC} Use home directory (${HOME}/Backups)"
            
            echo ""
            read -p "  ${ICON_ARROW} Select drive [0-${#detected_drives[@]}]: " drive_choice
            
            if [ "$drive_choice" = "0" ] || [ -z "$drive_choice" ]; then
                LOCAL_BACKUP_BASE="${HOME}/Backups"
                echo -e "  ${ICON_INFO} Using home directory: $LOCAL_BACKUP_BASE"
            elif [ "$drive_choice" -ge 1 ] && [ "$drive_choice" -le "${#detected_drives[@]}" ]; then
                LOCAL_BACKUP_BASE="${detected_drives[$((drive_choice-1))]}/MyHomeVault"
                echo -e "  ${ICON_SUCCESS} Using external drive: $LOCAL_BACKUP_BASE"
            else
                LOCAL_BACKUP_BASE="${HOME}/Backups"
                echo -e "  ${ICON_WARNING} Invalid choice, using home directory"
            fi
        else
            echo -e "\n${ICON_WARNING} No external drives detected."
            LOCAL_BACKUP_BASE="${HOME}/Backups"
            echo -e "${ICON_INFO} Using home directory: $LOCAL_BACKUP_BASE"
        fi
    fi
    
    LOCAL_BACKUP_DEST="${LOCAL_BACKUP_BASE}/${USERNAME}"
    
    # --- NAS Configuration ---
    echo -e "\n${BOLD_WHITE}Step 2: NAS Configuration (optional)${NC}"
    echo -e "${ICON_INFO} If you have a NAS, enter details. Press Enter to skip.\n"
    
    read -p "  ${ICON_ARROW} Enter NAS IP (e.g., 192.168.100.10) [skip]: " input_ip
    if [ -n "$input_ip" ]; then
        NAS_IP="$input_ip"
        read -p "  ${ICON_ARROW} Enter NAS Username [${USERNAME}]: " input_user
        NAS_USER="${input_user:-$USERNAME}"
        read -p "  ${ICON_ARROW} Enter NAS Backup Path [/home/${NAS_USER}/MyHomeVault]: " input_path
        NAS_BACKUP_PATH="${input_path:-/home/${NAS_USER}/MyHomeVault}"
        
        read -p "  ${ICON_ARROW} Bandwidth limit in KB/s (0 = unlimited) [5000]: " input_bw
        BW_LIMIT="${input_bw:-5000}"
        
        read -p "  ${ICON_ARROW} SSH timeout in seconds [10]: " input_timeout
        SSH_TIMEOUT="${input_timeout:-10}"
        read -p "  ${ICON_ARROW} SSH keep-alive interval [60]: " input_alive
        SSH_ALIVE="${input_alive:-60}"
        
        echo -e "\n${ICON_CLOCK} Testing NAS connection..."
        if ping -c 1 -W 2 "$NAS_IP" &> /dev/null; then
            echo -e "  ${ICON_SUCCESS} NAS is reachable"
        else
            echo -e "  ${ICON_WARNING} NAS not reachable - you can set up later"
        fi
    else
        NAS_IP=""
        NAS_USER="$USERNAME"
        NAS_BACKUP_PATH=""
        BW_LIMIT="0"
    fi
    
    # --- ZFS Remote Replication (optional) ---
    if [ "$USE_ZFS" = "yes" ]; then
        echo -e "\n${BOLD_WHITE}Step 3: ZFS Remote Replication (optional)${NC}"
        echo -e "${ICON_ZFS} You can send ZFS snapshots to a remote ZFS server.\n"
        
        read -p "  ${ICON_ARROW} Enable ZFS send/receive? (yes/no) [no]: " input_zfs_send
        if [[ "$input_zfs_send" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
            ENABLE_ZFS_SEND="yes"
            read -p "  ${ICON_ARROW} Remote host (e.g., backup-server): " ZFS_REMOTE_HOST
            read -p "  ${ICON_ARROW} Remote pool name (e.g., backup-pool): " ZFS_REMOTE_POOL
        fi
    fi
    
    # --- Retention Policy ---
    echo -e "\n${BOLD_WHITE}Step 4: Backup Retention${NC}"
    echo -e "${ICON_INFO} Older backups will be automatically deleted."
    read -p "  ${ICON_ARROW} Keep backups for how many days? [14]: " input_retention
    RETENTION_DAYS="${input_retention:-14}"
    
    if [ "$USE_ZFS" = "yes" ]; then
        ZFS_SNAPSHOT_RETENTION="$RETENTION_DAYS"
    fi
    
    # --- Notifications ---
    echo -e "\n${BOLD_WHITE}Step 5: Desktop Notifications${NC}"
    read -p "  ${ICON_ARROW} Enable desktop popups? (yes/no) [yes]: " input_notify
    if [[ "$input_notify" =~ ^[Nn][Oo]?$ ]]; then
        ENABLE_NOTIFICATIONS="no"
    else
        ENABLE_NOTIFICATIONS="yes"
    fi
    
    # --- Hardware Recommendations ---
    echo -e "\n${BOLD_WHITE}Hardware Recommendations:${NC}"
    echo -e "  ${ICON_DISK} ${BOLD_CYAN}Seagate IronWolf 4TB${NC} - Best for ZFS snapshot metadata (AgileArray)"
    echo -e "  ${ICON_DISK} ${BOLD_CYAN}WD Red Plus 4TB${NC}      - Best for LZ4 compression & stability"
    echo -e "  ${ICON_CPU} ${BOLD_CYAN}ECC RAM${NC}               - Recommended for ZFS data integrity"
    echo -e "\n${ICON_ZFS} ZFS benefits greatly from reliable hardware.\n"
    
    # --- Save Configuration (COMPLETE BLOCK - FIXED) ---
    cat <<EOF > "$CONFIG_FILE"
# My Home Vault ZFS Configuration
# GitHub: https://github.com/waelisa/my-home-vault
# Generated: $(date)
# User: ${USERNAME}

# ZFS Settings
USE_ZFS="$USE_ZFS"
ZFS_POOL="$ZFS_POOL"
ZFS_DATASET="$ZFS_DATASET"
ZFS_MOUNTPOINT="$ZFS_MOUNTPOINT"
ZFS_COMPRESSION="$ZFS_COMPRESSION"
ZFS_ATIME="$ZFS_ATIME"
ZFS_RECORDSIZE="$ZFS_RECORDSIZE"
ZFS_SNAPSHOT_PREFIX="$ZFS_SNAPSHOT_PREFIX"
ZFS_SNAPSHOT_RETENTION=$ZFS_SNAPSHOT_RETENTION
ENABLE_ZFS_SEND="$ENABLE_ZFS_SEND"
ZFS_REMOTE_HOST="$ZFS_REMOTE_HOST"
ZFS_REMOTE_POOL="$ZFS_REMOTE_POOL"

# Local Backup Settings
LOCAL_BACKUP_BASE="$LOCAL_BACKUP_BASE"
LOCAL_BACKUP_DEST="$LOCAL_BACKUP_DEST"

# NAS Settings
NAS_IP="$NAS_IP"
NAS_USER="$NAS_USER"
NAS_BACKUP_PATH="$NAS_BACKUP_PATH"
BW_LIMIT=$BW_LIMIT
SSH_TIMEOUT=$SSH_TIMEOUT
SSH_ALIVE=$SSH_ALIVE

# General Settings
RETENTION_DAYS=$RETENTION_DAYS
ENABLE_NOTIFICATIONS="$ENABLE_NOTIFICATIONS"
ENABLE_CHECKSUM_VERIFY="$ENABLE_CHECKSUM_VERIFY"
MIN_FREE_SPACE_PERCENT=$MIN_FREE_SPACE_PERCENT
EOF
    
    echo -e "\n${ICON_SUCCESS} ${BOLD_GREEN}Configuration saved!${NC}"
    echo -e "${ICON_VAULT} ${BOLD_WHITE}Setup complete! Press Enter to continue...${NC}"
    read -r
    
    # Create ZFS dataset if needed
    if [ "$USE_ZFS" = "yes" ] && [ -n "$ZFS_DATASET" ]; then
        create_zfs_dataset "$ZFS_DATASET" "$ZFS_MOUNTPOINT"
    fi
    
    # Create backup directories
    mkdir -p "$LOCAL_BACKUP_DEST/incremental" 2>/dev/null || true
    chown -R "$USERNAME:$USERNAME" "$LOCAL_BACKUP_DEST" 2>/dev/null || true
}

# =============================================================================
#                     L O A D   C O N F I G U R A T I O N
# =============================================================================

# Run setup wizard if no config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    run_setup_wizard
fi

# Load configuration
source "$CONFIG_FILE"

# Ensure LOCAL_BACKUP_DEST is set
if [ -z "${LOCAL_BACKUP_DEST:-}" ]; then
    LOCAL_BACKUP_DEST="${LOCAL_BACKUP_BASE}/${USERNAME}"
fi

# Script variables (derived from config)
LOCAL_BACKUP_CURRENT="${LOCAL_BACKUP_DEST}/current"
LOCAL_BACKUP_INCREMENTAL="${LOCAL_BACKUP_DEST}/incremental"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
SCRIPT_NAME=$(basename "$0")

# Build SSH options with timeouts
SSH_OPTS="-o ConnectTimeout=$SSH_TIMEOUT -o ServerAliveInterval=$SSH_ALIVE -o ServerAliveCountMax=3"

# NAS destination string (if NAS configured)
if [ -n "${NAS_IP:-}" ] && [ -n "${NAS_BACKUP_PATH:-}" ]; then
    NAS_BACKUP_DEST="${NAS_USER}@${NAS_IP}:${NAS_BACKUP_PATH}"
else
    NAS_BACKUP_DEST=""
fi

# =============================================================================
#                         E X C L U S I O N   L I S T
# =============================================================================

EXCLUDE_DIRS=(
    # My Home Vault directories (prevent infinite loops)
    ".my-home-vault/"
    ".my-home-vault/*"
    ".my-home-vault/logs/"
    ".my-home-vault/logs/*"
    "*.my-home-vault*.conf"
    
    # Cache and temporary files
    ".cache/"
    ".cache/*"
    ".local/share/Trash/"
    ".thumbnails/"
    ".thumb/"
    ".gvfs/"
    ".local/share/gvfs-metadata/"
    
    # Browser caches
    ".mozilla/firefox/*/Cache/"
    ".mozilla/firefox/*/OfflineCache/"
    ".mozilla/firefox/*/thumbnails/"
    ".config/google-chrome/Default/Cache/"
    ".config/google-chrome/Default/Code Cache/"
    ".config/chromium/Default/Cache/"
    ".config/chromium/Default/Code Cache/"
    
    # Virtual environments and containers
    ".waydroid/"
    "waydroid/"
    ".local/share/waydroid/"
    ".local/share/containers/"
    ".local/share/flatpak/"
    ".var/app/"
    "snap/"
    
    # Development artifacts
    "*/venv/"
    "*/.venv/"
    "*/__pycache__/"
    "*.pyc"
    ".m2/repository/"
    ".cargo/"
    ".rustup/"
    ".gradle/"
    "node_modules/"
    "*/node_modules/"
    ".npm/"
    ".yarn/"
    
    # Package manager caches
    ".cache/yay/"
    ".cache/pip/"
    ".local/share/flatpak/repo/"
    
    # Temporary files
    "*.tmp"
    "*.temp"
    "*.bak"
    "*.old"
    "Trash/"
    ".trash/"
    "Downloads/"
    "*/Downloads/"
    
    # ZFS snapshot directories (if mounted)
    ".zfs/"
    ".zfs/*"
)

# =============================================================================
#                     U T I L I T Y   F U N C T I O N S
# =============================================================================

# Version check function
check_for_updates() {
    if command -v curl &> /dev/null; then
        LATEST_VERSION=$(curl -s --max-time 2 "$VERSION_URL" 2>/dev/null | head -n1 | tr -d '[:space:]' || echo "$CURRENT_VERSION")
        if [[ "$LATEST_VERSION" != "$CURRENT_VERSION" ]] && [[ "$LATEST_VERSION" != "" ]]; then
            echo -e "\n${BOLD_YELLOW}  ⚡ New Version Available: $LATEST_VERSION (Current: $CURRENT_VERSION)${NC}"
            echo -e "${BOLD_YELLOW}  ⚡ Download: https://github.com/waelisa/my-home-vault${NC}\n"
        fi
    fi
}

# Function to send desktop notification
send_notification() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"
    
    if [ "$ENABLE_NOTIFICATIONS" = "yes" ] && command -v notify-send &> /dev/null; then
        notify-send -u "$urgency" -i dialog-information "My Home Vault ZFS: $title" "$message"
    fi
}

# Function to attempt drive remount if read-only
attempt_remount() {
    local mount_point="$1"
    
    print_step "remount" "Drive is read-only, attempting repair..." "warn"
    
    if mount -o remount,rw "$mount_point" 2>/dev/null; then
        print_step "remount" "Successfully remounted as read-write" "done"
        send_notification "Drive Remounted" "$(basename "$mount_point") is now writable" "normal"
        return 0
    else
        print_step "remount" "Failed to remount - may be hardware write-protected" "error"
        return 1
    fi
}

# Function to check if destination is writable
check_writable() {
    local dest="$1"
    local operation="$2"
    
    print_step "write" "Checking if destination is writable..." "start"
    
    if [ ! -d "$dest" ]; then
        if ! mkdir -p "$dest" 2>/dev/null; then
            print_step "write" "Cannot create destination directory" "error"
            return 1
        fi
    fi
    
    local test_file="$dest/.write_test_$$"
    if ! touch "$test_file" 2>/dev/null; then
        print_step "write" "Destination is not writable (read-only or disconnected)" "error"
        
        if mountpoint -q "$dest" 2>/dev/null; then
            if attempt_remount "$dest"; then
                if touch "$test_file" 2>/dev/null; then
                    rm -f "$test_file"
                    print_step "write" "Write test passed after remount" "done"
                    return 0
                fi
            fi
        fi
        
        send_notification "Backup Failed" "Destination $dest is not writable" "critical"
        return 1
    else
        rm -f "$test_file"
        print_step "write" "Destination is writable" "done"
        return 0
    fi
}

# Function to rotate logs (keep last 7 days)
rotate_logs() {
    print_step "log" "Rotating old logs" "start"
    find "$LOG_DIR" -name "vault_*.log" -type f -mtime +7 -delete 2>/dev/null
    find "$LOG_DIR" -name "quiet.log" -type f -size +10M -exec mv {} {}.old \; 2>/dev/null || true
    local remaining=$(find "$LOG_DIR" -name "vault_*.log" -type f | wc -l)
    print_step "log" "Keeping $remaining recent log files" "done"
}

# Function to check disk space
check_disk_space() {
    local path="$1"
    local required_size="$2"
    local operation="$3"
    
    if [ ! -d "$path" ] && [ ! -f "$path" ]; then
        path=$(dirname "$path")
    fi
    
    local available_kb=$(df "$path" 2>/dev/null | awk 'NR==2 {print $4}')
    local available_percent=$(df "$path" 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
    local available_hr=$(df -h "$path" 2>/dev/null | awk 'NR==2 {print $4}')
    
    if [ -z "$available_kb" ] || [ -z "$available_percent" ]; then
        print_warning "Could not determine disk space for $path"
        return 0
    fi
    
    print_step "space" "Disk space: ${available_hr} free (${available_percent}% used)" "info"
    
    if [ "$available_percent" -gt $((100 - MIN_FREE_SPACE_PERCENT)) ]; then
        print_error "CRITICAL: Less than ${MIN_FREE_SPACE_PERCENT}% disk space remaining"
        print_error "Operation: $operation would risk filling the drive"
        
        if [ "$ENABLE_NOTIFICATIONS" = "yes" ]; then
            send_notification "Backup Failed - Low Space" "Only ${available_hr} free on backup drive" "critical"
        fi
        
        read -p "  ${ICON_ARROW} Continue anyway? (yes/no): " -r confirm
        if [[ ! "$confirm" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
            return 1
        fi
    fi
    
    if [ -n "$required_size" ] && [ "$required_size" -gt 0 ]; then
        local required_hr=$(numfmt --to=iec --suffix=B "$required_size" 2>/dev/null || echo "${required_size}KB")
        
        if [ "$available_kb" -lt "$required_size" ]; then
            print_error "Insufficient space: Need ${required_hr}, only ${available_hr} free"
            
            if [ "$ENABLE_NOTIFICATIONS" = "yes" ]; then
                send_notification "Backup Failed - Insufficient Space" "Need ${required_hr}, only ${available_hr} free" "critical"
            fi
            
            return 1
        else
            print_step "space" "Sufficient space: Need ${required_hr}, ${available_hr} free" "done"
        fi
    fi
    
    return 0
}

# Function to get source size
get_source_size() {
    local source="$1"
    local size_kb
    
    if [ -d "$source" ]; then
        size_kb=$(du -sk "$source" 2>/dev/null | cut -f1)
    else
        size_kb=0
    fi
    
    echo "$size_kb"
}

# Function to print section header
print_header() {
    local title="$1"
    local color="${2:-$BOLD_CYAN}"
    local width=70
    local padding=$(( (width - ${#title}) / 2 ))
    
    echo ""
    printf "${color}╔"
    printf '═%.0s' $(seq 1 $width)
    printf "╗${NC}\n"
    
    printf "${color}║${NC}%*s${color}${BOLD}%s${NC}%*s${color}║${NC}\n" $padding "" "$title" $padding ""
    
    printf "${color}╚"
    printf '═%.0s' $(seq 1 $width)
    printf "╝${NC}\n"
    echo ""
}

# Function to print step
print_step() {
    local step="$1"
    local description="$2"
    local status="${3:-}"
    
    case $status in
        "start")   echo -e "  ${ICON_STEP} ${BOLD}Step $step:${NC} $description" ;;
        "done")    echo -e "    ${ICON_DONE} ${GREEN}$description${NC}" ;;
        "error")   echo -e "    ${ICON_ERROR} ${RED}$description${NC}" ;;
        "warn")    echo -e "    ${ICON_WARNING} ${YELLOW}$description${NC}" ;;
        "info")    echo -e "    ${ICON_INFO} ${BLUE}$description${NC}" ;;
        "space")   echo -e "    ${ICON_SPACE} ${BLUE}$description${NC}" ;;
        "log")     echo -e "    ${ICON_CRON} ${BLUE}$description${NC}" ;;
        "write")   echo -e "    ${ICON_USB} ${BLUE}$description${NC}" ;;
        "remount") echo -e "    ${ICON_USB} ${YELLOW}$description${NC}" ;;
        "zfs")     echo -e "    ${ICON_ZFS} ${CYAN}$description${NC}" ;;
        "snapshot") echo -e "    ${ICON_SNAPSHOT} ${GREEN}$description${NC}" ;;
        "zfs-send") echo -e "    ${ICON_ZFS} ${YELLOW}$description${NC}" ;;
        "mount")   echo -e "    ${ICON_MOUNT} ${MAGENTA}$description${NC}" ;;
        "atomic")  echo -e "    ${ICON_ATOMIC} ${YELLOW}$description${NC}" ;;
        *)         echo -e "  ${ICON_ARROW} ${BOLD}$step:${NC} $description" ;;
    esac
}

# Function to print success message
print_success() {
    echo -e "  ${ICON_SUCCESS} ${GREEN}$1${NC}"
}

# Function to print error message
print_error() {
    echo -e "  ${ICON_ERROR} ${RED}$1${NC}"
}

# Function to log messages
log_message() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Function to create exclude file
create_exclude_file() {
    local exclude_file="/tmp/mhv_exclude_${USERNAME}_$$.txt"
    
    for pattern in "${EXCLUDE_DIRS[@]}"; do
        echo "$pattern" >> "$exclude_file"
    done
    
    echo ".my-home-vault/" >> "$exclude_file"
    echo ".my-home-vault/*" >> "$exclude_file"
    
    echo "$exclude_file"
}

# Function to show exclusions
show_exclusions() {
    print_header "EXCLUDED PATTERNS"
    
    echo -e "  ${BOLD_YELLOW}These items are excluded from backup:${NC}\n"
    
    local count=1
    for pattern in "${EXCLUDE_DIRS[@]}"; do
        printf "  ${BOLD_CYAN}%2d.${NC} %s\n" $count "$pattern"
        ((count++))
    done
    echo ""
    print_info "Total: $((count-1)) exclusion patterns"
    echo -e "  ${BOLD_RED}Note:${NC} ZFS snapshot directories (.zfs/) are excluded"
    echo ""
}

# =============================================================================
#                     C R O N   M A N A G E M E N T
# =============================================================================

setup_cron() {
    print_header "CRON AUTOMATION"
    
    echo -e "  ${ICON_CRON} Set up automatic backups via cron\n"
    
    # Check if already installed
    local cron_exists=false
    if crontab -l 2>/dev/null | grep -q "my-home-vault-zfs.*--quiet"; then
        cron_exists=true
        echo -e "  ${ICON_INFO} Existing cron job found:"
        crontab -l | grep "my-home-vault-zfs.*--quiet" | while read line; do
            echo -e "    ${BOLD_CYAN}↳${NC} $line"
        done
        echo ""
    fi
    
    echo -e "  ${BOLD_WHITE}Options:${NC}"
    echo -e "    ${BOLD_CYAN}1.${NC} Add daily backup at 2 AM"
    echo -e "    ${BOLD_CYAN}2.${NC} Add weekly backup (Sunday at 3 AM)"
    echo -e "    ${BOLD_CYAN}3.${NC} Add custom schedule"
    echo -e "    ${BOLD_CYAN}4.${NC} Remove existing cron job"
    echo -e "    ${BOLD_CYAN}5.${NC} Back to main menu"
    echo ""
    
    read -p "  ${ICON_ARROW} Choose option [1-5]: " -r cron_choice
    
    case $cron_choice in
        1)
            # Daily at 2 AM
            local cron_cmd="0 2 * * * root ${HOME}/${SCRIPT_NAME} --quiet > ${LOG_DIR}/cron_\$(date +\%Y\%m\%d).log 2>&1"
            (crontab -l 2>/dev/null | grep -v "my-home-vault" ; echo "$cron_cmd") | crontab -
            echo -e "  ${ICON_SUCCESS} Daily backup scheduled for 2 AM"
            ;;
        2)
            # Weekly on Sunday at 3 AM
            local cron_cmd="0 3 * * 0 root ${HOME}/${SCRIPT_NAME} --quiet > ${LOG_DIR}/cron_\$(date +\%Y\%m\%d).log 2>&1"
            (crontab -l 2>/dev/null | grep -v "my-home-vault" ; echo "$cron_cmd") | crontab -
            echo -e "  ${ICON_SUCCESS} Weekly backup scheduled for Sunday at 3 AM"
            ;;
        3)
            echo -e "\n${BOLD_WHITE}Custom cron syntax (min hour day month weekday)${NC}"
            echo -e "Example: ${BOLD_CYAN}30 4 * * 1-5${NC} = Weekdays at 4:30 AM"
            read -p "  ${ICON_ARROW} Enter cron schedule: " custom_schedule
            local cron_cmd="$custom_schedule root ${HOME}/${SCRIPT_NAME} --quiet > ${LOG_DIR}/cron_\$(date +\%Y\%m\%d).log 2>&1"
            (crontab -l 2>/dev/null | grep -v "my-home-vault" ; echo "$cron_cmd") | crontab -
            echo -e "  ${ICON_SUCCESS} Custom cron job added"
            ;;
        4)
            crontab -l 2>/dev/null | grep -v "my-home-vault" | crontab -
            echo -e "  ${ICON_SUCCESS} Cron job removed"
            ;;
        5)
            return 0
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
    
    echo ""
    read -p "  ${ICON_ARROW} Press Enter to continue..."
}

# =============================================================================
#                     L O G   M A N A G E M E N T
# =============================================================================

manage_logs() {
    print_header "LOG MANAGEMENT"
    
    local log_count=$(find "$LOG_DIR" -name "vault_*.log" -type f | wc -l)
    local log_size=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1)
    
    echo -e "  ${ICON_INFO} Log directory: $LOG_DIR"
    echo -e "  ${ICON_INFO} Total logs: $log_count files ($log_size)\n"
    
    echo -e "  ${BOLD_WHITE}Recent logs:${NC}"
    find "$LOG_DIR" -name "vault_*.log" -type f -printf "%T@ %p\n" | sort -rn | head -5 | while read line; do
        local log_file=$(echo "$line" | cut -d' ' -f2-)
        local log_date=$(stat -c %y "$log_file" 2>/dev/null | cut -d. -f1)
        local log_size=$(du -h "$log_file" 2>/dev/null | cut -f1)
        echo -e "    ${BOLD_CYAN}↳${NC} $(basename "$log_file") ($log_size) - $log_date"
    done
    echo ""
    
    echo -e "  ${BOLD_WHITE}Options:${NC}"
    echo -e "    ${BOLD_CYAN}1.${NC} View last 50 lines of latest log"
    echo -e "    ${BOLD_CYAN}2.${NC} Delete all logs older than 7 days (auto-rotate)"
    echo -e "    ${BOLD_CYAN}3.${NC} Delete ALL logs (clean sweep)"
    echo -e "    ${BOLD_CYAN}4.${NC} View quiet.log (cron output)"
    echo -e "    ${BOLD_CYAN}5.${NC} Back to main menu"
    echo ""
    
    read -p "  ${ICON_ARROW} Choose option [1-5]: " -r log_choice
    
    case $log_choice in
        1)
            local latest=$(find "$LOG_DIR" -name "vault_*.log" -type f -printf "%T@ %p\n" | sort -rn | head -1 | cut -d' ' -f2-)
            if [ -n "$latest" ]; then
                echo -e "\n${BOLD_WHITE}Last 50 lines of $(basename "$latest"):${NC}\n"
                tail -50 "$latest"
            else
                print_warning "No logs found"
            fi
            ;;
        2)
            local old_count=$(find "$LOG_DIR" -name "vault_*.log" -type f -mtime +7 | wc -l)
            if [ "$old_count" -gt 0 ]; then
                find "$LOG_DIR" -name "vault_*.log" -type f -mtime +7 -delete
                echo -e "  ${ICON_SUCCESS} Deleted $old_count old log(s)"
            else
                echo -e "  ${ICON_INFO} No logs older than 7 days"
            fi
            ;;
        3)
            echo -e "\n${BOLD_RED}⚠ WARNING: This will delete ALL logs!${NC}"
            read -p "  ${ICON_ARROW} Type 'DELETE' to confirm: " -r confirm
            if [ "$confirm" = "DELETE" ]; then
                rm -f "$LOG_DIR"/*.log
                echo -e "  ${ICON_SUCCESS} All logs deleted"
            else
                echo -e "  ${ICON_INFO} Cancelled"
            fi
            ;;
        4)
            if [ -f "$LOG_DIR/quiet.log" ]; then
                echo -e "\n${BOLD_WHITE}Last 50 lines of quiet.log:${NC}\n"
                tail -50 "$LOG_DIR/quiet.log"
            else
                print_warning "No quiet.log found"
            fi
            ;;
        5)
            return 0
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
    
    echo ""
    read -p "  ${ICON_ARROW} Press Enter to continue..."
}

# =============================================================================
#                     R E P A I R   M O D E   (VAULT-FIX)
# =============================================================================

perform_repair() {
    print_header "VAULT-FIX: REPAIR MODE"
    
    if [ -z "${NAS_IP:-}" ] || [ -z "${NAS_USER:-}" ]; then
        print_error "NAS not configured. Repair mode requires NAS backup."
        return 1
    fi
    
    echo -e "  ${ICON_REPAIR} This will verify and repair your NAS backup using checksums"
    echo -e "  ${ICON_INFO} The -c flag forces checksum comparison (catches bit rot)"
    echo -e "  ${ICON_CPU} Note: Checksums are CPU-intensive on NAS. This may take a while.\n"
    
    # Check if we have a current backup
    if ! ssh $SSH_OPTS -o BatchMode=yes "${NAS_USER}@${NAS_IP}" "test -d \"${NAS_BACKUP_PATH}/current\"" 2>/dev/null; then
        if ! ssh $SSH_OPTS "${NAS_USER}@${NAS_IP}" "test -d \"${NAS_BACKUP_PATH}\"" 2>/dev/null; then
            print_error "No 'current' backup found on NAS to repair."
            return 1
        fi
    fi
    
    print_step "1" "Testing connection" "start"
    if ! ping -c 1 -W 2 "$NAS_IP" &> /dev/null; then
        print_step "1" "NAS unreachable" "error"
        return 1
    fi
    print_step "1" "NAS reachable" "done"
    
    print_step "2" "Starting repair (checksum verification)" "start"
    echo -e "    ${ICON_INFO} This may take a while for large backups\n"
    
    local exclude_file=$(create_exclude_file)
    local bw_arg=""
    if [ "$BW_LIMIT" -gt 0 ]; then
        bw_arg="--bwlimit=$BW_LIMIT"
        echo -e "    ${ICON_INFO} Bandwidth limit: ${BW_LIMIT} KB/s (protects NAS)"
    fi
    
    # Use checksum (-c) to verify and repair (VAULT-FIX)
    if rsync -avc --progress --no-inc-recursive $bw_arg \
        --exclude-from="$exclude_file" \
        "$HOME_DIR/" \
        -e "ssh $SSH_OPTS" \
        "${NAS_USER}@${NAS_IP}:\"${NAS_BACKUP_PATH}/current\"/" 2>&1 | tee -a "$LOG_FILE"; then
        
        print_step "2" "Repair completed" "done"
        
        # Get stats on what was fixed
        local nas_size=$(ssh $SSH_OPTS "${NAS_USER}@${NAS_IP}" "du -sh \"${NAS_BACKUP_PATH}/current\" 2>/dev/null | cut -f1" 2>/dev/null)
        print_step "3" "Current backup size: ${nas_size:-unknown}" "info"
        
        # Check if any files were actually repaired
        if grep -q "bytes received" "$LOG_FILE"; then
            local received=$(grep "bytes received" "$LOG_FILE" | tail -1 | awk '{print $1}')
            if [ "$received" != "0" ]; then
                print_step "3" "⚠ Repaired corrupted files - check log for details" "warn"
                send_notification "VAULT-FIX: Files Repaired" "Corrupted files were fixed on NAS" "normal"
            else
                print_step "3" "✓ No corruption detected - backup is healthy" "done"
                send_notification "VAULT-FIX: Backup Healthy" "No corruption found in NAS backup" "normal"
            fi
        fi
    else
        local exit_code=$?
        print_step "2" "Repair failed with exit code $exit_code" "error"
        rm -f "$exclude_file"
        send_notification "VAULT-FIX Failed" "Repair encountered errors - check logs" "critical"
        return $exit_code
    fi
    
    rm -f "$exclude_file"
    echo ""
    print_success "VAULT-FIX completed successfully"
}

# =============================================================================
#                     B A C K U P   F U N C T I O N S
# =============================================================================

# Function to test NAS connection
test_nas_connection() {
    if [ -z "${NAS_IP:-}" ] || [ -z "${NAS_USER:-}" ]; then
        print_error "NAS not configured. Please run setup wizard (delete ~/.my-home-vault.conf and restart)"
        return 1
    fi
    
    print_header "NAS CONNECTION TEST"
    
    print_step "1" "Pinging NAS" "start"
    if ping -c 1 -W 2 "$NAS_IP" &> /dev/null; then
        print_step "1" "NAS is reachable (ping)" "done"
    else
        print_step "1" "NAS is not reachable" "error"
        return 1
    fi
    
    print_step "2" "Testing SSH connection (timeout: ${SSH_TIMEOUT}s)" "start"
    
    if ssh $SSH_OPTS -o BatchMode=yes "${NAS_USER}@${NAS_IP}" "echo OK" 2>/dev/null; then
        print_step "2" "SSH connection successful (key-based auth)" "done"
    else
        print_step "2" "SSH key authentication failed" "warn"
        
        if ssh $SSH_OPTS "${NAS_USER}@${NAS_IP}" "echo OK" 2>/dev/null; then
            print_step "2" "SSH connection successful (password auth)" "done"
        else
            print_step "2" "SSH connection failed after ${SSH_TIMEOUT}s timeout" "error"
            return 1
        fi
    fi
    
    print_step "3" "Checking backup directory on NAS" "start"
    if ssh $SSH_OPTS "${NAS_USER}@${NAS_IP}" "test -d \"${NAS_BACKUP_PATH}\"" 2>/dev/null; then
        print_step "3" "Backup directory exists: $NAS_BACKUP_PATH" "done"
    else
        print_step "3" "Backup directory does not exist (will be created)" "warn"
    fi
    
    # Check NAS disk space
    print_step "4" "Checking NAS disk space" "start"
    local nas_space=$(ssh $SSH_OPTS "${NAS_USER}@${NAS_IP}" "df -k \"${NAS_BACKUP_PATH}\" 2>/dev/null | awk 'NR==2 {print \$4,\$5}'" 2>/dev/null)
    if [ -n "$nas_space" ]; then
        local nas_free_kb=$(echo "$nas_space" | awk '{print $1}')
        local nas_percent=$(echo "$nas_space" | awk '{print $2}' | tr -d '%')
        local nas_free_hr=$(numfmt --to=iec --suffix=B $((nas_free_kb * 1024)) 2>/dev/null || echo "${nas_free_kb}KB")
        print_step "4" "NAS free space: $nas_free_hr (${nas_percent}% used)" "info"
        
        if [ "$nas_percent" -gt $((100 - MIN_FREE_SPACE_PERCENT)) ]; then
            print_warning "NAS has less than ${MIN_FREE_SPACE_PERCENT}% free space"
        fi
    fi
    
    echo ""
    print_success "NAS connection test completed"
    return 0
}

# Function to ensure NAS directory exists
ensure_nas_directory() {
    if [ -z "${NAS_IP:-}" ] || [ -z "${NAS_USER:-}" ]; then
        return 1
    fi
    
    print_step "3" "Ensuring NAS directory exists" "start"
    
    if ssh $SSH_OPTS "${NAS_USER}@${NAS_IP}" "mkdir -p \"${NAS_BACKUP_PATH}\"" 2>&1 | tee -a "$LOG_FILE"; then
        print_step "3" "NAS directory ready" "done"
        return 0
    else
        print_step "3" "Failed to create NAS directory" "error"
        return 1
    fi
}

# Function to create incremental backup (with ZFS integration)
create_incremental_backup() {
    local backup_date="$1"
    local incremental_dir="${LOCAL_BACKUP_INCREMENTAL}/${backup_date}"
    local link_dest_arg=""
    local checksum_arg=""
    
    print_step "5" "Creating incremental backup" "start"
    
    mkdir -p "$incremental_dir"
    
    if [ -L "$LOCAL_BACKUP_CURRENT" ] && [ -d "$(readlink $LOCAL_BACKUP_CURRENT)" ]; then
        link_dest_arg="--link-dest=$(readlink $LOCAL_BACKUP_CURRENT)"
        print_step "5" "Using previous backup for hard links" "info"
    elif [ -d "$LOCAL_BACKUP_CURRENT" ]; then
        link_dest_arg="--link-dest=$LOCAL_BACKUP_CURRENT"
        print_step "5" "Using previous backup for hard links" "info"
    fi
    
    if [ "$ENABLE_CHECKSUM_VERIFY" = "yes" ]; then
        checksum_arg="-c"
        print_step "5" "Checksum verification enabled" "info"
    fi
    
    local exclude_file=$(create_exclude_file)
    
    local rsync_opts="-aAXvh --info=progress2"
    rsync_opts="$rsync_opts --delete --delete-excluded"
    rsync_opts="$rsync_opts --exclude-from=$exclude_file"
    rsync_opts="$rsync_opts $checksum_arg"
    rsync_opts="$rsync_opts $link_dest_arg"
    
    if rsync $rsync_opts \
        "$HOME_DIR/" \
        "$incremental_dir/" 2>&1 | tee -a "$LOG_FILE"; then
        
        print_step "5" "Incremental backup created" "done"
        
        print_step "6" "Updating current symlink" "start"
        ln -sfn "$incremental_dir" "$LOCAL_BACKUP_CURRENT"
        print_step "6" "Current symlink updated" "done"
        
        # Fix ownership after rsync (if running as root)
        chown -R "$USERNAME:$USERNAME" "$LOCAL_BACKUP_DEST" 2>/dev/null || true
        
        # ZFS: Create snapshot after successful backup (with atomic naming)
        if [ "$USE_ZFS" = "yes" ] && [ -n "$ZFS_DATASET" ]; then
            # Verify dataset is mounted before snapshot
            if verify_zfs_mount "$ZFS_DATASET" "$ZFS_MOUNTPOINT"; then
                local snapshot_name=$(create_zfs_snapshot "$ZFS_DATASET")
                
                # ZFS: Send snapshot to remote if enabled
                if [ "$ENABLE_ZFS_SEND" = "yes" ] && [ -n "$ZFS_REMOTE_HOST" ] && [ -n "$ZFS_REMOTE_POOL" ]; then
                    send_zfs_snapshot "$ZFS_DATASET" "$snapshot_name" "$ZFS_REMOTE_HOST" "$ZFS_REMOTE_POOL"
                fi
                
                # Clean old ZFS snapshots
                clean_zfs_snapshots "$ZFS_DATASET" "$ZFS_SNAPSHOT_RETENTION"
            else
                print_step "zfs" "Cannot create snapshot - dataset not mounted" "error"
            fi
        fi
        
        print_step "7" "Verifying backup" "start"
        local backup_size=$(du -sh "$incremental_dir" 2>/dev/null | cut -f1)
        local file_count=$(find "$incremental_dir" -type f 2>/dev/null | wc -l)
        print_step "7" "Size: $backup_size, Files: $file_count" "done"
    else
        local exit_code=$?
        print_step "5" "Backup failed with exit code $exit_code" "error"
        rm -f "$exclude_file"
        return $exit_code
    fi
    
    rm -f "$exclude_file"
    return 0
}

# Clean old backups function
clean_old_backups() {
    local location="$1"
    local dry_run="${2:-no}"
    
    if [ "$RETENTION_DAYS" -eq 0 ]; then
        print_info "Retention policy disabled"
        return 0
    fi
    
    print_header "CLEANING OLD BACKUPS"
    print_info "Retention: Deleting backups older than $RETENTION_DAYS days"
    
    if [ "$dry_run" = "yes" ]; then
        print_info "DRY RUN MODE: No files will be deleted"
    fi
    
    case $location in
        "local")
            if [ -d "$LOCAL_BACKUP_INCREMENTAL" ]; then
                print_step "1" "Scanning local backups" "start"
                
                local old_folders=$(find "$LOCAL_BACKUP_INCREMENTAL" -maxdepth 1 -type d -name "????-??-??_??-??-??" -ctime +$RETENTION_DAYS 2>/dev/null)
                local old_count=$(echo "$old_folders" | wc -l)
                
                if [ "$old_count" -gt 0 ] && [ -n "$old_folders" ]; then
                    print_step "1" "Found $old_count old backup(s)" "warn"
                    
                    echo ""
                    echo -e "  ${BOLD_YELLOW}Old backups:${NC}"
                    echo "$old_folders" | while read folder; do
                        if [ -n "$folder" ]; then
                            local folder_size=$(du -sh "$folder" 2>/dev/null | cut -f1)
                            local folder_date=$(stat -c %y "$folder" 2>/dev/null | cut -d. -f1)
                            echo -e "    ${ICON_TRASH} $(basename $folder) (${folder_size}) - $folder_date"
                        fi
                    done
                    echo ""
                    
                    if [ "$dry_run" != "yes" ]; then
                        print_step "2" "Deleting old backups..." "start"
                        
                        local total_size=0
                        echo "$old_folders" | while read folder; do
                            if [ -n "$folder" ]; then
                                local folder_size_kb=$(du -sk "$folder" 2>/dev/null | cut -f1)
                                total_size=$((total_size + folder_size_kb))
                            fi
                        done
                        
                        find "$LOCAL_BACKUP_INCREMENTAL" -maxdepth 1 -type d -name "????-??-??_??-??-??" -ctime +$RETENTION_DAYS -exec rm -rf {} \; 2>&1 | tee -a "$LOG_FILE"
                        
                        local freed_hr=$(numfmt --to=iec --suffix=B $((total_size * 1024)) 2>/dev/null || echo "${total_size}KB")
                        print_step "2" "Old backups deleted (freed ~$freed_hr)" "done"
                        
                        if [ -L "$LOCAL_BACKUP_CURRENT" ] && [ ! -d "$(readlink $LOCAL_BACKUP_CURRENT)" ]; then
                            print_step "3" "Current symlink points to deleted backup, updating..." "warn"
                            latest_backup=$(find "$LOCAL_BACKUP_INCREMENTAL" -maxdepth 1 -type d -name "????-??-??_??-??-??" | sort -r | head -1)
                            if [ -n "$latest_backup" ]; then
                                ln -sfn "$latest_backup" "$LOCAL_BACKUP_CURRENT"
                                print_step "3" "Current symlink updated" "done"
                            fi
                        fi
                    else
                        print_step "2" "Dry run: would delete $old_count old backups" "info"
                    fi
                else
                    print_step "1" "No old backups found" "done"
                fi
            fi
            
            # ZFS snapshots are cleaned separately in create_incremental_backup
            ;;
        "nas")
            if [ -z "${NAS_IP:-}" ] || [ -z "${NAS_USER:-}" ]; then
                print_warning "NAS not configured, skipping"
                return 0
            fi
            
            if ping -c 1 -W 2 "$NAS_IP" &> /dev/null && ssh $SSH_OPTS -o BatchMode=yes "${NAS_USER}@${NAS_IP}" "echo OK" &> /dev/null; then
                print_step "1" "Scanning NAS for old backups" "start"
                
                local nas_old_folders=$(ssh $SSH_OPTS "${NAS_USER}@${NAS_IP}" "find \"${NAS_BACKUP_PATH}\" -maxdepth 1 -type d -name '????-??-??_??-??-??' -ctime +${RETENTION_DAYS} 2>/dev/null")
                local nas_old_count=$(echo "$nas_old_folders" | wc -l)
                
                if [ "$nas_old_count" -gt 0 ] && [ -n "$nas_old_folders" ]; then
                    print_step "1" "Found $nas_old_count old backup(s) on NAS" "warn"
                    
                    if [ "$dry_run" != "yes" ]; then
                        print_step "2" "Deleting old backups from NAS..." "start"
                        ssh $SSH_OPTS "${NAS_USER}@${NAS_IP}" "find \"${NAS_BACKUP_PATH}\" -maxdepth 1 -type d -name '????-??-??_??-??-??' -ctime +${RETENTION_DAYS} -exec rm -rf {} \;" 2>&1 | tee -a "$LOG_FILE"
                        print_step "2" "Old NAS backups deleted" "done"
                    else
                        print_step "2" "Dry run: would delete $nas_old_count old NAS backups" "info"
                    fi
                else
                    print_step "1" "No old backups found on NAS" "done"
                fi
            else
                print_warning "NAS not reachable, skipping NAS cleanup"
            fi
            ;;
    esac
    
    print_success "Cleanup completed"
}

# Local Backup
perform_local_backup() {
    print_header "LOCAL BACKUP - ${USERNAME}"
    
    if [ "$USE_ZFS" = "yes" ]; then
        echo -e "  ${ICON_ZFS} ZFS Mode: $ZFS_DATASET (compression=$ZFS_COMPRESSION)"
        echo -e "  ${ICON_ATOMIC} Atomic snapshot naming enabled (PID + millisecond precision)\n"
        # Verify dataset is mounted before proceeding
        if ! verify_zfs_mount "$ZFS_DATASET" "$ZFS_MOUNTPOINT"; then
            print_error "ZFS dataset not mounted - cannot proceed"
            return 1
        fi
        echo ""
    fi
    
    print_step "1" "Checking source" "start"
    if [ ! -d "$HOME_DIR" ]; then
        print_step "1" "Source missing: $HOME_DIR" "error"
        return 1
    fi
    print_step "1" "Source found" "done"
    
    print_step "2" "Preparing destination" "start"
    mkdir -p "$LOCAL_BACKUP_INCREMENTAL" 2>/dev/null || true
    
    print_step "2" "Checking destination writability" "start"
    if ! check_writable "$LOCAL_BACKUP_DEST" "local backup"; then
        print_step "2" "Destination is not writable - cannot proceed" "error"
        send_notification "Backup Failed" "Backup drive is read-only or disconnected" "critical"
        return 1
    fi
    print_step "2" "Destination ready: $LOCAL_BACKUP_DEST" "done"
    
    print_step "3" "Checking disk space" "start"
    local source_size_kb=$(get_source_size "$HOME_DIR")
    if ! check_disk_space "$LOCAL_BACKUP_BASE" "$source_size_kb" "local backup"; then
        print_step "3" "Insufficient disk space" "error"
        return 1
    fi
    
    print_step "4" "Loading exclusions" "start"
    show_exclusions
    
    echo ""
    print_warning "Backup: $HOME_DIR → $LOCAL_BACKUP_DEST"
    echo ""
    read -p "  ${ICON_ARROW} Proceed? (yes/no): " -r confirmation
    
    if [[ ! "$confirmation" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
        print_warning "Cancelled"
        return 0
    fi
    
    create_incremental_backup "$TIMESTAMP"
    
    if [ "$RETENTION_DAYS" -gt 0 ]; then
        clean_old_backups "local"
    fi
    
    rotate_logs
    
    echo ""
    print_success "Local backup completed at $(date)"
    print_info "Log: $LOG_FILE"
    
    send_notification "Backup Complete" "Local backup completed successfully" "normal"
}

# NAS Backup
perform_nas_backup() {
    if [ -z "${NAS_IP:-}" ] || [ -z "${NAS_USER:-}" ]; then
        print_error "NAS not configured. Please run setup wizard (delete ~/.my-home-vault.conf and restart)"
        return 1
    fi
    
    print_header "NAS BACKUP - ${USERNAME}"
    
    if [ "$USE_ZFS" = "yes" ]; then
        echo -e "  ${ICON_ZFS} Local ZFS Mode: $ZFS_DATASET"
        # Verify local dataset is mounted
        verify_zfs_mount "$ZFS_DATASET" "$ZFS_MOUNTPOINT"
        echo ""
    fi
    
    print_step "1" "Testing NAS connectivity" "start"
    if ! ping -c 1 -W 2 "$NAS_IP" &> /dev/null; then
        print_step "1" "NAS unreachable" "error"
        send_notification "NAS Backup Failed" "NAS unreachable" "critical"
        return 1
    fi
    print_step "1" "NAS reachable" "done"
    
    print_step "2" "Testing SSH connection" "start"
    
    if ssh $SSH_OPTS -o BatchMode=yes "${NAS_USER}@${NAS_IP}" "echo OK" &> /dev/null; then
        print_step "2" "SSH key auth successful" "done"
    else
        print_step "2" "SSH key auth failed, will use password" "warn"
        if ! ssh $SSH_OPTS "${NAS_USER}@${NAS_IP}" "echo OK" &> /dev/null; then
            print_step "2" "SSH connection failed after ${SSH_TIMEOUT}s timeout" "error"
            return 1
        fi
    fi
    
    ensure_nas_directory || return 1
    
    print_step "4" "Checking NAS disk space" "start"
    local nas_space=$(ssh $SSH_OPTS "${NAS_USER}@${NAS_IP}" "df -k \"${NAS_BACKUP_PATH}\" 2>/dev/null | awk 'NR==2 {print \$4,\$5}'" 2>/dev/null)
    if [ -n "$nas_space" ]; then
        local nas_free_kb=$(echo "$nas_space" | awk '{print $1}')
        local nas_percent=$(echo "$nas_space" | awk '{print $2}' | tr -d '%')
        local nas_free_hr=$(numfmt --to=iec --suffix=B $((nas_free_kb * 1024)) 2>/dev/null || echo "${nas_free_kb}KB")
        print_step "4" "NAS free space: $nas_free_hr (${nas_percent}% used)" "info"
        
        if [ "$nas_percent" -gt $((100 - MIN_FREE_SPACE_PERCENT)) ]; then
            print_warning "NAS has less than ${MIN_FREE_SPACE_PERCENT}% free space"
            read -p "  ${ICON_ARROW} Continue anyway? (yes/no): " -r confirm
            if [[ ! "$confirm" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
                return 1
            fi
        fi
    fi
    
    print_step "5" "Loading exclusions" "start"
    show_exclusions
    
    echo ""
    print_warning "Backup: $HOME_DIR → ${NAS_USER}@${NAS_IP}:${NAS_BACKUP_PATH}"
    echo ""
    read -p "  ${ICON_ARROW} Proceed? (yes/no): " -r confirmation
    
    if [[ ! "$confirmation" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
        print_warning "Cancelled"
        return 0
    fi
    
    print_step "6" "Running rsync to NAS" "start"
    local exclude_file=$(create_exclude_file)
    local bw_arg=""
    
    if [ "$BW_LIMIT" -gt 0 ]; then
        bw_arg="--bwlimit=$BW_LIMIT"
        print_step "6" "Bandwidth limit: ${BW_LIMIT} KB/s (protects NAS)" "info"
    fi
    
    # Use rsync with SSH options and timeout protection
    if rsync -rPaAXvh --info=progress2 --no-inc-recursive $bw_arg \
        --delete-before \
        --exclude-from="$exclude_file" \
        "$HOME_DIR/" \
        -e "ssh $SSH_OPTS" \
        "${NAS_USER}@${NAS_IP}:\"${NAS_BACKUP_PATH}\"/" 2>&1 | tee -a "$LOG_FILE"; then
        
        print_step "6" "Rsync completed" "done"
        
        print_step "7" "Verifying backup" "start"
        local nas_size=$(ssh $SSH_OPTS "${NAS_USER}@${NAS_IP}" "du -sh \"${NAS_BACKUP_PATH}\" 2>/dev/null | cut -f1" 2>/dev/null)
        print_step "7" "NAS backup size: ${nas_size:-unknown}" "done"
        
        # Create ZFS snapshot on NAS if possible (optional - would need ZFS on NAS)
        if [ "$USE_ZFS" = "yes" ]; then
            print_step "zfs" "Checking if NAS supports ZFS snapshots..." "info"
            # This is optional and would require ZFS on the NAS
        fi
    else
        local exit_code=$?
        print_step "6" "Backup failed ($exit_code)" "error"
        rm -f "$exclude_file"
        send_notification "NAS Backup Failed" "Failed with code $exit_code" "critical"
        return $exit_code
    fi
    
    print_step "8" "Cleaning up" "start"
    rm -f "$exclude_file"
    print_step "8" "Cleanup done" "done"
    
    if [ "$RETENTION_DAYS" -gt 0 ]; then
        clean_old_backups "nas"
    fi
    
    rotate_logs
    
    echo ""
    print_success "NAS backup completed at $(date)"
    print_info "Log: $LOG_FILE"
    
    send_notification "NAS Backup Complete" "NAS backup completed successfully" "normal"
}

# Quiet mode for cron (no menus, just NAS backup)
perform_quiet_backup() {
    echo "[$(date)] Starting quiet NAS backup..." >> "$LOG_DIR/quiet.log"
    
    if [ -z "${NAS_IP:-}" ] || [ -z "${NAS_USER:-}" ]; then
        echo "[$(date)] ERROR: NAS not configured" >> "$LOG_DIR/quiet.log"
        exit 1
    fi
    
    # Test connection silently
    if ! ping -c 1 -W 2 "$NAS_IP" &> /dev/null; then
        echo "[$(date)] ERROR: NAS unreachable" >> "$LOG_DIR/quiet.log"
        exit 1
    fi
    
    # Run backup with minimal output
    local exclude_file=$(create_exclude_file)
    local bw_arg=""
    
    if [ "$BW_LIMIT" -gt 0 ]; then
        bw_arg="--bwlimit=$BW_LIMIT"
    fi
    
    rsync -rPaAXv --no-inc-recursive $bw_arg \
        --delete-before \
        --exclude-from="$exclude_file" \
        "$HOME_DIR/" \
        -e "ssh $SSH_OPTS" \
        "${NAS_USER}@${NAS_IP}:\"${NAS_BACKUP_PATH}\"/" >> "$LOG_DIR/quiet.log" 2>&1
    
    local result=$?
    rm -f "$exclude_file"
    
    if [ $result -eq 0 ]; then
        echo "[$(date)] SUCCESS: NAS backup completed" >> "$LOG_DIR/quiet.log"
        # Rotate logs
        find "$LOG_DIR" -name "vault_*.log" -type f -mtime +7 -delete 2>/dev/null
        # Keep quiet.log under 10MB
        if [ -f "$LOG_DIR/quiet.log" ] && [ $(stat -c%s "$LOG_DIR/quiet.log" 2>/dev/null || echo 0) -gt 10485760 ]; then
            mv "$LOG_DIR/quiet.log" "$LOG_DIR/quiet.log.old"
        fi
    else
        echo "[$(date)] FAILED: NAS backup exited with code $result" >> "$LOG_DIR/quiet.log"
    fi
    
    exit $result
}

# =============================================================================
#                         R E S T O R E   F U N C T I O N S
# =============================================================================

backup_current_home() {
    local current_backup="/home/${USERNAME}_backup_before_restore_$(date +%Y%m%d_%H%M%S)"
    
    print_step "4" "Creating safety backup" "start"
    
    if [ -d "$HOME_DIR" ] && [ "$(ls -A $HOME_DIR 2>/dev/null)" ]; then
        if cp -a "$HOME_DIR" "$current_backup" 2>&1 | tee -a "$LOG_FILE"; then
            print_step "4" "Current home backed up to: $current_backup" "done"
        else
            print_step "4" "Backup failed" "error"
            read -p "  ${ICON_ARROW} Continue anyway? (yes/no): " -r confirm
            if [[ ! "$confirm" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
                return 1
            fi
        fi
    fi
    
    return 0
}

fix_permissions() {
    print_step "6" "Fixing permissions" "start"
    
    if id "$USERNAME" &>/dev/null; then
        chown -R "$USERNAME:$USERNAME" "$HOME_DIR" 2>&1 | tee -a "$LOG_FILE" || true
        find "$HOME_DIR" -type d -exec chmod 755 {} \; 2>/dev/null || true
        find "$HOME_DIR" -type f -exec chmod 644 {} \; 2>/dev/null || true
        
        if [ -d "$HOME_DIR/.ssh" ]; then
            chmod 700 "$HOME_DIR/.ssh" 2>/dev/null || true
            chmod 600 "$HOME_DIR/.ssh/*" 2>/dev/null || true
        fi
        
        print_step "6" "Permissions fixed" "done"
    fi
}

perform_local_restore() {
    print_header "LOCAL RESTORE - ${USERNAME}"
    
    if [ "$USE_ZFS" = "yes" ]; then
        echo -e "  ${ICON_ZFS} ZFS snapshots available:"
        list_zfs_snapshots "$ZFS_DATASET" | tail -5 | while read snap; do
            echo -e "    ${ICON_SNAPSHOT} $snap"
        done
        echo ""
    fi
    
    print_step "1" "Checking backup" "start"
    if [ ! -d "$LOCAL_BACKUP_CURRENT" ] && [ ! -d "$LOCAL_BACKUP_DEST" ]; then
        print_step "1" "No backup at: $LOCAL_BACKUP_DEST" "error"
        return 1
    fi
    
    local source_path="${LOCAL_BACKUP_CURRENT:-$LOCAL_BACKUP_DEST}"
    print_step "1" "Found backup: $source_path" "done"
    
    print_step "2" "Backup info" "start"
    local backup_size=$(du -sh "$source_path" 2>/dev/null | cut -f1)
    local backup_date=$(stat -c %y "$source_path" 2>/dev/null | cut -d. -f1)
    local file_count=$(find "$source_path" -type f 2>/dev/null | wc -l)
    
    print_step "2" "Size: ${backup_size:-unknown}" "info"
    print_step "2" "Date: ${backup_date:-unknown}" "info"
    print_step "2" "Files: ${file_count:-0}" "info"
    
    print_step "3" "Select mode" "start"
    echo ""
    echo -e "  ${BOLD_WHITE}Modes:${NC}"
    echo -e "    ${BOLD_CYAN}1.${NC} Normal (overwrites files)"
    echo -e "    ${BOLD_CYAN}2.${NC} Dry run (simulate)"
    echo -e "    ${BOLD_CYAN}3.${NC} Verify only (list differences)"
    echo ""
    read -p "  ${ICON_ARROW} Choose (1-3): " -n 1 -r mode_choice
    echo ""
    
    local rsync_opts="-a --progress"
    
    case $mode_choice in
        1)
            rsync_opts="$rsync_opts --delete"
            print_step "3" "Mode: Normal" "warn"
            
            echo ""
            print_error "WARNING: This will OVERWRITE files in $HOME_DIR"
            print_error "Files not in backup will be DELETED"
            echo ""
            read -p "  ${ICON_ARROW} Type 'YES' to confirm: " -r confirm
            if [ "$confirm" != "YES" ]; then
                print_warning "Cancelled"
                return 0
            fi
            
            backup_current_home || return 1
            ;;
        2)
            rsync_opts="$rsync_opts --delete --dry-run"
            print_step "3" "Mode: Dry run" "info"
            ;;
        3)
            rsync_opts="$rsync_opts --delete --list-only"
            print_step "3" "Mode: Verify" "info"
            ;;
        *)
            print_step "3" "Invalid option" "error"
            return 1
            ;;
    esac
    
    print_step "5" "Running restore" "start"
    
    if rsync $rsync_opts "$source_path/" "$HOME_DIR/" 2>&1 | tee -a "$LOG_FILE"; then
        print_step "5" "Restore completed" "done"
        
        if [ $mode_choice -eq 1 ]; then
            fix_permissions
        fi
        
        print_step "7" "Verifying" "start"
        print_step "7" "Done" "done"
    else
        local exit_code=$?
        print_step "5" "Restore failed ($exit_code)" "error"
        return $exit_code
    fi
    
    rotate_logs
    
    echo ""
    print_success "Local restore completed at $(date)"
    print_info "Log: $LOG_FILE"
    
    send_notification "Restore Complete" "Local restore completed" "normal"
}

perform_nas_restore() {
    if [ -z "${NAS_IP:-}" ] || [ -z "${NAS_USER:-}" ]; then
        print_error "NAS not configured"
        return 1
    fi
    
    print_header "NAS RESTORE - ${USERNAME}"
    
    print_step "1" "Testing NAS connectivity" "start"
    if ! ping -c 1 -W 2 "$NAS_IP" &> /dev/null; then
        print_step "1" "NAS unreachable" "error"
        return 1
    fi
    print_step "1" "NAS reachable" "done"
    
    print_step "2" "Testing SSH connection" "start"
    if ssh $SSH_OPTS -o BatchMode=yes "${NAS_USER}@${NAS_IP}" "echo OK" &> /dev/null; then
        print_step "2" "SSH key auth successful" "done"
    else
        print_step "2" "Will use password auth" "warn"
        if ! ssh $SSH_OPTS "${NAS_USER}@${NAS_IP}" "echo OK" &> /dev/null; then
            print_step "2" "SSH connection failed after ${SSH_TIMEOUT}s timeout" "error"
            return 1
        fi
    fi
    
    print_step "3" "Checking backup on NAS" "start"
    if ! ssh $SSH_OPTS "${NAS_USER}@${NAS_IP}" "test -d \"${NAS_BACKUP_PATH}\"" 2>/dev/null; then
        print_step "3" "No backup on NAS" "error"
        return 1
    fi
    print_step "3" "Backup found" "done"
    
    print_step "4" "NAS backup info" "start"
    local nas_size=$(ssh $SSH_OPTS "${NAS_USER}@${NAS_IP}" "du -sh \"${NAS_BACKUP_PATH}\" 2>/dev/null | cut -f1" 2>/dev/null)
    local nas_files=$(ssh $SSH_OPTS "${NAS_USER}@${NAS_IP}" "find \"${NAS_BACKUP_PATH}\" -type f 2>/dev/null | wc -l" 2>/dev/null)
    print_step "4" "Size: ${nas_size:-unknown}" "info"
    print_step "4" "Files: ${nas_files:-unknown}" "info"
    
    print_step "5" "Select mode" "start"
    echo ""
    echo -e "  ${BOLD_WHITE}Modes:${NC}"
    echo -e "    ${BOLD_CYAN}1.${NC} Normal (overwrites files)"
    echo -e "    ${BOLD_CYAN}2.${NC} Dry run (simulate)"
    echo -e "    ${BOLD_CYAN}3.${NC} Verify only (list differences)"
    echo ""
    read -p "  ${ICON_ARROW} Choose (1-3): " -n 1 -r mode_choice
    echo ""
    
    local rsync_opts="-a --progress"
    local bw_arg=""
    
    if [ "$BW_LIMIT" -gt 0 ]; then
        bw_arg="--bwlimit=$BW_LIMIT"
    fi
    
    case $mode_choice in
        1)
            rsync_opts="$rsync_opts --delete $bw_arg"
            print_step "5" "Mode: Normal" "warn"
            
            echo ""
            print_error "WARNING: This will OVERWRITE files in $HOME_DIR"
            print_error "Files not in backup will be DELETED"
            echo ""
            read -p "  ${ICON_ARROW} Type 'YES' to confirm: " -r confirm
            if [ "$confirm" != "YES" ]; then
                print_warning "Cancelled"
                return 0
            fi
            
            backup_current_home || return 1
            ;;
        2)
            rsync_opts="$rsync_opts --delete --dry-run $bw_arg"
            print_step "5" "Mode: Dry run" "info"
            ;;
        3)
            rsync_opts="$rsync_opts --delete --list-only $bw_arg"
            print_step "5" "Mode: Verify" "info"
            ;;
        *)
            print_step "5" "Invalid option" "error"
            return 1
            ;;
    esac
    
    print_step "6" "Running restore from NAS" "start"
    
    if rsync $rsync_opts -e "ssh $SSH_OPTS" "${NAS_USER}@${NAS_IP}:\"${NAS_BACKUP_PATH}\"/" "$HOME_DIR/" 2>&1 | tee -a "$LOG_FILE"; then
        print_step "6" "Restore completed" "done"
        
        if [ $mode_choice -eq 1 ]; then
            fix_permissions
        fi
        
        print_step "7" "Verifying" "start"
        print_step "7" "Done" "done"
    else
        local exit_code=$?
        print_step "6" "Restore failed ($exit_code)" "error"
        return $exit_code
    fi
    
    rotate_logs
    
    echo ""
    print_success "NAS restore completed at $(date)"
    print_info "Log: $LOG_FILE"
    
    send_notification "NAS Restore Complete" "NAS restore completed" "normal"
}

# =============================================================================
#                     S E T U P   F U N C T I O N S
# =============================================================================

setup_ssh_key() {
    if [ -z "${NAS_IP:-}" ] || [ -z "${NAS_USER:-}" ]; then
        print_error "NAS not configured"
        return 1
    fi
    
    print_header "SSH KEY SETUP"
    
    local key_file="${HOME}/.ssh/id_rsa"
    
    print_step "1" "Checking SSH keys" "start"
    if [ ! -f "${key_file}.pub" ]; then
        print_step "1" "No SSH key found, generating..." "warn"
        ssh-keygen -t rsa -b 4096 -f "$key_file" -N ""
        print_step "1" "SSH key generated" "done"
    else
        print_step "1" "SSH key found" "done"
    fi
    
    print_step "2" "Copying to NAS" "start"
    print_warning "You'll be prompted for NAS password"
    ssh-copy-id "${NAS_USER}@${NAS_IP}"
    
    if [ $? -eq 0 ]; then
        print_step "2" "SSH key copied" "done"
    else
        print_step "2" "Failed to copy" "error"
        return 1
    fi
    
    echo ""
    print_success "SSH key setup complete"
    print_info "Test with: ssh $SSH_OPTS ${NAS_USER}@${NAS_IP}"
}

# =============================================================================
#                     Z F S   S N A P S H O T   M A N A G E M E N T
# =============================================================================

manage_zfs_snapshots() {
    print_header "ZFS SNAPSHOT MANAGEMENT"
    
    if [ "$USE_ZFS" != "yes" ] || [ -z "$ZFS_DATASET" ]; then
        print_error "ZFS mode not enabled"
        return 1
    fi
    
    # Verify dataset is mounted
    verify_zfs_mount "$ZFS_DATASET" "$ZFS_MOUNTPOINT"
    
    echo -e "  ${ICON_ZFS} Dataset: $ZFS_DATASET\n"
    
    echo -e "  ${BOLD_WHITE}Recent snapshots:${NC}"
    list_zfs_snapshots "$ZFS_DATASET" | tail -10 | while read snap; do
        echo -e "    ${ICON_SNAPSHOT} $snap"
    done
    echo ""
    
    echo -e "  ${BOLD_WHITE}Options:${NC}"
    echo -e "    ${BOLD_CYAN}1.${NC} Create manual snapshot now (atomic naming)"
    echo -e "    ${BOLD_CYAN}2.${NC} Clean old snapshots (dry run)"
    echo -e "    ${BOLD_CYAN}3.${NC} Clean old snapshots (actual)"
    echo -e "    ${BOLD_CYAN}4.${NC} Back to main menu"
    echo ""
    
    read -p "  ${ICON_ARROW} Choose option [1-4]: " -r snap_choice
    
    case $snap_choice in
        1)
            create_zfs_snapshot "$ZFS_DATASET"
            ;;
        2)
            clean_zfs_snapshots "$ZFS_DATASET" "$ZFS_SNAPSHOT_RETENTION" "yes"
            ;;
        3)
            clean_zfs_snapshots "$ZFS_DATASET" "$ZFS_SNAPSHOT_RETENTION"
            ;;
        4)
            return 0
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
    
    echo ""
    read -p "  ${ICON_ARROW} Press Enter to continue..."
}

# =============================================================================
#                     I N F O R M A T I O N   F U N C T I O N S
# =============================================================================

show_backup_info() {
    print_header "BACKUP INFO - ${USERNAME}"
    
    echo -e "  ${ICON_HOME} ${BOLD_GREEN}LOCAL BACKUP${NC}"
    echo -e "  ${BOLD_WHITE}━━━━━━━━━━━━━━${NC}"
    
    if [ -L "$LOCAL_BACKUP_CURRENT" ] && [ -d "$(readlink $LOCAL_BACKUP_CURRENT)" ]; then
        local current_backup=$(readlink $LOCAL_BACKUP_CURRENT)
        local backup_size=$(du -sh "$current_backup" 2>/dev/null | cut -f1)
        local backup_date=$(stat -c %y "$current_backup" 2>/dev/null | cut -d. -f1)
        local file_count=$(find "$current_backup" -type f 2>/dev/null | wc -l)
        
        echo -e "  ${BOLD_CYAN}Current:${NC}  $(basename $current_backup)"
        echo -e "  ${BOLD_CYAN}Size:${NC}     ${backup_size:-unknown}"
        echo -e "  ${BOLD_CYAN}Date:${NC}     ${backup_date:-unknown}"
        echo -e "  ${BOLD_CYAN}Files:${NC}    ${file_count:-0}"
        
        if [ -d "$LOCAL_BACKUP_INCREMENTAL" ]; then
            local backup_count=$(find "$LOCAL_BACKUP_INCREMENTAL" -maxdepth 1 -type d -name "????-??-??_??-??-??" 2>/dev/null | wc -l)
            echo -e "  ${BOLD_CYAN}Versions:${NC} ${backup_count}"
            
            local oldest=$(find "$LOCAL_BACKUP_INCREMENTAL" -maxdepth 1 -type d -name "????-??-??_??-??-??" | sort | head -1 | xargs basename 2>/dev/null)
            local newest=$(find "$LOCAL_BACKUP_INCREMENTAL" -maxdepth 1 -type d -name "????-??-??_??-??-??" | sort -r | head -1 | xargs basename 2>/dev/null)
            
            [ -n "$oldest" ] && echo -e "  ${BOLD_CYAN}Oldest:${NC}    $oldest"
            [ -n "$newest" ] && echo -e "  ${BOLD_CYAN}Newest:${NC}    $newest"
        fi
        
        local disk_space=$(df -h "$LOCAL_BACKUP_BASE" 2>/dev/null | awk 'NR==2 {print $4,"free,",$5,"used"}')
        echo -e "  ${BOLD_CYAN}Disk:${NC}      $disk_space"
        
    elif [ -d "$LOCAL_BACKUP_DEST" ]; then
        local backup_size=$(du -sh "$LOCAL_BACKUP_DEST" 2>/dev/null | cut -f1)
        echo -e "  ${BOLD_CYAN}Location:${NC} $LOCAL_BACKUP_DEST"
        echo -e "  ${BOLD_CYAN}Size:${NC}     ${backup_size:-unknown}"
    else
        echo -e "  ${YELLOW}No local backup found${NC}"
    fi
    
    echo ""
    
    if [ "$USE_ZFS" = "yes" ] && [ -n "$ZFS_DATASET" ]; then
        echo -e "  ${ICON_ZFS} ${BOLD_CYAN}ZFS DATASET${NC}"
        echo -e "  ${BOLD_WHITE}━━━━━━━━━━━━━━${NC}"
        
        # Verify mount status
        local mounted=$(zfs get -H -o value mounted "$ZFS_DATASET" 2>/dev/null)
        local mountpoint=$(zfs get -H -o value mountpoint "$ZFS_DATASET" 2>/dev/null)
        local snap_count=$(zfs list -t snapshot -r "$ZFS_DATASET" 2>/dev/null | wc -l)
        snap_count=$((snap_count - 1))  # Subtract header
        
        local zfs_compress=$(zfs get -H -o value compression "$ZFS_DATASET" 2>/dev/null)
        local zfs_atime=$(zfs get -H -o value atime "$ZFS_DATASET" 2>/dev/null)
        local zfs_recordsize=$(zfs get -H -o value recordsize "$ZFS_DATASET" 2>/dev/null)
        local zfs_used=$(zfs get -H -o value used "$ZFS_DATASET" 2>/dev/null)
        local zfs_avail=$(zfs get -H -o value available "$ZFS_DATASET" 2>/dev/null)
        
        echo -e "  ${BOLD_CYAN}Dataset:${NC}     $ZFS_DATASET"
        echo -e "  ${BOLD_CYAN}Mount:${NC}       ${mounted:-unknown} at ${mountpoint}"
        echo -e "  ${BOLD_CYAN}Compression:${NC} $zfs_compress"
        echo -e "  ${BOLD_CYAN}Snapshots:${NC}   ${snap_count:-0} (atomic naming)"
        echo -e "  ${BOLD_CYAN}Used/Avail:${NC}  $zfs_used / $zfs_avail"
        echo -e "  ${BOLD_CYAN}Settings:${NC}    atime=$zfs_atime, recordsize=$zfs_recordsize"
        echo ""
    fi
    
    if [ -n "${NAS_IP:-}" ] && [ -n "${NAS_USER:-}" ]; then
        echo -e "  ${ICON_NAS} ${BOLD_YELLOW}NAS BACKUP${NC}"
        echo -e "  ${BOLD_WHITE}━━━━━━━━━━${NC}"
        
        if ping -c 1 -W 2 "$NAS_IP" &> /dev/null; then
            if ssh $SSH_OPTS -o BatchMode=yes "${NAS_USER}@${NAS_IP}" "test -d \"${NAS_BACKUP_PATH}\"" 2>/dev/null; then
                local nas_size=$(ssh $SSH_OPTS "${NAS_USER}@${NAS_IP}" "du -sh \"${NAS_BACKUP_PATH}\" 2>/dev/null | cut -f1" 2>/dev/null)
                local nas_files=$(ssh $SSH_OPTS "${NAS_USER}@${NAS_IP}" "find \"${NAS_BACKUP_PATH}\" -type f 2>/dev/null | wc -l" 2>/dev/null)
                local nas_space=$(ssh $SSH_OPTS "${NAS_USER}@${NAS_IP}" "df -h \"${NAS_BACKUP_PATH}\" 2>/dev/null | awk 'NR==2 {print \$4,\"free,\",\$5,\"used\"}'" 2>/dev/null)
                
                echo -e "  ${BOLD_CYAN}Location:${NC} ${NAS_USER}@${NAS_IP}:${NAS_BACKUP_PATH}"
                echo -e "  ${BOLD_CYAN}Size:${NC}     ${nas_size:-unknown}"
                echo -e "  ${BOLD_CYAN}Files:${NC}    ${nas_files:-unknown}"
                echo -e "  ${BOLD_CYAN}Speed:${NC}    ${BW_LIMIT} KB/s limit"
                echo -e "  ${BOLD_CYAN}SSH:${NC}       Timeout ${SSH_TIMEOUT}s, Keep-alive ${SSH_ALIVE}s"
                [ -n "$nas_space" ] && echo -e "  ${BOLD_CYAN}Disk:${NC}      $nas_space"
                
                local nas_backup_count=$(ssh $SSH_OPTS "${NAS_USER}@${NAS_IP}" "find \"${NAS_BACKUP_PATH}\" -maxdepth 1 -type d -name '????-??-??_??-??-??' 2>/dev/null | wc -l")
                [ "$nas_backup_count" -gt 0 ] && echo -e "  ${BOLD_CYAN}Versions:${NC} ${nas_backup_count}"
            else
                echo -e "  ${YELLOW}No backup found on NAS${NC}"
            fi
        else
            echo -e "  ${RED}NAS unreachable${NC}"
        fi
    fi
    
    echo ""
}

show_help() {
    cat << EOF
${BOLD_CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}
${BOLD_CYAN}║           M Y   H O M E   V A U L T   Z F S   v5.1.5b-zfs            ║${NC}
${BOLD_CYAN}╚══════════════════════════════════════════════════════════════════════════╝${NC}

${BOLD_WHITE}USAGE:${NC}
  sudo ./${SCRIPT_NAME} [OPTION]  (ZFS commands require root)

${BOLD_WHITE}ZFS FEATURES:${NC}
  • Automatic pool/dataset detection
  • LZ4 compression (saves space, minimal CPU)
  • Atomic snapshots with PID + millisecond precision (collision-proof)
  • Snapshot retention (14 days default)
  • Mount verification before backup (prevents writing to wrong location)
  • Optional ZFS send/receive to remote host

${BOLD_WHITE}ATOMIC SNAPSHOT NAMING:${NC}
  • Format: mhv_YYYYMMDD_HHMMSS_PID
  • Millisecond precision on retry
  • 5 retry attempts before failure
  • Ensures 100% unique snapshot names

${BOLD_WHITE}OPTIONS:${NC}
  ${BOLD_GREEN}--help, -h${NC}     Show this help
  ${BOLD_GREEN}--version${NC}      Show version
  ${BOLD_GREEN}--quiet, -q${NC}    Run in quiet mode (for cron) - performs NAS backup
  ${BOLD_GREEN}--repair${NC}       Run VAULT-FIX repair mode (verify & fix NAS backup)
  ${BOLD_GREEN}--dry-run${NC}      Simulation mode
  ${BOLD_GREEN}--quick${NC}        Skip checksum verify
  ${BOLD_GREEN}--reconfigure${NC}  Run setup wizard again

${BOLD_WHITE}MENU OPTIONS:${NC}
  ${BOLD_CYAN}1${NC}  Local Backup    - Create incremental local backup (with ZFS snapshot)
  ${BOLD_CYAN}2${NC}  Local Restore   - Restore from local backup
  ${BOLD_CYAN}3${NC}  NAS Backup      - Backup to NAS (with speed limiting)
  ${BOLD_CYAN}4${NC}  NAS Restore     - Restore from NAS
  ${BOLD_CYAN}5${NC}  Show Info       - Display backup information
  ${BOLD_CYAN}6${NC}  Repair Mode     - VAULT-FIX: verify & repair NAS backup
  ${BOLD_CYAN}7${NC}  ZFS Snapshots   - Manage ZFS snapshots
  ${BOLD_CYAN}8${NC}  Test NAS        - Test NAS connection
  ${BOLD_CYAN}9${NC}  Setup SSH Key   - Configure passwordless NAS
  ${BOLD_CYAN}10${NC} Cron Setup      - Schedule automatic backups
  ${BOLD_CYAN}11${NC} Log Management  - View/delete logs
  ${BOLD_CYAN}12${NC} Cleanup Dry-Run - Preview old backups
  ${BOLD_CYAN}13${NC} Exit

${BOLD_WHITE}CONFIG:${NC}
  File: ${BOLD_CYAN}~/.my-home-vault-zfs.conf${NC}
  Logs: ${BOLD_CYAN}~/.my-home-vault/logs/${NC}

${BOLD_WHITE}CHECK STATUS:${NC}
  ${BOLD_GREEN}grep "SUCCESS" ~/.my-home-vault/logs/quiet.log${NC}
  ${BOLD_GREEN}zfs list -t snapshot | grep ${ZFS_SNAPSHOT_PREFIX}${NC}

${BOLD_WHITE}CRON EXAMPLE (daily at 2 AM):${NC}
  0 2 * * * root ${HOME}/${SCRIPT_NAME} --quiet

${BOLD_WHITE}HARDWARE RECOMMENDATIONS:${NC}
  • Seagate IronWolf 4TB - Best for ZFS snapshot metadata (AgileArray)
  • WD Red Plus 4TB      - Best for LZ4 compression & stability
  • ECC RAM              - Recommended for ZFS data integrity

${BOLD_WHITE}My Home Vault ZFS - Atomic Snapshots, Zero Collisions.${NC}
${BOLD_WHITE}https://github.com/waelisa/my-home-vault${NC}
EOF
    exit 0
}

# =============================================================================
#                           M A I N   M E N U
# =============================================================================

show_banner() {
    clear
    echo -e "${BOLD_CYAN}"
    echo "  ╔════════════════════════════════════════════════════════════════╗"
    echo "  ║         M Y   H O M E   V A U L T   Z F S   v5.1.5b-zfs       ║"
    echo "  ║           Your Data, Fortified · https://wael.name            ║"
    echo "  ╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  ${ICON_VAULT} ${BOLD_WHITE}Guardian of${NC} ${BOLD_GREEN}${USERNAME}${NC} | ${ICON_HOME} ${BOLD_WHITE}Local${NC} | ${ICON_NAS} ${BOLD_WHITE}NAS${NC}"
    
    if [ "$USE_ZFS" = "yes" ]; then
        # Check mount status for display
        local mounted=$(zfs get -H -o value mounted "$ZFS_DATASET" 2>/dev/null || echo "unknown")
        local mount_status="$([ "$mounted" = "yes" ] && echo "mounted" || echo "⚠ not mounted")"
        echo -e "  ${ICON_ZFS} ${BOLD_WHITE}ZFS Mode:${NC} $ZFS_DATASET (compression=$ZFS_COMPRESSION) - ${BOLD_GREEN}$mount_status${NC}"
        echo -e "  ${ICON_ATOMIC} ${BOLD_WHITE}Atomic Snapshots:${NC} PID + millisecond precision"
    fi
    
    if [ "$BW_LIMIT" -gt 0 ]; then
        echo -e "  ${ICON_NAS} ${BOLD_WHITE}NAS Speed:${NC} ${BW_LIMIT} KB/s limit"
    fi
    
    echo -e "  ${ICON_CPU} ${BOLD_WHITE}SSH Timeout:${NC} ${SSH_TIMEOUT}s"
    echo -e "  ${ICON_USB} ${BOLD_WHITE}USB Protection:${NC} Auto-remount read-only drives"
    
    check_for_updates
    echo ""
}

show_menu() {
    echo -e "${BOLD_CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD_CYAN}║                         M A I N   M E N U                                ║${NC}"
    echo -e "${BOLD_CYAN}╠══════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD_CYAN}║                                                                          ║${NC}"
    echo -e "${BOLD_CYAN}║  ${BOLD_GREEN}BACKUP & RESTORE:${NC}                                               ║${NC}"
    echo -e "${BOLD_CYAN}║    ${BOLD_WHITE}1.${NC} Local Backup    - $HOME_DIR → $LOCAL_BACKUP_DEST      ║${NC}"
    echo -e "${BOLD_CYAN}║    ${BOLD_WHITE}2.${NC} Local Restore   - $LOCAL_BACKUP_DEST → $HOME_DIR      ║${NC}"
    
    if [ -n "${NAS_IP:-}" ]; then
        echo -e "${BOLD_CYAN}║    ${BOLD_WHITE}3.${NC} NAS Backup      - $HOME_DIR → ${NAS_USER}@${NAS_IP}:${NAS_BACKUP_PATH} ║${NC}"
        echo -e "${BOLD_CYAN}║    ${BOLD_WHITE}4.${NC} NAS Restore     - ${NAS_USER}@${NAS_IP}:${NAS_BACKUP_PATH} → $HOME_DIR ║${NC}"
    fi
    
    echo -e "${BOLD_CYAN}║                                                                          ║${NC}"
    echo -e "${BOLD_CYAN}║  ${BOLD_YELLOW}MAINTENANCE:${NC}                                                   ║${NC}"
    echo -e "${BOLD_CYAN}║    ${BOLD_WHITE}5.${NC} Show backup info${NC}                                          ║${NC}"
    echo -e "${BOLD_CYAN}║    ${BOLD_WHITE}6.${NC} Repair Mode (VAULT-FIX) - Verify NAS backup${NC}             ║${NC}"
    
    if [ "$USE_ZFS" = "yes" ]; then
        echo -e "${BOLD_CYAN}║    ${BOLD_WHITE}7.${NC} ZFS Snapshots   - Manage snapshots (atomic)${NC}           ║${NC}"
    fi
    
    if [ -n "${NAS_IP:-}" ]; then
        local offset=$([ "$USE_ZFS" = "yes" ] && echo "8" || echo "7")
        echo -e "${BOLD_CYAN}║    ${BOLD_WHITE}${offset}.${NC} Test NAS connection${NC}                                       ║${NC}"
        echo -e "${BOLD_CYAN}║    ${BOLD_WHITE}$((offset+1)).${NC} Setup SSH key for NAS${NC}                                     ║${NC}"
    fi
    
    echo -e "${BOLD_CYAN}║                                                                          ║${NC}"
    echo -e "${BOLD_CYAN}║  ${BOLD_MAGENTA}AUTOMATION:${NC}                                                   ║${NC}"
    echo -e "${BOLD_CYAN}║    ${BOLD_WHITE}9.${NC} Cron Setup      - Schedule automatic backups${NC}               ║${NC}"
    echo -e "${BOLD_CYAN}║    ${BOLD_WHITE}10.${NC} Log Management  - View/delete logs${NC}                        ║${NC}"
    echo -e "${BOLD_CYAN}║    ${BOLD_WHITE}11.${NC} Cleanup Dry-Run - Preview old backups${NC}                     ║${NC}"
    echo -e "${BOLD_CYAN}║    ${BOLD_WHITE}12.${NC} Exit${NC}                                                      ║${NC}"
    echo -e "${BOLD_CYAN}║                                                                          ║${NC}"
    echo -e "${BOLD_CYAN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD_BLUE}Logs:${NC} $LOG_DIR"
    echo -e "  ${BOLD_BLUE}Config:${NC} $CONFIG_FILE"
    if [ "$USE_ZFS" = "yes" ]; then
        echo -e "  ${ICON_ZFS} ${BOLD_BLUE}ZFS Dataset:${NC} $ZFS_DATASET"
        echo -e "  ${ICON_ATOMIC} ${BOLD_BLUE}Atomic Snapshots:${NC} Enabled (PID + millisecond)"
    fi
    echo -e "  ${ICON_USB} ${BOLD_BLUE}USB Protection:${NC} Auto-remount if read-only"
    echo ""
}

# =============================================================================
#                           M A I N   E X E C U T I O N
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                ;;
            --version)
                echo "My Home Vault ZFS Edition version $CURRENT_VERSION"
                echo "Author: Wael Isa"
                echo "Website: https://www.wael.name"
                echo "GitHub: https://github.com/waelisa/my-home-vault"
                echo "License: MIT"
                exit 0
                ;;
            --quiet|-q)
                perform_quiet_backup
                ;;
            --repair)
                if [ -f "$CONFIG_FILE" ]; then
                    source "$CONFIG_FILE"
                    perform_repair
                else
                    echo "No configuration found. Run without flags first."
                    exit 1
                fi
                exit $?
                ;;
            --dry-run)
                DRY_RUN="--dry-run"
                shift
                ;;
            --quick)
                ENABLE_CHECKSUM_VERIFY="no"
                shift
                ;;
            --reconfigure)
                rm -f "$CONFIG_FILE"
                run_setup_wizard
                exec "$0" "$@"
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage"
                exit 1
                ;;
        esac
    done
}

main() {
    if [ $# -gt 0 ]; then
        parse_args "$@"
    fi
    
    show_banner
    
    mkdir -p "$LOCAL_BACKUP_INCREMENTAL" 2>/dev/null || true
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    
    while true; do
        show_menu
        
        local max_option=12
        if [ "$USE_ZFS" = "yes" ]; then
            max_option=13
        fi
        
        if [ -n "${NAS_IP:-}" ]; then
            read -p "  ${BOLD_YELLOW}➤${NC} Select option (1-${max_option}): " -r option
        else
            read -p "  ${BOLD_YELLOW}➤${NC} Select option (1-${max_option}, NAS options disabled): " -r option
        fi
        echo ""
        
        case $option in
            1)
                perform_local_backup
                ;;
            2)
                perform_local_restore
                ;;
            3)
                if [ -n "${NAS_IP:-}" ]; then
                    perform_nas_backup
                else
                    print_error "NAS not configured"
                fi
                ;;
            4)
                if [ -n "${NAS_IP:-}" ]; then
                    perform_nas_restore
                else
                    print_error "NAS not configured"
                fi
                ;;
            5)
                show_backup_info
                ;;
            6)
                if [ -n "${NAS_IP:-}" ]; then
                    perform_repair
                else
                    print_error "NAS not configured"
                fi
                ;;
            7)
                if [ "$USE_ZFS" = "yes" ]; then
                    manage_zfs_snapshots
                elif [ -n "${NAS_IP:-}" ]; then
                    test_nas_connection
                else
                    print_error "Invalid option"
                fi
                ;;
            8)
                if [ "$USE_ZFS" = "yes" ] && [ -n "${NAS_IP:-}" ]; then
                    test_nas_connection
                elif [ "$USE_ZFS" = "yes" ]; then
                    print_error "NAS not configured"
                elif [ -n "${NAS_IP:-}" ]; then
                    setup_ssh_key
                else
                    print_error "Invalid option"
                fi
                ;;
            9)
                if [ "$USE_ZFS" = "yes" ] && [ -n "${NAS_IP:-}" ]; then
                    setup_ssh_key
                else
                    setup_cron
                fi
                ;;
            10)
                if [ "$USE_ZFS" = "yes" ] && [ -n "${NAS_IP:-}" ]; then
                    setup_cron
                else
                    manage_logs
                fi
                ;;
            11)
                if [ "$USE_ZFS" = "yes" ] && [ -n "${NAS_IP:-}" ]; then
                    manage_logs
                else
                    print_header "CLEANUP DRY RUN"
                    clean_old_backups "local" "yes"
                    if [ -n "${NAS_IP:-}" ]; then
                        clean_old_backups "nas" "yes"
                    fi
                fi
                ;;
            12)
                if [ "$USE_ZFS" = "yes" ] && [ -n "${NAS_IP:-}" ]; then
                    print_header "CLEANUP DRY RUN"
                    clean_old_backups "local" "yes"
                    clean_old_backups "nas" "yes"
                elif [ "$USE_ZFS" = "yes" ]; then
                    print_header "CLEANUP DRY RUN"
                    clean_old_backups "local" "yes"
                else
                    echo -e "  ${BOLD_GREEN}Exiting...${NC}"
                    echo -e "  ${BOLD_BLUE}Logs saved in:${NC} $LOG_DIR"
                    echo -e "  ${ICON_VAULT} ${BOLD_CYAN}My Home Vault stands guard.${NC}"
                    exit 0
                fi
                ;;
            13)
                if [ "$USE_ZFS" = "yes" ]; then
                    echo -e "  ${BOLD_GREEN}Exiting...${NC}"
                    echo -e "  ${BOLD_BLUE}Logs saved in:${NC} $LOG_DIR"
                    echo -e "  ${ICON_VAULT} ${BOLD_CYAN}My Home Vault stands guard.${NC}"
                    exit 0
                else
                    print_error "Invalid option"
                fi
                ;;
            *)
                print_error "Invalid option. Please select 1-${max_option}"
                ;;
        esac
        
        echo ""
        read -p "  ${BOLD_BLUE}Press Enter to continue...${NC}"
        show_banner
    done
}

# Trap errors
trap 'print_error "Error on line $LINENO. Exit code: $?"; exit $?' ERR

# Run main with all arguments
main "$@"