#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/dreadloke/ProxmoxVE/refs/heads/feature-strapi-hs/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: dreadloke (dreadloke)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://strapi.io/

## App Default Values
APP="Strapi"
var_tags="cms;api;headless"
var_disk="10"
var_cpu="2"
var_ram="2048"
var_os="debian"
var_version="12"

header_info "$APP" 
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -d /opt/strapi ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    msg_error "Strapi should be updated via the user interface."
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN} ${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}/admin/${CL}" 