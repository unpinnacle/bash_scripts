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
  echo -e "Uninstall PostgreSQL database and clean up configuration."
  echo -e "\nOptions:"
  echo -e "  -v, --version VERSION    PostgreSQL version (default: 15)"
  echo -e "  -d, --database NAME      Database name to drop (default: connectors)"
  echo -e "  -u, --user USERNAME      User to drop (default: admin)"
  echo -e "  -p, --purge              Completely remove PostgreSQL packages"
  echo -e "  -h, --help               Display this help and exit"
  exit 1
}

# Default values
PG_VERSION=15
PG_SERVICE="postgresql-$PG_VERSION"
DB_NAME="connectors"
DB_USER="admin"
PURGE=false

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
    -p|--purge)
      PURGE=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      error_exit "Unknown parameter: $1"
      ;;
  esac
done

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
  error_exit "Please run this script as root or with sudo."
fi

# Function to execute PostgreSQL commands
exec_psql() {
  sudo -u postgres bash -c "cd /tmp && psql -t -c \"$1\""
}

# Function to check if PostgreSQL is running
check_postgres_running() {
  log "Checking if PostgreSQL is running..."
  
  # Try default service name, then fallbacks
  if systemctl is-active --quiet $PG_SERVICE; then
    log "✅ PostgreSQL service ($PG_SERVICE) is running."
    return 0
  elif systemctl is-active --quiet postgresql; then
    PG_SERVICE="postgresql"
    log "✅ PostgreSQL service ($PG_SERVICE) is running."
    return 0
  else
    warn "PostgreSQL service is not running."
    
    # Try to start the service
    if systemctl list-unit-files | grep -q "$PG_SERVICE"; then
      log "Attempting to start PostgreSQL service..."
      systemctl start $PG_SERVICE
      sleep 5
      
      if systemctl is-active --quiet $PG_SERVICE; then
        log "✅ PostgreSQL service started successfully."
        return 0
      fi
    elif systemctl list-unit-files | grep -q "postgresql"; then
      log "Attempting to start PostgreSQL service (generic name)..."
      systemctl start postgresql
      sleep 5
      
      if systemctl is-active --quiet postgresql; then
        PG_SERVICE="postgresql"
        log "✅ PostgreSQL service started successfully."
        return 0
      fi
    fi
    
    warn "Unable to start PostgreSQL service. Some uninstallation steps will be skipped."
    return 1
  fi
}

# Function to get PostgreSQL data directory
get_data_directory() {
  log "Locating PostgreSQL data directory..."
  
  # Try to get the data directory using psql
  if check_postgres_running; then
    DATA_DIR=$(sudo -u postgres psql -t -c "SHOW data_directory;" 2>/dev/null | xargs)
    
    if [ -n "$DATA_DIR" ] && [ -d "$DATA_DIR" ]; then
      log "✅ PostgreSQL data directory found at: $DATA_DIR"
      return 0
    fi
  fi
  
  # If that fails, use standard locations based on version
  DATA_DIR="/var/lib/pgsql/$PG_VERSION/data"
  if [ -d "$DATA_DIR" ]; then
    log "✅ Using standard data directory: $DATA_DIR"
    return 0
  fi
  
  DATA_DIR="/var/lib/postgresql/$PG_VERSION/main"
  if [ -d "$DATA_DIR" ]; then
    log "✅ Using standard Debian/Ubuntu data directory: $DATA_DIR"
    return 0
  fi
  
  warn "Could not locate PostgreSQL data directory. Configuration restoration will be skipped."
  return 1
}

