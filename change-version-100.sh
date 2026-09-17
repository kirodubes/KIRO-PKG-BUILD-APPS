#!/bin/bash
set -euo pipefail
#####################################################################
# Author    : Erik Dubois
# Website   : https://kiroproject.be
#####################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
# Purpose:
#   Pin EVERY package in this folder to a fixed version
#   pkgver=<current YY.MM> pkgrel=100 by rewriting each PKGBUILD and recording
#   the result in .current-version. Does NOT build anything — run
#   build-100.sh afterwards to build and publish the pinned set.
#
# Why:
#   pkgrel=100 deliberately out-ranks any release currently installed
#   or in the repo, so a later force-build + `pacman -Syu` pulls fresh
#   copies of the whole set across every Kiro system — a clean re-sync.
#   Splitting the version pin from the build lets you inspect or tweak
#   the pinned PKGBUILDs before committing CPU to a full rebuild.
#####################################################################

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

FORCE_PKGVER="$(date +%y.%m)"
FORCE_PKGREL="100"

#####################################################################
# Colors
#####################################################################
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"
    CYAN="$(tput setaf 6)"
    RESET="$(tput sgr0)"
else
    RED="" GREEN="" YELLOW="" BLUE="" CYAN="" RESET=""
fi

#####################################################################
# Logging
#####################################################################
log_section() {
    echo
    echo "${GREEN}############################################################################${RESET}"
    echo "$1"
    echo "${GREEN}############################################################################${RESET}"
    echo
}

log_info() {
    echo
    echo "${BLUE}############################################################################${RESET}"
    echo "$1"
    echo "${BLUE}############################################################################${RESET}"
    echo
}

log_warn() {
    echo
    echo "${YELLOW}############################################################################${RESET}"
    echo "$1"
    echo "${YELLOW}############################################################################${RESET}"
    echo
}

log_error() {
    echo
    echo "${RED}############################################################################${RESET}"
    echo "$1"
    echo "${RED}############################################################################${RESET}"
    echo
}

log_success() {
    echo
    echo "${GREEN}############################################################################${RESET}"
    echo "$1"
    echo "${GREEN}############################################################################${RESET}"
    echo
}

#####################################################################
# Error handling
#####################################################################
on_error() {
    local lineno="$1"
    local cmd="$2"
    echo
    echo "${RED}ERROR on line ${lineno}: ${cmd}${RESET}"
    echo
    sleep 10
}

trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

#####################################################################
# Functions
#####################################################################
force_version() {
    # Pin a single package's PKGBUILD to FORCE_PKGVER/FORCE_PKGREL and
    # record the result in .current-version.
    local dir="$1"
    local pkgbuild="${dir}/PKGBUILD"
    local epoch

    sed -i "s/^pkgver=.*/pkgver=${FORCE_PKGVER}/" "${pkgbuild}"
    sed -i "s/^pkgrel=.*/pkgrel=${FORCE_PKGREL}/" "${pkgbuild}"

    epoch=$(grep -m1 "epoch" "${pkgbuild}" | cut -d= -f2 || true)
    {
        echo "pkgver=${FORCE_PKGVER}"
        echo "pkgrel=${FORCE_PKGREL}"
        echo "epoch=${epoch}"
    } > "${dir}/.current-version"

    log_info "Pinned $(basename "${dir}") to ${FORCE_PKGVER}-${FORCE_PKGREL}"
}

pin_all_packages() {
    local dirs total count

    mapfile -t dirs < <(find "${SCRIPT_DIR}" -maxdepth 1 -mindepth 1 -type d -not -name ".*" | sort)
    total="${#dirs[@]}"
    count=0

    log_section "Pinning ${total} packages to ${FORCE_PKGVER}-${FORCE_PKGREL}"

    for dir in "${dirs[@]}"; do
        count=$((count + 1))
        local name
        name="$(basename "${dir}")"

        log_info "Package ${count} of ${total}: ${name}"

        if [[ ! -f "${dir}/PKGBUILD" ]]; then
            log_warn "No PKGBUILD in ${name} — skipping"
            continue
        fi

        force_version "${dir}"
    done
}

#####################################################################
# Main
#####################################################################
main() {
    pin_all_packages

    log_success "$(basename "$0") done"
}

main "$@"
