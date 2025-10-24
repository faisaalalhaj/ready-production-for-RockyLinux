#!/bin/bash
# ===========================================================
# 🚀 Rocky Linux Production Setup Script
# Stack: Next.js + Node.js + PM2 + Nginx
# Author: CloudCode (for Rocky Linux)
# ===========================================================

set -e

# ====== EDIT THESE VARIABLES ======
APP_NAME="my-nextjs-app"
DOMAIN="example.com"
REPO_URL="https://github.com/yourname/my-nextjs-app.git"
NODE_VERSION="20"
TIMEZONE="Asia/Riyadh"
HOSTNAME_VALUE="prod-server"
APP_DIR="/var/www/$APP_NAME"
# =================================

echo "============================================"
echo "🚀 Starting production setup for $APP_NAME"
echo "============================================"

# --- 1. Update & upgrade system ---
echo "📦 Updating system packages..."
dnf -y update && dnf -y upgrade

# --- 2. Set timezone ---
echo "🌍 Setting timezone to $TIMEZONE"
timedatectl set-timezone "$TIMEZONE"

# --- 3. Set hostname ---
echo "💻 Setting hostname to $HOSTNAME_VALUE"
hostnamectl set-hostname "$HOSTNAME_VALUE"

# --- 4. Install dependencies ---
echo "📦 Installing dependencies..."
dnf install -y curl git nginx firewalld 

# --- 5. Install Node.js LTS ---
echo "📦 Installing Node.js v$NODE_VERSION..."
curl -fsSL https://rpm.nodesource.com/setup_$NODE_VERSION.x | bash -
dnf install -y nodejs

# --- 6. Prepare app directory ---
echo "📁 Setting up application directory..."
mkdir -p "$APP_DIR"
cd /var/www

if [ ! -d "$APP_DIR/.git" ]; then
  echo "📥 Cloning application repository..."
  git clone "$REPO_URL" "$APP_DIR"
else
  echo "🔁 Repo already exists, pulling latest changes..."
  cd "$APP_DIR" && git pull
fi

cd "$APP_DIR"

# --- 7. Install dependencies & build ---
echo "📦 Installing NPM packages..."
npm install --legacy-peer-deps
echo "🏗️ Building Next.js app..."
npm run build

# --- 8. Setup PM2 ---
echo "⚙️ Installing PM2 process manager..."
npm install -g pm2
pm2 start "npm run start" --name "$APP_NAME" --cwd "$APP_DIR"
pm2 save
pm2 startup systemd -u $USER --hp $HOME

# --- 9. Configure Nginx Reverse Proxy ---
echo "🌐 Configuring Nginx for $DOMAIN..."
NGINX_CONF="/etc/nginx/conf.d/$APP_NAME.conf"

cat > "$NGINX_CONF" <<EOL
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }

    # Gzip Compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss image/svg+xml;
    gzip_vary on;

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header Referrer-Policy "no-referrer-when-downgrade";
    add_header X-XSS-Protection "1; mode=block";

    access_log /var/log/nginx/${APP_NAME}_access.log;
    error_log /var/log/nginx/${APP_NAME}_error.log;
}
EOL

# --- 10. Test & restart Nginx ---
echo "🔄 Testing and restarting Nginx..."
nginx -t && systemctl enable nginx && systemctl restart nginx

# --- 11. Configure firewall ---
echo "🛡️ Configuring firewall..."
systemctl enable firewalld --now
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

# --- 12. Log rotation (optional) ---
echo "🧹 Setting up log rotation..."
cat > /etc/logrotate.d/$APP_NAME <<EOL
/var/log/nginx/${APP_NAME}_*.log {
    weekly
    missingok
    rotate 12
    compress
    delaycompress
    notifempty
    create 0640 nginx adm
    sharedscripts
    postrotate
        [ -f /var/run/nginx.pid ] && kill -USR1 \`cat /var/run/nginx.pid\`
    endscript
}
EOL

# --- 13. Final Summary ---
echo "============================================"
echo "✅ Setup completed successfully!"
echo "🌍 Domain: http://$DOMAIN"
echo "🕒 Timezone: $TIMEZONE"
echo "💻 Hostname: $HOSTNAME_VALUE"
echo "📁 App Path: $APP_DIR"
echo "⚙️ PM2 App: $APP_NAME"
echo "============================================"
