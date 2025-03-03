#!/bin/bash

set -e

# Configuration
JAR_FILE_PATH="$1"
SPRING_PROFILE="$2"
SERVER_PORT="${3:-8080}"
APP_NAME="inbound"
APP_USER="root"
SERVICE_NAME="${APP_NAME}.service"
APP_DIR="/etc/systemd/system"
LOG_DIR="/var/log/${APP_NAME}"
CONFIG_FILE="/etc/${APP_NAME}.conf"
JVM_OPTS="-Xms512m -Xmx1024m -XX:+UseG1GC"

# Custom IP and port
MY_IP="11.0.65.222"
MY_PORT="5432"

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

# Validate input
if [ -z "$JAR_FILE_PATH" ]; then
  error_exit "No JAR file path provided. Usage: $0 <JAR_FILE_PATH> <PROFILE> [PORT]"
fi

if [ ! -f "$JAR_FILE_PATH" ]; then
  error_exit "JAR file not found at provided path: $JAR_FILE_PATH"
fi

if [ -z "$SPRING_PROFILE" ]; then
  error_exit "No Spring profile provided. Usage: $0 <JAR_FILE_PATH> <PROFILE> [PORT]. Valid profiles: dev, test, prod"
fi

# Validate Spring profile
if [[ ! "$SPRING_PROFILE" =~ ^(dev|test|prod)$ ]]; then
  error_exit "Invalid Spring profile: $SPRING_PROFILE. Valid profiles: dev, test, prod"
fi

if [ "$EUID" -ne 0 ]; then
  error_exit "Please run this script as root."
fi

# Detect OS
detect_os() {
  log "Detecting operating system..."
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
  else
    error_exit "Unable to detect OS."
  fi

  case $OS in
    "amzn")
      PKG_MANAGER="yum"
      JAVA_PKG="java-21-amazon-corretto-headless"
      log "✅ Amazon Linux detected. Using YUM."
      ;;
    "ubuntu")
      PKG_MANAGER="apt-get"
      JAVA_PKG="openjdk-21-jdk"
      log "✅ Ubuntu detected. Using APT."
      ;;
    *)
      error_exit "Unsupported OS: $OS"
      ;;
  esac
}

# Install required packages
install_packages() {
  log "Updating system packages..."
  $PKG_MANAGER update -y && log "✅ System packages updated successfully."

  log "Checking and installing Java 21, telnet & utilities..."
  if $PKG_MANAGER install -y $JAVA_PKG htop unzip logrotate firewalld telnet; then
    log "✅ Java, telnet, and utilities installed successfully."
  else
    log "ℹ️ No new packages were installed."
  fi
}

# Free the port if in use
free_port_if_needed() {
  log "Checking if port $SERVER_PORT is already in use..."
  if netstat -tulnp | grep ":$SERVER_PORT " &>/dev/null; then
    warn "Port $SERVER_PORT is already in use! Stopping process using it..."
    
    # Find and kill the process using the port
    PID=$(netstat -tulnp | grep ":$SERVER_PORT " | awk '{print $7}' | cut -d'/' -f1)
    if [ -n "$PID" ]; then
      kill -9 "$PID"
      log "✅ Process on port $SERVER_PORT has been terminated."
    else
      error_exit "Failed to free port $SERVER_PORT."
    fi
  else
    log "✅ Port $SERVER_PORT is free to use."
  fi
}

# Configure firewall properly
configure_firewall() {
  log "Configuring firewall for port $SERVER_PORT..."

  if ! systemctl is-active --quiet firewalld; then
    log "Starting Firewalld service..."
    systemctl start firewalld
    systemctl enable firewalld
    log "✅ Firewalld started and enabled."
  fi

  if ! firewall-cmd --list-ports | grep -q "${SERVER_PORT}/tcp"; then
    firewall-cmd --permanent --add-port=${SERVER_PORT}/tcp
    firewall-cmd --reload
    log "✅ Firewall rule added for port $SERVER_PORT."
  else
    log "ℹ️ Firewall rule for port $SERVER_PORT already exists."
  fi
}

