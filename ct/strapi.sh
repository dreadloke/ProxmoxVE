#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/dreadloke/ProxmoxVE/refs/heads/feature-strapi-hs-test/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: dreadloke (dreadloke)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://strapi.io/

# Add more descriptive header comments
# Description: Strapi CMS Container Setup Script
# Dependencies: curl, build.func
# Version: 1.0.0

## App Default Values
APP="Strapi"
var_tags="cms;api;headless"
var_disk="20"  # Increased from 10 to accommodate growth
var_cpu="2"
var_ram="4096"  # Increased from 2048 for better performance
var_os="debian"
var_version="12"

header_info "$APP" 
variables
color
catch_errors

# Add input validation
function validate_inputs() {
    if [[ $var_ram -lt 2048 ]]; then
        msg_error "Strapi requires at least 2GB RAM to run properly"
        exit 1
    fi
    if [[ $var_disk -lt 10 ]]; then
        msg_error "Minimum disk size of 10GB required"
        exit 1
    fi
}

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    
    # Add error trapping
    trap 'error_handler $LINENO' ERR
    
    if [[ ! -d /opt/strapi ]]; then
        msg_error "No ${APP} Installation Found!"
        exit 1
    fi
    
    # Add more detailed error message
    msg_error "Strapi updates should be managed through the admin interface or using npm/yarn."
    msg_info "Please visit http://${IP}/admin/ to manage your Strapi instance."
    exit 0
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN} ${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}/admin/${CL}" 