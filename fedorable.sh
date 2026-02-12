#!/bin/bash

# Fedorable v5.0 - Fedora System Maintenance
# https://github.com/V8V88V8V88/fedorable

set -euo pipefail

readonly SCRIPT_NAME=$(basename "$0")
readonly VERSION="5.0"
readonly LOG_DIR="/var/log/fedorable"
readonly LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}_$(date +%Y%m%d_%H%M%S).log"
readonly LOCK_FILE="/var/run/fedorable.lock"
CONFIG_FILE="/etc/fedorable.conf"

KERNELS_TO_KEEP=2
JOURNAL_VACUUM_TIME="7d"
JOURNAL_VACUUM_SIZE="500M"
TEMP_FILE_AGE_DAYS=10
MIN_DISK_SPACE_MB=1024

declare -i DO_UPDATE=1
declare -i DO_AUTOREMOVE=1
declare -i DO_CLEAN_DNF=1
declare -i DO_CLEAN_KERNELS=1
declare -i DO_CLEAN_JOURNAL=1
declare -i DO_CLEAN_TEMP=1
declare -i DO_UPDATE_GRUB=1
declare -i DO_CLEAN_FLATPAK=1
declare -i DO_OPTIMIZE_RPMDB=1
declare -i DO_RESET_FAILED=1
declare -i DO_TRIM=1
declare -i DO_FIRMWARE=1
declare -i DO_CLEAN_CACHE=1
declare -i DO_CLEAN_COREDUMPS=1

declare -i CHECK_ONLY=0
declare -i FORCE_YES=0
declare -i QUIET_MODE=0
declare -i DRY_RUN=0
declare -i SHOW_HELP=0
declare -i ERROR_COUNT=0
declare -i SKIP_MENU=0

BOLD="" DIM="" BLUE="" GREEN="" YELLOW="" RED="" WHITE="" CYAN="" RESET=""

setup_colors() {
    if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
        BOLD="\e[1m"    DIM="\e[2m"
        BLUE="\e[1;34m" GREEN="\e[1;32m" YELLOW="\e[1;33m"
        RED="\e[1;31m"  WHITE="\e[1;37m" CYAN="\e[1;36m"
        RESET="\e[0m"
    fi
}

log_info() {
    local ts
    ts=$(date +'%Y-%m-%d %H:%M:%S')
    [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${DIM}[$ts]${RESET} $1"
    echo "[$ts] [INFO] $1" >> "$LOG_FILE"
}

log_error() {
    local ts
    ts=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "  ${DIM}[$ts]${RESET} ${RED}ERROR${RESET} $1" >&2
    echo "[$ts] [ERROR] $1" >> "$LOG_FILE"
    ERROR_COUNT=$((ERROR_COUNT + 1))
}

log_warn() {
    local ts
    ts=$(date +'%Y-%m-%d %H:%M:%S')
    [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${DIM}[$ts]${RESET} ${YELLOW}WARN${RESET}  $1" >&2
    echo "[$ts] [WARN] $1" >> "$LOG_FILE"
}

log_ok() {
    local ts
    ts=$(date +'%Y-%m-%d %H:%M:%S')
    [[ $QUIET_MODE -eq 0 ]] && echo -e "  ${DIM}[$ts]${RESET} ${GREEN}OK${RESET}    $1"
    echo "[$ts] [OK] $1" >> "$LOG_FILE"
}

print_header() {
    if [[ $QUIET_MODE -eq 0 ]]; then
        echo
        echo -e "  ${BLUE}━━━${RESET} ${WHITE}$1${RESET} ${BLUE}━━━${RESET}"
    fi
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [TASK] $1" >> "$LOG_FILE"
}

check_cmd() { command -v "$1" &>/dev/null; }

confirm() {
    [[ $FORCE_YES -eq 1 || $DRY_RUN -eq 1 ]] && return 0
    local answer
    while true; do
        read -rp "  $1 [y/N]: " answer
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no|"") return 1 ;;
            *) echo "  Enter y or n." ;;
        esac
    done
}

run() {
    local cmd="$1"
    local desc="${2:-Running command}"
    log_info "$desc"
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY RUN] $cmd"
        return 0
    fi
    local rc=0
    eval "$cmd" || rc=$?
    return "$rc"
}

