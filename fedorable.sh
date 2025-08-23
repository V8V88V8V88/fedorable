#!/bin/bash

# Fedorable - Fedora System Maintenance Script
# Version: 4.0
# Usage: sudo ./fedorable.sh [OPTIONS]
#
# Performs system updates, cleanup, and optimizations
# Requires root privileges. Use with caution.

# Strict error handling
set -euo pipefail

#=============================================
# CONFIGURATION
#=============================================
readonly SCRIPT_NAME=$(basename "$0")
readonly LOG_DIR="/var/log/fedorable"
readonly LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}_$(date +%Y%m%d_%H%M%S).log"
readonly LOCK_FILE="/var/run/fedorable.lock"
readonly CONFIG_FILE="/etc/fedorable.conf"

# Default settings
readonly KERNELS_TO_KEEP=2
readonly JOURNAL_VACUUM_TIME="7d"
readonly JOURNAL_VACUUM_SIZE="500M"
readonly TEMP_FILE_AGE_DAYS=10
readonly MIN_DISK_SPACE_MB=1024

# Task flags (0=disabled, 1=enabled)
declare -i UPDATE=1
declare -i AUTOREMOVE=1
declare -i CLEAN_DNF=1
declare -i CLEAN_KERNELS=1
declare -i CLEAN_JOURNAL=1
declare -i CLEAN_TEMP=1
declare -i UPDATE_GRUB=1
declare -i CLEAN_FLATPAK=1
declare -i OPTIMIZE_RPMDB=1
declare -i RESET_FAILED_UNITS=1
declare -i TRIM=1

# Control flags
declare -i CHECK_ONLY=0
declare -i FORCE_YES=0
declare -i QUIET_MODE=0
declare -i DRY_RUN=0
declare -i SHOW_HELP=0
declare -i ERROR_COUNT=0

#=============================================
# LOGGING FUNCTIONS
#=============================================
log_msg() {
    local timestamp="[$(date +'%Y-%m-%d %H:%M:%S')]"
    local message="$1"
    [[ $QUIET_MODE -ne 1 ]] && echo "$timestamp [INFO] $message"
    echo "$timestamp [INFO] $message" >> "$LOG_FILE"
}

log_error() {
    local timestamp="[$(date +'%Y-%m-%d %H:%M:%S')]"
    local message="$1"
    echo "$timestamp [ERROR] $message" >&2
    echo "$timestamp [ERROR] $message" >> "$LOG_FILE"
    ((ERROR_COUNT++))
}

log_warn() {
    local timestamp="[$(date +'%Y-%m-%d %H:%M:%S')]"
    local message="$1"
    [[ $QUIET_MODE -ne 1 ]] && echo "$timestamp [WARN] $message" >&2
    echo "$timestamp [WARN] $message" >> "$LOG_FILE"
}

log_success() {
    local timestamp="[$(date +'%Y-%m-%d %H:%M:%S')]"
    local message="$1"
    [[ $QUIET_MODE -ne 1 ]] && echo -e "$timestamp [SUCCESS] \e[32m$message\e[0m"
    echo "$timestamp [SUCCESS] $message" >> "$LOG_FILE"
}

print_header() {
    [[ $QUIET_MODE -ne 1 ]] && echo -e "\n\e[1;34m=== $1 ===\e[0m"
    log_msg "=== $1 ==="
}

#=============================================
# UTILITY FUNCTIONS
#=============================================
# Check if a command exists
check_command() {
    command -v "$1" &>/dev/null
}

# Confirm an action with the user
confirm_action() {
    local prompt="$1"
    if [[ $FORCE_YES -eq 1 || $DRY_RUN -eq 1 ]]; then
        return 0
    fi
    
    while true; do
        read -rp "[CONFIRM] $prompt [y/N]: " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]*|"" ) return 1;;
            * ) echo "Please answer yes (y) or no (n).";;
        esac
    done
}

# Execute a command if not in dry run mode
run_cmd() {
    local cmd="$1"
    local description="${2:-Command execution}"
    
    log_msg "Running: $description"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_msg "[DRY RUN] Would execute: $cmd"
        return 0
    else
        eval "$cmd"
        return $?
    fi
}

