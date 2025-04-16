#!/bin/bash

set -eou pipefail

# --- Configuration ---
METAHUB_DIR="${HOME}/Metahub" # Base directory of the cloned repo

# --- Colors ---
export TERM=xterm
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
WHITE=$(tput setaf 7)
ORANGE=$(tput setaf 9)
RESET=$(tput sgr0)

echo -e "${BLUE}Starting Metahub PtokaX setup for Linux Laptop...${RESET}"
echo -e "${YELLOW}Repository location assumed: ${METAHUB_DIR}${RESET}"
if [ ! -d "${METAHUB_DIR}" ] || [ ! -f "${METAHUB_DIR}/ptokax-laptop-setup.sh" ]; then
    echo -e "${RED}Error: Script not run from the correct directory or Metahub not found at ${METAHUB_DIR}.${RESET}"
    echo -e "${RED}Please clone the repo to ${METAHUB_DIR} and run from there.${RESET}"
    exit 1
fi
cd "${METAHUB_DIR}" # Ensure we are in the correct directory

# --- Detect Network Interface and IP Address ---
echo -e "${GREEN}[+] ${BLUE}Detecting active network interface and IP address...${RESET}"
# Try to get the interface used for the default route
INTERFACE=$(ip route get 1.1.1.1 | grep -oP 'dev \K\w+' || echo "")
if [ -z "$INTERFACE" ]; then
    echo -e "${YELLOW}[!] Could not auto-detect interface. Trying common names (eth0, wlan0, eno1)...${RESET}"
    # Fallback to common interfaces if detection fails
    if ip addr show eth0 &>/dev/null; then INTERFACE="eth0";
    elif ip addr show wlan0 &>/dev/null; then INTERFACE="wlan0";
    elif ip addr show eno1 &>/dev/null; then INTERFACE="eno1";
    # Add more common names if needed: e.g., enpXsY, wlpXsY
    fi
fi

if [ -z "$INTERFACE" ]; then
    echo -e "${RED}Error: Could not determine active network interface. Please check your network connection.${RESET}"
    exit 1
fi
echo -e "${GREEN}    Detected Interface: ${INTERFACE}${RESET}"

# Get IP address (without CIDR) from the detected interface
LAPTOP_IP=$(ip -4 addr show dev "${INTERFACE}" | grep -oP 'inet \K[\d.]+')
if [ -z "$LAPTOP_IP" ]; then
    echo -e "${RED}Error: Could not determine IPv4 address for interface ${INTERFACE}.${RESET}"
    exit 1
fi
echo -e "${GREEN}    Detected IP Address: ${LAPTOP_IP}${RESET}"
echo -e "${YELLOW}[!] Note: PtokaX will be configured with this IP. If it changes, reconfiguration is needed.${RESET}"

# --- Make Helper Scripts Executable ---
echo -e "${GREEN}[+] ${BLUE}Making helper scripts executable...${RESET}"
find "${METAHUB_DIR}/psm" -name 'ptokax-*' -type f -exec chmod +x {} \;
find "${METAHUB_DIR}" -maxdepth 1 -name '*.sh' -type f -exec chmod +x {} \;


# --- Configure PtokaX Aliases ---
ALIAS_FILE="${METAHUB_DIR}/psm/ptokax-alias"
BASHRC_FILE="${HOME}/.bashrc"
ALIAS_LINE="source ${ALIAS_FILE}"

echo -e "${GREEN}[+] ${BLUE}Configuring PtokaX management aliases in ${BASHRC_FILE}...${RESET}"
if ! grep -qF "${ALIAS_LINE}" "${BASHRC_FILE}"; then
    echo -e "\n# PtokaX Server Management Aliases\n${ALIAS_LINE}" >> "${BASHRC_FILE}"
    echo -e "${GREEN}    Aliases added. Run 'source ~/.bashrc' or restart your terminal to use them.${RESET}"
else
    echo -e "${YELLOW}[-] Aliases already configured in ${BASHRC_FILE}.${RESET}"
fi

# --- Install Dependencies ---
echo -e "${GREEN}[+] ${BLUE}Installing/Updating required packages (requires sudo)...${RESET}"
echo -e "${YELLOW}    Using 'apt-get'. If you use a different package manager (dnf, pacman), install equivalent packages.${RESET}"
echo -e "${YELLOW}    Required: C++ compiler (g++), make, Lua 5.2 dev files, zlib dev files, TinyXML dev files, MySQL/MariaDB client dev files, libcap2-bin.${RESET}"

sudo apt-get update
sudo apt-get install -y curl g++ make liblua5.2-dev zlib1g-dev libtinyxml-dev default-libmysqlclient-dev lua-sql-mysql libcap2-bin
sudo apt-get autoremove -y
echo -e "${GREEN}    Package installation attempted.${RESET}"

# --- Apply Fixes and Configuration Updates ---

