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
#   For all the Kiro tiling window managers plus the XFCE desktop, the
#   KDE Plasma keybindings package, and the Hyprland (Wayland) edition,
#   in order: (1) push each source repo to GitHub via its own up.sh,
#   (2) build each package from its build.sh, and (3) publish
#   nemesis_repo once at the end.
#
# Why:
#   After a cross-environment change (e.g. regenerating every env's
#   keybindings cheatsheet, or propagating ohmychadwm's keybindings),
#   all of these packages need rebuilding together. The build dirs pull
#   kirodubes/<name> as a git+ source, so the source MUST be pushed
#   before building or the chroot pulls stale config. This runs the
#   push, build, and publish in one pass, sequentially, so each step can
#   be watched in turn.
#
#   Most packages live under ~/KIRO/<name> (source) + this dir/<name>
#   (build). Hyprland is the exception: its source is ~/KIROTUX/
#   kiro-hyprland and its build recipe ~/KIROTUX/KIROTUX-PKG-BUILD/
#   kiro-hyprland — handled via the SOURCE_OVERRIDE / BUILD_OVERRIDE
#   maps below.
#####################################################################

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Canonical source repos (where the config edits live and get pushed to GitHub).
# The build dirs here pull those same kirodubes/<name> repos as their git+ source,
# so the source must be pushed BEFORE building or the chroot pulls stale bindings.
SOURCE_DIR="/home/erik/KIRO"

# Each name is BOTH the source repo dir (${SOURCE_DIR}/<name>) and the build dir
# (${SCRIPT_DIR}/<name>) — the two match one-to-one, EXCEPT where overridden below.
PACKAGES=(
    ohmychadwm
    kiro-chadwm
    kiro-awesome
    kiro-bspwm
    kiro-i3
    kiro-leftwm
    kiro-qtile
    kiro-xfce
    kiro-plasma-keybindings
    kiro-hyprland
)

# Per-package location overrides. Hyprland lives in the KIROTUX (Wayland) tree,
# not under ~/KIRO and ~/KIRO-PKG-BUILD-APPS like everything else.
declare -A SOURCE_OVERRIDE=(
    [kiro-hyprland]="/home/erik/KIROTUX/kiro-hyprland"
)
declare -A BUILD_OVERRIDE=(
    [kiro-hyprland]="/home/erik/KIROTUX/KIROTUX-PKG-BUILD/kiro-hyprland"
)

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
push_sources() {
    local total count name dir
    total="${#PACKAGES[@]}"
    count=0

    log_section "Pushing ${total} source repos to GitHub (commit + push via each up.sh)"

    for name in "${PACKAGES[@]}"; do
        count=$((count + 1))
        dir="${SOURCE_OVERRIDE[${name}]:-${SOURCE_DIR}/${name}}"

        log_info "Source ${count} of ${total}: ${name}"

        if [[ ! -d "${dir}" ]]; then
            log_warn "Source repo not found: ${dir} — skipping push"
            echo "Error: ${name} source repo not found" | tee -a /tmp/failed
            FAILED+=("${name} (push: source repo not found)")
            continue
        fi

        if [[ ! -f "${dir}/up.sh" ]]; then
            log_warn "No up.sh in source ${name} — skipping push"
            echo "Error: ${name} source has no up.sh" | tee -a /tmp/failed
            FAILED+=("${name} (push: no up.sh)")
            continue
        fi

        # A repo that will not push must not stop the other pushes or the builds.
        if (cd "${dir}" && bash ./up.sh); then
            continue
        fi

        log_error "Push FAILED for ${name} — continuing with the rest"
        echo "Error: ${name} failed to push" | tee -a /tmp/failed
        FAILED+=("${name} (push)")
    done
}

build_packages() {
    local total count name dir
    total="${#PACKAGES[@]}"
    count=0

    log_section "Building ${total} packages one by one"

    for name in "${PACKAGES[@]}"; do
        count=$((count + 1))
        dir="${BUILD_OVERRIDE[${name}]:-${SCRIPT_DIR}/${name}}"

        log_info "Package ${count} of ${total}: ${name}"

        if [[ ! -d "${dir}" ]]; then
            log_warn "Directory not found: ${dir} — skipping"
            echo "Error: ${name} directory not found" | tee -a /tmp/failed
            FAILED+=("${name} (build: directory not found)")
            continue
        fi

        if [[ ! -f "${dir}/build.sh" ]]; then
            log_warn "No build.sh in ${name} — skipping"
            echo "Error: ${name} has no build.sh" | tee -a /tmp/failed
            FAILED+=("${name} (build: no build.sh)")
            continue
        fi

        # One bad package must not take the batch down with it.
        if (cd "${dir}" && bash ./build.sh); then
            continue
        fi

        log_error "Build FAILED for ${name} — continuing with the rest"
        FAILED+=("${name} (build)")
    done
}

report_failures() {
    if [[ "${#FAILED[@]}" -eq 0 ]]; then
        log_success "All ${#PACKAGES[@]} packages pushed and built without errors"
        return 0
    fi

    log_error "$(printf '%s step(s) did NOT complete:\n%s\nFull log: /tmp/failed' \
        "${#FAILED[@]}" "$(printf '  - %s\n' "${FAILED[@]}")")"
}

publish_repo() {
    log_section "Publishing nemesis_repo"
    bash /home/erik/EDU/nemesis_repo/up.sh
}

#####################################################################
# Main
#####################################################################
main() {
    FAILED=()
    : > /tmp/failed

    push_sources
    build_packages
    publish_repo
    report_failures

    log_success "$(basename "$0") done"
}

main "$@"
