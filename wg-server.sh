#!/usr/bin/env bash

set -euo pipefail

readonly INTERFACE="wg0"

# Colors
C_RESET='\033[0m'
C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'

# systemd-style output prefixes
PREFIX_INFO="[INFO]"
PREFIX_OK="[OK]"
PREFIX_ERR="[FAILED]"
PREFIX_WARN="[WARN]"
PREFIX_RUN="[*]"

log_info()    { printf "${C_YELLOW}${PREFIX_INFO}${C_RESET} $1\n"; }
log_ok()      { printf "${C_GREEN}${PREFIX_OK}${C_RESET} $1\n"; }
log_err()     { printf "${C_RED}${PREFIX_ERR}${C_RESET} $1\n"; }
log_warn()    { printf "${C_YELLOW}${PREFIX_WARN}${C_RESET} $1\n"; }
log_run()     { printf "${C_CYAN}${PREFIX_RUN}${C_RESET} $1\n"; }

usage() {
    log_err "Usage: $0 {up|down} --ip-wg <EXPECTED_IP>"
    exit 1
}

fix_resolvconf() {
    log_run "Refreshing DNS (resolvconf -u)"
    sudo resolvconf -u || true
}

get_masked_ip() {
    local full_ip
    full_ip=$(curl -4 -s --max-time 5 ifconfig.me || echo "OFFLINE")
    if [[ "$full_ip" =~ ^([0-9]+)\.([0-9]+)\.[0-9]+\.[0-9]+$ ]]; then
        echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.*.*"
    else
        echo "$full_ip"
    fi
}

check_wg_active() {
    sudo wg show "$INTERFACE" &>/dev/null
}

vpn_up() {
    local target_ip=$1

    if check_wg_active; then
        log_warn "$INTERFACE is already up"
    else
        log_run "Bringing up $INTERFACE"
        fix_resolvconf
        sudo wg-quick up "$INTERFACE" || { fix_resolvconf; exit 1; }
    fi

    fix_resolvconf
    
    local current_full_ip
    current_full_ip=$(curl -4 -s --max-time 5 ifconfig.me || echo "")

    if [[ "$current_full_ip" == "$target_ip" ]]; then
        log_ok "Connected to VPS: $target_ip"
    else
        log_err "Connection failed (Current IP: $(get_masked_ip))"
        vpn_down "$target_ip"
        exit 1
    fi
}

vpn_down() {
    local target_ip=$1
    log_run "Stopping $INTERFACE"
    
    fix_resolvconf
    
    if check_wg_active || ip link show "$INTERFACE" &>/dev/null; then
        sudo wg-quick down "$INTERFACE" || {
            sudo ip link delete dev "$INTERFACE" || true
        }
    fi

    fix_resolvconf

    log_run "Verifying shutdown"
    local current_full_ip
    current_full_ip=$(curl -4 -s --max-time 5 ifconfig.me || echo "")

    if [[ "$current_full_ip" != "$target_ip" ]]; then
        log_ok "Disconnected (Current IP: $(get_masked_ip))"
    else
        log_warn "Still showing VPS IP: $target_ip"
        exit 1
    fi
}

main() {
    if [[ $# -lt 2 ]]; then usage; fi
    local action=$1
    shift
    local target_ip=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ip-wg) target_ip="${2:-}"; shift 2 ;;
            *) usage ;;
        esac
    done

    if [[ -z "$target_ip" ]]; then usage; fi

    case "$action" in
        up) vpn_up "$target_ip" ;;
        down) vpn_down "$target_ip" ;;
        *) usage ;;
    esac
}

main "$@"
