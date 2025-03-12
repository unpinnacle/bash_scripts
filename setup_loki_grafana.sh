set -e

# Function to install Loki and Grafana
install_loki_grafana() {
    # Set default bind_addr to ens5, override if argument provided
    BIND_ADDR="${2:-ens5}"

    echo "Process: Installing required packages started..."
    sudo yum install -y wget unzip
    echo "Process: Required packages installed successfully."
    echo ""

    # Define stable Loki version
    LOKI_VERSION="2.9.4"
    LOKI_URL="https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-arm64.zip"

    # Check if Loki is already installed
    if [ -f /usr/local/bin/loki ]; then
        echo "Process: Loki binary already exists, checking version..."
        INSTALLED_VERSION=$(/usr/local/bin/loki --version | grep -oP 'version=\K[^,]+')
        if [ "$INSTALLED_VERSION" = "$LOKI_VERSION" ]; then
            echo "Process: Loki $LOKI_VERSION already installed, skipping."
        else
            echo "Process: Replacing existing Loki with version $LOKI_VERSION..."
            sudo rm -f /usr/local/bin/loki
            echo "Process: Downloading Loki $LOKI_VERSION for ARM64 started..."
            wget -O loki-linux-arm64.zip "$LOKI_URL"
            echo "Process: Loki downloaded successfully."

            echo "Process: Unzipping Loki started..."
            unzip loki-linux-arm64.zip
            echo "Process: Loki unzipped successfully."

            echo "Process: Installing Loki started..."
            sudo mv loki-linux-arm64 /usr/local/bin/loki
            sudo chmod +x /usr/local/bin/loki
            echo "Process: Loki $LOKI_VERSION installed successfully."
        fi
    else
        echo "Process: Downloading Loki $LOKI_VERSION for ARM64 started..."
        wget -O loki-linux-arm64.zip "$LOKI_URL"
        echo "Process: Loki downloaded successfully."

        echo "Process: Unzipping Loki started..."
        unzip loki-linux-arm64.zip
        echo "Process: Loki unzipped successfully."

        echo "Process: Installing Loki started..."
        sudo mv loki-linux-arm64 /usr/local/bin/loki
        sudo chmod +x /usr/local/bin/loki
        echo "Process: Loki $LOKI_VERSION installed successfully."
    fi
    echo ""

    # Set up Loki configuration (only if not already present)
    if [ -f /etc/loki/loki-config.yaml ]; then
        echo "Process: Loki configuration already exists, skipping setup."
    else
        echo "Process: Setting up Loki configuration started..."
        sudo mkdir -p /etc/loki
        sudo tee /etc/loki/loki-config.yaml > /dev/null <<EOL
---
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2022-06-01
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /tmp/loki/index
    cache_location: /tmp/loki/cache

  filesystem:
    directory: /tmp/loki/chunks

limits_config:
  allow_structured_metadata: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

compactor:
  working_directory: /tmp/loki/compactor

common:
  path_prefix: /tmp/loki

table_manager:
  retention_deletes_enabled: false
  retention_period: 0s

memberlist:
  bind_addr: ["$BIND_ADDR"]
  bind_port: 7946
EOL
        echo "Process: Loki configuration set up successfully with bind_addr set to $BIND_ADDR."
    fi
    echo ""

    # Set up Loki systemd service (only if not already present)
    if [ -f /etc/systemd/system/loki.service ]; then
        echo "Process: Loki systemd service already exists, skipping creation."
    else
        echo "Process: Creating Loki systemd service started..."
        sudo tee /etc/systemd/system/loki.service > /dev/null <<EOL
[Unit]
Description=Loki Log Aggregation System
After=network.target

[Service]
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki-config.yaml
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOL
        echo "Process: Loki systemd service created successfully."
    fi
    echo ""

    # Start Loki service (only if not already running)
    if systemctl is-active loki > /dev/null 2>&1; then
        echo "Process: Loki service is already running, skipping start."
    else
        echo "Process: Starting Loki service started..."
        sudo systemctl daemon-reload
        sudo systemctl enable loki
        sudo systemctl start loki
        echo "Process: Loki service started successfully."
    fi
    echo ""

    # Check if Grafana is already installed
    if rpm -q grafana > /dev/null 2>&1; then
        echo "Process: Grafana is already installed, skipping installation."
    else
        echo "Process: Installing Grafana started..."
        sudo yum install -y yum-utils
        sudo tee /etc/yum.repos.d/grafana.repo > /dev/null <<EOL
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOL
        sudo yum install -y grafana
        echo "Process: Grafana installed successfully."
    fi
    echo ""

    # Start Grafana service (only if not already running)
    if systemctl is-active grafana-server > /dev/null 2>&1; then
        echo "Process: Grafana service is already running, skipping start."
    else
        echo "Process: Starting Grafana service started..."
        sudo systemctl enable grafana-server
        sudo systemctl start grafana-server
        echo "Process: Grafana service started successfully."
    fi
    echo ""

    echo "Loki $LOKI_VERSION and Grafana installation completed."
    echo "Loki is running on port 3100."
    echo "Grafana is accessible at http://localhost:3000 (or http://<server-ip>:3000 if accessing remotely)."
    echo ""
    echo "Useful Commands:"
    echo "  - Check Loki service status: sudo systemctl status loki"
    echo "  - Restart Loki service: sudo systemctl restart loki"
    echo "  - Check Grafana service status: sudo systemctl status grafana-server"
    echo "  - Restart Grafana service: sudo systemctl restart grafana-server"
    echo "  - View Loki logs: sudo journalctl -u loki"
    echo "  - View Grafana logs: sudo journalctl -u grafana-server"
}

# Function to uninstall Loki and Grafana
uninstall_loki_grafana() {
    echo "Process: Stopping and removing Loki service started..."
    sudo systemctl stop loki || true
    sudo systemctl disable loki || true
    sudo rm -f /etc/systemd/system/loki.service
    sudo systemctl daemon-reload
    echo "Process: Loki service stopped and removed successfully."
    echo ""

    echo "Process: Stopping and removing Grafana service started..."
    sudo systemctl stop grafana-server || true
    sudo systemctl disable grafana-server || true
    echo "Process: Grafana service stopped and removed successfully."
    echo ""

    echo "Process: Removing installed packages started..."
    sudo yum remove -y grafana
    sudo yum autoremove -y
    echo "Process: Installed packages removed successfully."
    echo ""

    echo "Process: Removing Loki binary and configuration started..."
    sudo rm -f /usr/local/bin/loki
    sudo rm -rf /etc/loki
    sudo rm -rf /tmp/loki
    echo "Process: Loki binary and configuration removed successfully."
    echo ""

    echo "Process: Cleaning up downloaded files started..."
    rm -f loki-linux-arm64.zip
    echo "Process: Downloaded files cleaned up successfully."
    echo ""

    echo "Process: Removing Grafana repository started..."
    sudo rm -f /etc/yum.repos.d/grafana.repo
    echo "Process: Grafana repository removed successfully."
    echo ""

    echo "Loki and Grafana uninstallation completed."
}

# Check command line argument
case "$1" in
    "install")
        install_loki_grafana "$@"
        ;;
    "uninstall")
        uninstall_loki_grafana
        ;;
    *)
        echo "Usage: $0 {install [bind_addr]|uninstall}"
        echo "  install [bind_addr] - Install Loki and Grafana, optionally specify bind_addr (default: ens5)"
        echo "  uninstall           - Uninstall Loki and Grafana and remove all related files"
        exit 1
        ;;
esac