# Setup application directory structure
setup_app_dirs() {
  log "Setting up log directory at $LOG_DIR..."
  mkdir -p "$LOG_DIR"
  chown -R "$APP_USER:$APP_USER" "$LOG_DIR"
  log "✅ Log directory setup complete."
}

# Create environment configuration
create_app_config() {
  log "Creating environment configuration file at $CONFIG_FILE..."
  cat << EOF > "$CONFIG_FILE"
# Application environment variables
JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
APP_ENV=$SPRING_PROFILE
SERVER_PORT=$SERVER_PORT
MY_IP=$MY_IP
MY_PORT=$MY_PORT
SPRING_PROFILE=$SPRING_PROFILE
EOF

  chown "$APP_USER:$APP_USER" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  log "✅ Environment configuration file created."
}

# Create systemd service
create_systemd_service() {
  SERVICE_FILE_PATH="${APP_DIR}/${SERVICE_NAME}"
  
  log "Creating systemd service file at $SERVICE_FILE_PATH..."
  cat << EOF > "$SERVICE_FILE_PATH"
[Unit]
Description=Java Application Service
After=network.target

[Service]
User=$APP_USER
EnvironmentFile=$CONFIG_FILE
ExecStart=/usr/bin/java ${JVM_OPTS} -Dspring.profiles.active=${SPRING_PROFILE} -jar ${JAR_FILE_PATH} --server.port=${SERVER_PORT}
SuccessExitStatus=143
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$APP_NAME

[Install]
WantedBy=multi-user.target
EOF

  chmod 644 "$SERVICE_FILE_PATH"
  log "✅ Systemd service file created."

  log "Reloading systemd daemon and enabling the service..."
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  log "✅ Systemd service configured successfully."
}

# Setup log rotation
setup_log_rotation() {
  log "Configuring log rotation at /etc/logrotate.d/$APP_NAME..."
  cat << EOF > "/etc/logrotate.d/$APP_NAME"
$LOG_DIR/*.log {
    daily
    rotate 7
    missingok
    compress
    delaycompress
    notifempty
    create 0640 $APP_USER $APP_USER
    sharedscripts
    postrotate
      systemctl restart $SERVICE_NAME >/dev/null 2>&1 || true
    endscript
}
EOF
  log "✅ Log rotation setup complete."
}

# Check Telnet Connection
check_telnet_connection() {
  log "Checking Telnet connectivity to $MY_IP:$MY_PORT..."
  if timeout 5 telnet "$MY_IP" "$MY_PORT" &>/dev/null; then
    log "✅ Telnet connection to $MY_IP:$MY_PORT successful."
  else
    warn "⚠️ Unable to connect to $MY_IP:$MY_PORT via Telnet."
  fi
}

# Main installation process
main() {
  log "🚀 Starting installation process..."
  detect_os
  install_packages
  free_port_if_needed
  configure_firewall
  setup_app_dirs
  create_app_config
  create_systemd_service
  setup_log_rotation
  check_telnet_connection

  log "Starting application service..."
  systemctl restart "$SERVICE_NAME"

  log "✅ Installation complete! Your application is now running on port $SERVER_PORT with profile $SPRING_PROFILE."

  echo -e "\n📌 **SYSTEMD COMMANDS YOU CAN USE:**"
  echo -e "--------------------------------------------"
  echo -e "🔹 Check service status:     \t systemctl status $SERVICE_NAME"
  echo -e "🔹 Start the service:        \t systemctl start $SERVICE_NAME"
  echo -e "🔹 Stop the service:         \t systemctl stop $SERVICE_NAME"
  echo -e "🔹 Restart the service:      \t systemctl restart $SERVICE_NAME"
  echo -e "🔹 View service logs:        \t journalctl -u $SERVICE_NAME -f"
  echo -e "--------------------------------------------\n"
}

main