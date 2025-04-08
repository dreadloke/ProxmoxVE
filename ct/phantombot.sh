#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/dreadloke/ProxmoxVE/feature-phantombot-script/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: dreadloke
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/PhantomBot/PhantomBot

# App Default Values
APP="PhantomBot"
# Name of the app (e.g. Google, Adventurelog, Apache-Guacamole"
var_tags="chatbot;stream"
# Tags for Proxmox VE, maximum 2 pcs., no spaces allowed, separated by a semicolon ; (e.g. database | adblock;dhcp)
var_cpu="2"
# Number of cores (1-X) (e.g. 4) - default are 2
var_ram="1024"
# Amount of used RAM in MB (e.g. 2048 or 4096)
var_disk="8"
# Amount of used disk space in GB (e.g. 4 or 10)
var_os="debian"
# Default OS (e.g. debian, ubuntu, alpine)
var_version="12"
# Default OS version (e.g. 12 for debian, 24.04 for ubuntu, 3.20 for alpine)
var_unprivileged="1"
# 1 = unprivileged container, 0 = privileged container

# --- Helper Functions (Password Prompt) ---
# Included directly as build.func might not have it
prompt_for_password() {
    local prompt="Enter password for LXC root user: "
    local password_var=""
    while IFS= read -p "$prompt" -r -s password_var && [[ -z "$password_var" ]]; do
        echo "Password cannot be empty."
    done
    echo # Add newline after password input
    PASSWORD="$password_var" # Set the global PASSWORD variable
}
# ---------------------------------------

header_info "$APP"
variables # This function from build.func likely handles cmd-line args for CPU, RAM etc.
color
catch_errors

# This function is called by build.func after variable processing
function custom_variables() {
    # Prompt for password after standard variables are processed
    prompt_for_password
    if [[ -z "${PASSWORD:-}" ]]; then # Check if PASSWORD is set and not empty
        error "Password acquisition failed."
        exit 1
    fi
}

