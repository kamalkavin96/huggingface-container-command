#!/bin/bash
set -e

# ... [your existing Postgres setup script from before, unchanged] ...

# ==========================================
# Nextcloud setup
# ==========================================
NEXTCLOUD_DIR="/var/www/nextcloud"
NEXTCLOUD_DATA="/data/nextcloud_data"

apt install -y apache2 libapache2-mod-php php php-pgsql php-gd php-curl php-mbstring \
  php-xml php-zip php-intl php-bcmath php-gmp unzip wget

if [ ! -f "$NEXTCLOUD_DIR/config/config.php" ]; then
  echo "Installing Nextcloud..."
  wget -q https://download.nextcloud.com/server/releases/latest.zip -O /tmp/nextcloud.zip
  unzip -q /tmp/nextcloud.zip -d /var/www/
  rm /tmp/nextcloud.zip

  mkdir -p "$NEXTCLOUD_DATA"
  chown -R www-data:www-data "$NEXTCLOUD_DIR" "$NEXTCLOUD_DATA"

  sudo -u www-data php "$NEXTCLOUD_DIR/occ" maintenance:install \
    --database "pgsql" \
    --database-name "${DB_NAME}" \
    --database-user "${DB_USER}" \
    --database-pass "${DB_PASS}" \
    --database-host "127.0.0.1" \
    --admin-user "admin" \
    --admin-pass "${NEXTCLOUD_ADMIN_PASS:-adminpass}" \
    --data-dir "$NEXTCLOUD_DATA"
else
  echo "Nextcloud already installed — skipping."
fi

# Configure Apache port (idempotent, safe to repeat)
sed -i "s/Listen 80/Listen 3000/g" /etc/apache2/ports.conf
sed -i "s/<VirtualHost \*:80>/<VirtualHost *:3000>/g" /etc/apache2/sites-available/000-default.conf
sed -i "s|DocumentRoot .*|DocumentRoot $NEXTCLOUD_DIR|g" /etc/apache2/sites-available/000-default.conf
a2enmod rewrite headers env dir mime >/dev/null

# Trust the container's proxy domain (needed behind Nginx/Cloudflare Tunnel)
sudo -u www-data php "$NEXTCLOUD_DIR/occ" config:system:set trusted_domains 1 --value="*"

apache2ctl start

echo "Nextcloud running on port 3000, backed by Postgres at $DATA_DIR"