check_disk_space() {
    local path="$1"
    local required_mb="$2"
    local available_kb
    available_kb=$(df --output=avail -B 1K "$path" | tail -n 1)
    if [[ -z "$available_kb" ]]; then
        log_error "Could not read disk space for '$path'."
        return 1
    fi
    local available_mb=$((available_kb / 1024))
    if [[ $available_mb -lt $required_mb ]]; then
        log_error "Low disk space on '$path': ${available_mb}MB free, need ${required_mb}MB."
        return 1
    fi
    return 0
}

acquire_lock() {
    if [[ -e "$LOCK_FILE" ]]; then
        local pid
        pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && ps -p "$pid" &>/dev/null; then
            log_error "Another instance running (PID: $pid)."
            exit 1
        fi
        log_warn "Removing stale lock file."
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"
}

release_lock() {
    if [[ -e "$LOCK_FILE" ]]; then
        local pid
        pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ "$pid" == "$$" ]]; then
            rm -f "$LOCK_FILE"
        fi
    fi
}

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading config: $CONFIG_FILE"
        if source "$CONFIG_FILE"; then
            log_info "Config loaded."
        else
            log_error "Bad config syntax in $CONFIG_FILE."
            return 1
        fi
    fi
    return 0
}

print_banner() {
    [[ $QUIET_MODE -eq 1 ]] && return
    local a1="█▀▀ █▀▀ █▀▄ █▀█ █▀█ ▄▀█ █▄▄ █   █▀▀"
    local a2="█▀  ██▄ █▄▀ █▄█ █▀▄ █▀█ █▄█ █▄▄ ██▄"
    local sub="Fedora System Maintenance"
    local ver="v${VERSION}"
    local by="by V8"
    local w=46
    local bar
    printf -v bar '%*s' "$w" ''
    bar=${bar// /─}
    local apad=$((w - 3 - ${#a1}))
    [[ $apad -lt 0 ]] && apad=0
    local gap=$((w - 6 - ${#sub} - ${#ver}))
    [[ $gap -lt 0 ]] && gap=0
    local bypad=$((w - 3 - ${#by}))
    [[ $bypad -lt 0 ]] && bypad=0
    echo
    echo -e "  ${BLUE}╭${bar}╮${RESET}"
    echo -e "  ${BLUE}│${RESET}$(printf '%*s' "$w" '')${BLUE}│${RESET}"
    echo -e "  ${BLUE}│${RESET}   ${WHITE}${a1}${RESET}$(printf '%*s' "$apad" '')${BLUE}│${RESET}"
    echo -e "  ${BLUE}│${RESET}   ${WHITE}${a2}${RESET}$(printf '%*s' "$apad" '')${BLUE}│${RESET}"
    echo -e "  ${BLUE}│${RESET}$(printf '%*s' "$w" '')${BLUE}│${RESET}"
    echo -e "  ${BLUE}│${RESET}   ${DIM}${sub}$(printf '%*s' "$gap" '')${ver}${RESET}   ${BLUE}│${RESET}"
    echo -e "  ${BLUE}│${RESET}   ${DIM}${by}${RESET}$(printf '%*s' "$bypad" '')${BLUE}│${RESET}"
    echo -e "  ${BLUE}│${RESET}$(printf '%*s' "$w" '')${BLUE}│${RESET}"
    echo -e "  ${BLUE}╰${bar}╯${RESET}"
    echo
}

show_system_info() {
    [[ $QUIET_MODE -eq 1 ]] && return

    local os_name="Fedora Linux"
    if [[ -f /etc/os-release ]]; then
        local _name _ver
        _name=$(grep -oP '^NAME=\K.*' /etc/os-release 2>/dev/null | tr -d '"') || true
        _ver=$(grep -oP '^VERSION=\K.*' /etc/os-release 2>/dev/null | tr -d '"') || true
        [[ -n "$_name" ]] && os_name="${_name} ${_ver}"
    fi

    local kernel
    kernel=$(uname -r)

    local uptime_str="unknown"
    uptime_str=$(uptime -p 2>/dev/null | sed 's/^up //' || echo "unknown")

    local disk_used="" disk_total="" disk_pct=""
    local disk_line
    disk_line=$(df -h / --output=used,size,pcent 2>/dev/null | tail -1) || true
    if [[ -n "$disk_line" ]]; then
        read -r disk_used disk_total disk_pct <<< "$disk_line"
    fi

    echo -e "  ${DIM}OS${RESET}       $os_name"
    echo -e "  ${DIM}Kernel${RESET}   $kernel"
    echo -e "  ${DIM}Uptime${RESET}   $uptime_str"
    echo -e "  ${DIM}Disk /${RESET}   ${disk_used} / ${disk_total} (${disk_pct})"
    echo
}

toggle_task() {
    local label="$1"
    local var_name="$2"
    local current=${!var_name}
    local hint
    if [[ $current -eq 1 ]]; then hint="Y/n"; else hint="y/N"; fi

    local answer
    while true; do
        read -rp "  $(printf '%-42s' "$label") [${hint}]: " answer
        case "${answer,,}" in
            y|yes) eval "$var_name=1"; break ;;
            n|no)  eval "$var_name=0"; break ;;
            "")    break ;;
            *)     echo "  Enter y or n." ;;
        esac
    done
}

select_mode() {
    [[ -t 0 ]] || return

    echo -e "  ${WHITE}Select maintenance mode:${RESET}"
    echo
    echo -e "    ${BOLD}1${RESET})  Minimal       ${DIM}Update + reset failed units${RESET}"
    echo -e "    ${BOLD}2${RESET})  Recommended   ${DIM}Updates + safe cleanups${RESET}"
    echo -e "    ${BOLD}3${RESET})  Advanced      ${DIM}Pick tasks individually${RESET}"
    echo

    local choice
    while true; do
        read -rp "  Enter choice [1-3]: " choice
        case "$choice" in
            1)
                DO_UPDATE=1
                DO_AUTOREMOVE=0; DO_CLEAN_DNF=0; DO_CLEAN_KERNELS=0
                DO_CLEAN_JOURNAL=0; DO_CLEAN_TEMP=0; DO_UPDATE_GRUB=0
                DO_CLEAN_FLATPAK=0; DO_OPTIMIZE_RPMDB=0; DO_RESET_FAILED=1
                DO_TRIM=0; DO_FIRMWARE=0; DO_CLEAN_CACHE=0; DO_CLEAN_COREDUMPS=0
                log_info "Mode: minimal"
                break ;;
            2)
                DO_UPDATE=1; DO_AUTOREMOVE=1; DO_CLEAN_DNF=1
                DO_CLEAN_KERNELS=1; DO_CLEAN_JOURNAL=1; DO_CLEAN_TEMP=1
                DO_UPDATE_GRUB=1; DO_CLEAN_FLATPAK=1; DO_OPTIMIZE_RPMDB=0
                DO_RESET_FAILED=1; DO_TRIM=1; DO_FIRMWARE=0
                DO_CLEAN_CACHE=0; DO_CLEAN_COREDUMPS=1
                log_info "Mode: recommended"
                break ;;
            3)
                log_info "Mode: advanced"
                echo
                echo -e "  ${WHITE}Toggle tasks:${RESET} ${DIM}(Enter keeps default)${RESET}"
                echo
                toggle_task "System package update"           DO_UPDATE
                toggle_task "Remove unused packages"          DO_AUTOREMOVE
                toggle_task "Clean DNF cache"                 DO_CLEAN_DNF
                toggle_task "Remove old kernels"              DO_CLEAN_KERNELS
                toggle_task "Clean system journal"            DO_CLEAN_JOURNAL
                toggle_task "Clean temporary files"           DO_CLEAN_TEMP
                toggle_task "Update GRUB configuration"       DO_UPDATE_GRUB
                toggle_task "Clean/update Flatpak"            DO_CLEAN_FLATPAK
                toggle_task "Optimize RPM database"           DO_OPTIMIZE_RPMDB
                toggle_task "Reset failed systemd units"      DO_RESET_FAILED
                toggle_task "SSD TRIM"                        DO_TRIM
                toggle_task "Firmware updates"                DO_FIRMWARE
                toggle_task "Clean user cache"                DO_CLEAN_CACHE
                toggle_task "Clean coredumps"                 DO_CLEAN_COREDUMPS
                break ;;
            *) echo "  Enter 1, 2, or 3." ;;
        esac
    done
}

print_task_summary() {
    [[ $QUIET_MODE -eq 1 ]] && return
    echo
    echo -e "  ${WHITE}Tasks:${RESET}"
    echo

    local -a task_defs=(
        "DO_UPDATE:System package update"
        "DO_AUTOREMOVE:Remove unused packages"
        "DO_CLEAN_DNF:Clean DNF cache"
        "DO_CLEAN_KERNELS:Remove old kernels"
        "DO_CLEAN_JOURNAL:Clean system journal"
        "DO_CLEAN_TEMP:Clean temporary files"
        "DO_UPDATE_GRUB:Update GRUB config"
        "DO_CLEAN_FLATPAK:Clean/update Flatpak"
        "DO_OPTIMIZE_RPMDB:Optimize RPM database"
        "DO_RESET_FAILED:Reset failed systemd units"
        "DO_TRIM:SSD TRIM"
        "DO_FIRMWARE:Firmware updates"
        "DO_CLEAN_CACHE:Clean user cache"
        "DO_CLEAN_COREDUMPS:Clean coredumps"
    )

    local any_enabled=0
    for entry in "${task_defs[@]}"; do
        local var="${entry%%:*}"
        local label="${entry#*:}"
        if [[ ${!var} -eq 1 ]]; then
            echo -e "    ${GREEN}●${RESET} $label"
            any_enabled=1
        else
            echo -e "    ${DIM}○ $label${RESET}"
        fi
    done
    echo

    if [[ $any_enabled -eq 0 ]]; then
        echo -e "  ${YELLOW}No tasks selected. Nothing to do.${RESET}"
        exit 0
    fi
}

task_update() {
    print_header "System Package Update"

    if ! check_disk_space "/" "$MIN_DISK_SPACE_MB"; then
        return 1
    fi

    if [[ $CHECK_ONLY -eq 1 ]]; then
        log_info "Checking for updates..."
        local rc=0
        dnf check-update || rc=$?
        case $rc in
            0)   log_info "System is up to date." ;;
            100) log_info "Updates are available." ;;
            *)   log_error "Failed to check for updates." ;;
        esac
        return 0
    fi

    log_info "Upgrading system packages..."
    if run "dnf upgrade -y" "dnf upgrade"; then
        log_ok "System updated."
    else
        log_error "System update failed."
    fi
}

