#!/bin/bash

set -e  # Exit on error

PG_VERSION=15
PG_SERVICE="postgresql"
PG_DATA="/var/lib/pgsql/$PG_VERSION/data"
PG_CONF="$PG_DATA/postgresql.conf"
PG_HBA="$PG_DATA/pg_hba.conf"
DB_HOST=$(hostname -I | awk '{print $1}')
DB_NAME="connectors"
DB_USER="admin"
DB_PASS="admin_password"

# Function to check if PostgreSQL is installed
install_postgresql() {
    echo "\n🔍 Checking if PostgreSQL is installed..."
    if ! rpm -qa | grep -q "postgresql$PG_VERSION"; then
        echo "⬇️ Installing PostgreSQL..."
        sudo dnf install -y postgresql$PG_VERSION postgresql$PG_VERSION-server
    else
        echo "✅ PostgreSQL is already installed."
    fi
}

# Function to initialize PostgreSQL database if not already initialized
initialize_postgresql() {
    echo "\n📂 Checking PostgreSQL data directory..."
    if [ -d "$PG_DATA" ] && [ -n "$(ls -A "$PG_DATA" 2>/dev/null)" ]; then
        echo "✅ Data directory already exists. Skipping initialization."
    else
        echo "📂 Initializing PostgreSQL database..."
        sudo /usr/bin/postgresql-setup --initdb
        echo "✅ Database initialized."
    fi
}

# Function to configure PostgreSQL to allow remote connections
configure_postgresql() {
    echo "\n⚙️ Configuring PostgreSQL..."
    if [ -f "$PG_CONF" ]; then
        sudo sed -i "s|^#listen_addresses = 'localhost'|listen_addresses = '*'|" "$PG_CONF"
        echo "host    all             all             0.0.0.0/0               md5" | sudo tee -a "$PG_HBA"
        echo "✅ Configuration updated."
    else
        echo "❌ PostgreSQL configuration file not found! Skipping."
    fi
}

# Function to start PostgreSQL service
start_postgresql() {
    echo "\n🚀 Starting PostgreSQL service..."
    sudo systemctl enable --now $PG_SERVICE || echo "⚠️ Failed to enable/start PostgreSQL service."
}

# Function to create the 'admin' role with all privileges on 'connectors' database
create_admin_role() {
    echo "\n👤 Creating admin role and database..."
    sudo -u postgres psql <<EOF
DO
\$do\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME') THEN
      CREATE DATABASE IF NOT EXISTS $DB_NAME;
   END IF;
END
\$do\$;

DO
\$do\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_USER') THEN
      CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';
      ALTER ROLE $DB_USER WITH SUPERUSER CREATEDB CREATEROLE;
   END IF;
END
\$do\$;

GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF
    echo "✅ Admin role '$DB_USER' created with full privileges on '$DB_NAME'."
}

# Function to check if PostgreSQL is listening on port 5432
verify_postgresql() {
    echo "\n🔎 Verifying PostgreSQL service..."
    if ss -tulnp | grep -q ":5432"; then
        echo "✅ PostgreSQL is running successfully!"
        echo "🔗 PostgreSQL is running on: $DB_HOST:5432"
        echo "   Login using: sudo -u postgres psql -d $DB_NAME"
    else
        echo "❌ PostgreSQL is NOT running properly! Check logs."
        exit 1
    fi
}

# Execute functions
install_postgresql
initialize_postgresql
configure_postgresql
start_postgresql
create_admin_role
verify_postgresql

echo "\n✅ PostgreSQL setup completed."