ACTION=$1
SERVICE_NAME=${2:-"connectors-logs"}  # Default service name if not provided
TOML_FILES="${@:3}"  # All arguments after action & service name are TOML files
VECTOR_DEFAULT_PATH="/root/.vector/bin/vector"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
CONFIG_DIR="/etc/vector/$SERVICE_NAME"
DATA_DIR="/var/lib/vector/$SERVICE_NAME"
LOKI_IP="11.0.70.82"  # Replace with actual Loki IP

if [ "$ACTION" != "install" ] && [ "$ACTION" != "uninstall" ]; then
  echo "Error: First argument must be 'install' or 'uninstall'"
  exit 1
fi

if [ "$ACTION" == "install" ]; then
  if [ -z "$TOML_FILES" ]; then
    echo "Error: Please provide at least one TOML file as an argument"
    exit 1
  fi

  for TOML_FILE in $TOML_FILES; do
    if [ ! -f "$TOML_FILE" ]; then
      echo "Error: TOML file '$TOML_FILE' not found"
      exit 1
    fi
  done

  if [ -f "$SERVICE_FILE" ]; then
    echo "Vector service '$SERVICE_NAME' is already set up."
    mkdir -p "$CONFIG_DIR"
    for TOML_FILE in $TOML_FILES; do
      cp "$TOML_FILE" "$CONFIG_DIR/$(basename "$TOML_FILE")"
    done
    systemctl restart "$SERVICE_NAME"
    systemctl enable "$SERVICE_NAME"
    echo "Service '$SERVICE_NAME' restarted and enabled."
    echo "curl -s http://$LOKI_IP:3100/ready"
    exit 0
  fi

  curl --proto '=https' --tlsv1.2 -sSfL https://sh.vector.dev | bash -s -- -y

  VECTOR_BIN=$(command -v vector || echo "$VECTOR_DEFAULT_PATH")
  if [ ! -f "$VECTOR_BIN" ]; then
    echo "Error: Vector binary not found!"
    exit 1
  fi

  mkdir -p "$CONFIG_DIR"
  mkdir -p "$DATA_DIR"
  sudo mkdir -p "$DATA_DIR"
  sudo chown root:root "$DATA_DIR"
  sudo chmod 755 "$DATA_DIR"
  
  for TOML_FILE in $TOML_FILES; do
    cp "$TOML_FILE" "$CONFIG_DIR/$(basename "$TOML_FILE")"
  done

  TOML_LIST=$(find "$CONFIG_DIR" -name "*.toml" | tr '\n' ',' | sed 's/,$//')

  cat << EOF > "$SERVICE_FILE"
[Unit]
Description=Vector Service for $SERVICE_NAME
After=network.target

[Service]
ExecStart=$VECTOR_BIN --config $TOML_LIST
Restart=always
User=root
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl start "$SERVICE_NAME"

  echo "Vector installed and service '$SERVICE_NAME' set up successfully with configs: $TOML_LIST"
  echo "curl -s http://$LOKI_IP:3100/ready"
fi

if [ "$ACTION" == "uninstall" ]; then
  systemctl stop "$SERVICE_NAME"
  systemctl disable "$SERVICE_NAME"
  rm -f "$SERVICE_FILE"
  systemctl daemon-reload
  rm -rf "$CONFIG_DIR"
  rm -rf "$DATA_DIR"
  echo "Vector uninstalled and service '$SERVICE_NAME' removed."
  curl -s http://$LOKI_IP:3100/ready
fi