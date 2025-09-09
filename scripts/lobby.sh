#!/usr/bin/env bash
# Lobby System Management Script
# Manages installation, updates, and resets for lobby screen systems

set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"
LOGFILE="/var/log/lobby-setup.log"

# Default values
export LOBBY_USER="${LOBBY_USER:-lobby}"
export LOBBY_HOME="${LOBBY_HOME:-/home/$LOBBY_USER}"
export LOBBY_LOG="$LOGFILE"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') [lobby.sh] $1"
    echo "$message"
    # Only write to log file if we have permission
    if [[ -w "$LOGFILE" ]] || [[ -w "$(dirname "$LOGFILE")" ]]; then
        echo "$message" >> "$LOGFILE"
    fi
}

# Colored output functions
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log "INFO: $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log "SUCCESS: $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log "WARNING: $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log "ERROR: $1"
}

# Show usage
usage() {
    cat << EOF
Lobby System Management Script v$VERSION

USAGE:
    $0 <command> [options]

COMMANDS:
    setup [module]          Run full setup or specific module
    reset [module]          Reset configuration (full or specific module)
    update [module]         Update configuration (full or specific module)
    validate [module]       Validate installation (full or specific module)
    sync [--force]          Update scripts from GitHub repository
    check-updates [--force] Check for available updates from GitHub
    list                    List available modules
    status                  Show system status
    logs                    Show recent logs
    health                  Run comprehensive system health check

MODULES:
    kiosk                  Cage Wayland kiosk setup
    plymouth               Boot splash screen setup
    auto-updates           Automatic system updates
    monitoring             Service monitoring setup
    scheduler              Daily schedule management
    cleanup                Cleanup and finalization

EXAMPLES:
    $0 setup                # Full system setup
    $0 setup kiosk          # Setup only kiosk
    $0 reset kiosk          # Reset kiosk config
    $0 update auto-updates  # Update automatic updates config
    $0 validate             # Validate full installation
    $0 sync                 # Update scripts from GitHub
    $0 sync --force         # Force update (bypass cache)
    $0 check-updates        # Check for script updates
    $0 check-updates --force # Force check (bypass cache)
    $0 status               # Show system status
    $0 health               # Run comprehensive health check

ENVIRONMENT VARIABLES:
    LOBBY_USER             Username (default: lobby)
    LOBBY_HOME             User home directory (default: /home/lobby)
    LOBBY_LOG              Log file location (default: /var/log/lobby-setup.log)

NOTES:
    GitHub's CDN may cache files for several minutes after updates.
    Use --force flag to bypass cache and ensure you get the latest files.
    The sync command creates backups before updating any files.

EOF
}

# Get available modules
get_modules() {
    find "$MODULES_DIR" -name "*.sh" -executable | sort | while read -r module; do
        basename "$module" .sh | sed 's/^[0-9]*-//'
    done
}

# Find module script
find_module() {
    local module="$1"
    find "$MODULES_DIR" -name "*-${module}.sh" -executable | head -1
}

# Run module
run_module() {
    local action="$1"
    local module="$2"

    local module_script
    module_script=$(find_module "$module")

    if [[ -z "$module_script" ]]; then
        error "Module '$module' not found"
        return 1
    fi

    info "Running $action for module: $module"

    if "$module_script" "$action"; then
        success "$action completed for module: $module"
        return 0
    else
        error "$action failed for module: $module"
        return 1
    fi
}

