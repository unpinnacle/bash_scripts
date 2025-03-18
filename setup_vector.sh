ACTION=$1
SERVICE_NAME=${2:-"connectors-logs"}  # Default service name
TOML_FILES="${@:3}"  # All arguments after action & service name are TOML files
VECTOR_DEFAULT_PATH="/root/.vector/bin/vector"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
CONFIG_DIR="/etc/vector/$SERVICE_NAME"
DATA_DIR="/var/lib/vector/$SERVICE_NAME"
STORAGE_IP="11.0.70.82"
LOG_DIR="/var/log"
SETUP_LOG="$LOG_DIR/vector_setup.log"
SERVICE_LOG="$LOG_DIR/vector_service.log"
CRASH_LOG="$LOG_DIR/vector_crash.log"

mkdir -p "$LOG_DIR"
echo -e "\n🚀 Starting Vector setup for service: $SERVICE_NAME\n" | tee -a "$SETUP_LOG"

# Check if Vector is already installed
if ! command -v vector &>/dev/null && [ ! -f "$VECTOR_DEFAULT_PATH" ]; then
  echo -e "✅ Vector is not installed. Installing now...\n" | tee -a "$SETUP_LOG"
  curl --proto '=https' --tlsv1.2 -sSfL https://sh.vector.dev | bash -s -- -y >> "$SETUP_LOG" 2>&1
else
  echo -e "✅ Vector is already installed. Skipping installation.\n" | tee -a "$SETUP_LOG"
fi

VECTOR_BIN=$(command -v vector || echo "$VECTOR_DEFAULT_PATH")
if [ ! -f "$VECTOR_BIN" ]; then
  echo -e "❌ Error: Vector binary not found after installation!\n" | tee -a "$SETUP_LOG"
  exit 1
fi

if [ "$ACTION" == "install" ]; then
  if [ -z "$TOML_FILES" ]; then
    echo -e "❌ Error: Please provide at least one TOML file as an argument\n" | tee -a "$SETUP_LOG"
    exit 1
  fi

  for TOML_FILE in $TOML_FILES; do
    if [ ! -f "$TOML_FILE" ]; then
      echo -e "❌ Error: TOML file '$TOML_FILE' not found\n" | tee -a "$SETUP_LOG"
      exit 1
    fi
  done

  mkdir -p "$CONFIG_DIR" "$DATA_DIR"
  sudo chown root:root "$DATA_DIR"
  sudo chmod 755 "$DATA_DIR"

  for TOML_FILE in $TOML_FILES; do
    cp "$TOML_FILE" "$CONFIG_DIR/$(basename "$TOML_FILE")"
  done

  TOML_LIST=$(find "$CONFIG_DIR" -name "*.toml" | tr '\n' ',' | sed 's/,$//')

  if [ -f "$SERVICE_FILE" ]; then
    echo -e "🔄 Service '$SERVICE_NAME' already exists. Updating configurations...\n" | tee -a "$SETUP_LOG"
    systemctl restart "$SERVICE_NAME"
    echo -e "🔁 Service '$SERVICE_NAME' restarted with updated configuration.\n" | tee -a "$SETUP_LOG"
  else
    echo -e "🛠 Creating new service for Vector...\n" | tee -a "$SETUP_LOG"

    cat << EOF > "$SERVICE_FILE"
[Unit]
Description=Vector Service for $SERVICE_NAME
After=network.target

[Service]
ExecStart=$VECTOR_BIN --config $TOML_LIST
Restart=always
User=root
AmbientCapabilities=CAP_NET_BIND_SERVICE
StandardOutput=file:$SERVICE_LOG
StandardError=file:$CRASH_LOG

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
    echo -e "✅ Vector installed and service '$SERVICE_NAME' set up successfully.\n" | tee -a "$SETUP_LOG"
  fi

  echo -e "📂 Logs:\n   - Setup log:       $SETUP_LOG\n   - Service log:     $SERVICE_LOG\n   - Crash log:       $CRASH_LOG\n" | tee -a "$SETUP_LOG"
  echo -e "📡 Check service status Loki:\n   curl -s http://$STORAGE_IP:3100/ready\n" | tee -a "$SETUP_LOG"
  echo -e "📡 Checking Elasticsearch health:\n   curl -s http://$STORAGE_IP:9200/_cluster/health?pretty\n" | tee -a "$SETUP_LOG"
fi

if [ "$ACTION" == "uninstall" ]; then
  systemctl stop "$SERVICE_NAME"
  systemctl disable "$SERVICE_NAME"
  rm -f "$SERVICE_FILE"
  systemctl daemon-reload
  rm -rf "$CONFIG_DIR" "$DATA_DIR"

  echo -e "❌ Vector service '$SERVICE_NAME' removed.\n" | tee -a "$SETUP_LOG"
  echo -e "📡 Check service status Loki:\n   curl -s http://$STORAGE_IP:3100/ready\n" | tee -a "$SETUP_LOG"
  echo -e "📡 Checking Elasticsearch health:\n   curl -s http://$STORAGE_IP:9200/_cluster/health?pretty\n" | tee -a "$SETUP_LOG"
fi