# Check available disk space
check_disk_space() {
    local path="$1"
    local required_mb="$2"
    
    local available_kb
    available_kb=$(df --output=avail -B 1K "$path" | tail -n 1)
    
    if [[ -z "$available_kb" ]]; then
        log_error "Could not determine available disk space for '$path'."
        return 1
    fi
    
    local available_mb=$((available_kb / 1024))
    if [[ $available_mb -lt $required_mb ]]; then
        log_error "Insufficient disk space on '$path'. Need ${required_mb}MB, Have ${available_mb}MB."
        return 1
    fi
    
    log_msg "Disk space check passed for '$path'."
    return 0
}

# Create lock file
create_lock() {
    if [[ -e "$LOCK_FILE" ]]; then
        local pid=$(cat "$LOCK_FILE")
        if ps -p "$pid" -o comm= | grep -q "$(basename "$0")"; then
            log_error "Another instance is already running (PID: $pid)."
            exit 1
        else
            log_warn "Stale lock file found. Removing lock."
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
    log_msg "Lock file created: $LOCK_FILE"
}

# Remove lock file
remove_lock() {
    if [[ -e "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE")" == "$$" ]]; then
        rm -f "$LOCK_FILE"
        log_msg "Lock file removed."
    fi
}

# Load config file if it exists
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_msg "Loading configuration from $CONFIG_FILE"
        if source "$CONFIG_FILE"; then
            log_msg "Configuration loaded successfully."
            return 0
        else
            log_error "Failed to load configuration. Check syntax."
            return 1
        fi
    else
        log_msg "Config file not found, using defaults."
        return 1
    fi
}

#=============================================
# TASK FUNCTIONS
#=============================================
task_update_system() {
    print_header "System Package Update"
    check_disk_space "/" "$MIN_DISK_SPACE_MB" || return 1

    if [[ $CHECK_ONLY -eq 1 ]]; then
        log_msg "Checking for available system updates..."
        dnf check-update
        local update_status=$?
        if [[ $update_status -eq 0 ]]; then
            log_msg "No package updates available."
        elif [[ $update_status -eq 100 ]]; then
            log_msg "Package updates are available."
        else
            log_error "Error checking for package updates."
            return 1
        fi
        return 0
    fi

    log_msg "Performing system package upgrade..."
    run_cmd "dnf upgrade -y" "System package upgrade"
    if [[ $? -eq 0 ]]; then
        log_success "System update completed successfully."
    else
        log_error "System update failed."
        return 1
    fi
}

task_autoremove() {
    print_header "Removing Unused Packages"
    
    local packages_to_remove
    packages_to_remove=$(dnf autoremove --assumeno 2>/dev/null | grep -E '^[[:space:]]+Removing:' -A 1000 || true)

    if [[ -z "$packages_to_remove" ]]; then
        log_msg "No unused packages found to remove."
        return 0
    fi

    log_msg "The following packages are identified as unused:"
    echo "$packages_to_remove" | tee -a "$LOG_FILE"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_msg "[DRY RUN] Would remove the above unused packages."
        return 0
    fi

    confirm_action "Proceed with removing unused packages?" || return 0
    run_cmd "dnf autoremove -y" "Remove unused packages"
    if [[ $? -eq 0 ]]; then
        log_success "Unused packages removed successfully."
    else
        log_error "Failed to remove unused packages."
    fi
}

task_clean_dnf_cache() {
    print_header "DNF Cache Management"
    
    run_cmd "dnf clean all" "Clean DNF cache"
    if [[ $? -ne 0 ]]; then
        log_error "Failed to clean DNF cache."
        return 1
    fi
    
    run_cmd "dnf makecache" "Rebuild DNF metadata cache"
    if [[ $? -eq 0 ]]; then
        log_success "DNF cache cleaned and rebuilt successfully."
    else
        log_error "Failed to rebuild DNF cache."
    fi
}