# Run all modules
run_all_modules() {
    local action="$1"
    local failed_modules=()
    local success_count=0

    info "Running $action for all modules"

    while IFS= read -r module; do
        if run_module "$action" "$module"; then
            ((success_count++))
        else
            failed_modules+=("$module")
        fi
    done < <(get_modules)

    if [[ ${#failed_modules[@]} -eq 0 ]]; then
        success "All modules completed successfully ($success_count modules)"
        return 0
    else
        error "$action failed for modules: ${failed_modules[*]}"
        warning "Successful modules: $success_count"
        return 1
    fi
}

# List available modules
list_modules() {
    info "Available modules:"
    get_modules | while read -r module; do
        local module_script
        module_script=$(find_module "$module")
        local version
        version=$(grep "^MODULE_VERSION=" "$module_script" 2>/dev/null | cut -d'"' -f2 || echo "unknown")
        echo "  • $module (v$version)"
    done
}

# Show system status
show_status() {
    info "Lobby System Status"
    echo

    # User info
    echo "User Configuration:"
    echo "  • Username: $LOBBY_USER"
    echo "  • Home: $LOBBY_HOME"
    echo "  • User exists: $(id "$LOBBY_USER" >/dev/null 2>&1 && echo "Yes" || echo "No")"
    echo

    # Module validation
    echo "Module Status:"
    while IFS= read -r module; do
        local status
        if run_module "validate" "$module" >/dev/null 2>&1; then
            status="${GREEN}✓ OK${NC}"
        else
            status="${RED}✗ FAILED${NC}"
        fi
        echo -e "  • $module: $status"
    done < <(get_modules)
    echo

    # Log info
    echo "Logs:"
    echo "  • Log file: $LOBBY_LOG"
    if [[ -f "$LOBBY_LOG" ]]; then
        echo "  • Log size: $(du -h "$LOBBY_LOG" | cut -f1)"
        echo "  • Last entry: $(tail -1 "$LOBBY_LOG" | cut -d' ' -f1-2)"
    else
        echo "  • Log file not found"
    fi
}

# Comprehensive system health check
system_health_check() {
    info "Running comprehensive system health check"
    echo

    local warnings=0
    local errors=0

    # Check system resources
    echo "=== SYSTEM RESOURCES ==="

    # Memory usage
    local mem_usage
    mem_usage=$(free | grep '^Mem:' | awk '{printf "%.1f", $3/$2 * 100.0}')
    if (( $(echo "$mem_usage > 90.0" | bc -l) )); then
        error "High memory usage: ${mem_usage}%"
        ((errors++))
    elif (( $(echo "$mem_usage > 75.0" | bc -l) )); then
        warning "Elevated memory usage: ${mem_usage}%"
        ((warnings++))
    else
        info "Memory usage: ${mem_usage}%"
    fi

    # Disk usage
    local disk_usage
    disk_usage=$(df / | tail -1 | awk '{print $(NF-1)}' | sed 's/%//')
    if [[ $disk_usage -gt 90 ]]; then
        error "High disk usage: ${disk_usage}%"
        ((errors++))
    elif [[ $disk_usage -gt 75 ]]; then
        warning "Elevated disk usage: ${disk_usage}%"
        ((warnings++))
    else
        info "Disk usage: ${disk_usage}%"
    fi

    # Load average
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_count
    cpu_count=$(nproc)
    if (( $(echo "$load_avg > $cpu_count * 2" | bc -l) )); then
        error "High system load: $load_avg (CPUs: $cpu_count)"
        ((errors++))
    elif (( $(echo "$load_avg > $cpu_count" | bc -l) )); then
        warning "Elevated system load: $load_avg (CPUs: $cpu_count)"
        ((warnings++))
    else
        info "System load: $load_avg (CPUs: $cpu_count)"
    fi

    echo
    echo "=== NETWORK CONNECTIVITY ==="

    # Check lobby-display app
    if curl -s --connect-timeout 5 http://localhost:8080 >/dev/null; then
        success "Lobby display app responding on port 8080"
    else
        error "Lobby display app not responding on port 8080"
        ((errors++))
    fi

    # Check external connectivity
    if curl -s --connect-timeout 10 https://www.google.com >/dev/null; then
        success "External internet connectivity OK"
    else
        error "No external internet connectivity"
        ((errors++))
    fi

    # Check GitHub connectivity (for updates)
    if curl -s --connect-timeout 10 https://api.github.com/repos/kenzie/lobby-arch >/dev/null; then
        success "GitHub API connectivity OK"
    else
        warning "Cannot reach GitHub API - updates may fail"
        ((warnings++))
    fi

    echo
    echo "=== SERVICE STATUS ==="

    # Check critical services
    local services=("lobby-display.service" "lobby-kiosk.service" "seatd.service")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            if systemctl is-enabled --quiet "$service"; then
                success "$service: active and enabled"
            else
                warning "$service: active but not enabled"
                ((warnings++))
            fi
        else
            if systemctl is-failed --quiet "$service"; then
                error "$service: failed"
                ((errors++))
            else
                error "$service: not running"
                ((errors++))
            fi
        fi
    done

    echo
    echo "=== LOG HEALTH ==="

    # Check log file sizes
    for logfile in "/var/log/lobby-setup.log" "/var/log/lobby-monitor.log" "/var/log/lobby-auto-update.log"; do
        if [[ -f "$logfile" ]]; then
            local log_size
            log_size=$(stat -c%s "$logfile" 2>/dev/null || echo "0")
            local log_size_mb
            log_size_mb=$((log_size / 1024 / 1024))

            if [[ $log_size_mb -gt 100 ]]; then
                warning "Large log file: $logfile (${log_size_mb}MB)"
                ((warnings++))
            else
                info "Log file size OK: $logfile (${log_size_mb}MB)"
            fi

            # Check for recent errors in last 1000 lines
            local recent_errors
            recent_errors=$(tail -1000 "$logfile" 2>/dev/null | grep -c "ERROR" || echo "0")
            if [[ $recent_errors -gt 10 ]]; then
                warning "Many recent errors in $logfile: $recent_errors"
                ((warnings++))
            fi
        fi
    done

    echo
    echo "=== PROCESS HEALTH ==="

    # Check for zombie processes
    local zombies
    zombies=$(ps aux | awk '$8 ~ /^Z/ { print $2 }' | wc -l)
    if [[ $zombies -gt 0 ]]; then
        warning "Found $zombies zombie processes"
        ((warnings++))
    else
        info "No zombie processes found"
    fi

    # Check Chromium processes
    local chromium_procs
    chromium_procs=$(pgrep -c chromium || echo "0")
    if [[ $chromium_procs -eq 0 ]]; then
        error "No Chromium processes found"
        ((errors++))
    elif [[ $chromium_procs -gt 20 ]]; then
        warning "Many Chromium processes: $chromium_procs (possible memory leak)"
        ((warnings++))
    else
        info "Chromium processes: $chromium_procs"
    fi

    echo
    echo "=== SUMMARY ==="

    if [[ $errors -eq 0 && $warnings -eq 0 ]]; then
        success "System health check passed with no issues"
        return 0
    elif [[ $errors -eq 0 ]]; then
        warning "System health check completed with $warnings warning(s)"
        return 0
    else
        error "System health check failed with $errors error(s) and $warnings warning(s)"
        return 1
    fi
}

# Show recent logs
show_logs() {
    if [[ -f "$LOBBY_LOG" ]]; then
        info "Recent logs (last 50 lines):"
        tail -50 "$LOBBY_LOG"
    else
        warning "Log file not found: $LOBBY_LOG"
    fi
}

# Ensure running as root for system operations
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
}

# GitHub repository configuration
GITHUB_REPO="kenzie/lobby-arch"
GITHUB_BASE_URL="https://raw.githubusercontent.com/$GITHUB_REPO/main/scripts"

# File list for syncing
declare -A SYNC_FILES=(
    ["lobby.sh"]="lobby.sh"
    ["post-install.sh"]="post-install.sh"
    ["modules/02-kiosk.sh"]="modules/02-kiosk.sh"
    ["modules/03-plymouth.sh"]="modules/03-plymouth.sh"
    ["modules/04-auto-updates.sh"]="modules/04-auto-updates.sh"
    ["modules/05-monitoring.sh"]="modules/05-monitoring.sh"
    ["modules/06-scheduler.sh"]="modules/06-scheduler.sh"
    ["modules/99-cleanup.sh"]="modules/99-cleanup.sh"
    ["configs/plymouth/route19.plymouth"]="configs/plymouth/route19.plymouth"
    ["configs/plymouth/route19.script"]="configs/plymouth/route19.script"
    ["configs/plymouth/logo.png"]="configs/plymouth/logo.png"
)

# Get file hash
get_file_hash() {
    local file="$1"
    if [[ -f "$file" ]]; then
        sha256sum "$file" | cut -d' ' -f1
    else
        echo "missing"
    fi
}

# Download file with cache handling
download_file() {
    local url="$1"
    local output="$2"
    local force_cache_bypass="${3:-false}"
    local max_retries=3
    local retry_delay=5

    for attempt in $(seq 1 $max_retries); do
        local curl_opts="-sSL"

        if [[ "$force_cache_bypass" == "true" ]]; then
            # Add timestamp to URL as query parameter for cache busting
            local cache_buster="?cb=$(date +%s)&t=$(date +%N)"
            url="${url}${cache_buster}"
        fi

        if curl -sSL \
            ${force_cache_bypass:+-H "Cache-Control: no-cache, no-store, must-revalidate"} \
            ${force_cache_bypass:+-H "Pragma: no-cache"} \
            ${force_cache_bypass:+-H "Expires: 0"} \
            "$url" -o "$output" 2>/dev/null; then
            return 0
        else
            if [[ $attempt -lt $max_retries ]]; then
                warning "Download attempt $attempt failed, retrying in ${retry_delay}s..."
                sleep $retry_delay
                retry_delay=$((retry_delay * 2))  # Exponential backoff
            fi
        fi
    done

    return 1
}

# Check for updates from GitHub
check_for_updates() {
    local force_cache_bypass="${1:-false}"

    if [[ "$force_cache_bypass" == "true" ]]; then
        info "Checking for updates from GitHub repository: $GITHUB_REPO (bypassing cache)"
    else
        info "Checking for updates from GitHub repository: $GITHUB_REPO"
    fi

    local updates_available=0
    local temp_dir
    temp_dir=$(mktemp -d)

    for local_path in "${!SYNC_FILES[@]}"; do
        local github_path="${SYNC_FILES[$local_path]}"
        local local_file="$SCRIPT_DIR/$local_path"
        local temp_file="$temp_dir/$(basename "$github_path")"

        # Download file from GitHub
        if download_file "$GITHUB_BASE_URL/$github_path" "$temp_file" "$force_cache_bypass"; then
            local local_hash
            local remote_hash
            local_hash=$(get_file_hash "$local_file")
            remote_hash=$(get_file_hash "$temp_file")

            if [[ "$local_hash" != "$remote_hash" ]]; then
                warning "Update available for: $local_path"
                ((updates_available++))
            fi
        else
            warning "Failed to check updates for: $local_path"
        fi
    done

    rm -rf "$temp_dir"

    if [[ $updates_available -eq 0 ]]; then
        success "All files are up to date"
        return 0
    else
        info "Found $updates_available file(s) with updates available"
        info "Run 'sudo ./lobby.sh sync' to update"
        return 1
    fi
}

# Sync files from GitHub
sync_from_github() {
    local force_cache_bypass="${1:-false}"

    if [[ "$force_cache_bypass" == "true" ]]; then
        info "Syncing files from GitHub repository: $GITHUB_REPO (bypassing cache)"
    else
        info "Syncing files from GitHub repository: $GITHUB_REPO"
    fi

    local synced_count=0
    local failed_count=0
    local temp_dir
    temp_dir=$(mktemp -d)

    # Create backup directory
    local backup_dir="/tmp/lobby-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"

    for local_path in "${!SYNC_FILES[@]}"; do
        local github_path="${SYNC_FILES[$local_path]}"
        local local_file="$SCRIPT_DIR/$local_path"
        local temp_file="$temp_dir/$(basename "$github_path")"

        info "Syncing: $local_path"

        # Download file from GitHub
        if download_file "$GITHUB_BASE_URL/$github_path" "$temp_file" "$force_cache_bypass"; then
            # Check if file content changed
            local local_hash
            local remote_hash
            local_hash=$(get_file_hash "$local_file")
            remote_hash=$(get_file_hash "$temp_file")

            if [[ "$local_hash" != "$remote_hash" ]]; then
                # Backup existing file if it exists
                if [[ -f "$local_file" ]]; then
                    cp "$local_file" "$backup_dir/$(basename "$local_file")-$(date +%H%M%S)"
                fi

                # Ensure directory exists
                mkdir -p "$(dirname "$local_file")"

                # Copy new file and set permissions
                cp "$temp_file" "$local_file"
                if [[ "$local_path" == *.sh ]]; then
                    chmod +x "$local_file"
                fi

                success "Updated: $local_path"
                ((synced_count++))
            else
                info "No changes: $local_path"
            fi
        else
            error "Failed to download: $local_path"
            ((failed_count++))
        fi
    done

    rm -rf "$temp_dir"

    if [[ $synced_count -eq 0 && $failed_count -eq 0 ]]; then
        success "All files are already up to date"
    elif [[ $failed_count -eq 0 ]]; then
        success "Successfully synced $synced_count file(s)"
        info "Backup created at: $backup_dir"

        if [[ $synced_count -gt 0 ]]; then
            warning "Some files were updated. Consider running 'sudo ./lobby.sh validate' to ensure everything still works correctly."
        fi
    else
        error "Sync completed with errors: $synced_count synced, $failed_count failed"
        return 1
    fi
}

# Main command dispatcher
main() {
    local command="${1:-}"
    local arg2="${2:-}"
    local force_cache_bypass="false"

    # Check for --force flag in any position
    if [[ "$arg2" == "--force" ]] || [[ "${3:-}" == "--force" ]]; then
        force_cache_bypass="true"
        # Remove --force from arguments, keep module name if present
        if [[ "$arg2" == "--force" ]]; then
            arg2=""
        fi
    fi

    local module="$arg2"

    case "$command" in
        "setup"|"reset"|"update"|"validate")
            check_root
            if [[ -n "$module" ]]; then
                run_module "$command" "$module"
            else
                run_all_modules "$command"
            fi
            ;;
        "sync")
            check_root
            sync_from_github "$force_cache_bypass"
            ;;
        "check-updates")
            check_for_updates "$force_cache_bypass"
            ;;
        "list")
            list_modules
            ;;
        "status")
            show_status
            ;;
        "logs")
            show_logs
            ;;
        "health")
            system_health_check
            ;;
        "help"|"--help"|"-h")
            usage
            ;;
        "")
            error "No command specified"
            usage
            exit 1
            ;;
        *)
            error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Handle interruption gracefully
trap 'error "Script interrupted"; exit 130' INT TERM

# Run main function
main "$@"
