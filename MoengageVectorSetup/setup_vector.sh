ACTION=$1
TOML_FILE=$2

if [[ -z "$ACTION" || -z "$TOML_FILE" ]]; then
    echo -e "❌ Error: Missing arguments."
    echo "Usage:"
    echo "  sudo bash setup_vector.sh install <TOML_FILE>"
    echo "  sudo bash setup_vector.sh uninstall <TOML_FILE>"
    exit 1
fi

CONSUMER=$(basename "$TOML_FILE" .toml)  

VECTOR_DEFAULT_PATH="/root/.vector/bin/vector"
SERVICE_FILE="/etc/systemd/system/$CONSUMER.service"
CONFIG_DIR="/etc/vector"
DATA_DIR="/var/lib/vector/$CONSUMER"
LOG_DIR="/var/log/vector-logs"
SETUP_LOG="$LOG_DIR/setup.log"
SERVICE_LOG="$LOG_DIR/service.log"
CRASH_LOG="$LOG_DIR/crash.log"

mkdir -p "$LOG_DIR"

if [[ "$ACTION" == "install" || "$ACTION" == "i" ]]; then
    echo -e "\n🚀 Installing Vector for CONSUMER: $CONSUMER\n" | tee -a "$SETUP_LOG"

    if ! command -v vector &>/dev/null && [ ! -f "$VECTOR_DEFAULT_PATH" ]; then
        echo -e "✅ Vector is not installed. Installing now...\n" | tee -a "$SETUP_LOG"
        curl --proto '=https' --tlsv1.2 -sSfL https://sh.vector.dev | bash -s -- -y >> "$SETUP_LOG" 2>&1
    else
        echo -e "✅ Vector is already installed. Skipping installation.\n" | tee -a "$SETUP_LOG"
    fi

    VECTOR_BIN=$(command -v vector || echo "$VECTOR_DEFAULT_PATH")
    if [ ! -f "$VECTOR_BIN" ]; then
        echo -e "❌ Error: Vector binary not found!\n" | tee -a "$SETUP_LOG"
        exit 1
    fi

    if [ ! -f "$TOML_FILE" ]; then
        echo -e "❌ Error: TOML file '$TOML_FILE' not found\n" | tee -a "$SETUP_LOG"
        exit 1
    fi

    mkdir -p "$CONFIG_DIR" "$DATA_DIR"
    sudo chown root:root "$DATA_DIR"
    sudo chmod 755 "$DATA_DIR"

    cp "$TOML_FILE" "$CONFIG_DIR/$(basename "$TOML_FILE")"

    if [ -f "$SERVICE_FILE" ]; then
        echo -e "🔄 CONSUMER '$CONSUMER' exists. Restarting...\n" | tee -a "$SETUP_LOG"
        systemctl restart "$CONSUMER"
    else
        echo -e "🛠 Creating new Vector CONSUMER service...\n" | tee -a "$SETUP_LOG"

        cat << EOF > "$SERVICE_FILE"
[Unit]
Description=Vector Service for $CONSUMER
After=network.target

[Service]
ExecStart=$VECTOR_BIN --config $CONFIG_DIR/$TOML_FILE
Restart=always
User=root
AmbientCapabilities=CAP_NET_BIND_SERVICE
StandardOutput=file:$SERVICE_LOG
StandardError=file:$CRASH_LOG

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl enable "$CONSUMER"
        systemctl start "$CONSUMER"
        echo -e "✅ Vector service '$CONSUMER' set up successfully.\n" | tee -a "$SETUP_LOG"
    fi

    echo -e "📂 Logs:\n   - Setup log:       $SETUP_LOG\n   - Service log:     $SERVICE_LOG\n   - Crash log:       $CRASH_LOG\n" | tee -a "$SETUP_LOG"

elif [[ "$ACTION" == "uninstall" || "$ACTION" == "u" ]]; then
    echo -e "\n🚀 Uninstalling Vector service: $CONSUMER\n"

    echo "🔹 Stopping and disabling service: $CONSUMER"
    sudo systemctl stop "$CONSUMER" 2>/dev/null
    sudo systemctl disable "$CONSUMER" 2>/dev/null

    echo "🗑 Removing service file: $SERVICE_FILE"
    sudo rm -f "$SERVICE_FILE"

    echo "🗑 Removing configuration and logs..."
    sudo rm -rf "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR/vector-logs"

    echo "✅ Successfully removed $CONSUMER"

    echo "🔄 Reloading systemd..."
    sudo systemctl daemon-reload
    sudo systemctl reset-failed

    echo "✅ Uninstallation completed!"

else
    echo -e "❌ Error: Invalid action. Use 'install' (or 'i') or 'uninstall' (or 'u')."
    echo "Usage:"
    echo "  sudo bash setup_vector.sh install <TOML_FILE>"
    echo "  sudo bash setup_vector.sh uninstall <TOML_FILE>"
    exit 1
fi