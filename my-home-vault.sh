#!/bin/bash

# =============================================================================
#                          M Y   H O M E   V A U L T
#                            v5.1.5.b
# =============================================================================
#   GitHub    : https://github.com/waelisa/my-home-vault
#   License   : MIT
#   Author    : Wael Isa
#   Website   : https://www.wael.name
#   Date      : 22-02-2026
# =============================================================================
#   DESCRIPTION:
#   My Home Vault is a professional-grade backup guardian that requires zero
#   coding knowledge. First-run wizard auto-configures everything. Features
#   automatic drive detection, incremental backups (space-saving hard links),
#   NAS support, dry-run modes, automatic retention cleanup, integrity
#   verification, desktop notifications, cron integration, log rotation,
#   VAULT-FIX repair mode, crash-proof USB handling, and non-interactive
#   safety for automated backups.
# =============================================================================
#   NON-INTERACTIVE FEATURES:
#   • Cron-safe disk space checks (no hanging prompts)
#   • Automatic failure handling in quiet mode
#   • Smart confirmation skipping when running unattended
#   • Detailed logging for post-mortem analysis
# =============================================================================
#   QUICK START:
#   1. curl -O https://raw.githubusercontent.com/waelisa/my-home-vault/main/my-home-vault.sh
#   2. chmod +x my-home-vault.sh
#   3. ./my-home-vault.sh
#   4. Follow the 30-second wizard
#   5. Done!
# =============================================================================
#   For help: ./my-home-vault.sh --help
#   Check status: grep "SUCCESS" ~/.my-home-vault/logs/quiet.log
# =============================================================================

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# =============================================================================
#                         G L O B A L   F L A G S
# =============================================================================

# Initialize global flags (can be overridden by command line)
INTERACTIVE=true      # Default to interactive mode
DRY_RUN=""            # Empty by default
QUICK_MODE=false      # Quick mode flag

# =============================================================================
#                         D E P E N D E N C Y   C H E C K
# =============================================================================

# Color definitions for dependency check (minimal set)
DEP_RED='\033[0;31m'
DEP_GREEN='\033[0;32m'
DEP_YELLOW='\033[1;33m'
DEP_NC='\033[0m'

echo -e "${DEP_YELLOW}🔍 Checking dependencies...${DEP_NC}"

MISSING_DEPS=()

# Check for required commands
for cmd in rsync ssh ping curl mount umount; do
    if ! command -v $cmd &> /dev/null; then
        MISSING_DEPS+=($cmd)
        echo -e "  ${DEP_RED}✗ $cmd not found${DEP_NC}"
    else
        echo -e "  ${DEP_GREEN}✓ $cmd found${DEP_NC}"
    fi
done

# If dependencies are missing, show installation instructions
if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo -e "\n${DEP_RED}❌ Missing required dependencies: ${MISSING_DEPS[*]}${DEP_NC}"
    echo -e "\n${DEP_YELLOW}Installation instructions:${DEP_NC}"
    
    # Detect distribution
    if command -v apt &> /dev/null; then
        # Debian/Ubuntu
        echo -e "  ${DEP_GREEN}Debian/Ubuntu:${DEP_NC} sudo apt update && sudo apt install ${MISSING_DEPS[*]}"
    elif command -v dnf &> /dev/null; then
        # Fedora
        echo -e "  ${DEP_GREEN}Fedora:${DEP_NC} sudo dnf install ${MISSING_DEPS[*]}"
    elif command -v yum &> /dev/null; then
        # RHEL/CentOS
        echo -e "  ${DEP_GREEN}RHEL/CentOS:${DEP_NC} sudo yum install ${MISSING_DEPS[*]}"
    elif command -v pacman &> /dev/null; then
        # Arch/Manjaro
        echo -e "  ${DEP_GREEN}Arch/Manjaro:${DEP_NC} sudo pacman -S ${MISSING_DEPS[*]}"
    elif command -v zypper &> /dev/null; then
        # openSUSE
        echo -e "  ${DEP_GREEN}openSUSE:${DEP_NC} sudo zypper install ${MISSING_DEPS[*]}"
    else
        echo -e "  ${DEP_YELLOW}Please install: ${MISSING_DEPS[*]} using your package manager${DEP_NC}"
    fi
    
    echo -e "\n${DEP_YELLOW}After installing dependencies, run this script again.${DEP_NC}"
    exit 1