# Function to drop database and user
drop_database_and_user() {
  if check_postgres_running; then
    log "Dropping database '$DB_NAME' and user '$DB_USER'..."
    
    # Drop database
    exec_psql "DROP DATABASE IF EXISTS $DB_NAME;"
    if [ $? -eq 0 ]; then
      log "✅ Database '$DB_NAME' dropped successfully (if it existed)."
    else
      warn "Failed to drop database '$DB_NAME'."
    fi
    
    # Drop user role
    exec_psql "DROP ROLE IF EXISTS $DB_USER;"
    if [ $? -eq 0 ]; then
      log "✅ User '$DB_USER' dropped successfully (if it existed)."
    else
      warn "Failed to drop user '$DB_USER'."
    fi
  else
    warn "PostgreSQL not running. Skipping database and user removal."
  fi
}

# Function to restore original PostgreSQL configuration
restore_postgresql_config() {
  if get_data_directory; then
    log "Restoring PostgreSQL configuration..."
    
    # Set configuration file paths
    PG_CONF="$DATA_DIR/postgresql.conf"
    PG_HBA="$DATA_DIR/pg_hba.conf"
    
    # Check if backup files exist and restore them
    if [ -f "$PG_CONF.bak" ]; then
      sudo cp "$PG_CONF.bak" "$PG_CONF"
      log "✅ Restored postgresql.conf from backup."
    elif [ -f "$PG_CONF" ]; then
      # If no backup exists, modify the existing file
      if grep -q "^listen_addresses = '*'" "$PG_CONF"; then
        sudo sed -i "s|^listen_addresses = '*'|#listen_addresses = 'localhost'|" "$PG_CONF"
        log "✅ Restored listen_addresses to localhost."
      fi
    else
      warn "PostgreSQL configuration file not found at: $PG_CONF"
    fi
    
    # Restore pg_hba.conf
    if [ -f "$PG_HBA.bak" ]; then
      sudo cp "$PG_HBA.bak" "$PG_HBA"
      log "✅ Restored pg_hba.conf from backup."
    elif [ -f "$PG_HBA" ]; then
      # If no backup exists, modify the existing file
      if grep -q "0.0.0.0/0" "$PG_HBA"; then
        sudo sed -i "/0.0.0.0\/0/d" "$PG_HBA"
        log "✅ Removed '0.0.0.0/0' rule from pg_hba.conf."
      fi
    else
      warn "PostgreSQL HBA file not found at: $PG_HBA"
    fi
    
    # Restart PostgreSQL if it's running
    if systemctl is-active --quiet $PG_SERVICE; then
      log "Restarting PostgreSQL to apply configuration changes..."
      systemctl restart $PG_SERVICE
      log "✅ PostgreSQL restarted."
    fi
  fi
}

# Function to purge PostgreSQL if requested
purge_postgresql() {
  if [ "$PURGE" = true ]; then
    log "Purging PostgreSQL packages as requested..."
    
    # Stop PostgreSQL service
    if systemctl list-unit-files | grep -q postgresql; then
      log "Stopping PostgreSQL services..."
      systemctl stop postgresql*
    fi
    
    # Determine the package manager
    if command -v dnf &> /dev/null; then
      PKG_MANAGER="dnf"
    else
      PKG_MANAGER="yum"
    fi
    
    # Remove PostgreSQL packages
    log "Removing PostgreSQL packages with $PKG_MANAGER..."
    $PKG_MANAGER remove -y postgresql* 2>/dev/null || true
    
    # Remove data directory
    if [ -d "/var/lib/pgsql" ]; then
      log "Removing PostgreSQL data directory..."
      rm -rf /var/lib/pgsql
    fi
    
    if [ -d "/var/lib/postgresql" ]; then
      log "Removing PostgreSQL data directory (Debian/Ubuntu style)..."
      rm -rf /var/lib/postgresql
    fi
    
    log "✅ PostgreSQL has been purged from the system."
  else
    log "Skipping package removal. Use --purge to completely remove PostgreSQL."
  fi
}

# Main uninstallation function
main() {
  log "${RED}🛑 Starting PostgreSQL uninstallation process...${NC}"
  
  drop_database_and_user
  restore_postgresql_config
  purge_postgresql
  
  log "${GREEN}✅ PostgreSQL uninstallation completed successfully.${NC}"
}

# Execute main function
main