task_remove_old_kernels() {
    print_header "Old Kernel Removal (Keep: $KERNELS_TO_KEEP)"
    
    local installed_kernels_count
    installed_kernels_count=$(rpm -q kernel-core | wc -l)

    if [[ $installed_kernels_count -le $KERNELS_TO_KEEP ]]; then
        log_msg "Found $installed_kernels_count kernel(s). No old kernels to remove."
        return 0
    fi

    log_msg "Current installed kernels ($installed_kernels_count):"
    rpm -q kernel-core | tee -a "$LOG_FILE"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_msg "[DRY RUN] Would remove old kernels."
        return 0
    fi

    confirm_action "Proceed with removing old kernels?" || return 0
    run_cmd "dnf remove --oldinstallonly --setopt installonly_limit=$KERNELS_TO_KEEP -y" "Remove old kernels"
                    if [[ $? -eq 0 ]]; then
        log_success "Old kernels removed successfully."
                    else
        log_error "Failed to remove old kernels."
        fi
}

task_clean_journal() {
    print_header "System Journal Cleanup"
    
    run_cmd "journalctl --vacuum-time=$JOURNAL_VACUUM_TIME" "Journal vacuum by time"
    run_cmd "journalctl --rotate" "Journal rotate"
    run_cmd "journalctl --vacuum-size=$JOURNAL_VACUUM_SIZE" "Journal vacuum by size"
    log_success "Journal cleaned successfully."
}

task_clean_temp_files() {
    print_header "Temporary File Cleanup (Age > $TEMP_FILE_AGE_DAYS days)"

    if [[ $DRY_RUN -eq 1 ]]; then
        local found_tmp=$(find /tmp -type f -atime +"$TEMP_FILE_AGE_DAYS" -print 2>/dev/null | wc -l)
        local found_var_tmp=$(find /var/tmp -type f -atime +"$TEMP_FILE_AGE_DAYS" -print 2>/dev/null | wc -l)
        log_msg "[DRY RUN] Would delete $found_tmp file(s) from /tmp and $found_var_tmp from /var/tmp."
        return 0
    fi

    find /tmp -type f -atime +"$TEMP_FILE_AGE_DAYS" -delete 2>/dev/null || log_warn "Some errors occurred deleting from /tmp."
    find /var/tmp -type f -atime +"$TEMP_FILE_AGE_DAYS" -delete 2>/dev/null || log_warn "Some errors occurred deleting from /var/tmp."
    log_success "Temporary files cleaned successfully."
}

task_update_grub() {
    print_header "GRUB Configuration Update"

    # Try grubby first, then fall back to grub2-mkconfig if needed
    if check_command grubby; then
        run_cmd "grubby --update-kernel=ALL" "Update kernel entries via grubby"
        if [[ $? -eq 0 ]]; then
             local default_kernel=$(grubby --default-kernel)
             log_msg "Default kernel set to: $default_kernel"
            log_success "GRUB updated successfully via grubby."
            return 0
        else
             log_warn "grubby update failed. Will attempt fallback using grub2-mkconfig."
        fi
    else
        log_msg "grubby command not found. Will use grub2-mkconfig."
    fi

    # Fallback to grub2-mkconfig
    local grub_cfg=""
        if [[ -d /sys/firmware/efi/efivars ]]; then
        if [[ -f /boot/efi/EFI/fedora/grub.cfg ]]; then 
            grub_cfg="/boot/efi/EFI/fedora/grub.cfg"
        elif [[ -f /boot/grub2/grub.cfg ]]; then 
            grub_cfg="/boot/grub2/grub.cfg"
        else 
            log_error "Could not find GRUB config path for UEFI."
            return 1
        fi
    else
        if [[ -f /boot/grub2/grub.cfg ]]; then 
            grub_cfg="/boot/grub2/grub.cfg"
        else 
            log_error "Could not find GRUB config path for BIOS."
            return 1
        fi
    fi
    
    run_cmd "grub2-mkconfig -o \"$grub_cfg\"" "GRUB config generation"
    if [[ $? -eq 0 ]]; then
        log_success "GRUB updated successfully via grub2-mkconfig."
    else
        log_error "Failed to update GRUB configuration."
        return 1
    fi
}

task_clean_flatpak() {
    print_header "Flatpak Management"
    
    if ! check_command flatpak; then
        log_msg "Flatpak command not found. Skipping."
        return 0
    fi

    run_cmd "flatpak uninstall --unused -y" "Remove unused Flatpak runtimes/apps"
    run_cmd "flatpak repair --user" "Repair user Flatpak installations"
    run_cmd "flatpak repair" "Repair system Flatpak installations"
    run_cmd "flatpak update -y" "Update Flatpak applications"
    log_success "Flatpak cleaned and updated successfully."
}

