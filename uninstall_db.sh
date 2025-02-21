#!/bin/bash

DB_USER="admin"
DB_NAME="connectors"

echo "🛑 Uninstalling PostgreSQL setup..."

# Execute PostgreSQL commands safely from /tmp to avoid permission issues
exec_psql() {
    sudo -u postgres bash -c "cd /tmp && psql -t -c \"$1\""
}

# Drop database if it exists
echo "🔽 Dropping database: $DB_NAME..."
exec_psql "DROP DATABASE IF EXISTS $DB_NAME;"

# Drop user if it exists
echo "🔽 Dropping user: $DB_USER..."
exec_psql "DROP ROLE IF EXISTS $DB_USER;"

# Get PostgreSQL data directory safely
DATA_DIR=$(sudo -u postgres psql -t -c "SHOW data_directory;" | xargs)

# Restore original PostgreSQL configuration
restore_postgresql_config() {
    if [ -d "$DATA_DIR" ]; then
        echo "🔄 Restoring PostgreSQL configuration..."
        
        # Ensure sed modifies the correct config file
        PG_CONF="$DATA_DIR/postgresql.conf"
        PG_HBA="$DATA_DIR/pg_hba.conf"

        # Restore `listen_addresses`
        if grep -q "^listen_addresses = '*'" "$PG_CONF"; then
            sudo sed -i "s|^listen_addresses = '*'|#listen_addresses = 'localhost'|" "$PG_CONF"
            echo "✅ Restored listen_addresses to localhost."
        fi
        
        # Remove added `pg_hba.conf` rule
        if grep -q "0.0.0.0/0" "$PG_HBA"; then
            sudo sed -i "/0.0.0.0\/0/d" "$PG_HBA"
            echo "✅ Removed 0.0.0.0/0 rule from pg_hba.conf."
        fi

        # Restart PostgreSQL to apply changes
        sudo systemctl restart postgresql
        echo "✅ PostgreSQL configuration restored."
    else
        echo "❌ Error: PostgreSQL data directory not found at $DATA_DIR."
        exit 1
    fi
}

restore_postgresql_config

echo "✅ PostgreSQL uninstallation completed."