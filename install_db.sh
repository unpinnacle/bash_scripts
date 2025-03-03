#!/bin/bash

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print messages with clear formatting
log() {
  echo -e "\n🔹 $1"
}

warn() {
  echo -e "\n${YELLOW}⚠️ WARNING:${NC} $1"
}

error_exit() {
  echo -e "\n${RED}❌ ERROR:${NC} $1"
  exit 1
}

usage() {
  echo -e "\nUsage: $0 [OPTIONS]"
  echo -e "Install and configure PostgreSQL database."
  echo -e "\nOptions:"
  echo -e "  -v, --version VERSION    PostgreSQL version (default: 15)"
  echo -e "  -d, --database NAME      Database name (default: connectors)"
  echo -e "  -u, --user USERNAME      Admin username (default: admin)"
  echo -e "  -p, --password PASSWORD  Admin password (default: randomly generated)"
  echo -e "  -g, --postgres-pass PASS Set password for postgres user (default: postgres)"
  echo -e "  -h, --help               Display this help and exit"
  exit 1
}

# Default values
PG_VERSION=15
PG_SERVICE="postgresql-$PG_VERSION"
DB_NAME="connectors"
DB_USER="admin"
DB_PASS=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c16)
POSTGRES_PASS="postgres"

# Parse command line arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    -v|--version)
      PG_VERSION="$2"
      PG_SERVICE="postgresql-$PG_VERSION"
      shift 2
      ;;
    -d|--database)
      DB_NAME="$2"
      shift 2
      ;;
    -u|--user)
      DB_USER="$2"
      shift 2
      ;;
    -p|--password)
      DB_PASS="$2"
      shift 2
      ;;
    -g|--postgres-pass)
      POSTGRES_PASS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      error_exit "Unknown parameter: $1"
      ;;
  esac
done

PG_DATA="/var/lib/pgsql/$PG_VERSION/data"
PG_CONF="$PG_DATA/postgresql.conf"
PG_HBA="$PG_DATA/pg_hba.conf"
DB_HOST=$(hostname -I | awk '{print $1}')

# Check if required utilities are installed
check_required_tools() {
    log "Checking required tools..."
    
    # Check if we're on a Red Hat-based system
    if ! command -v rpm &> /dev/null && ! command -v dnf &> /dev/null && ! command -v yum &> /dev/null; then
        error_exit "This script is designed for Red Hat-based systems (RHEL, CentOS, Fedora, Amazon Linux) with dnf/yum."
    fi
    
    # Determine the package manager
    if command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    else
        PKG_MANAGER="yum"
    fi
    
    log "✅ Using $PKG_MANAGER as package manager."
}

# Function to check if PostgreSQL is installed
install_postgresql() {
    log "Checking if PostgreSQL $PG_VERSION is installed..."
    
    local pg_pkg_installed=false
    if rpm -qa | grep -q "postgresql$PG_VERSION"; then
        pg_pkg_installed=true
    fi
    
    if [ "$pg_pkg_installed" = false ]; then
        log "⬇️ Installing PostgreSQL $PG_VERSION..."
        sudo $PKG_MANAGER install -y postgresql$PG_VERSION postgresql$PG_VERSION-server
        
        if [ $? -ne 0 ]; then
            # Try with different package name format
            log "Trying alternative package names..."
            sudo $PKG_MANAGER install -y postgresql-$PG_VERSION postgresql-server-$PG_VERSION
            
            if [ $? -ne 0 ]; then
                error_exit "Failed to install PostgreSQL packages. Please check repository configuration."
            fi
        fi
        
        log "✅ PostgreSQL $PG_VERSION installed successfully."
    else
        log "✅ PostgreSQL $PG_VERSION is already installed."
    fi
}

# Function to initialize PostgreSQL database if not already initialized
initialize_postgresql() {
    log "Checking PostgreSQL data directory..."
    
    if [ -d "$PG_DATA" ] && [ -n "$(ls -A "$PG_DATA" 2>/dev/null)" ]; then
        log "✅ Data directory already exists. Skipping initialization."
    else
        log "📂 Initializing PostgreSQL database..."
        
        # Check which initialization command is available
        if command -v postgresql-$PG_VERSION-setup &> /dev/null; then
            sudo postgresql-$PG_VERSION-setup --initdb
        elif command -v postgresql-setup &> /dev/null; then
            sudo postgresql-setup --initdb --unit postgresql-$PG_VERSION
        else
            sudo /usr/pgsql-$PG_VERSION/bin/postgresql-$PG_VERSION-setup initdb
        fi
        
        if [ $? -ne 0 ]; then
            error_exit "Failed to initialize PostgreSQL database."
        fi
        
        log "✅ Database initialized."
    fi
}

# Function to configure PostgreSQL to allow remote connections
configure_postgresql() {
    log "Configuring PostgreSQL for remote connections..."
    
    if [ -f "$PG_CONF" ]; then
        # Backup configuration files
        sudo cp "$PG_CONF" "$PG_CONF.bak"
        sudo cp "$PG_HBA" "$PG_HBA.bak"
        
        # Configure postgresql.conf
        if grep -q "^#listen_addresses" "$PG_CONF"; then
            sudo sed -i "s|^#listen_addresses = 'localhost'|listen_addresses = '*'|" "$PG_CONF"
        elif grep -q "^listen_addresses" "$PG_CONF"; then
            sudo sed -i "s|^listen_addresses = .*$|listen_addresses = '*'|" "$PG_CONF"
        else
            echo "listen_addresses = '*'" | sudo tee -a "$PG_CONF" > /dev/null
        fi
        
        # Configure pg_hba.conf - only add if not already present
        if ! grep -q "0.0.0.0/0" "$PG_HBA"; then
            echo "host    all             all             0.0.0.0/0               md5" | sudo tee -a "$PG_HBA" > /dev/null
        fi
        
        log "✅ Remote connection configuration updated."
    else
        error_exit "PostgreSQL configuration file not found at: $PG_CONF"
    fi
}