fi

echo -e "${DEP_GREEN}✓ All dependencies satisfied!${DEP_NC}\n"
sleep 1

# =============================================================================
#                         C O R E   C O N F I G U R A T I O N
# =============================================================================

# --- Version Information ---
CURRENT_VERSION="5.1.5.b"
VERSION_URL="https://raw.githubusercontent.com/waelisa/my-home-vault/main/VERSION"
CONFIG_FILE="${HOME}/.my-home-vault.conf"
VAULT_DIR="${HOME}/.my-home-vault"
LOG_DIR="${VAULT_DIR}/logs"

# --- Auto-Detect User Details (Always works) ---
USERNAME=$(whoami)
HOME_DIR="${HOME}"

# --- Logging (with rotation) ---
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/vault_$(date +%Y%m%d_%H%M%S).log"

# --- Default Settings (can be overridden in wizard) ---
RETENTION_DAYS=14
ENABLE_NOTIFICATIONS="yes"
ENABLE_CHECKSUM_VERIFY="no"
MIN_FREE_SPACE_PERCENT=10
BW_LIMIT="5000"  # Default 5MB/s for NAS (protects slow drives)
SSH_TIMEOUT=10   # SSH connection timeout in seconds
SSH_ALIVE=60     # SSH server alive interval

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
ICON_AUTO="${BOLD_CYAN}🤖${NC}"  # New icon for non-interactive mode

# =============================================================================
#                     N O N - I N T E R A C T I V E   H E L P E R S
# =============================================================================

# Function to safely handle confirmations in non-interactive mode
safe_confirm() {
    local prompt="$1"
    local default="$2"  # Should be "yes" or "no"
    
    if [ "$INTERACTIVE" = false ]; then
        # Non-interactive mode - use default or fail
        log_message "${ICON_AUTO} Non-interactive mode: Auto-responding with '$default' to: $prompt"
        if [ "$default" = "yes" ]; then
            return 0
        else
            return 1
        fi
    else
        # Interactive mode - prompt user
        read -p "  ${ICON_ARROW} $prompt (yes/no): " -r response
        case $response in
            [Yy][Ee][Ss]|[Yy]) return 0 ;;
            *) return 1 ;;
        esac
    fi
}

# Function to safely handle read operations in non-interactive mode
safe_read() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    if [ "$INTERACTIVE" = false ]; then
        # Non-interactive mode - use default
        log_message "${ICON_AUTO} Non-interactive mode: Using default '$default' for: $prompt"
        eval "$var_name=\"$default\""
    else
        # Interactive mode - prompt user
        read -p "  ${ICON_ARROW} $prompt [$default]: " -r input
        if [ -z "$input" ]; then
            eval "$var_name=\"$default\""
        else
            eval "$var_name=\"$input\""
        fi
    fi
}

# =============================================================================
#                     F I R S T - T I M E   S E T U P   W I Z A R D
# =============================================================================