function update_script() {
    header_info

    # Define paths and user within the container
    local phantombot_user="phantombot"
    local phantombot_dir="/home/${phantombot_user}/phantombot"
    local version_file="/opt/${APP}_version.txt" # Consistent with install script template
    local service_name="${APP}.service"

    # --- Check 1: Does the container exist and is running? ---
    # build.func might handle this via check_container_resources, but adding explicit check
    if ! pct status $CTID | grep -q "status: running"; then
        msg_error "Container ${CTID} is not running. Cannot update."
        exit 1
    fi
    msg_ok "Container ${CTID} is running."

    # --- Check 2: Does the version file exist? ---
    msg_info "Checking for existing installation version..."
    local current_version
    # Use pct exec to run cat inside the container. Capture output, ignore errors if file not found.
    current_version=$(pct exec $CTID -- bash -c "cat ${version_file} 2>/dev/null")

    if [[ -z "${current_version}" ]]; then
        msg_warn "Could not read current version from ${version_file} in container ${CTID}."
        msg_warn "Attempting update based on latest Git tag."
        # Optionally exit if strict version checking is required
        # exit 1
    else
        msg_ok "Current installed version (from file): ${current_version}"
    fi

    # --- Check 3: Get latest version from Git repo --- ##
    msg_info "Fetching latest version tag from GitHub repository..."
    local latest_version
    # Run git command inside the container as the phantombot user
    local git_cmd="cd ${phantombot_dir} && git fetch --tags origin && git describe --tags --abbrev=0"
    latest_version=$(pct exec $CTID -- su - "${phantombot_user}" -c "${git_cmd}" 2>/dev/null) 

    if [[ -z "${latest_version}" ]]; then
        msg_error "Failed to fetch the latest version tag from the repository in ${phantombot_dir}."
        msg_error "Ensure git is installed and the directory exists and is a git repo."
        exit 1
    fi
    msg_ok "Latest available version tag: ${latest_version}"

    # --- Check 4: Compare versions --- #
    # Simple string comparison. Assumes tags are comparable directly.
    if [[ "${current_version}" == "${latest_version}" ]]; then
        msg_ok "${APP} is already up to date (Version: ${current_version})."
        exit 0
    fi

    msg_info "Update available: ${current_version:-'Unknown'} -> ${latest_version}"
    read -p "Proceed with update? (y/N): " confirm_update
    if [[ "${confirm_update,,}" != "y" ]]; then
        info "Update aborted by user."
        exit 0
    fi

    # --- Step 5: Stop Service --- #
    msg_info "Stopping ${service_name}..."
    pct exec $CTID -- systemctl stop "${service_name}" || warn "Failed to stop ${service_name}. Attempting update anyway."
    # Add a small delay to allow service to stop gracefully
    sleep 3
    msg_ok "Service stop command issued."

    # --- Step 6: Backup (Optional but Recommended) --- #
    local backup_file="/opt/${APP}_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    msg_info "Creating backup of ${phantombot_dir} to ${backup_file}..."
    pct exec $CTID -- tar -czf "${backup_file}" -C "$(dirname "${phantombot_dir}")" "$(basename "${phantombot_dir}")" || {
        warn "Failed to create backup file ${backup_file}. Proceeding without backup."
    }
    msg_ok "Backup created (or skipped on error)."

    # --- Step 7: Update --- #
    msg_info "Performing git pull in ${phantombot_dir} as user '${phantombot_user}'..."
    # Ensure ownership is correct before pulling as user
    pct exec $CTID -- chown -R "${phantombot_user}:${phantombot_user}" "${phantombot_dir}" || warn "Could not ensure ownership of ${phantombot_dir}."
    # Pull changes
    local pull_cmd="cd ${phantombot_dir} && git checkout master && git pull origin master"
    # Execute as phantombot user
    pct exec $CTID -- su - "${phantombot_user}" -c "${pull_cmd}" || {
        error "Failed to update ${APP} using git pull."
        error "Attempting to restore backup (if exists) and restart service."
        # Attempt restore
        if pct exec $CTID -- test -f "${backup_file}"; then
            msg_info "Restoring backup from ${backup_file}..."
            pct exec $CTID -- rm -rf "${phantombot_dir}"
            pct exec $CTID -- tar -xzf "${backup_file}" -C "$(dirname "${phantombot_dir}")"
            msg_ok "Backup restored."
        else
            warn "No backup file found at ${backup_file} to restore."
        fi
        # Attempt restart even after failed update/restore
        pct exec $CTID -- systemctl start "${service_name}" || warn "Failed to restart ${service_name} after update failure."
        exit 1
    }
    msg_ok "Update performed successfully via git pull."

    # --- Step 8: Start Service --- #
    msg_info "Starting ${service_name}..."
    pct exec $CTID -- systemctl start "${service_name}" || {
        error "Failed to start ${service_name} after update."
        error "Please check the service status manually inside the container: systemctl status ${service_name}"
        # Don't exit, let user know update happened but service failed
    }
    msg_ok "Service start command issued."

    # --- Step 9: Update Version File --- #
    msg_info "Updating version file ${version_file} to ${latest_version}..."
    # Use tee via bash -c to write the file
    pct exec $CTID -- bash -c "echo '${latest_version}' > '${version_file}'" || {
        warn "Failed to update version file ${version_file}."
    }
    msg_ok "Version file updated."

    msg_ok "Update process for ${APP} to version ${latest_version} completed."
    exit 0
}

# Called by build.func
function build_container() {
    # Standard container creation is handled by build.func
    # We add the confirmation prompt here
    warn "You are about to create a ${APP} LXC container with the following settings:"
    echo "  CTID:           ${CTID}"
    echo "  Hostname:       ${HOSTNAME}"
    echo "  CPU Cores:      ${CORE_COUNT}"
    echo "  RAM:            ${RAM_SIZE} MB"
    echo "  Disk Size:      ${DISK_SIZE} GB"
    echo "  OS:             ${OS_TYPE}-${OS_VERSION}"
    echo "  Storage Pool:   ${DISK_STORAGE}"
    echo "  Network:        ${NETWORK_SETTINGS}"
    echo "  Unprivileged:   $( [[ "${UNPRIVILEGED}" == "1" ]] && echo "Yes" || echo "No" )"
    read -p "Do you want to proceed? (y/N): " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        info "Container creation aborted by user."
        exit 0
    fi

    # Call the main container creation function from build.func
    # It will use the variables set (CTID, HOSTNAME, CORE_COUNT, RAM_SIZE, DISK_SIZE, etc.)
    # and the PASSWORD variable for the root user.
    create_container

    # Any steps *after* container creation but *before* installation script runs?
}

start # This function from build.func likely handles initial checks & calls variables
build_container # This calls our function above, which then calls create_container from build.func
description # This function from build.func likely sets the CT description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} container has been created successfully!${CL}"
echo -e "The installation script will now run inside the container."
# The final message with IP/Port might be better placed in the install script's completion message
# echo -e "${INFO}${YW} Access details will be provided upon completion of the installation.${CL}"
# echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:[PORT]${CL}" # IP and PORT might not be available yet or relevant here 