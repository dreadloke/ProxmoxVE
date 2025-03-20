#!/usr/bin/env bash

# Copyright (c) 2021-2025 communtiy-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://strapi.io/

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies (Patience)"
$STD apt-get install -y \
  curl \
  sudo \
  mc \
  nginx \
  nodejs \
  npm \
  postgresql \
  postgresql-contrib \
  libpq-dev
msg_ok "Installed Dependencies"

msg_info "Setting up Database"
DB_NAME=strapi_db
DB_USER=strapi
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;"
$STD sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
{
    echo "Strapi Credentials"
    echo "Database User: $DB_USER"
    echo "Database Password: $DB_PASS"
    echo "Database Name: $DB_NAME"
} >> ~/strapi.creds
msg_ok "Set up Database"

msg_info "Installing Strapi (Patience)"
mkdir -p /opt/strapi || exit
cd /opt/strapi || exit
$STD npx create-strapi-app@latest . --quickstart --no-run
msg_ok "Installed Strapi"

msg_info "Configuring Strapi"
cat <<EOF > /opt/strapi/config/database.js
module.exports = ({ env }) => ({
  connection: {
    client: 'postgres',
    connection: {
      host: env('DATABASE_HOST', '127.0.0.1'),
      port: env.int('DATABASE_PORT', 5432),
      database: env('DATABASE_NAME', '$DB_NAME'),
      user: env('DATABASE_USERNAME', '$DB_USER'),
      password: env('DATABASE_PASSWORD', '$DB_PASS'),
      ssl: env.bool('DATABASE_SSL', false),
    },
    debug: false,
  },
});
EOF

cat <<EOF > /opt/strapi/.env
HOST=0.0.0.0
PORT=1337
APP_KEYS=$(openssl rand -base64 32)
API_TOKEN_SALT=$(openssl rand -base64 32)
ADMIN_JWT_SECRET=$(openssl rand -base64 32)
TRANSFER_TOKEN_SALT=$(openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 32)
DATABASE_CLIENT=postgres
DATABASE_HOST=127.0.0.1
DATABASE_PORT=5432
DATABASE_NAME=$DB_NAME
DATABASE_USERNAME=$DB_USER
DATABASE_PASSWORD=$DB_PASS
EOF
msg_ok "Configured Strapi"

msg_info "Setup Services"
cat <<EOF > /etc/nginx/sites-available/strapi
server {
    listen 80;
    server_name yourdomain.com;

    location / {
        proxy_pass http://localhost:1337;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Server \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

$STD ln -s /etc/nginx/sites-available/strapi /etc/nginx/sites-enabled/
$STD rm /etc/nginx/sites-enabled/default
$STD nginx -t
$STD systemctl restart nginx

# Create systemd service for Strapi
$STD cat <<EOF > /etc/systemd/system/strapi.service
[Unit]
Description=Strapi server
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/strapi
ExecStart=/usr/bin/npm run start
Restart=always
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

$STD systemctl daemon-reload
$STD systemctl enable strapi
$STD systemctl start strapi
msg_ok "Created Services"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get autoremove
$STD apt-get autoclean
msg_ok "Cleaned" 