task_optimize_rpmdb() {
    print_header "RPM Database Optimization"
    
    run_cmd "rpm --rebuilddb" "RPM database rebuild"
    if [[ $? -eq 0 ]]; then
        log_success "RPM database optimized successfully."
    else
        log_error "Failed to optimize RPM database."
        return 1
    fi
}

task_reset_failed_units() {
    print_header "Systemd Failed Units Reset"
    
    local failed_units
    failed_units=$(systemctl --failed --no-legend | wc -l)

    if [[ $failed_units -eq 0 ]]; then
        log_msg "No failed systemd units found to reset."
        return 0
    fi

    log_warn "Found $failed_units failed systemd units. Resetting..."
    systemctl --failed --no-legend | tee -a "$LOG_FILE"

    run_cmd "systemctl reset-failed" "Reset failed systemd units"
    if [[ $? -eq 0 ]]; then
        log_success "Failed systemd units reset successfully."
    else
        log_error "Failed to reset systemd units."
        return 1
    fi
}

task_ssd_trim() {
    print_header "SSD TRIM Execution"
    
    if ! check_command fstrim; then
        log_msg "fstrim command not found. Skipping."
        return 0
    fi

    run_cmd "fstrim -av" "SSD TRIM operation"
    if [[ $? -eq 0 ]]; then
        log_success "TRIM operation completed successfully."
    else
        log_warn "TRIM command reported errors (might be harmless on non-SSD filesystems)."
    fi
}

#=============================================
# COMMAND LINE PARSING
#=============================================
show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]
  Performs system maintenance tasks on Fedora.

Options:
  -h, --help            Display this help message and exit.
  -y, --yes             Assume yes to all confirmation prompts.
  --dry-run             Show what would be done without making changes.
  -q, --quiet           Suppress console output (errors still shown).
  --check-only          Only check for updates, do not install.
  --config FILE         Specify alternative configuration file.

Task Selection:
  --all                 Enable all tasks.
  --none                Disable all tasks.
  
  --no-update           Skip system package update.
  --no-autoremove       Skip removing unused packages.
  --no-clean-dnf        Skip cleaning DNF cache.
  --no-clean-kernels    Skip removing old kernels.
  --no-clean-journal    Skip cleaning system journal.
  --no-clean-temp       Skip cleaning temporary files.
  --no-update-grub      Skip updating GRUB configuration.
  --no-clean-flatpak    Skip cleaning/updating Flatpak.
  --no-optimize-rpmdb   Skip optimizing RPM database.
  --no-reset-failed     Skip resetting failed systemd units.
  --no-trim             Skip manual SSD TRIM run.
EOF
  exit 0
}

