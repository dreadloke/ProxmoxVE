#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: dreadloke
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/PhantomBot/PhantomBot

# Import Functions und Setup
source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

APPLICATION="PhantomBot"
APP_NAME="phantombot" # Lowercase for user/service names
PHANTOMBOT_HOME="/home/${APP_NAME}"
PHANTOMBOT_DIR="${PHANTOMBOT_HOME}/phantombot"
PHANTOMBOT_REPO="https://github.com/PhantomBot/PhantomBot.git"

# Installing Dependencies
msg_info "Installing Dependencies for ${APPLICATION}"
$STD apt-get install -y \
  openjdk-17-jre-headless \
  curl \
  git \
  screen
msg_ok "Installed Dependencies"

# Setup App User and Clone Repo
msg_info "Setting up User and Downloading ${APPLICATION}"

# Create user
useradd -m -s /bin/bash "${APP_NAME}" || {
    error "Failed to create user '${APP_NAME}'."
    exit 1
}
msg_ok "Created user '${APP_NAME}'"

# Clone PhantomBot as the new user
su - "${APP_NAME}" -c "git clone ${PHANTOMBOT_REPO} ${PHANTOMBOT_DIR}" || {
    error "Failed to clone PhantomBot repository."
    # Attempt to clean up user?
    userdel -r "${APP_NAME}" 2>/dev/null || true
    exit 1
}
msg_ok "Cloned ${APPLICATION} repository to ${PHANTOMBOT_DIR}"

# Make launch script executable (as root, since user might not have permissions yet)
launch_script="${PHANTOMBOT_DIR}/launch.sh"
if [[ -f "${launch_script}" ]]; then
    chmod +x "${launch_script}" || {
        warn "Failed to make launch script (${launch_script}) executable."
        # Not exiting, as it might be a minor issue
    }
    msg_ok "Made launch script executable"
else
    warn "Launch script (${launch_script}) not found after clone."
fi

# Optionally: Store release/version info (if needed for updates)
# Could try getting the tag from the cloned repo?
# latest_tag=$(cd "${PHANTOMBOT_DIR}" && git describe --tags --abbrev=0)
# if [[ -n "${latest_tag}" ]]; then
#     echo "${latest_tag}" > "/opt/${APP_NAME}_version.txt"
#     msg_ok "Stored version info (${latest_tag})"
# else
#     warn "Could not determine PhantomBot version from git tags."
# fi
msg_ok "Setup ${APPLICATION}"

# Creating Service (Optional but Recommended)
# PhantomBot often runs in screen. A simple service might just launch it in screen.
# More complex setup could involve running the Java process directly.
msg_info "Creating systemd Service (Optional: runs PhantomBot in screen)"
SERVICE_NAME="${APP_NAME}.service"
cat <<EOF > "/etc/systemd/system/${SERVICE_NAME}"
[Unit]
Description=${APPLICATION} Service (via screen)
# Ensures network is up, adjust if PhantomBot has other dependencies (e.g., database)
After=network.target

[Service]
User=${APP_NAME}
WorkingDirectory=${PHANTOMBOT_DIR}

# Using screen to run launch.sh in a detached session.
# This is a common way to run PhantomBot, but not ideal for systemd
# as systemd doesn't directly manage the Java process PID.
ExecStart=/usr/bin/screen -DmS ${APP_NAME} ${PHANTOMBOT_DIR}/launch.sh

# Stopping the service by killing the screen session.
# This might not allow for graceful shutdown of PhantomBot itself.
# A more robust solution would involve signalling the Java process directly,
# but that is significantly more complex to implement here.
ExecStop=/usr/bin/screen -S ${APP_NAME} -X quit

# Restart the service if it fails
Restart=on-failure

# Type=simple assumes ExecStart exits shortly after forking screen.
# If Type=forking were used, systemd would need a PID file, which screen doesn't easily provide.
Type=simple

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now "${SERVICE_NAME}" || {
    warn "Failed to enable or start ${SERVICE_NAME}. PhantomBot might need manual starting."
    warn "Check service status: systemctl status ${SERVICE_NAME}"
    warn "Check service logs: journalctl -u ${SERVICE_NAME}"
}
msg_ok "Created and enabled systemd service (${SERVICE_NAME})"

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

# Final message
msg_ok "${APPLICATION} installation complete!"
echo -e "${INFO} PhantomBot is installed in ${PHANTOMBOT_DIR}"
echo -e "${INFO} It requires manual configuration via the botlogin.txt file."
echo -e "${INFO} Access the container using: pct enter ${CTID}"
echo -e "${INFO} Configure as the '${APP_NAME}' user: su - ${APP_NAME}"
echo -e "${INFO} The service (${SERVICE_NAME}) attempts to run PhantomBot in a screen session."
echo -e "${INFO} You can attach to it (as root or ${APP_NAME}) using: screen -r ${APP_NAME}" 