# 1. Edit SettingDefaults.h
SETTINGS_DEFAULTS="${METAHUB_DIR}/PtokaX/core/SettingDefaults.h"
echo -e "${GREEN}[+] ${BLUE}Updating ${SETTINGS_DEFAULTS} with detected IP...${RESET}"
if grep -q "//HUB_ADDRESS" "${SETTINGS_DEFAULTS}"; then
    # Use sed to replace the IP address, keeping the comment intact
    sudo sed -i "s|^\s*\".*\".*, //HUB_ADDRESS|\    \"${LAPTOP_IP}\", //HUB_ADDRESS|" "${SETTINGS_DEFAULTS}"
    sudo sed -i "s|^\s*\".*\".*, //REDIRECT_ADDRESS|\    \"${LAPTOP_IP}:411\", //REDIRECT_ADDRESS|" "${SETTINGS_DEFAULTS}"
    # Optionally update HubName if desired
    sudo sed -i "s|^\s*\".*\".*, //HUB_NAME|\    \"MetahubLaptop\", //HUB_NAME|" "${SETTINGS_DEFAULTS}"
    echo -e "${GREEN}    ${SETTINGS_DEFAULTS} updated.${RESET}"
else
    echo -e "${YELLOW}[!] Could not find '//HUB_ADDRESS' marker in ${SETTINGS_DEFAULTS}. Manual check required.${RESET}"
fi

# 2. Edit Settings.pxt (example config, changes might be overwritten by actual Settings.pxt if it exists)
SETTINGS_PXT_EXAMPLE="${METAHUB_DIR}/PtokaX/cfg.example/Settings.pxt"
SETTINGS_PXT_ACTUAL="${METAHUB_DIR}/PtokaX/cfg/Settings.pxt"
echo -e "${GREEN}[+] ${BLUE}Updating example config ${SETTINGS_PXT_EXAMPLE} with detected IP...${RESET}"
# Update the *commented out* examples in the example file
if grep -q "#HubAddress" "${SETTINGS_PXT_EXAMPLE}"; then
    sudo sed -i "s|^#HubAddress.*|#HubAddress     =       ${LAPTOP_IP}|" "${SETTINGS_PXT_EXAMPLE}"
    sudo sed -i "s|^#RedirectAddress.*|#RedirectAddress        =       ${LAPTOP_IP}:411|" "${SETTINGS_PXT_EXAMPLE}"
    sudo sed -i "s|^#HubName.*|#HubName        =       MetahubLaptop|" "${SETTINGS_PXT_EXAMPLE}"
    echo -e "${GREEN}    ${SETTINGS_PXT_EXAMPLE} updated.${RESET}"
    # If an actual config exists, warn the user it might need manual update
    if [ -f "${SETTINGS_PXT_ACTUAL}" ]; then
        echo -e "${YELLOW}[!] Note: Actual config ${SETTINGS_PXT_ACTUAL} exists. Ensure it has the correct HubAddress and RedirectAddress (${LAPTOP_IP}).${RESET}"
    fi
else
     echo -e "${YELLOW}[!] Could not find '#HubAddress' marker in ${SETTINGS_PXT_EXAMPLE}. Manual check required.${RESET}"
fi

# 3. Update MOTD (Message Of The Day)
MOTD_FILE="${METAHUB_DIR}/PtokaX/cfg/Motd.txt"
echo -e "${GREEN}[+] ${BLUE}Updating ${MOTD_FILE} with detected IP address...${RESET}"
if [ -f "${MOTD_FILE}" ]; then
    # Replace the line containing "Hub Address" with the new IP
    # This is less prone to breaking if surrounding text changes slightly
    sudo sed -i "/Hub Address/c\          Hub Address        -    ${LAPTOP_IP}" "${MOTD_FILE}"
    echo -e "${GREEN}    ${MOTD_FILE} updated to show IP ${LAPTOP_IP}.${RESET}"
else
    echo -e "${YELLOW}[!] ${MOTD_FILE} not found. Skipping MOTD update.${RESET}"
fi

# --- Compile PtokaX ---
PTOKAX_SOURCE_DIR="${METAHUB_DIR}/PtokaX"
PTOKAX_BINARY="/usr/local/bin/PtokaX"
SKEIN_LIB="${PTOKAX_SOURCE_DIR}/skein/skein.a"

echo -e "${GREEN}[+] ${BLUE}Checking PtokaX compilation status...${RESET}"
if [ ! -f "${SKEIN_LIB}" ] || [ ! -f "${PTOKAX_SOURCE_DIR}/PtokaX" ] ; then
    echo -e "${GREEN}[+] ${BLUE}Compiling PtokaX (this may take some time)...${RESET}"
    cd "${PTOKAX_SOURCE_DIR}" || (echo "${RED}cd to ${PTOKAX_SOURCE_DIR} failed${RESET}" && exit 1)
    # Ensure obj directories exist
    mkdir -p obj skein/obj
    # Compile with MySQL and Lua 5.2 support
    make -f makefile-mysql lua52
    cd "${METAHUB_DIR}" || (echo "${RED}cd back to ${METAHUB_DIR} failed${RESET}" && exit 1)
    echo -e "${GREEN}    Compilation finished.${RESET}"
