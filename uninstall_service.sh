#!/bin/bash

set -e

# Configuration
APP_NAME="inbound"
SERVICE_NAME="${APP_NAME}.service"
APP_DIR="/etc/systemd/system"
LOG_DIR="/var/log/${APP_NAME}"
CONFIG_FILE="/etc/${APP_NAME}.conf"
LOGROTATE_FILE="/etc/logrotate.d/${APP_NAME}"
SERVICE_FILE="${APP_DIR}/${SERVICE_NAME}"

# Function to print messages with clear formatting
log() {
  echo -e "\n🔹 $1"
}

warn() {
  echo -e "\n⚠️ WARNING: $1"
}

error_exit() {
  echo -e "\n❌ ERROR: $1"
  exit 1
}

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
  error_exit "Please run this script as root."
fi

# Stop and disable service
uninstall_service() {
  log "Stopping and disabling ${SERVICE_NAME}..."
  
  # Check if service exists
  if systemctl list-unit-files | grep -q "${SERVICE_NAME}"; then
    # Stop and disable the service
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || warn "Service was not running"
    systemctl disable "${SERVICE_NAME}" 2>/dev/null || warn "Service was not enabled"
    log "✅ Service stopped and disabled."
  else
    warn "Service ${SERVICE_NAME} does not exist."
  fi
  
  # Remove service file
  if [ -f "${SERVICE_FILE}" ]; then
    rm -f "${SERVICE_FILE}"
    log "✅ Service file removed: ${SERVICE_FILE}"
  else
    warn "Service file not found: ${SERVICE_FILE}"
  fi
  
  # Reload systemd
  systemctl daemon-reload
  log "✅ Systemd daemon reloaded."
}

# Remove configuration files
remove_config_files() {
  # Remove config file
  if [ -f "${CONFIG_FILE}" ]; then
    rm -f "${CONFIG_FILE}"
    log "✅ Configuration file removed: ${CONFIG_FILE}"
  else
    warn "Configuration file not found: ${CONFIG_FILE}"
  fi
  
  # Remove logrotate config
  if [ -f "${LOGROTATE_FILE}" ]; then
    rm -f "${LOGROTATE_FILE}"
    log "✅ Logrotate configuration removed: ${LOGROTATE_FILE}"
  else
    warn "Logrotate configuration not found: ${LOGROTATE_FILE}"
  fi
}

# Remove log directory
remove_log_dir() {
  if [ -d "${LOG_DIR}" ]; then
    rm -rf "${LOG_DIR}"
    log "✅ Log directory removed: ${LOG_DIR}"
  else
    warn "Log directory not found: ${LOG_DIR}"
  fi
}

# Clean up firewall rules
clean_firewall_rules() {
  log "Checking firewall rules..."
  
  # Remove port from firewall
  if systemctl is-active --quiet firewalld; then
    PORTS_TO_CHECK=$(firewall-cmd --list-ports)
    # Extract all ports from list
    for PORT in $(echo "$PORTS_TO_CHECK" | grep -o '[0-9]\+/tcp'); do
      # Check if this port was used by our app (we can't know for sure which port was used)
      log "Removing port ${PORT} from firewall..."
      firewall-cmd --permanent --remove-port=${PORT}
    done
    
    firewall-cmd --reload
    log "✅ Firewall rules cleaned."
  else
    warn "Firewalld is not running. Skipping firewall cleanup."
  fi
}

# Main uninstallation process
main() {
  log "🚀 Starting uninstallation process for ${APP_NAME}..."
  
  uninstall_service
  remove_config_files
  remove_log_dir
  clean_firewall_rules
  
  log "✅ Uninstallation complete! All ${APP_NAME} components have been removed."
}

# Execute main function
main