parse_args() {
    local TEMP_ARGS
    TEMP_ARGS=$(getopt -o hyq --long help,config:,yes,dry-run,quiet,check-only,all,none,no-update,no-autoremove,no-clean-dnf,no-clean-kernels,no-clean-journal,no-clean-temp,no-update-grub,no-clean-flatpak,no-optimize-rpmdb,no-reset-failed,no-trim -n "$SCRIPT_NAME" -- "$@")

if [[ $? -ne 0 ]]; then
  echo "Error parsing options. Use --help for usage." >&2
  exit 1
fi

eval set -- "$TEMP_ARGS"

while true; do
  case "$1" in
    -h | --help) SHOW_HELP=1; shift ;;
            --config) CONFIG_FILE="$2"; shift 2 ;;
    -y | --yes) FORCE_YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -q | --quiet) QUIET_MODE=1; shift ;;
            --check-only) CHECK_ONLY=1; shift ;;
            
            --all)
                UPDATE=1; AUTOREMOVE=1; CLEAN_DNF=1; CLEAN_KERNELS=1;
                CLEAN_JOURNAL=1; CLEAN_TEMP=1; UPDATE_GRUB=1;
                CLEAN_FLATPAK=1; OPTIMIZE_RPMDB=1; RESET_FAILED_UNITS=1; TRIM=1;
                shift ;;
            --none)
                UPDATE=0; AUTOREMOVE=0; CLEAN_DNF=0; CLEAN_KERNELS=0;
                CLEAN_JOURNAL=0; CLEAN_TEMP=0; UPDATE_GRUB=0;
                CLEAN_FLATPAK=0; OPTIMIZE_RPMDB=0; RESET_FAILED_UNITS=0; TRIM=0;
                shift ;;
                
            --no-update) UPDATE=0; shift ;;
            --no-autoremove) AUTOREMOVE=0; shift ;;
            --no-clean-dnf) CLEAN_DNF=0; shift ;;
            --no-clean-kernels) CLEAN_KERNELS=0; shift ;;
            --no-clean-journal) CLEAN_JOURNAL=0; shift ;;
            --no-clean-temp) CLEAN_TEMP=0; shift ;;
            --no-update-grub) UPDATE_GRUB=0; shift ;;
            --no-clean-flatpak) CLEAN_FLATPAK=0; shift ;;
            --no-optimize-rpmdb) OPTIMIZE_RPMDB=0; shift ;;
            --no-reset-failed) RESET_FAILED_UNITS=0; shift ;;
            --no-trim) TRIM=0; shift ;;

    --) shift; break ;;
    *) echo "Internal error processing options!" >&2 ; exit 1 ;;
  esac
done
}

#=============================================
# MAIN EXECUTION
#=============================================
main() {
    # Parse command line arguments
    parse_args "$@"

# Show help if requested
    [[ $SHOW_HELP -eq 1 ]] && show_help

    # Check for root privileges
if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: This script must be run as root or using sudo." >&2
    exit 1
fi

    # Setup logging
mkdir -p "$LOG_DIR" || { echo "ERROR: Could not create log directory: $LOG_DIR" >&2; exit 1; }
touch "$LOG_FILE" || { echo "ERROR: Could not create log file: $LOG_FILE" >&2; exit 1; }
    chmod 600 "$LOG_FILE"

# Create lock file and set trap for cleanup
create_lock
    trap remove_lock EXIT INT TERM
    
    # Load user config
    load_config

    # Print startup message
    log_msg "--- Fedorable System Maintenance Script Started ---"
[[ $DRY_RUN -eq 1 ]] && log_warn "*** DRY RUN MODE ENABLED - NO CHANGES WILL BE MADE ***"

    # Record initial disk usage
    local initial_disk_usage=$(df -h /)
    
    # Execute tasks
    [[ $UPDATE -eq 1 ]] && task_update_system
    [[ $AUTOREMOVE -eq 1 ]] && task_autoremove
    [[ $CLEAN_DNF -eq 1 ]] && task_clean_dnf_cache
    [[ $CLEAN_KERNELS -eq 1 ]] && task_remove_old_kernels
    [[ $CLEAN_JOURNAL -eq 1 ]] && task_clean_journal
    [[ $CLEAN_TEMP -eq 1 ]] && task_clean_temp_files
    [[ $UPDATE_GRUB -eq 1 ]] && task_update_grub
    [[ $CLEAN_FLATPAK -eq 1 ]] && task_clean_flatpak
    [[ $OPTIMIZE_RPMDB -eq 1 ]] && task_optimize_rpmdb
    [[ $RESET_FAILED_UNITS -eq 1 ]] && task_reset_failed_units
    [[ $TRIM -eq 1 ]] && task_ssd_trim
    
    # Final summary
print_header "Maintenance Summary"
    local final_disk_usage=$(df -h /)
log_msg "Initial Disk Usage (/):"
log_msg "$initial_disk_usage"
log_msg "Final Disk Usage (/):"
log_msg "$final_disk_usage"

[[ $DRY_RUN -eq 1 ]] && log_warn "*** DRY RUN COMPLETED - NO CHANGES WERE MADE ***"

if [[ $ERROR_COUNT -gt 0 ]]; then
    log_error "Script finished with $ERROR_COUNT error(s). Review log: $LOG_FILE"
    exit 1
else
    log_success "System maintenance completed successfully!"
    exit 0
fi
}

# Execute main function
main "$@"