task_autoremove() {
    print_header "Remove Unused Packages"

    if [[ $DRY_RUN -eq 1 ]]; then
        run "dnf autoremove --assumeno 2>/dev/null" "Check unused packages" || true
        log_info "[DRY RUN] Would remove the above packages."
        return 0
    fi

    if confirm "Remove unused packages?"; then
        if run "dnf autoremove -y" "dnf autoremove"; then
            log_ok "Unused packages removed."
        else
            log_error "Failed to remove unused packages."
        fi
    fi
}

task_clean_dnf() {
    print_header "DNF Cache"

    if run "dnf clean all" "Clean DNF cache"; then
        log_info "Cache cleaned."
    else
        log_error "Failed to clean DNF cache."
        return 1
    fi

    if run "dnf makecache" "Rebuild DNF metadata"; then
        log_ok "DNF cache rebuilt."
    else
        log_warn "Failed to rebuild cache (no network?)."
    fi
}

task_clean_kernels() {
    print_header "Old Kernel Removal (keep: $KERNELS_TO_KEEP)"

    local running_kernel
    running_kernel=$(uname -r)

    local -a all_kernels
    mapfile -t all_kernels < <(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V)

    local total=${#all_kernels[@]}
    if [[ $total -le $KERNELS_TO_KEEP ]]; then
        log_info "Only $total kernel(s) installed. Nothing to remove."
        return 0
    fi

    log_info "Installed kernels ($total):"
    for k in "${all_kernels[@]}"; do
        if [[ "$k" == "$running_kernel" ]]; then
            log_info "  $k ${GREEN}(running)${RESET}"
        else
            log_info "  $k"
        fi
    done

    local remove_count=$((total - KERNELS_TO_KEEP))
    local -a to_remove=()
    for ((i = 0; i < remove_count; i++)); do
        local kver="${all_kernels[$i]}"
        if [[ "$kver" == "$running_kernel" ]]; then
            log_warn "Skipping running kernel: $kver"
            continue
        fi
        to_remove+=("$kver")
    done

    if [[ ${#to_remove[@]} -eq 0 ]]; then
        log_info "No old kernels safe to remove."
        return 0
    fi

    local -a pkgs=()
    for kver in "${to_remove[@]}"; do
        for prefix in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra kernel-devel kernel-headers; do
            if rpm -q "${prefix}-${kver}" &>/dev/null; then
                pkgs+=("${prefix}-${kver}")
            fi
        done
    done

    if [[ ${#pkgs[@]} -eq 0 ]]; then
        log_info "No kernel packages to remove."
        return 0
    fi

    log_info "Packages to remove:"
    for p in "${pkgs[@]}"; do
        log_info "  $p"
    done

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY RUN] Would remove the above packages."
        return 0
    fi

    if confirm "Remove ${#pkgs[@]} old kernel package(s)?"; then
        if run "dnf remove -y ${pkgs[*]}" "Remove old kernels"; then
            log_ok "Old kernels removed."
        else
            log_error "Failed to remove old kernels."
        fi
    fi
}

task_clean_journal() {
    print_header "Journal Cleanup"
    run "journalctl --vacuum-time=$JOURNAL_VACUUM_TIME" "Vacuum by time ($JOURNAL_VACUUM_TIME)" || true
    run "journalctl --rotate" "Rotate journal" || true
    run "journalctl --vacuum-size=$JOURNAL_VACUUM_SIZE" "Vacuum by size ($JOURNAL_VACUUM_SIZE)" || true
    log_ok "Journal cleaned."
}

task_clean_temp() {
    print_header "Temporary Files (older than ${TEMP_FILE_AGE_DAYS}d)"

    if [[ $DRY_RUN -eq 1 ]]; then
        local cnt_tmp cnt_var
        cnt_tmp=$(find /tmp -type f -atime +"$TEMP_FILE_AGE_DAYS" -print 2>/dev/null | wc -l || echo 0)
        cnt_var=$(find /var/tmp -type f -atime +"$TEMP_FILE_AGE_DAYS" -print 2>/dev/null | wc -l || echo 0)
        log_info "[DRY RUN] Would delete $cnt_tmp files from /tmp, $cnt_var from /var/tmp."
        return 0
    fi

    find /tmp -type f -atime +"$TEMP_FILE_AGE_DAYS" -delete 2>/dev/null || true
    find /var/tmp -type f -atime +"$TEMP_FILE_AGE_DAYS" -delete 2>/dev/null || true
    log_ok "Temporary files cleaned."
}

task_update_grub() {
    print_header "GRUB Configuration"

    if check_cmd grubby; then
        if run "grubby --update-kernel=ALL" "Update kernels via grubby"; then
            local dk
            dk=$(grubby --default-kernel 2>/dev/null || echo "unknown")
            log_info "Default kernel: $dk"
            log_ok "GRUB updated via grubby."
            return 0
        fi
        log_warn "grubby failed, falling back to grub2-mkconfig."
    fi

    local grub_cfg=""
    if [[ -d /sys/firmware/efi/efivars ]]; then
        if [[ -f /boot/efi/EFI/fedora/grub.cfg ]]; then
            grub_cfg="/boot/efi/EFI/fedora/grub.cfg"
        elif [[ -f /boot/grub2/grub.cfg ]]; then
            grub_cfg="/boot/grub2/grub.cfg"
        fi
    else
        [[ -f /boot/grub2/grub.cfg ]] && grub_cfg="/boot/grub2/grub.cfg"
    fi

    if [[ -z "$grub_cfg" ]]; then
        log_error "Could not find GRUB config path."
        return 1
    fi

    if run "grub2-mkconfig -o \"$grub_cfg\"" "Generate GRUB config"; then
        log_ok "GRUB updated via grub2-mkconfig."
    else
        log_error "Failed to update GRUB."
    fi
}

task_clean_flatpak() {
    print_header "Flatpak Cleanup & Update"

    if ! check_cmd flatpak; then
        log_info "Flatpak not installed. Skipping."
        return 0
    fi

    run "flatpak uninstall --unused -y 2>/dev/null" "Remove unused runtimes" || true
    run "flatpak repair --user 2>/dev/null" "Repair user installations" || true
    run "flatpak repair 2>/dev/null" "Repair system installations" || true

    if run "flatpak update -y" "Update Flatpak apps"; then
        log_ok "Flatpak cleaned and updated."
    else
        log_warn "Flatpak update had issues."
    fi
}

task_optimize_rpmdb() {
    print_header "RPM Database Optimization"
    if run "rpm --rebuilddb" "Rebuild RPM database"; then
        log_ok "RPM database optimized."
    else
        log_error "Failed to rebuild RPM database."
    fi
}

task_reset_failed() {
    print_header "Failed Systemd Units"

    local count
    count=$(systemctl --failed --no-legend 2>/dev/null | wc -l || echo 0)

    if [[ "$count" -eq 0 ]]; then
        log_info "No failed units."
        return 0
    fi

    log_warn "Found $count failed unit(s):"
    systemctl --failed --no-legend 2>/dev/null | while IFS= read -r line; do
        log_info "  $line"
    done

    if run "systemctl reset-failed" "Reset failed units"; then
        log_ok "Failed units reset."
    else
        log_error "Failed to reset units."
    fi
}

task_trim() {
    print_header "SSD TRIM"

    if ! check_cmd fstrim; then
        log_info "fstrim not found. Skipping."
        return 0
    fi

    if run "fstrim -av" "TRIM filesystems"; then
        log_ok "TRIM completed."
    else
        log_warn "TRIM reported errors (may be normal on non-SSD)."
    fi
}

task_firmware() {
    print_header "Firmware Updates"

    if ! check_cmd fwupdmgr; then
        log_info "fwupdmgr not found. Skipping."
        return 0
    fi

    run "fwupdmgr refresh --force 2>/dev/null" "Refresh firmware metadata" || true

    local rc=0
    fwupdmgr get-updates &>/dev/null || rc=$?

    if [[ $rc -ne 0 ]]; then
        log_info "No firmware updates available."
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY RUN] Would apply firmware updates."
        return 0
    fi

    if confirm "Apply available firmware updates?"; then
        if run "fwupdmgr update" "Apply firmware updates"; then
            log_ok "Firmware updated."
        else
            log_error "Firmware update failed."
        fi
    fi
}

task_clean_cache() {
    print_header "User Cache Cleanup"

    local target_user="${SUDO_USER:-}"
    if [[ -z "$target_user" ]]; then
        target_user=$(logname 2>/dev/null) || target_user="root"
    fi

    local user_home
    user_home=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)

    if [[ -z "$user_home" || ! -d "$user_home/.cache" ]]; then
        log_info "No user cache found."
        return 0
    fi

    local total_size
    total_size=$(du -sh "$user_home/.cache" 2>/dev/null | cut -f1 || echo "0")
    log_info "Total cache: $total_size ($user_home/.cache)"

    local -a safe_targets=(
        "$user_home/.cache/thumbnails"
        "$user_home/.cache/mesa_shader_cache"
        "$user_home/.cache/fontconfig"
        "$user_home/.cache/pip"
        "$user_home/.cache/yarn"
        "$user_home/.cache/go-build"
        "$user_home/.cache/bazel"
    )

    local -a found=()
    local cleanable_kb=0

    for dir in "${safe_targets[@]}"; do
        if [[ -d "$dir" ]]; then
            local sz_kb sz_human
            sz_kb=$(du -sk "$dir" 2>/dev/null | cut -f1 || echo 0)
            sz_human=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "0")
            found+=("$dir")
            cleanable_kb=$((cleanable_kb + sz_kb))
            log_info "  $sz_human  ${dir#"$user_home"/}"
        fi
    done

    if [[ ${#found[@]} -eq 0 ]]; then
        log_info "No safe cache directories to clean."
        return 0
    fi

    local total_human
    if [[ $cleanable_kb -ge 1024 ]]; then
        total_human="$((cleanable_kb / 1024))M"
    else
        total_human="${cleanable_kb}K"
    fi
    log_info "Cleanable: $total_human"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY RUN] Would clean the above directories."
        return 0
    fi

    if confirm "Clean ${#found[@]} cache director(y/ies)?"; then
        for dir in "${found[@]}"; do
            rm -rf "$dir" 2>/dev/null || log_warn "Failed to clean $dir"
        done
        log_ok "User cache cleaned."
    fi
}

task_clean_coredumps() {
    print_header "Coredump Cleanup"

    local dump_dir="/var/lib/systemd/coredump"

    if [[ ! -d "$dump_dir" ]]; then
        log_info "No coredump directory found."
        return 0
    fi

    local count
    count=$(find "$dump_dir" -type f 2>/dev/null | wc -l || echo 0)

    if [[ "$count" -eq 0 ]]; then
        log_info "No coredumps found."
        return 0
    fi

    local dump_size
    dump_size=$(du -sh "$dump_dir" 2>/dev/null | cut -f1 || echo "0")
    log_info "Found $count coredump(s) using $dump_size."

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY RUN] Would remove $count coredump(s)."
        return 0
    fi

    if confirm "Remove all coredumps ($dump_size)?"; then
        rm -f "$dump_dir"/* 2>/dev/null || true
        run "journalctl --rotate 2>/dev/null" "Rotate journal" || true
        log_ok "Coredumps cleaned."
    fi
}

show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

  Fedora system maintenance toolkit.

Modes:
  --minimal           Run system update only
  --recommended       Run common safe maintenance tasks
  --all               Enable all tasks
  --none              Disable all tasks (combine with individual enables)

Options:
  -h, --help          Show this help
  -y, --yes           Skip all confirmation prompts
  --dry-run           Preview without making changes
  -q, --quiet         Suppress terminal output
  --check-only        Check for updates without installing
  --config FILE       Use alternative config file

Skip individual tasks:
  --no-update         --no-autoremove      --no-clean-dnf
  --no-kernels        --no-journal         --no-temp
  --no-grub           --no-flatpak         --no-rpmdb
  --no-failed         --no-trim            --no-firmware
  --no-cache          --no-coredumps

EOF
    exit 0
}

parse_args() {
    local TEMP_ARGS
    TEMP_ARGS=$(getopt -o hyq --long \
        help,config:,yes,dry-run,quiet,check-only,\
all,none,minimal,recommended,\
no-update,no-autoremove,no-clean-dnf,no-kernels,no-journal,no-temp,\
no-grub,no-flatpak,no-rpmdb,no-failed,no-trim,no-firmware,no-cache,no-coredumps \
        -n "$SCRIPT_NAME" -- "$@") || { echo "Bad options. Try --help." >&2; exit 1; }

    eval set -- "$TEMP_ARGS"

    while true; do
        case "$1" in
            -h|--help)        SHOW_HELP=1; shift ;;
            --config)         CONFIG_FILE="$2"; shift 2 ;;
            -y|--yes)         FORCE_YES=1; shift ;;
            --dry-run)        DRY_RUN=1; shift ;;
            -q|--quiet)       QUIET_MODE=1; shift ;;
            --check-only)     CHECK_ONLY=1; shift ;;

            --minimal)
                SKIP_MENU=1
                DO_UPDATE=1
                DO_AUTOREMOVE=0; DO_CLEAN_DNF=0; DO_CLEAN_KERNELS=0
                DO_CLEAN_JOURNAL=0; DO_CLEAN_TEMP=0; DO_UPDATE_GRUB=0
                DO_CLEAN_FLATPAK=0; DO_OPTIMIZE_RPMDB=0; DO_RESET_FAILED=1
                DO_TRIM=0; DO_FIRMWARE=0; DO_CLEAN_CACHE=0; DO_CLEAN_COREDUMPS=0
                shift ;;
            --recommended)
                SKIP_MENU=1
                DO_UPDATE=1; DO_AUTOREMOVE=1; DO_CLEAN_DNF=1
                DO_CLEAN_KERNELS=1; DO_CLEAN_JOURNAL=1; DO_CLEAN_TEMP=1
                DO_UPDATE_GRUB=1; DO_CLEAN_FLATPAK=1; DO_OPTIMIZE_RPMDB=0
                DO_RESET_FAILED=1; DO_TRIM=1; DO_FIRMWARE=0
                DO_CLEAN_CACHE=0; DO_CLEAN_COREDUMPS=1
                shift ;;
            --all)
                SKIP_MENU=1
                DO_UPDATE=1; DO_AUTOREMOVE=1; DO_CLEAN_DNF=1
                DO_CLEAN_KERNELS=1; DO_CLEAN_JOURNAL=1; DO_CLEAN_TEMP=1
                DO_UPDATE_GRUB=1; DO_CLEAN_FLATPAK=1; DO_OPTIMIZE_RPMDB=1
                DO_RESET_FAILED=1; DO_TRIM=1; DO_FIRMWARE=1
                DO_CLEAN_CACHE=1; DO_CLEAN_COREDUMPS=1
                shift ;;
            --none)
                SKIP_MENU=1
                DO_UPDATE=0; DO_AUTOREMOVE=0; DO_CLEAN_DNF=0
                DO_CLEAN_KERNELS=0; DO_CLEAN_JOURNAL=0; DO_CLEAN_TEMP=0
                DO_UPDATE_GRUB=0; DO_CLEAN_FLATPAK=0; DO_OPTIMIZE_RPMDB=0
                DO_RESET_FAILED=0; DO_TRIM=0; DO_FIRMWARE=0
                DO_CLEAN_CACHE=0; DO_CLEAN_COREDUMPS=0
                shift ;;

            --no-update)      SKIP_MENU=1; DO_UPDATE=0; shift ;;
            --no-autoremove)  SKIP_MENU=1; DO_AUTOREMOVE=0; shift ;;
            --no-clean-dnf)   SKIP_MENU=1; DO_CLEAN_DNF=0; shift ;;
            --no-kernels)     SKIP_MENU=1; DO_CLEAN_KERNELS=0; shift ;;
            --no-journal)     SKIP_MENU=1; DO_CLEAN_JOURNAL=0; shift ;;
            --no-temp)        SKIP_MENU=1; DO_CLEAN_TEMP=0; shift ;;
            --no-grub)        SKIP_MENU=1; DO_UPDATE_GRUB=0; shift ;;
            --no-flatpak)     SKIP_MENU=1; DO_CLEAN_FLATPAK=0; shift ;;
            --no-rpmdb)       SKIP_MENU=1; DO_OPTIMIZE_RPMDB=0; shift ;;
            --no-failed)      SKIP_MENU=1; DO_RESET_FAILED=0; shift ;;
            --no-trim)        SKIP_MENU=1; DO_TRIM=0; shift ;;
            --no-firmware)    SKIP_MENU=1; DO_FIRMWARE=0; shift ;;
            --no-cache)       SKIP_MENU=1; DO_CLEAN_CACHE=0; shift ;;
            --no-coredumps)   SKIP_MENU=1; DO_CLEAN_COREDUMPS=0; shift ;;

            --) shift; break ;;
            *)  echo "Internal error!" >&2; exit 1 ;;
        esac
    done
}

main() {
    setup_colors
    parse_args "$@"

    [[ $SHOW_HELP -eq 1 ]] && show_help

    if [[ "$EUID" -ne 0 ]]; then
        echo -e "  ${RED}Run as root: sudo $SCRIPT_NAME${RESET}" >&2
        exit 1
    fi

    mkdir -p "$LOG_DIR" || { echo "Cannot create $LOG_DIR" >&2; exit 1; }
    touch "$LOG_FILE" || { echo "Cannot create $LOG_FILE" >&2; exit 1; }
    chmod 600 "$LOG_FILE"

    acquire_lock
    trap release_lock EXIT
    trap 'release_lock; exit 130' INT
    trap 'release_lock; exit 143' TERM

    load_config || true

    print_banner
    show_system_info

    if [[ $SKIP_MENU -eq 0 ]]; then
        select_mode
    fi

    print_task_summary

    log_info "Fedorable v${VERSION} started"
    [[ $DRY_RUN -eq 1 ]] && log_warn "DRY RUN MODE — no changes will be made"

    local initial_avail
    initial_avail=$(df -B1M / --output=avail 2>/dev/null | tail -1 | xargs || echo 0)

    if [[ $DO_UPDATE -eq 1 ]];         then task_update          || true; fi
    if [[ $DO_AUTOREMOVE -eq 1 ]];     then task_autoremove      || true; fi
    if [[ $DO_CLEAN_DNF -eq 1 ]];      then task_clean_dnf       || true; fi
    if [[ $DO_CLEAN_KERNELS -eq 1 ]];  then task_clean_kernels   || true; fi
    if [[ $DO_CLEAN_JOURNAL -eq 1 ]];  then task_clean_journal   || true; fi
    if [[ $DO_CLEAN_TEMP -eq 1 ]];     then task_clean_temp      || true; fi
    if [[ $DO_UPDATE_GRUB -eq 1 ]];    then task_update_grub     || true; fi
    if [[ $DO_CLEAN_FLATPAK -eq 1 ]];  then task_clean_flatpak   || true; fi
    if [[ $DO_OPTIMIZE_RPMDB -eq 1 ]]; then task_optimize_rpmdb  || true; fi
    if [[ $DO_RESET_FAILED -eq 1 ]];   then task_reset_failed    || true; fi
    if [[ $DO_TRIM -eq 1 ]];           then task_trim            || true; fi
    if [[ $DO_FIRMWARE -eq 1 ]];       then task_firmware         || true; fi
    if [[ $DO_CLEAN_CACHE -eq 1 ]];    then task_clean_cache     || true; fi
    if [[ $DO_CLEAN_COREDUMPS -eq 1 ]];then task_clean_coredumps || true; fi

    print_header "Summary"

    local final_avail freed
    final_avail=$(df -B1M / --output=avail 2>/dev/null | tail -1 | xargs || echo 0)
    freed=$((final_avail - initial_avail))

    if [[ $freed -gt 0 ]]; then
        log_ok "Freed ~${freed}MB on /"
    elif [[ $freed -lt 0 ]]; then
        local used=$(( -freed ))
        log_info "Disk usage increased by ~${used}MB (likely from updates)."
    else
        log_info "Disk usage unchanged."
    fi

    [[ $DRY_RUN -eq 1 ]] && log_warn "DRY RUN — no changes were made"

    if [[ $ERROR_COUNT -gt 0 ]]; then
        log_error "Finished with $ERROR_COUNT error(s). Log: $LOG_FILE"
        exit 1
    fi

    log_ok "All done!"
    log_info "Log: $LOG_FILE"
}

main "$@"
