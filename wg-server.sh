#!/usr/bin/env bash

set -euo pipefail

readonly INTERFACE="wg0"

G='\033[0;32m'
R='\033[0;31m'
Y='\033[0;33m'
NC='\033[0m'

usage() {
    printf "${R}Usage: $0 {up|down} --ip-wg <EXPECTED_IP>${NC}\n"
    exit 1
}

fix_resolvconf() {
    printf "${Y}Running: resolvconf -u${NC}\n"
    sudo resolvconf -u || true
}

get_masked_ip() {
    local full_ip
    full_ip=$(curl -s --max-time 5 ifconfig.me || echo "OFFLINE")
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
        printf "${Y}Status: $INTERFACE is already up${NC}\n"
    else
        printf "${G}Action: Bringing up $INTERFACE${NC}\n"
        fix_resolvconf
        sudo wg-quick up "$INTERFACE" || { fix_resolvconf; exit 1; }
    fi

    fix_resolvconf
    
    local current_full_ip
    current_full_ip=$(curl -s --max-time 5 ifconfig.me || echo "")
    
    if [[ "$current_full_ip" == "$target_ip" ]]; then
        printf "${G}Status: Success (Connected to VPS: $target_ip)${NC}\n"
    else
        printf "${R}Status: Failure (Current IP: $(get_masked_ip))${NC}\n"
        vpn_down "$target_ip"
        exit 1
    fi
}

vpn_down() {
    local target_ip=$1
    printf "${R}Action: Stopping $INTERFACE${NC}\n"
    
    fix_resolvconf
    
    if check_wg_active || ip link show "$INTERFACE" &>/dev/null; then
        sudo wg-quick down "$INTERFACE" || {
            sudo ip link delete dev "$INTERFACE" || true
        }
    fi

    fix_resolvconf

    printf "${G}Action: Verifying Shutdown${NC}\n"
    local current_full_ip
    current_full_ip=$(curl -s --max-time 5 ifconfig.me || echo "")

    if [[ "$current_full_ip" != "$target_ip" ]]; then
        printf "${G}Status: Success (Current IP: $(get_masked_ip))${NC}\n"
    else
        printf "${R}Status: Warning (Still showing VPS IP: $target_ip)${NC}\n"
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