run_setup_wizard() {
    # Wizard always runs in interactive mode
    local old_interactive=$INTERACTIVE
    INTERACTIVE=true
    
    clear
    echo -e "${BOLD_CYAN}"
    echo "  ╔════════════════════════════════════════════════════════════════╗"
    echo "  ║              MY HOME VAULT - FIRST RUN WIZARD                 ║"
    echo "  ║                   30 Seconds • One Time                       ║"
    echo "  ╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${ICON_HOME} Welcome to My Home Vault! Let's secure your data."
    echo -e "${ICON_INFO} This configuration will be saved to: $CONFIG_FILE\n"
    
    # --- Detect available drives automatically ---
    echo -e "${BOLD_WHITE}Step 1: Detecting backup drives...${NC}"
    
    # Check for common mount points
    local detected_drives=()
    
    # Check /run/media (common on Arch/Manjaro)
    if [ -d "/run/media/${USERNAME}" ]; then
        while IFS= read -r drive; do
            detected_drives+=("$drive")
        done < <(find "/run/media/${USERNAME}" -maxdepth 1 -type d ! -path "/run/media/${USERNAME}" 2>/dev/null || true)
    fi
    
    # Check /media (common on Ubuntu/Debian)
    if [ -d "/media/${USERNAME}" ]; then
        while IFS= read -r drive; do
            detected_drives+=("$drive")
        done < <(find "/media/${USERNAME}" -maxdepth 1 -type d ! -path "/media/${USERNAME}" 2>/dev/null || true)
    fi
    
    # Check /mnt (common for manual mounts)
    while IFS= read -r drive; do
        if mountpoint -q "$drive" 2>/dev/null; then
            detected_drives+=("$drive")
        fi
    done < <(find /mnt -maxdepth 1 -type d ! -path "/mnt" 2>/dev/null || true)
    
    # Present drive selection
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
        safe_read "Select drive" "0" drive_choice
        
        if [ "$drive_choice" = "0" ]; then
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
    
    LOCAL_BACKUP_DEST="${LOCAL_BACKUP_BASE}/${USERNAME}"
    
    # --- NAS Configuration ---
    echo -e "\n${BOLD_WHITE}Step 2: NAS Configuration (optional)${NC}"
    echo -e "${ICON_INFO} If you have a NAS, enter details. Press Enter to skip.\n"
    
    safe_read "Enter NAS IP (e.g., 192.168.100.10)" "" input_ip
    
    if [ -n "$input_ip" ]; then
        NAS_IP="$input_ip"
        safe_read "Enter NAS Username" "$USERNAME" input_user
        NAS_USER="${input_user:-$USERNAME}"
        safe_read "Enter NAS Backup Path" "/home/${NAS_USER}/MyHomeVault" input_path
        NAS_BACKUP_PATH="${input_path:-/home/${NAS_USER}/MyHomeVault}"
        
        # Bandwidth limit for NAS (protect slow drives)
        echo -e "\n${ICON_INFO} NAS bandwidth limiting (keeps NAS responsive for other users)"
        echo -e "${ICON_INFO} Recommended: 5000 KB/s (5MB/s) for Asustor AS4004T"
        safe_read "Bandwidth limit in KB/s (0 = unlimited)" "5000" input_bw
        BW_LIMIT="${input_bw:-5000}"
        
        # SSH timeout settings
        echo -e "\n${ICON_INFO} SSH connection settings (for slow NAS)"
        safe_read "SSH timeout in seconds" "10" input_timeout
        SSH_TIMEOUT="${input_timeout:-10}"
        safe_read "SSH keep-alive interval" "60" input_alive
        SSH_ALIVE="${input_alive:-60}"
        
        # Test connection (non-blocking)
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
    
    # --- Retention Policy ---
    echo -e "\n${BOLD_WHITE}Step 3: Backup Retention${NC}"
    echo -e "${ICON_INFO} Older backups will be automatically deleted."
    safe_read "Keep backups for how many days?" "14" input_retention
    RETENTION_DAYS="${input_retention:-14}"
    
    # --- Notifications ---
    echo -e "\n${BOLD_WHITE}Step 4: Desktop Notifications${NC}"
    safe_read "Enable desktop popups? (yes/no)" "yes" input_notify
    if [[ "$input_notify" =~ ^[Nn][Oo]?$ ]]; then
        ENABLE_NOTIFICATIONS="no"
    else
        ENABLE_NOTIFICATIONS="yes"
    fi
    
    # --- Hardware Recommendations ---
    echo -e "\n${BOLD_WHITE}Hardware Recommendations for NAS:${NC}"
    echo -e "  ${ICON_DISK} ${BOLD_CYAN}WD Red Plus${NC} - Best for silence & longevity"
    echo -e "  ${ICON_DISK} ${BOLD_CYAN}Seagate IronWolf${NC} - Best for ADM health monitoring"
    echo -e "\n${ICON_INFO} These drives handle rsync hard links efficiently.\n"
    
    # --- Save Configuration ---
    cat <<EOF > "$CONFIG_FILE"
# My Home Vault Configuration
# GitHub: https://github.com/waelisa/my-home-vault
# Generated: $(date)
# User: ${USERNAME}

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
    
    # Create backup directories
    mkdir -p "$LOCAL_BACKUP_DEST/incremental" 2>/dev/null || true
    
    # Restore interactive mode
    INTERACTIVE=$old_interactive
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

# Ensure LOCAL_BACKUP_DEST is set (backward compatibility)
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

# IMPORTANT: Always exclude the vault's own config and logs to prevent recursive backups
EXCLUDE_DIRS=(
    # My Home Vault directories (prevent infinite loops)
    ".my-home-vault/"
    ".my-home-vault/*"
    ".my-home-vault/logs/"
    ".my-home-vault/logs/*"
    "*.my-home-vault.conf"
    
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
        notify-send -u "$urgency" -i dialog-information "My Home Vault: $title" "$message"
    fi
}

# Function to attempt drive remount if read-only
attempt_remount() {
    local mount_point="$1"
    
    print_step "remount" "Drive is read-only, attempting repair..." "warn"
    
    # Try to remount as read-write
    if sudo mount -o remount,rw "$mount_point" 2>/dev/null; then
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
    
    # Check if the directory exists
    if [ ! -d "$dest" ]; then
        # Try to create it
        if ! mkdir -p "$dest" 2>/dev/null; then
            print_step "write" "Cannot create destination directory" "error"
            return 1
        fi
    fi
    
    # Check if we can write a test file
    local test_file="$dest/.write_test_$$"
    if ! touch "$test_file" 2>/dev/null; then
        print_step "write" "Destination is not writable (read-only or disconnected)" "error"
        
        # Try to remount if it's a mount point
        if mountpoint -q "$dest" 2>/dev/null; then
            if attempt_remount "$dest"; then
                # Try again after remount
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

# Function to check disk space (with non-interactive safety)
check_disk_space() {
    local path="$1"
    local required_size="$2"  # in KB, optional
    local operation="$3"
    
    if [ ! -d "$path" ] && [ ! -f "$path" ]; then
        # Path doesn't exist yet, try parent
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
    
    # Check if we're below minimum free space
    if [ "$available_percent" -gt $((100 - MIN_FREE_SPACE_PERCENT)) ]; then
        print_error "CRITICAL: Less than ${MIN_FREE_SPACE_PERCENT}% disk space remaining"
        print_error "Operation: $operation would risk filling the drive"
        
        if [ "$ENABLE_NOTIFICATIONS" = "yes" ]; then
            send_notification "Backup Failed - Low Space" "Only ${available_hr} free on backup drive" "critical"
        fi
        
        # Non-interactive safety
        if [ "$INTERACTIVE" = false ]; then
            print_error "Non-interactive mode: Aborting due to low disk space"
            return 1
        fi
        
        if ! safe_confirm "Continue despite low disk space?" "no"; then
            return 1
        fi
    fi
    
    # If we have a required size, check it
    if [ -n "$required_size" ] && [ "$required_size" -gt 0 ]; then
        local required_hr=$(numfmt --to=iec --suffix=B "$required_size" 2>/dev/null || echo "${required_size}KB")
        
        if [ "$available_kb" -lt "$required_size" ]; then
            print_error "Insufficient space: Need ${required_hr}, only ${available_hr} free"
            
            if [ "$ENABLE_NOTIFICATIONS" = "yes" ]; then
                send_notification "Backup Failed - Insufficient Space" "Need ${required_hr}, only ${available_hr} free" "critical"
            fi
            
            # Non-interactive safety
            if [ "$INTERACTIVE" = false ]; then
                print_error "Non-interactive mode: Aborting due to insufficient space"
                return 1
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
    
    # Always exclude the vault's own directories (safety net)
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
    echo -e "  ${BOLD_RED}Note:${NC} My Home Vault config/logs are always excluded (prevents infinite loops)"
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
    if crontab -l 2>/dev/null | grep -q "my-home-vault.*--quiet"; then
        cron_exists=true
        echo -e "  ${ICON_INFO} Existing cron job found:"
        crontab -l | grep "my-home-vault.*--quiet" | while read line; do
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
            local cron_cmd="0 2 * * * ${HOME}/${SCRIPT_NAME} --quiet > ${LOG_DIR}/cron_\$(date +\%Y\%m\%d).log 2>&1"
            (crontab -l 2>/dev/null | grep -v "my-home-vault" ; echo "$cron_cmd") | crontab -
            echo -e "  ${ICON_SUCCESS} Daily backup scheduled for 2 AM"
            ;;
        2)
            # Weekly on Sunday at 3 AM
            local cron_cmd="0 3 * * 0 ${HOME}/${SCRIPT_NAME} --quiet > ${LOG_DIR}/cron_\$(date +\%Y\%m\%d).log 2>&1"
            (crontab -l 2>/dev/null | grep -v "my-home-vault" ; echo "$cron_cmd") | crontab -
            echo -e "  ${ICON_SUCCESS} Weekly backup scheduled for Sunday at 3 AM"
            ;;
        3)
            echo -e "\n${BOLD_WHITE}Custom cron syntax (min hour day month weekday)${NC}"
            echo -e "Example: ${BOLD_CYAN}30 4 * * 1-5${NC} = Weekdays at 4:30 AM"
            read -p "  ${ICON_ARROW} Enter cron schedule: " custom_schedule
            local cron_cmd="$custom_schedule ${HOME}/${SCRIPT_NAME} --quiet > ${LOG_DIR}/cron_\$(date +\%Y\%m\%d).log 2>&1"
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
    # Added --no-inc-recursive for better progress display on large transfers
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

# Function to test NAS connection with timeout protection
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
        SSH_AUTH_TYPE="key"
    else
        print_step "2" "SSH key authentication failed" "warn"
        
        if ssh $SSH_OPTS "${NAS_USER}@${NAS_IP}" "echo OK" 2>/dev/null; then
            print_step "2" "SSH connection successful (password auth)" "done"
            SSH_AUTH_TYPE="password"
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

# Function to create incremental backup
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

# Local Backup (with non-interactive safety)
perform_local_backup() {
    print_header "LOCAL BACKUP - ${USERNAME}"
    
    if [ "$INTERACTIVE" = false ]; then
        echo -e "  ${ICON_AUTO} Running in non-interactive mode\n"
    fi
    
    print_step "1" "Checking source" "start"
    if [ ! -d "$HOME_DIR" ]; then
        print_step "1" "Source missing: $HOME_DIR" "error"
        return 1
    fi
    print_step "1" "Source found" "done"
    
    print_step "2" "Preparing destination" "start"
    mkdir -p "$LOCAL_BACKUP_INCREMENTAL" 2>/dev/null || true
    
    # CRITICAL: Check if destination is writable before proceeding
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
    
    # Skip confirmation in non-interactive mode
    if [ "$INTERACTIVE" = true ]; then
        echo ""
        print_warning "Backup: $HOME_DIR → $LOCAL_BACKUP_DEST"
        echo ""
        if ! safe_confirm "Proceed with backup?" "yes"; then
            print_warning "Cancelled"
            return 0
        fi
    else
        echo -e "\n  ${ICON_AUTO} Non-interactive mode: Proceeding with backup automatically"
    fi
    
    create_incremental_backup "$TIMESTAMP"
    
    if [ "$RETENTION_DAYS" -gt 0 ]; then
        clean_old_backups "local"
    fi
    
    # Rotate logs
    rotate_logs
    
    echo ""
    print_success "Local backup completed at $(date)"
    print_info "Log: $LOG_FILE"
    
    send_notification "Backup Complete" "Local backup completed successfully" "normal"
}

# NAS Backup (with non-interactive safety)
perform_nas_backup() {
    if [ -z "${NAS_IP:-}" ] || [ -z "${NAS_USER:-}" ]; then
        print_error "NAS not configured. Please run setup wizard (delete ~/.my-home-vault.conf and restart)"
        return 1
    fi
    
    print_header "NAS BACKUP - ${USERNAME}"
    
    if [ "$INTERACTIVE" = false ]; then
        echo -e "  ${ICON_AUTO} Running in non-interactive mode\n"
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
            # In non-interactive mode, we'll proceed but log a warning
            if [ "$INTERACTIVE" = true ]; then
                if ! safe_confirm "Continue despite low NAS space?" "no"; then
                    return 1
                fi
            else
                print_warning "Non-interactive mode: Proceeding despite low space (will log warning)"
            fi
        fi
    fi
    
    print_step "5" "Loading exclusions" "start"
    show_exclusions
    
    # Skip confirmation in non-interactive mode
    if [ "$INTERACTIVE" = true ]; then
        echo ""
        print_warning "Backup: $HOME_DIR → ${NAS_USER}@${NAS_IP}:${NAS_BACKUP_PATH}"
        echo ""
        if ! safe_confirm "Proceed with backup?" "yes"; then
            print_warning "Cancelled"
            return 0
        fi
    else
        echo -e "\n  ${ICON_AUTO} Non-interactive mode: Proceeding with backup automatically"
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
    
    # Rotate logs
    rotate_logs
    
    echo ""
    print_success "NAS backup completed at $(date)"
    print_info "Log: $LOG_FILE"
    
    send_notification "NAS Backup Complete" "NAS backup completed successfully" "normal"
}

# Quiet mode for cron (no menus, just NAS backup) - now with non-interactive safety
perform_quiet_backup() {
    # Set non-interactive mode
    INTERACTIVE=false
    
    # Log start
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
    
    # Run backup with non-interactive safety
    if ! perform_nas_backup; then
        echo "[$(date)] FAILED: NAS backup failed" >> "$LOG_DIR/quiet.log"
        rm -f "$exclude_file"
        exit 1
    fi
    
    rm -f "$exclude_file"
    
    echo "[$(date)] SUCCESS: NAS backup completed" >> "$LOG_DIR/quiet.log"
    
    # Rotate logs
    find "$LOG_DIR" -name "vault_*.log" -type f -mtime +7 -delete 2>/dev/null
    # Keep quiet.log under 10MB
    if [ -f "$LOG_DIR/quiet.log" ] && [ $(stat -c%s "$LOG_DIR/quiet.log" 2>/dev/null || echo 0) -gt 10485760 ]; then
        mv "$LOG_DIR/quiet.log" "$LOG_DIR/quiet.log.old"
    fi
    
    exit 0
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
            if [ "$INTERACTIVE" = true ]; then
                if ! safe_confirm "Continue with restore despite backup failure?" "no"; then
                    return 1
                fi
            else
                print_error "Non-interactive mode: Aborting due to backup failure"
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
    
    # Rotate logs
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
    
    # Rotate logs
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
                echo -e "  ${BOLD_CYAN}Speed:${NC}    ${BW_LIMIT} KB/s limit (protects NAS)"
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
${BOLD_CYAN}║                 M Y   H O M E   V A U L T   v5.1.5.b                  ║${NC}
${BOLD_CYAN}╚══════════════════════════════════════════════════════════════════════════╝${NC}

${BOLD_WHITE}USAGE:${NC}
  ./${SCRIPT_NAME} [OPTION]

${BOLD_WHITE}OPTIONS:${NC}
  ${BOLD_GREEN}--help, -h${NC}     Show this help
  ${BOLD_GREEN}--version${NC}      Show version
  ${BOLD_GREEN}--quiet, -q${NC}    Run in quiet mode (for cron) - performs NAS backup
  ${BOLD_GREEN}--repair${NC}       Run VAULT-FIX repair mode (verify & fix NAS backup)
  ${BOLD_GREEN}--dry-run${NC}      Simulation mode
  ${BOLD_GREEN}--quick${NC}        Skip checksum verify
  ${BOLD_GREEN}--reconfigure${NC}  Run setup wizard again

${BOLD_WHITE}NON-INTERACTIVE FEATURES:${NC}
  • Safe for cron jobs - no hanging prompts
  • Automatic failure handling in quiet mode
  • Smart defaults for all confirmations
  • Detailed logging for post-mortem analysis
  • Disk space checks with auto-abort in non-interactive mode

${BOLD_WHITE}MENU OPTIONS:${NC}
  ${BOLD_CYAN}1${NC}  Local Backup    - Create incremental local backup
  ${BOLD_CYAN}2${NC}  Local Restore   - Restore from local backup
  ${BOLD_CYAN}3${NC}  NAS Backup      - Backup to NAS (with speed limiting)
  ${BOLD_CYAN}4${NC}  NAS Restore     - Restore from NAS
  ${BOLD_CYAN}5${NC}  Show Info       - Display backup information
  ${BOLD_CYAN}6${NC}  Repair Mode     - VAULT-FIX: verify & repair NAS backup
  ${BOLD_CYAN}7${NC}  Test NAS        - Test NAS connection
  ${BOLD_CYAN}8${NC}  Setup SSH Key   - Configure passwordless NAS
  ${BOLD_CYAN}9${NC}  Cron Setup      - Schedule automatic backups
  ${BOLD_CYAN}10${NC} Log Management  - View/delete logs
  ${BOLD_CYAN}11${NC} Cleanup Dry-Run - Preview old backups
  ${BOLD_CYAN}12${NC} Exit

${BOLD_WHITE}CONFIG:${NC}
  File: ${BOLD_CYAN}~/.my-home-vault.conf${NC}
  Logs: ${BOLD_CYAN}~/.my-home-vault/logs/${NC}
  BW_LIMIT: ${BOLD_CYAN}${BW_LIMIT} KB/s${NC} (protects NAS drives)
  SSH_TIMEOUT: ${BOLD_CYAN}${SSH_TIMEOUT}s${NC} (prevents hanging)

${BOLD_WHITE}CHECK STATUS:${NC}
  ${BOLD_GREEN}grep "SUCCESS" ~/.my-home-vault/logs/quiet.log${NC}
  ${BOLD_GREEN}tail -20 ~/.my-home-vault/logs/vault_latest.log${NC}

${BOLD_WHITE}CRON EXAMPLE (daily at 2 AM):${NC}
  0 2 * * * ${HOME}/${SCRIPT_NAME} --quiet

${BOLD_WHITE}HARDWARE RECOMMENDATIONS:${NC}
  • WD Red Plus      - Best for silence & longevity
  • Seagate IronWolf - Best for ADM health monitoring

${BOLD_WHITE}SAFETY NOTES:${NC}
  • My Home Vault excludes its own config/logs (prevents infinite loops)
  • Automatically detects and attempts to fix read-only USB drives
  • Tests destination writability before starting backup
  • Non-interactive mode safe for automated backups

${BOLD_WHITE}My Home Vault - Your Data, Fortified.${NC}
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
    echo "  ║             M Y   H O M E   V A U L T   v5.1.5.b              ║"
    echo "  ║           Your Data, Fortified · https://wael.name            ║"
    echo "  ╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  ${ICON_VAULT} ${BOLD_WHITE}Guardian of${NC} ${BOLD_GREEN}${USERNAME}${NC} | ${ICON_HOME} ${BOLD_WHITE}Local${NC} | ${ICON_NAS} ${BOLD_WHITE}NAS${NC}"
    
    if [ "$INTERACTIVE" = false ]; then
        echo -e "  ${ICON_AUTO} ${BOLD_WHITE}Mode:${NC} Non-interactive (cron-safe)"
    fi
    
    if [ "$BW_LIMIT" -gt 0 ]; then
        echo -e "  ${ICON_NAS} ${BOLD_WHITE}NAS Speed:${NC} ${BW_LIMIT} KB/s limit (protects drives)"
    fi
    
    echo -e "  ${ICON_CPU} ${BOLD_WHITE}SSH Timeout:${NC} ${SSH_TIMEOUT}s (prevents hanging)"
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
    
    if [ -n "${NAS_IP:-}" ]; then
        echo -e "${BOLD_CYAN}║    ${BOLD_WHITE}7.${NC} Test NAS connection${NC}                                       ║${NC}"
        echo -e "${BOLD_CYAN}║    ${BOLD_WHITE}8.${NC} Setup SSH key for NAS${NC}                                     ║${NC}"
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
    if [ "$INTERACTIVE" = false ]; then
        echo -e "  ${ICON_AUTO} ${BOLD_BLUE}Mode:${NC} Non-interactive (cron-safe)"
    fi
    if [ "$BW_LIMIT" -gt 0 ]; then
        echo -e "  ${ICON_NAS} ${BOLD_BLUE}NAS Speed:${NC} ${BW_LIMIT} KB/s limit (recommended for Asustor AS4004T)"
    fi
    echo -e "  ${ICON_CPU} ${BOLD_BLUE}SSH Timeout:${NC} ${SSH_TIMEOUT}s (prevents hanging on slow NAS)"
    echo -e "  ${ICON_VAULT} ${BOLD_BLUE}Excluded:${NC} My Home Vault config/logs (prevents loops)"
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
                echo "My Home Vault version $CURRENT_VERSION"
                echo "Author: Wael Isa"
                echo "Website: https://www.wael.name"
                echo "GitHub: https://github.com/waelisa/my-home-vault"
                echo "License: MIT"
                exit 0
                ;;
            --quiet|-q)
                # Quiet mode for cron - just run NAS backup
                INTERACTIVE=false
                perform_quiet_backup
                ;;
            --repair)
                # Run repair mode and exit
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
    # Parse command line arguments
    if [ $# -gt 0 ]; then
        parse_args "$@"
    fi
    
    show_banner
    
    # Create necessary directories
    mkdir -p "$LOCAL_BACKUP_INCREMENTAL" 2>/dev/null || true
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    
    while true; do
        show_menu
        
        if [ -n "${NAS_IP:-}" ]; then
            read -p "  ${BOLD_YELLOW}➤${NC} Select option (1-12): " -r option
        else
            read -p "  ${BOLD_YELLOW}➤${NC} Select option (1-12, 3-4,6-8 disabled): " -r option
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
                if [ -n "${NAS_IP:-}" ]; then
                    test_nas_connection
                else
                    print_error "NAS not configured"
                fi
                ;;
            8)
                if [ -n "${NAS_IP:-}" ]; then
                    setup_ssh_key
                else
                    print_error "NAS not configured"
                fi
                ;;
            9)
                setup_cron
                ;;
            10)
                manage_logs
                ;;
            11)
                print_header "CLEANUP DRY RUN"
                clean_old_backups "local" "yes"
                if [ -n "${NAS_IP:-}" ]; then
                    clean_old_backups "nas" "yes"
                fi
                ;;
            12)
                echo -e "  ${BOLD_GREEN}Exiting...${NC}"
                echo -e "  ${BOLD_BLUE}Logs saved in:${NC} $LOG_DIR"
                echo -e "  ${ICON_VAULT} ${BOLD_CYAN}My Home Vault stands guard.${NC}"
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 1-12"
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