else
    echo -e "${YELLOW}[-] PtokaX appears to be already compiled (found ${SKEIN_LIB}). Skipping compilation.${RESET}"
fi

# --- Install PtokaX ---
echo -e "${GREEN}[+] ${BLUE}Checking PtokaX installation status...${RESET}"
if [ ! -f "${PTOKAX_BINARY}" ]; then
    echo -e "${GREEN}[+] ${BLUE}Installing PtokaX to ${PTOKAX_BINARY} (requires sudo)...${RESET}"
    cd "${PTOKAX_SOURCE_DIR}" || (echo "${RED}cd to ${PTOKAX_SOURCE_DIR} failed${RESET}" && exit 1)
    sudo make install
    cd "${METAHUB_DIR}" || (echo "${RED}cd back to ${METAHUB_DIR} failed${RESET}" && exit 1)
    echo -e "${GREEN}    PtokaX installed.${RESET}"
else
    echo -e "${YELLOW}[-] PtokaX binary already found at ${PTOKAX_BINARY}. Skipping installation.${RESET}"
fi

# --- Handle PtokaX Systemd Service ---
SERVICE_FILE_SRC="${METAHUB_DIR}/psm/systemd/ptokax.service"
SERVICE_FILE_DST="/etc/systemd/system/ptokax.service"

if command -v systemctl &> /dev/null; then
    echo -e "${GREEN}[+] ${BLUE}Setting up systemd service...${RESET}"
    if [ ! -f "${SERVICE_FILE_DST}" ]; then
        echo -e "${GREEN}    Creating PtokaX service file at ${SERVICE_FILE_DST} (requires sudo)...${RESET}"
        sudo cp "${SERVICE_FILE_SRC}" "${SERVICE_FILE_DST}"
        sudo chmod 644 "${SERVICE_FILE_DST}" # Standard permissions for service files
        echo -e "${GREEN}    Reloading systemd daemon (requires sudo)...${RESET}"
        sudo systemctl daemon-reload
    else
        echo -e "${YELLOW}[-] PtokaX service file already exists at ${SERVICE_FILE_DST}.${RESET}"
    fi

    if ! systemctl is-enabled ptokax &>/dev/null; then
        echo -e "${GREEN}    Enabling PtokaX service to start on boot (requires sudo)...${RESET}"
        sudo systemctl enable ptokax
    else
        echo -e "${YELLOW}[-] PtokaX service already enabled.${RESET}"
    fi
    echo -e "${GREEN}    Systemd service setup complete. Manage with 'sudo systemctl [start|stop|status] ptokax'.${RESET}"
else
    echo -e "${YELLOW}[!] systemctl command not found. Skipping systemd service setup.${RESET}"
    echo -e "${YELLOW}    You will need to manually start PtokaX using '${PTOKAX_BINARY}' or the 'ptokax.start' alias.${RESET}"
fi

# --- Final Instructions ---
echo ""
echo -e "${GREEN}===============================================================${RESET}"
echo -e "${GREEN} Metahub PtokaX Setup for Laptop Completed! ${RESET}"
echo -e "${GREEN}===============================================================${RESET}"
echo -e "${BLUE}Important Reminders:${RESET}"
echo -e "  - The server is configured to use IP: ${ORANGE}${LAPTOP_IP}${RESET}"
echo -e "  - ${YELLOW}If this IP changes, you must update configs and restart PtokaX!${RESET}"
echo -e "    (${SETTINGS_DEFAULTS}, ${SETTINGS_PXT_ACTUAL} if used)"
echo -e "  - Consider setting a DHCP reservation on your router for a stable IP."
echo -e "  - Use the aliases to manage the server (run ${ORANGE}source ~/.bashrc${BLUE} first if this is a new terminal):"
echo -e "    - ${ORANGE}ptokax.start${RESET}  : Start the server"
echo -e "    - ${ORANGE}ptokax.stop${RESET}   : Stop the server"
echo -e "    - ${ORANGE}ptokax.status${RESET} : Check server status"
echo -e "    - ${ORANGE}ptokax.config${RESET} : Edit main config (if needed, stop server first)"
echo -e "  - If systemd is available, you can also use: ${ORANGE}sudo systemctl [start|stop|status] ptokax${RESET}"
echo -e "${BLUE}You should now be able to start the server using ${ORANGE}ptokax.start${RESET}"
echo -e "${GREEN}===============================================================${RESET}"

exit 0