#!/bin/bash

# --- Variables ---
WP_BIN="/usr/local/bin/wireproxy"
CONF_DIR="/etc/wireproxy"
WG_CONF_DIR="$CONF_DIR/wg-conf"
SERVICE_FILE="/etc/systemd/system/wireproxy@.service"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Check Root ---
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run this script with sudo (sudo ./manage_wireproxy.sh)${NC}"
  exit 1
fi

# --- Functions ---

# 1. Install Wireproxy
install_wireproxy() {
    echo -e "${BLUE}=== Starting Wireproxy Installation ===${NC}"

    # Check if installed
    if [ -f "$WP_BIN" ]; then
        echo -e "${YELLOW}Wireproxy already exists, skipping download.${NC}"
    else
        # Download latest (using pufferffish release)
        echo "Downloading Wireproxy..."
        DOWNLOAD_URL="https://github.com/pufferffish/wireproxy/releases/latest/download/wireproxy_linux_amd64.tar.gz"
        wget -q --show-progress "$DOWNLOAD_URL" -O wireproxy.tar.gz

        if [ $? -ne 0 ]; then
            echo -e "${RED}Download failed. Please check your internet connection.${NC}"
            rm wireproxy.tar.gz
            return
        fi

        echo "Extracting and installing..."
        tar -zxf wireproxy.tar.gz
        mv wireproxy "$WP_BIN"
        chmod +x "$WP_BIN"
        rm wireproxy.tar.gz
        echo -e "${GREEN}Wireproxy installed successfully!${NC}"
    fi

    # Create Systemd Template
    echo "Setting up Systemd service template..."
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Wireproxy Service - %I
After=network.target

[Service]
Type=simple
ExecStart=$WP_BIN -c $CONF_DIR/%i.conf
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    echo -e "${GREEN}Systemd service template created at $SERVICE_FILE${NC}"

    # Create directories
    mkdir -p "$WG_CONF_DIR"

    echo -e "${BLUE}=== Installation finished, proceeding to config generation ===${NC}"
    sleep 1
    generate_config
}

# 2. Generate Configuration
generate_config() {
    echo -e "${BLUE}=== Generating New Wireproxy Config ===${NC}"

    # Ensure dir exists
    mkdir -p "$WG_CONF_DIR"

    read -p "Please enter config name (e.g., office, game, jp-server): " CONF_NAME
    if [[ -z "$CONF_NAME" ]]; then
        echo -e "${RED}Name cannot be empty!${NC}"
        return
    fi

    # Check if exists
    if [ -f "$CONF_DIR/$CONF_NAME.conf" ]; then
        echo -e "${RED}Config '$CONF_NAME' already exists. Please remove it or choose a different name.${NC}"
        return
    fi

    read -p "Please enter local SOCKS5 listening port (e.g., 1080): " PORT
    if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Port must be a number!${NC}"
        return
    fi

    # Define paths
    TARGET_WG_FILE="$WG_CONF_DIR/${CONF_NAME}_wg.conf"
    TARGET_WP_FILE="$CONF_DIR/${CONF_NAME}.conf"

    # Generate 1: WireGuard Config Template
    cat <<EOF > "$TARGET_WG_FILE"
# === WireGuard Config ($CONF_NAME) ===
# Please fill in the details provided by your VPN provider below
[Interface]
PrivateKey = <Insert Private Key Here>
Address = 10.0.0.2/32
DNS = 1.1.1.1
MTU = 1280

[Peer]
PublicKey = <Insert Server Public Key Here>
Endpoint = <IP>:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    chmod 600 "$TARGET_WG_FILE"

    # Generate 2: Wireproxy Config (Imports the file above)
    cat <<EOF > "$TARGET_WP_FILE"
# Import WireGuard config
WGConfig = $TARGET_WG_FILE

# Define SOCKS5 proxy
[Socks5]
BindAddress = 0.0.0.0:$PORT
EOF

    # Enable Systemd
    echo "Enabling auto-start at boot..."
    systemctl enable "wireproxy@$CONF_NAME"

    echo -e "${GREEN}=== Config Generated Successfully ===${NC}"
    echo -e "1. WireGuard Config File: ${YELLOW}$TARGET_WG_FILE${NC}"
    echo -e "2. Wireproxy Config File: ${YELLOW}$TARGET_WP_FILE${NC}"
    echo -e "3. Systemd Service Name:  ${YELLOW}wireproxy@$CONF_NAME${NC}"
    echo -e "${RED}!!! IMPORTANT NEXT STEP !!!${NC}"
    echo -e "You must edit the WireGuard config file to add your real Key and Endpoint:"
    echo -e "Command: ${YELLOW}sudo nano $TARGET_WG_FILE${NC}"
    echo -e "After editing, start the service: ${YELLOW}sudo systemctl start wireproxy@$CONF_NAME${NC}"
}

