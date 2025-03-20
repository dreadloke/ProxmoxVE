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

# Use Node.js directly to install Strapi
# Install yarn using npm instead of apt-get to get the correct package
$STD npm install -g yarn
if [ $? -ne 0 ]; then
    msg_error "Failed to install yarn. Trying alternative method..."
    $STD curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | tee /usr/share/keyrings/yarn-archive-keyring.gpg >/dev/null
    $STD echo "deb [signed-by=/usr/share/keyrings/yarn-archive-keyring.gpg] https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
    $STD apt-get update && apt-get install -y yarn
fi

# Create directory structure
mkdir -p /opt/strapi/config

# Create a package.json file
cat > /opt/strapi/package.json << EOF
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

# Install dependencies - run in the correct directory with explicit path
cd /opt/strapi || { msg_error "Failed to change to /opt/strapi directory"; exit 1; }
msg_info "Installing Strapi dependencies with yarn (this may take a while)..."
$STD yarn install --non-interactive --network-timeout 600000
if [ $? -ne 0 ]; then
    msg_error "Yarn install failed. Trying with npm instead..."
    $STD npm install --no-fund --no-audit
fi

# Initialize Strapi with database connection
cat > /opt/strapi/config/database.js << EOF
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
cat > /opt/strapi/.env << EOF
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
cd /opt/strapi || { msg_error "Failed to change to /opt/strapi directory"; exit 1; }
msg_info "Building Strapi (this may take a while)..."
$STD yarn build
if [ $? -ne 0 ]; then
    msg_error "Yarn build failed. Trying with npm instead..."
    $STD npm run build
fi

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