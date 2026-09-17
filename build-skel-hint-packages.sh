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
#   Build, one by one, only the packages that got the post-install
#   copy-paste "cp /etc/skel/... ~/..." hint added to their install
#   scriptlet. Each package's own build.sh (the flow script) is run
#   from inside its directory, then nemesis_repo is published once at
#   the end.
#
# Why:
#   After editing several readme.install / *.install files we only
#   want to rebuild the affected packages, not the whole tree. This
#   runs them sequentially so each build can be watched in turn.
#####################################################################

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

PACKAGES=(
    kiro-bash-config
    kiro-ghostty
    kiro-kitty
    kiro-plasma-konsole
    kiro-zsh-config
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
build_packages() {
    local total count name dir
    total="${#PACKAGES[@]}"
    count=0

    log_section "Building ${total} packages one by one"

    for name in "${PACKAGES[@]}"; do
        count=$((count + 1))
        dir="${SCRIPT_DIR}/${name}"

        log_info "Package ${count} of ${total}: ${name}"

        if [[ ! -d "${dir}" ]]; then
            log_warn "Directory not found: ${dir} — skipping"
            echo "Error: ${name} directory not found" | tee -a /tmp/failed
            FAILED+=("${name} (directory not found)")
            continue
        fi

        if [[ ! -f "${dir}/build.sh" ]]; then
            log_warn "No build.sh in ${name} — skipping"
            echo "Error: ${name} has no build.sh" | tee -a /tmp/failed
            FAILED+=("${name} (no build.sh)")
            continue
        fi

        # One bad package must not take the batch down with it.
        if (cd "${dir}" && bash ./build.sh); then
            continue
        fi

        log_error "Build FAILED for ${name} — continuing with the rest"
        FAILED+=("${name}")
    done
}

report_failures() {
    if [[ "${#FAILED[@]}" -eq 0 ]]; then
        log_success "All ${#PACKAGES[@]} packages built without errors"
        return 0
    fi

    log_error "$(printf '%s of %s package(s) did NOT build:\n%s\nFull log: /tmp/failed' \
        "${#FAILED[@]}" "${#PACKAGES[@]}" "$(printf '  - %s\n' "${FAILED[@]}")")"
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

    build_packages
    publish_repo
    report_failures

    log_success "$(basename "$0") done"
}

main "$@"
