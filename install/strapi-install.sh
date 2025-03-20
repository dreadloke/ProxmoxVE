#!/usr/bin/env bash

# Description: Strapi CMS Installation Script
# Dependencies: curl, nginx, nodejs, npm, postgresql
# Version: 1.0.0
# Author: MickLesk (Canbiz)
# License: MIT
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

# Add error handling function
function error_handler() {
    local line_number=$1
    msg_error "An error occurred in line ${line_number}"
    cleanup
}

# Add cleanup function
function cleanup() {
    msg_info "Performing cleanup..."
    apt-get autoremove -y >/dev/null 2>&1
    apt-get autoclean -y >/dev/null 2>&1
}

# Add trap for error handling
trap 'error_handler $LINENO' ERR

# Add function for database setup
function setup_database() {
    local db_name=$1
    local db_user=$2
    local db_pass=$3
    
    msg_info "Setting up PostgreSQL Database"
    $STD sudo -u postgres psql -c "CREATE DATABASE $db_name;"
    $STD sudo -u postgres psql -c "CREATE USER $db_user WITH PASSWORD '$db_pass';"
    $STD sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $db_name TO $db_user;"
}

# Add function for Strapi configuration
function configure_strapi() {
    msg_info "Configuring Strapi Environment"
    local db_name=$1
    local db_user=$2
    local db_pass=$3
    
    # Generate secure random keys
    local app_keys=$(openssl rand -base64 32)
    local api_token_salt=$(openssl rand -base64 32)
    local admin_jwt_secret=$(openssl rand -base64 32)
    
    # Create environment file with proper configurations
    cat <<EOF > /opt/strapi/.env
HOST=0.0.0.0
PORT=1337
APP_KEYS=$app_keys
API_TOKEN_SALT=$api_token_salt
ADMIN_JWT_SECRET=$admin_jwt_secret
TRANSFER_TOKEN_SALT=$(openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 32)
DATABASE_CLIENT=postgres
DATABASE_HOST=127.0.0.1
DATABASE_PORT=5432
DATABASE_NAME=$db_name
DATABASE_USERNAME=$db_user
DATABASE_PASSWORD=$db_pass
DATABASE_SSL=false
NODE_ENV=production
EOF
}

msg_info "Setting up Database"
DB_NAME=strapi_db
DB_USER=strapi
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
setup_database $DB_NAME $DB_USER $DB_PASS
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

# Use a direct approach with yarn instead of npm/npx to avoid prompts
$STD apt-get update
$STD apt-get install -y yarn

# Create a package.json file
cat > package.json << EOF
{
  "name": "strapi-app",
  "private": true,
  "version": "0.1.0",
  "description": "Strapi application",
  "scripts": {
    "develop": "strapi develop",
    "start": "strapi start",
    "build": "strapi build",
    "strapi": "strapi"
  },
  "dependencies": {
    "@strapi/strapi": "latest",
    "@strapi/plugin-users-permissions": "latest",
    "@strapi/plugin-i18n": "latest",
    "pg": "latest"
  },
  "engines": {
    "node": ">=16.0.0",
    "npm": ">=6.0.0"
  },
  "strapi": {
    "uuid": "$(openssl rand -hex 16)"
  }
}
EOF

# Install dependencies
$STD yarn install

# Create config directory and initialize Strapi with database connection
mkdir -p config
cat > config/database.js << EOF
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

# Create .env file with proper configuration
cat > .env << EOF
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
DATABASE_SSL=false
NODE_ENV=production
EOF

# Build Strapi for production use
$STD yarn build

msg_ok "Installed Strapi"

msg_info "Configuring Strapi"
configure_strapi $DB_NAME $DB_USER $DB_PASS
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
cleanup
msg_ok "Cleaned" 