# 3. Remove Configuration
remove_config() {
    echo -e "${BLUE}=== Remove Wireproxy Config ===${NC}"

    # List current configs
    EXISTING_CONFS=$(ls $CONF_DIR/*.conf 2>/dev/null | xargs -n 1 basename | sed 's/.conf//')

    if [ -z "$EXISTING_CONFS" ]; then
        echo -e "${YELLOW}No configurations found.${NC}"
        return
    fi

    echo "Available configurations:"
    echo -e "${YELLOW}$EXISTING_CONFS${NC}"
    echo ""
    read -p "Enter the config name to remove: " CONF_NAME

    if [ ! -f "$CONF_DIR/$CONF_NAME.conf" ]; then
        echo -e "${RED}Config '$CONF_NAME' not found.${NC}"
        return
    fi

    # Stop and disable service
    echo "Stopping service..."
    systemctl stop "wireproxy@$CONF_NAME" 2>/dev/null
    systemctl disable "wireproxy@$CONF_NAME" 2>/dev/null

    # Delete files
    rm "$CONF_DIR/$CONF_NAME.conf"
    rm "$WG_CONF_DIR/${CONF_NAME}_wg.conf" 2>/dev/null

    echo -e "${GREEN}Config '$CONF_NAME' removed.${NC}"
}

# 4. Uninstall Wireproxy
uninstall_wireproxy() {
    echo -e "${RED}=== WARNING: About to uninstall Wireproxy ===${NC}"
    read -p "Are you sure you want to remove the wireproxy binary? (y/N): " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        echo "Operation cancelled."
        return
    fi

    # Stop all wireproxy services
    echo "Stopping all related services..."
    systemctl stop "wireproxy@*" 2>/dev/null
    systemctl disable "wireproxy@*" 2>/dev/null

    # Remove systemd template
    rm "$SERVICE_FILE" 2>/dev/null
    systemctl daemon-reload

    # Remove binary
    rm "$WP_BIN"
    echo -e "${GREEN}Binary removed.${NC}"

    # Ask to remove config dir
    read -p "Do you also want to delete the config directory ($CONF_DIR)? This cannot be undone! (y/N): " DEL_CONF
    if [[ "$DEL_CONF" == "y" || "$DEL_CONF" == "Y" ]]; then
        rm -rf "$CONF_DIR"
        echo -e "${GREEN}Config directory deleted.${NC}"
    else
        echo -e "${YELLOW}Config directory preserved.${NC}"
    fi
}

# --- Main Menu ---
while true; do
    echo -e "\n${BLUE}--- Wireproxy Manager (WSL) ---${NC}"
    echo "1. Install wireproxy (Proceeds to config generation)"
    echo "2. Generate a new config profile"
    echo "3. Remove a config profile"
    echo "4. Uninstall wireproxy"
    echo "0. Exit"

    read -p "Enter option [0-4]: " OPTION

    case $OPTION in
        1) install_wireproxy ;;
        2) generate_config ;;
        3) remove_config ;;
        4) uninstall_wireproxy ;;
        0) echo "Goodbye!"; exit 0 ;;
        *) echo -e "${RED}Invalid option, please try again.${NC}" ;;
    esac
done