# Function to set postgres user password
set_postgres_password() {
    log "Setting postgres user password..."
    
    # Check if PostgreSQL service is running
    if ! systemctl is-active --quiet $PG_SERVICE; then
        log "Starting PostgreSQL service temporarily..."
        sudo systemctl start $PG_SERVICE
        sleep 3
    fi
    
    # Set postgres user password
    sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '$POSTGRES_PASS';"
    
    if [ $? -eq 0 ]; then
        log "✅ Password for 'postgres' user set successfully."
    else
        warn "Failed to set password for 'postgres' user."
    fi
}

# Function to start PostgreSQL service
start_postgresql() {
    log "Starting PostgreSQL service..."
    
    # Check and fix service name if needed
    if ! systemctl list-unit-files | grep -q "$PG_SERVICE"; then
        warn "Service $PG_SERVICE not found, trying alternative service name..."
        PG_SERVICE="postgresql"
    fi
    
    sudo systemctl enable $PG_SERVICE
    sudo systemctl start $PG_SERVICE
    
    # Check if service started successfully
    if systemctl is-active --quiet $PG_SERVICE; then
        log "✅ PostgreSQL service ($PG_SERVICE) started successfully."
    else
        error_exit "Failed to start PostgreSQL service. Check logs with: journalctl -u $PG_SERVICE"
    fi
}

# Function to create the admin role and database
create_admin_role() {
    log "Creating database '$DB_NAME' and user '$DB_USER'..."
    
    # Create database and user
    sudo -u postgres psql <<EOF
-- Create database if it doesn't exist
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME') THEN
      CREATE DATABASE $DB_NAME;
   END IF;
END \$\$;

-- Create user if it doesn't exist
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_USER') THEN
      CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';
      ALTER ROLE $DB_USER WITH SUPERUSER CREATEDB CREATEROLE;
   ELSE
      ALTER ROLE $DB_USER WITH PASSWORD '$DB_PASS';
   END IF;
END \$\$;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF

    if [ $? -eq 0 ]; then
        log "✅ Database '$DB_NAME' and user '$DB_USER' created successfully."
    else
        error_exit "Failed to create database and user."
    fi
}

# Function to check if PostgreSQL is listening on port 5432
verify_postgresql() {
    log "Verifying PostgreSQL service..."
    
    # Wait a bit for service to fully start
    sleep 2
    
    if ss -tulnp | grep -q ":5432"; then
        log "✅ PostgreSQL is running successfully!"
        
        # Show connection info
        log "${GREEN}PostgreSQL Connection Information:${NC}"
        echo -e "  🔹 Host: $DB_HOST"
        echo -e "  🔹 Port: 5432"
        echo -e "  🔹 Database: $DB_NAME"
        echo -e "  🔹 Admin Username: $DB_USER"
        echo -e "  🔹 Admin Password: $DB_PASS"
        echo -e "  🔹 Postgres Username: postgres"
        echo -e "  🔹 Postgres Password: $POSTGRES_PASS"
        echo -e "\n  🔹 JDBC URL: jdbc:postgresql://$DB_HOST:5432/$DB_NAME"
        echo -e "  🔹 Admin Connection: psql -h $DB_HOST -U $DB_USER -d $DB_NAME"
    else
        error_exit "PostgreSQL is NOT running properly! Check logs with: journalctl -u $PG_SERVICE"
    fi
}

# Function to save connection details to a file
save_connection_details() {
    local details_file="/tmp/pg_connection_details.txt"
    
    log "Saving connection details to $details_file..."
    
    cat > "$details_file" <<EOF
PostgreSQL Connection Information
--------------------------------
Host: $DB_HOST
Port: 5432
Database: $DB_NAME
Admin Username: $DB_USER
Admin Password: $DB_PASS
Postgres Username: postgres
Postgres Password: $POSTGRES_PASS

JDBC URL: jdbc:postgresql://$DB_HOST:5432/$DB_NAME
Admin Connection: psql -h $DB_HOST -U $DB_USER -d $DB_NAME

Created on: $(date)
EOF
    
    chmod 600 "$details_file"
    log "✅ Connection details saved to $details_file"
}

# Main function
main() {
    log "🚀 Starting PostgreSQL $PG_VERSION installation..."
    
    # Check if script is run as root
    if [ "$EUID" -ne 0 ]; then
        error_exit "Please run this script as root or with sudo."
    fi
    
    # Display installation settings
    log "${BLUE}Installation settings:${NC}"
    echo -e "  🔹 PostgreSQL Version: $PG_VERSION"
    echo -e "  🔹 Database Name: $DB_NAME"
    echo -e "  🔹 Admin User: $DB_USER"
    echo -e "  🔹 Randomly generated password will be displayed at the end"
    
    check_required_tools
    install_postgresql
    initialize_postgresql
    configure_postgresql
    start_postgresql
    set_postgres_password
    create_admin_role
    verify_postgresql
    save_connection_details
    
    log "${GREEN}✅ PostgreSQL setup completed successfully!${NC}"
    log "Connection details saved to /tmp/pg_connection_details.txt"
}

# Execute main function
main