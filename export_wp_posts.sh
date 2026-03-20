#!/bin/bash
################################################################################
# Script Name: export_wp_posts.sh
#
# Description:
#   Unified WordPress export script that can run either locally or via SSH.
#   Exports WordPress posts and custom permalink information using WP-CLI,
#   then merges the data into a final CSV with columns in the order:
#   ID, post_title, post_name, custom_permalink, post_date, post_status, post_type.
#
#   Additionally exports WordPress users with their details and post counts 
#   across all public post types (excluding attachments).
#
#   Generates a final Excel (.xlsx) file with:
#     - Row 1: editable base domain
#     - Row 2: headers  
#     - Column A: formula-generated URLs
#     - Column I: WP Admin edit links
#
# Author: Eric Rasch
#   GitHub: https://github.com/ericrasch/script-export-wp-posts
# Date Created: 2025-08-11
# Last Modified: 2025-08-12
# Version: 5.0
# 
# Usage:
#   ./export_wp_posts.sh
#
# Output Files (in timestamped directory with domain name):
#   - export_all_posts.csv: Exported post details
#   - export_custom_permalinks.csv: Exported custom_permalink data
#   - export_wp_posts_<timestamp>.csv: Final merged posts file
#   - export_wp_posts_<timestamp>.xlsx: Final Excel file with formulas
#   - export_users.csv: Raw export of user details
#   - export_users_with_post_counts.csv: Users with post counts
#   - export_debug_log.txt: Debug log (if DEBUG mode enabled)
#
# Configuration:
#   Config file is stored at .config/wp-export-config.json in the script directory
#   Stores recent domains, SSH connections, and export statistics
################################################################################

set -euo pipefail

# Parse command-line arguments
REMOTE_MODE=0
VERBOSE=0
DEBUG=0
for arg in "$@"; do
    case "$arg" in
        --remote|-r) REMOTE_MODE=1 ;;
        --verbose|-v) VERBOSE=1 ;;
        --debug) DEBUG=1; VERBOSE=1 ;;
    esac
done

# Pre-flight check: verify Python + openpyxl for Excel generation
EXCEL_AVAILABLE=0
for cmd in python3 /usr/bin/python3 /usr/local/bin/python3 /opt/homebrew/bin/python3; do
    if command -v $cmd &> /dev/null; then
        export PYTHONPATH="$HOME/.local/lib/python3.*/site-packages:${PYTHONPATH:-}"
        if $cmd -c "import openpyxl" 2>/dev/null; then
            EXCEL_AVAILABLE=1
            break
        fi
    fi
done

if [ "$EXCEL_AVAILABLE" -eq 0 ]; then
    # Check if Python 3 exists at all (needed for both install and Excel)
    PREFLIGHT_PYTHON=""
    for cmd in python3 /usr/bin/python3 /usr/local/bin/python3 /opt/homebrew/bin/python3; do
        if command -v $cmd &> /dev/null; then
            PREFLIGHT_PYTHON=$cmd
            break
        fi
    done

    echo -e "${YELLOW}⚠️  Excel generation is not available (Python 3 + openpyxl required).${NC}"
    echo ""
    if [ -n "$PREFLIGHT_PYTHON" ]; then
        echo "  i) Install openpyxl now and continue"
    fi
    echo "  c) Continue anyway (CSV export only)"
    echo "  q) Quit"
    echo ""
    read -rp "Choose an option: " EXCEL_CHOICE
    EXCEL_CHOICE=$(echo "$EXCEL_CHOICE" | tr '[:upper:]' '[:lower:]')

    case "$EXCEL_CHOICE" in
        i)
            if [ -z "$PREFLIGHT_PYTHON" ]; then
                echo -e "${RED}Python 3 is not installed. Install it first (e.g., brew install python@3).${NC}"
                exit 1
            fi
            echo ""
            echo "Installing openpyxl..."
            # Detect pip version to determine if --break-system-packages is needed
            PIP_VERSION=$($PREFLIGHT_PYTHON -m pip --version 2>/dev/null | awk '{print $2}')
            BREAK_FLAG=""
            if [[ "$PIP_VERSION" =~ ^([0-9]+)\. ]] && (( ${BASH_REMATCH[1]} >= 23 )); then
                BREAK_FLAG="--break-system-packages"
            fi
            if $PREFLIGHT_PYTHON -m pip install --user $BREAK_FLAG openpyxl; then
                echo -e "${GREEN}✅ openpyxl installed successfully!${NC}"
                EXCEL_AVAILABLE=1
            else
                echo -e "${RED}❌ Installation failed.${NC}"
                read -rp "Continue without Excel? (y/N): " FALLBACK_CHOICE
                if [[ ! "$FALLBACK_CHOICE" =~ ^[Yy]$ ]]; then
                    exit 1
                fi
            fi
            ;;
        c)
            echo "Continuing without Excel export..."
            ;;
        *)
            echo "Exiting."
            exit 0
            ;;
    esac
    echo ""
fi

# Expected final columns for merged posts (computed dynamically after meta field prompt):
# Base: ID, post_title, post_name, custom_permalink, post_date, post_status, post_type = 7
# Plus any custom meta fields the user adds
EXPECTED_COLUMNS=7

# Flag: set to 1 when permalink structure requires full path export
EXPORT_PERMALINK_PATH=0
PERMALINK_PATH_FILE=""
HOME_URL=""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# SSH options (consistent across all SSH calls)
SSH_OPTS="-T -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -o ConnectTimeout=30"
# Route SSH stderr to terminal in verbose mode, suppress otherwise
if [ "$VERBOSE" -eq 1 ]; then
    SSH_STDERR="/dev/stderr"
else
    SSH_STDERR="/dev/null"
fi
# Sudo prefix for remote commands (set during RemoteCommand detection)
SUDO_PREFIX=""

# Build a remote command string, wrapping with sudo if needed
# Usage: build_remote_cmd "cd /path && wp post-type list"
build_remote_cmd() {
    local cmd="$1"
    if [ -n "$SUDO_PREFIX" ]; then
        # Wrap in sudo -iu <user> bash -c '...'
        # Escape single quotes in the command for bash -c wrapping
        local escaped_cmd="${cmd//\'/\'\\\'\'}"
        echo "$SUDO_PREFIX bash -c '$escaped_cmd'"
    else
        echo "$cmd"
    fi
}

# Configuration directory and file
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_DIR="$SCRIPT_DIR/.config"
CONFIG_FILE="$CONFIG_DIR/wp-export-config.json"
MAX_RECENT_DOMAINS=10
MAX_SSH_FAVORITES=10

#########################################
# Configuration Functions
#########################################

# Initialize configuration directory and file
init_config() {
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << 'EOF'
{
  "recent_domains": [],
  "ssh_favorites": [],
  "export_stats": {
    "total_exports": 0,
    "last_export": null
  }
}
EOF
    fi
}

# Load configuration
load_config() {
    init_config
    if [ -f "$CONFIG_FILE" ]; then
        cat "$CONFIG_FILE"
    else
        echo '{"recent_domains":[],"ssh_favorites":[],"export_stats":{"total_exports":0,"last_export":null}}'
    fi
}

# Save configuration (with validation to prevent writing empty/corrupt data)
save_config() {
    local config_data="$1"
    # Validate that config_data is non-empty and valid JSON before writing
    if [ -z "$config_data" ]; then
        echo "Warning: Refusing to save empty config data" >&2
        return 1
    fi
    if ! echo "$config_data" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        echo "Warning: Refusing to save invalid JSON config data" >&2
        return 1
    fi
    echo "$config_data" > "$CONFIG_FILE"
}

# Add domain to recent history (with deduplication and limit)
add_domain_to_history() {
    local domain="$1"
    local config=$(load_config)

    # Add new domain to the beginning, remove duplicates, and limit to MAX_RECENT_DOMAINS
    local updated_config
    updated_config=$(echo "$config" | python3 -c "
import json, sys
from datetime import datetime, timezone
config = json.load(sys.stdin)
domain = '$domain'
domains = config.get('recent_domains', [])
domain_stats = config.get('domain_stats', {})
# Remove existing occurrence if present
if domain in domains:
    domains.remove(domain)
# Add to beginning
domains.insert(0, domain)
# Limit to max
config['recent_domains'] = domains[:$MAX_RECENT_DOMAINS]
# Update domain stats
if 'domain_stats' not in config:
    config['domain_stats'] = {}
if domain not in config['domain_stats']:
    config['domain_stats'][domain] = {}
config['domain_stats'][domain]['last_export'] = datetime.now(timezone.utc).isoformat()
config['domain_stats'][domain]['export_count'] = config['domain_stats'][domain].get('export_count', 0) + 1
print(json.dumps(config, indent=2))
") || true

    save_config "$updated_config" || echo "Warning: Failed to save domain history" >&2
}

# Add SSH connection to favorites
add_ssh_to_favorites() {
    local ssh_connection="$1"
    local wp_path="$2"
    local config=$(load_config)

    local updated_config
    updated_config=$(echo "$config" | python3 -c "
import json, sys
config = json.load(sys.stdin)
connection = '$ssh_connection'
path = '$wp_path'
favorites = config.get('ssh_favorites', [])
# Create entry
entry = {'connection': connection, 'path': path}
# Remove existing if present
favorites = [f for f in favorites if f.get('connection') != connection]
# Add to beginning
favorites.insert(0, entry)
# Limit to max
config['ssh_favorites'] = favorites[:$MAX_SSH_FAVORITES]
print(json.dumps(config, indent=2))
") || true

    save_config "$updated_config" || echo "Warning: Failed to save SSH favorites" >&2
}

# Get recent domains as array with timestamps
get_recent_domains() {
    local config=$(load_config)
    echo "$config" | python3 -c "
import json, sys
from datetime import datetime, timezone
config = json.load(sys.stdin)
domains = config.get('recent_domains', [])
domain_stats = config.get('domain_stats', {})
for domain in domains:
    stats = domain_stats.get(domain, {})
    last_export = stats.get('last_export', '')
    if last_export:
        try:
            # Parse the timestamp and calculate days ago
            export_date = datetime.fromisoformat(last_export.replace('Z', '+00:00'))
            now = datetime.now(timezone.utc)
            days_ago = (now - export_date).days
            if days_ago == 0:
                time_str = 'today'
            elif days_ago == 1:
                time_str = 'yesterday'
            else:
                time_str = f'{days_ago} days ago'
            print(f'{domain}|{time_str}')
        except:
            print(f'{domain}|never')
    else:
        print(f'{domain}|never')
"
}

# Get SSH favorites
get_ssh_favorites() {
    local config=$(load_config)
    echo "$config" | python3 -c "
import json, sys
config = json.load(sys.stdin)
favorites = config.get('ssh_favorites', [])
for i, fav in enumerate(favorites):
    print(f'{i+1}|{fav.get(\"connection\", \"\")}|{fav.get(\"path\", \"\")}')
"
}

# Get saved meta keys for a domain
get_domain_meta_keys() {
    local domain="$1"
    local config=$(load_config)
    echo "$config" | python3 -c "
import json, sys
config = json.load(sys.stdin)
domain = '$domain'
stats = config.get('domain_stats', {}).get(domain, {})
meta_keys = stats.get('meta_keys', [])
for key in meta_keys:
    print(key)
" 2>/dev/null || true
}

# Save meta keys for a domain
save_domain_meta_keys() {
    local domain="$1"
    shift
    local meta_keys=("$@")
    local config=$(load_config)

    # Build a JSON array of meta keys
    local meta_json="["
    local first=1
    for key in "${meta_keys[@]}"; do
        if [ "$first" -eq 1 ]; then
            meta_json="$meta_json\"$key\""
            first=0
        else
            meta_json="$meta_json,\"$key\""
        fi
    done
    meta_json="$meta_json]"

    local updated_config
    updated_config=$(echo "$config" | python3 -c "
import json, sys
config = json.load(sys.stdin)
domain = '$domain'
meta_keys = json.loads('$meta_json')
if 'domain_stats' not in config:
    config['domain_stats'] = {}
if domain not in config['domain_stats']:
    config['domain_stats'][domain] = {}
config['domain_stats'][domain]['meta_keys'] = meta_keys
print(json.dumps(config, indent=2))
") || true

    save_config "$updated_config" || echo "Warning: Failed to save meta keys" >&2
}

# Update export statistics
update_export_stats() {
    local domain="$1"
    local config=$(load_config)
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local updated_config
    updated_config=$(echo "$config" | python3 -c "
import json, sys
config = json.load(sys.stdin)
stats = config.get('export_stats', {})
stats['total_exports'] = stats.get('total_exports', 0) + 1
stats['last_export'] = '$timestamp'
stats['last_domain'] = '$domain'
config['export_stats'] = stats
print(json.dumps(config, indent=2))
") || true

    save_config "$updated_config" || echo "Warning: Failed to save export stats" >&2
}

#########################################
# Mode Selection
#########################################

echo -e "${GREEN}=== WordPress Export Script v5.0 ===${NC}"

if [ "$VERBOSE" -eq 1 ]; then
    echo -e "${YELLOW}Verbose mode enabled — SSH debug output will be shown${NC}"
fi

# Skip mode selection if --remote was passed via CLI
if [ "$REMOTE_MODE" -eq 0 ]; then
    echo ""
    echo "Select export mode:"
    echo "  1) Local WordPress"
    echo "  2) Remote WordPress (SSH)"
    echo ""
    read -rp "Enter choice (1 or 2): " MODE_CHOICE

    if [[ "$MODE_CHOICE" == "2" ]]; then
        REMOTE_MODE=1
    fi
fi

#########################################
# Local vs Remote Setup
#########################################

if [ "$REMOTE_MODE" -eq 0 ]; then
    echo -e "\n${GREEN}Local Mode Selected${NC}"
    
    # Check for WP-CLI locally
    if ! command -v wp &> /dev/null; then
        echo "❌ Error: WP-CLI (wp) is not installed or not in PATH."
        echo "Please install WP-CLI before running this script."
        echo ""
        echo "Install instructions: https://wp-cli.org/#installing"
        exit 1
    fi
    
    # Set local environment
    export LC_ALL=C
    WP_PATH="."
    
else
    echo -e "\n${GREEN}Remote Mode Selected${NC}"
    echo "This script exports all post types and custom permalinks via SSH."
    
    # Function to parse SSH config
    parse_ssh_config() {
        local config_file="${1:-$HOME/.ssh/config}"
        local hosts=()
        
        if [ -f "$config_file" ]; then
            while IFS= read -r line; do
                if [[ "$line" =~ ^Host[[:space:]]+(.+)$ ]]; then
                    local host="${BASH_REMATCH[1]}"
                    if [[ ! "$host" =~ [*?] ]] && [[ ! "$host" =~ github ]]; then
                        hosts+=("$host")
                    fi
                fi
            done < "$config_file"
        fi
        
        printf '%s\n' "${hosts[@]}"
    }
    
    # Get SSH favorites from config
    SSH_FAVORITES=()
    while IFS='|' read -r idx connection path; do
        if [ -n "$connection" ]; then
            SSH_FAVORITES+=("$idx|$connection|$path")
        fi
    done < <(get_ssh_favorites)
    
    # Check for SSH config hosts
    SSH_HOSTS=($(parse_ssh_config))
    
    echo -e "\n${YELLOW}SSH Connection Options:${NC}"
    
    # Show favorites if any
    if [ ${#SSH_FAVORITES[@]} -gt 0 ]; then
        echo -e "\n${GREEN}Recent SSH connections:${NC}"
        for fav in "${SSH_FAVORITES[@]}"; do
            IFS='|' read -r idx connection path <<< "$fav"
            echo "  F$idx. $connection (path: $path)"
        done
    fi
    
    # Show SSH config hosts
    if [ ${#SSH_HOSTS[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}SSH config hosts:${NC}"
        for i in "${!SSH_HOSTS[@]}"; do
            echo "  $((i+1)). ${SSH_HOSTS[$i]}"
        done
    fi
    
    echo "  0. Enter custom connection"
    
    # Get selection
    if [ ${#SSH_FAVORITES[@]} -gt 0 ]; then
        read -rp $'\nSelect an option (F1-F'${#SSH_FAVORITES[@]}', 1-'${#SSH_HOSTS[@]}', or 0): ' HOST_CHOICE
    else
        read -rp $'\nSelect a host (1-'${#SSH_HOSTS[@]}') or 0 for custom: ' HOST_CHOICE
    fi
    
    # Process selection
    HOST_CHOICE_UPPER=$(echo "$HOST_CHOICE" | tr '[:lower:]' '[:upper:]')
    if [[ "$HOST_CHOICE_UPPER" =~ ^F([0-9]+)$ ]]; then
        # Favorite selected — pre-fill connection and path, allow override
        FAV_NUM="${BASH_REMATCH[1]}"
        FAV_CONNECTION=""
        FAV_PATH=""
        for fav in "${SSH_FAVORITES[@]}"; do
            IFS='|' read -r idx connection path <<< "$fav"
            if [[ "$idx" == "$FAV_NUM" ]]; then
                FAV_CONNECTION="$connection"
                FAV_PATH="$path"
                break
            fi
        done
        if [ -n "$FAV_CONNECTION" ]; then
            echo -e "${GREEN}Favorite: $FAV_CONNECTION (path: $FAV_PATH)${NC}"
            read -rp "SSH connection [$FAV_CONNECTION]: " SSH_CONNECTION
            SSH_CONNECTION=${SSH_CONNECTION:-$FAV_CONNECTION}
            read -rp "WordPress path [$FAV_PATH]: " WP_PATH
            WP_PATH=${WP_PATH:-$FAV_PATH}
        fi
    elif [[ "$HOST_CHOICE" =~ ^[1-9][0-9]*$ ]] && [ "$HOST_CHOICE" -le "${#SSH_HOSTS[@]}" ]; then
        # SSH config host selected
        SSH_CONNECTION="${SSH_HOSTS[$((HOST_CHOICE-1))]}"
        echo -e "${GREEN}Using: $SSH_CONNECTION${NC}"

        # Check if this host has a saved path in favorites
        SAVED_PATH=""
        for fav in ${SSH_FAVORITES[@]+"${SSH_FAVORITES[@]}"}; do
            IFS='|' read -r idx fav_conn fav_path <<< "$fav"
            if [[ "$fav_conn" == "$SSH_CONNECTION" ]]; then
                SAVED_PATH="$fav_path"
                break
            fi
        done

        if [ -n "$SAVED_PATH" ]; then
            echo -e "${YELLOW}Previous path found: $SAVED_PATH${NC}"
            read -rp "Enter WordPress path (previous: $SAVED_PATH): " WP_PATH
            WP_PATH=${WP_PATH:-$SAVED_PATH}
        else
        # Auto-detect common paths based on hostname patterns
        DETECTED_HOST=""
        if [[ "$SSH_CONNECTION" =~ press ]] || [[ "$SSH_CONNECTION" =~ pressable ]]; then
            SUGGESTED_PATH="/htdocs"
            DETECTED_HOST="Pressable"
        elif [[ "$SSH_CONNECTION" =~ wpe ]] || [[ "$SSH_CONNECTION" =~ wpengine ]]; then
            SITE_NAME="${SSH_CONNECTION#wpe-}"
            SITE_NAME="${SITE_NAME%%.*}"
            SUGGESTED_PATH="/home/wpe-user/sites/$SITE_NAME"
            DETECTED_HOST="WP Engine"
        elif [[ "$SSH_CONNECTION" =~ kinsta ]]; then
            SUGGESTED_PATH="/www/[sitename]_[id]/public"
            DETECTED_HOST="Kinsta"
        elif [[ "$SSH_CONNECTION" =~ siteground ]]; then
            SUGGESTED_PATH="~/public_html"
            DETECTED_HOST="SiteGround"
        elif [[ "$SSH_CONNECTION" =~ ec2 ]] || [[ "$SSH_CONNECTION" =~ amazonaws ]] || [[ "$SSH_CONNECTION" =~ aws ]]; then
            SUGGESTED_PATH="/var/www/html"
            DETECTED_HOST="AWS/EC2"
        elif [[ "$SSH_CONNECTION" =~ bitnami ]]; then
            SUGGESTED_PATH="/opt/bitnami/wordpress"
            DETECTED_HOST="Bitnami"
        elif [[ "$SSH_CONNECTION" =~ lightsail ]]; then
            SUGGESTED_PATH="/opt/bitnami/wordpress"
            DETECTED_HOST="AWS Lightsail"
        elif [[ "$SSH_CONNECTION" =~ cloudways ]]; then
            SUGGESTED_PATH="~/public_html"
            DETECTED_HOST="Cloudways"
        elif [[ "$SSH_CONNECTION" =~ flywheel ]] || [[ "$SSH_CONNECTION" =~ getflywheel ]]; then
            SUGGESTED_PATH="~/public_html"
            DETECTED_HOST="Flywheel"
        else
            SUGGESTED_PATH="~/public_html"
        fi

        # Get WordPress path
        if [ -n "$SUGGESTED_PATH" ]; then
            if [ -n "$DETECTED_HOST" ]; then
                echo -e "${YELLOW}Detected: $DETECTED_HOST host${NC}"
            fi
            
            read -rp "Enter WordPress path (suggested: $SUGGESTED_PATH): " WP_PATH
            WP_PATH=${WP_PATH:-$SUGGESTED_PATH}
        else
            read -rp "Enter WordPress path (e.g., ~/htdocs): " WP_PATH
        fi
        fi  # end of saved path else block
    else
        # Custom connection
        read -rp "Enter SSH user@host: " SSH_CONNECTION
        read -rp "Enter WordPress path (e.g., ~/htdocs): " WP_PATH
    fi
    
    # Detect SSH config overrides (RemoteCommand, RequestTTY)
    # These prevent passing commands via CLI and must be overridden for scripted use
    SUDO_PREFIX=""
    SSH_CONFIG_REMOTE_CMD=$(ssh -G "$SSH_CONNECTION" 2>/dev/null | grep -i "^remotecommand " | sed 's/^remotecommand //i' || true)
    if [ -n "$SSH_CONFIG_REMOTE_CMD" ] && [[ "$SSH_CONFIG_REMOTE_CMD" != "none" ]]; then
        echo -e "\n${YELLOW}Detected RemoteCommand in SSH config for $SSH_CONNECTION${NC}"
        [ "$VERBOSE" -eq 1 ] && echo "  [DEBUG] RemoteCommand: $SSH_CONFIG_REMOTE_CMD"

        # Override RemoteCommand and RequestTTY so we can pass commands
        SSH_OPTS="$SSH_OPTS -o RemoteCommand=none -o RequestTTY=no"
        echo "  Overriding RemoteCommand for scripted access"

        # Extract sudo user if the RemoteCommand uses sudo -iu <user>
        if [[ "$SSH_CONFIG_REMOTE_CMD" =~ sudo\ -iu\ ([a-zA-Z0-9_-]+) ]]; then
            SUDO_USER="${BASH_REMATCH[1]}"
            SUDO_PREFIX="sudo -iu $SUDO_USER"
            echo -e "  Detected sudo user: ${GREEN}$SUDO_USER${NC} — will wrap WP-CLI commands with '$SUDO_PREFIX'"
        fi
    fi

    # Validate SSH connection before proceeding
    echo -e "\n${YELLOW}Validating SSH connection...${NC}"

    # Test 1: Can we connect at all?
    echo -n "  Testing SSH connectivity... "
    SSH_TEST_OUTPUT=$(ssh $SSH_OPTS -o BatchMode=yes "$SSH_CONNECTION" "echo SSH_OK" 2>&1) || true
    if [[ "$SSH_TEST_OUTPUT" == *"SSH_OK"* ]]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        echo -e "${RED}Cannot connect to $SSH_CONNECTION${NC}"
        echo "SSH output: $SSH_TEST_OUTPUT"
        echo ""
        echo "Troubleshooting:"
        echo "  - Verify the hostname/IP is correct"
        echo "  - Check that your SSH key is added: ssh-add -l"
        echo "  - Try connecting manually: ssh -v $SSH_CONNECTION"
        echo "  - Check ~/.ssh/config for this host entry"
        exit 1
    fi

    # Test 2: Does the WordPress path exist?
    echo -n "  Checking WordPress path ($WP_PATH)... "
    REMOTE_CMD=$(build_remote_cmd "[ -d \"$WP_PATH\" ] && echo PATH_OK || echo PATH_MISSING")
    PATH_TEST=$(ssh $SSH_OPTS "$SSH_CONNECTION" "$REMOTE_CMD" 2>&1) || true
    if [[ "$PATH_TEST" == *"PATH_OK"* ]]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        echo -e "${RED}Path '$WP_PATH' does not exist on $SSH_CONNECTION${NC}"
        echo ""
        echo "Troubleshooting — try: ssh $SSH_CONNECTION 'ls -la ~/'"
        echo "Common WordPress paths:"
        echo "  /var/www/html             (Generic Linux/Apache)"
        echo "  /var/www/html/wp          (AWS subdirectory install)"
        echo "  /opt/bitnami/wordpress    (AWS Bitnami/Lightsail)"
        echo "  /htdocs                   (Pressable)"
        echo "  ~/public_html             (cPanel/SiteGround)"
        exit 1
    fi

    # Test 3: Is WP-CLI available?
    echo -n "  Checking WP-CLI availability... "
    REMOTE_CMD=$(build_remote_cmd "cd \"$WP_PATH\" && wp --version 2>&1")
    WPCLI_TEST=$(ssh $SSH_OPTS "$SSH_CONNECTION" "$REMOTE_CMD" 2>&1) || true
    if [[ "$WPCLI_TEST" == *"WP-CLI"* ]]; then
        echo -e "${GREEN}OK (${WPCLI_TEST})${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        echo -e "${RED}WP-CLI is not available at $WP_PATH on $SSH_CONNECTION${NC}"
        [ -n "$WPCLI_TEST" ] && echo "Output: $WPCLI_TEST"
        echo ""
        echo "Install WP-CLI on the remote server:"
        echo "  curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar"
        echo "  chmod +x wp-cli.phar"
        echo "  sudo mv wp-cli.phar /usr/local/bin/wp"
        exit 1
    fi

    echo -e "${GREEN}All pre-flight checks passed.${NC}"
fi

#########################################
# Detect Permalink Structure
#########################################

echo -e "\n${YELLOW}Detecting permalink structure...${NC}"

if [ "$REMOTE_MODE" -eq 0 ]; then
    PERMALINK_STRUCTURE=$(wp option get permalink_structure --allow-root 2>/dev/null || echo "")
    HOME_URL=$(wp option get home --allow-root 2>/dev/null | sed 's|/$||' || echo "")
else
    REMOTE_CMD=$(build_remote_cmd "cd \"$WP_PATH\" && wp option get permalink_structure --allow-root 2>/dev/null")
    PERMALINK_STRUCTURE=$(ssh $SSH_OPTS "$SSH_CONNECTION" "$REMOTE_CMD" 2>"$SSH_STDERR" | tr -d '\r' || echo "")
    REMOTE_CMD=$(build_remote_cmd "cd \"$WP_PATH\" && wp option get home --allow-root 2>/dev/null")
    HOME_URL=$(ssh $SSH_OPTS "$SSH_CONNECTION" "$REMOTE_CMD" 2>"$SSH_STDERR" | tr -d '\r' | sed 's|/$||' || echo "")
fi

# Normalize: trim whitespace and carriage returns
PERMALINK_STRUCTURE=$(echo "$PERMALINK_STRUCTURE" | xargs 2>/dev/null || echo "")

echo "  Permalink structure: ${PERMALINK_STRUCTURE:-'(default/plain)'}"

# If structure contains anything beyond %postname%, we need full permalink paths
# Simple structures: /%postname%/, /%post_id%/ — these don't need extra path resolution
if [[ -n "$PERMALINK_STRUCTURE" ]] && \
   [[ "$PERMALINK_STRUCTURE" != "/%postname%/" ]] && \
   [[ "$PERMALINK_STRUCTURE" != "/%postname%" ]] && \
   [[ "$PERMALINK_STRUCTURE" != "/%post_id%/" ]]; then
    EXPORT_PERMALINK_PATH=1
    echo -e "  ${YELLOW}Non-simple permalink structure detected — will export full permalink paths${NC}"
else
    echo -e "  ${GREEN}Simple permalink structure — standard URL construction will be used${NC}"
fi

#########################################
# Domain Input with History
#########################################

echo ""

# Get recent domains
RECENT_DOMAINS=()
RECENT_DOMAINS_INFO=()
while IFS='|' read -r domain last_export; do
    if [ -n "$domain" ]; then
        RECENT_DOMAINS+=("$domain")
        RECENT_DOMAINS_INFO+=("$domain|$last_export")
    fi
done < <(get_recent_domains)

if [ ${#RECENT_DOMAINS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Recent domains:${NC}"
    for i in "${!RECENT_DOMAINS_INFO[@]}"; do
        IFS='|' read -r domain last_export <<< "${RECENT_DOMAINS_INFO[$i]}"
        echo "  $((i+1)). $domain (last export: $last_export)"
    done
    echo ""
    read -rp "Select a recent domain (1-${#RECENT_DOMAINS[@]}) or enter new domain: " DOMAIN_CHOICE
    
    if [[ "$DOMAIN_CHOICE" =~ ^[1-9][0-9]*$ ]] && [ "$DOMAIN_CHOICE" -le "${#RECENT_DOMAINS[@]}" ]; then
        BASE_DOMAIN="${RECENT_DOMAINS[$((DOMAIN_CHOICE-1))]}"
        echo -e "${GREEN}Using: $BASE_DOMAIN${NC}"
    else
        BASE_DOMAIN="$DOMAIN_CHOICE"
    fi
else
    read -rp "Enter base domain: " BASE_DOMAIN
fi

BASE_DOMAIN=${BASE_DOMAIN:-example.com}

# Normalize domain: strip protocol prefix and trailing slashes
# Allows users to paste full URLs like https://example.com/blog/ and still get clean domain
BASE_DOMAIN=$(echo "$BASE_DOMAIN" | sed 's|^https\?://||' | sed 's|/*$||')

# Save domain to history immediately so it's not lost if the script fails later
add_domain_to_history "$BASE_DOMAIN"

read -rp "Include user export? (Y/n): " EXPORT_USERS
EXPORT_USERS=${EXPORT_USERS:-y}

# Create local directory with domain name
timestamp=$(date +"%Y%m%d_%H%M%S")
# Create sheet-friendly timestamp format
sheet_timestamp=$(date +"%Y-%m-%d_%H%M%S")
# Sanitize domain name for filesystem and Excel sheet names
# Replace . / : with dashes (colon is invalid in Excel sheet titles)
DOMAIN_SAFE=$(echo "$BASE_DOMAIN" | tr './:' '-' | tr '[:upper:]' '[:lower:]')
EXPORT_DIR="!export_wp_posts_${timestamp}_${DOMAIN_SAFE}"
mkdir -p "$EXPORT_DIR"

# Define file paths
ALL_POSTS_FILE="$EXPORT_DIR/export_all_posts.csv"
CUSTOM_PERMALINKS_FILE="$EXPORT_DIR/export_custom_permalinks.csv"
PERMALINK_PATH_FILE="$EXPORT_DIR/export_permalink_paths.csv"
TEMP_FILE="$EXPORT_DIR/export_wp_posts_temp.csv"
VALIDATED_FILE="$EXPORT_DIR/export_wp_posts_validated.csv"
FINAL_CSV_FILE="$EXPORT_DIR/export_wp_posts_${timestamp}.csv"
EXCEL_FILE="$EXPORT_DIR/export_wp_posts_${timestamp}.xlsx"
DEBUG_FILE="$EXPORT_DIR/export_debug_log.txt"

# Clear previous export files
> "$ALL_POSTS_FILE"
> "$CUSTOM_PERMALINKS_FILE"
[ "$EXPORT_PERMALINK_PATH" -eq 1 ] && > "$PERMALINK_PATH_FILE"
[ "$DEBUG" -eq 1 ] && > "$DEBUG_FILE"

echo -e "\n${YELLOW}Discovering post types...${NC}"

#########################################
# Discover Post Types
#########################################

# Initialize POST_TYPES array
POST_TYPES=()

if [ "$REMOTE_MODE" -eq 0 ]; then
    # Local discovery - simpler and more reliable
    echo "Discovering post types locally..."
    POST_TYPES=($(wp post-type list --fields=name,public --allow-root --format=csv | tail -n +2 | awk -F, '$2=="1" && $1!="attachment" {print $1}'))
    
    if [ ${#POST_TYPES[@]} -gt 0 ]; then
        echo -e "${GREEN}✓ Discovered ${#POST_TYPES[@]} post types${NC}"
    else
        echo -e "${YELLOW}No public post types found. Using defaults.${NC}"
        POST_TYPES=("post" "page")
    fi
else
    # Remote discovery - try multiple methods
    echo "Attempting to discover post types remotely..."
    
    # Method 1: Simple approach
    echo "Method 1: Trying standard discovery..."
    REMOTE_CMD=$(build_remote_cmd "cd \"$WP_PATH\" && wp post-type list --field=name --public=true --format=csv 2>/dev/null")
    [ "$VERBOSE" -eq 1 ] && echo -e "  ${YELLOW}[SSH] $REMOTE_CMD${NC}"
    POST_TYPES_RAW=$(ssh $SSH_OPTS "$SSH_CONNECTION" "$REMOTE_CMD" 2>"$SSH_STDERR" || echo "")

    # Clean output — filter SSH noise, || true prevents grep exit code 1 from killing script via pipefail
    POST_TYPES_RAW=$(echo "$POST_TYPES_RAW" | tr -d '\r' | grep -v "^$" | grep -v "^Connection to" | grep -v "^Warning:" | grep -v "^Pseudo-terminal" || true)
    [ "$VERBOSE" -eq 1 ] && echo "  [DEBUG] Method 1 raw output: '$POST_TYPES_RAW'"

    if [ -z "$POST_TYPES_RAW" ] || [[ "$POST_TYPES_RAW" == *"Error"* ]]; then
        echo "Method 2: Trying with simpler format..."
        REMOTE_CMD=$(build_remote_cmd "cd \"$WP_PATH\" && wp post-type list --field=name 2>/dev/null | grep -v attachment")
        [ "$VERBOSE" -eq 1 ] && echo -e "  ${YELLOW}[SSH] $REMOTE_CMD${NC}"
        POST_TYPES_RAW=$(ssh $SSH_OPTS "$SSH_CONNECTION" "$REMOTE_CMD" 2>"$SSH_STDERR" || echo "")
        POST_TYPES_RAW=$(echo "$POST_TYPES_RAW" | tr -d '\r' | grep -v "^$" || true)
        [ "$VERBOSE" -eq 1 ] && echo "  [DEBUG] Method 2 raw output: '$POST_TYPES_RAW'"
    fi

    if [ -z "$POST_TYPES_RAW" ] || [[ "$POST_TYPES_RAW" == *"Error"* ]]; then
        echo "Method 3: Trying PHP evaluation..."
        REMOTE_CMD=$(build_remote_cmd "cd \"$WP_PATH\" && wp eval 'foreach(get_post_types(array(\"public\"=>true)) as \$t) if(\$t!=\"attachment\") echo \$t.\"\n\";'")
        [ "$VERBOSE" -eq 1 ] && echo -e "  ${YELLOW}[SSH] $REMOTE_CMD${NC}"
        POST_TYPES_RAW=$(ssh $SSH_OPTS "$SSH_CONNECTION" "$REMOTE_CMD" 2>"$SSH_STDERR" || echo "")
        POST_TYPES_RAW=$(echo "$POST_TYPES_RAW" | tr -d '\r' | grep -v "^$" || true)
        [ "$VERBOSE" -eq 1 ] && echo "  [DEBUG] Method 3 raw output: '$POST_TYPES_RAW'"
    fi
    
    if [ -n "$POST_TYPES_RAW" ] && [[ "$POST_TYPES_RAW" != *"closed"* ]] && [[ "$POST_TYPES_RAW" != *"Error"* ]]; then
        # Parse discovered post types
        while IFS= read -r type; do
            type=$(echo "$type" | xargs)
            if [ -n "$type" ] && [[ ! "$type" =~ ^(name|attachment)$ ]] && [[ "$type" != "name" ]]; then
                POST_TYPES+=("$type")
            fi
        done <<< "$POST_TYPES_RAW"
        
        if [ ${#POST_TYPES[@]} -gt 0 ]; then
            echo -e "${GREEN}✓ Discovered ${#POST_TYPES[@]} post types automatically${NC}"
        else
            echo -e "${YELLOW}Discovery returned no valid post types${NC}"
        fi
    else
        echo -e "${YELLOW}Auto-discovery failed. Will use manual entry.${NC}"
    fi
    
    # If we still don't have post types, fall back to manual
    if [ ${#POST_TYPES[@]} -eq 0 ]; then
        echo "Using standard WordPress post types as base..."
        POST_TYPES=("post" "page")
        
        echo -e "\n${YELLOW}Tip: You can check post types manually by SSHing in and running:${NC}"
        echo "  wp post-type list --public=true"
        echo ""
        
        read -rp "Do you know your custom post types? (y/n): " ADD_CUSTOM
        if [[ "$ADD_CUSTOM" == "y" || "$ADD_CUSTOM" == "Y" ]]; then
            echo "Enter post types one per line (press Enter twice when done):"
            echo "Example: commercial, article, press_release, etc."
            
            while true; do
                read -rp "> " type
                if [ -z "$type" ]; then
                    break
                fi
                type=$(echo "$type" | xargs | tr -d ',')
                if [ -n "$type" ] && [[ ! " ${POST_TYPES[@]} " =~ " ${type} " ]]; then
                    POST_TYPES+=("$type")
                    echo "  Added: $type"
                fi
            done
        fi
    fi
fi

# Ensure we have at least some post types
if [ ${#POST_TYPES[@]} -eq 0 ]; then
    echo -e "${RED}Error: No post types defined. Using defaults.${NC}"
    POST_TYPES=("post" "page")
fi

echo "Will export post types: ${POST_TYPES[*]}"

# Create a comma-separated list for user post counts
POST_TYPES_LIST=$(IFS=,; echo "${POST_TYPES[*]}")

#########################################
# Custom Meta Fields
#########################################

CUSTOM_META_KEYS=()
META_FILES=()

# Check for previously used meta keys for this domain
SAVED_META_KEYS=()
while IFS= read -r key; do
    if [ -n "$key" ]; then
        SAVED_META_KEYS+=("$key")
    fi
done < <(get_domain_meta_keys "$BASE_DOMAIN")

echo ""
if [ ${#SAVED_META_KEYS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Previous meta fields for $BASE_DOMAIN:${NC} ${SAVED_META_KEYS[*]}"
    read -rp "Use previous meta fields? (Y/n): " USE_SAVED_META
    if [[ "$USE_SAVED_META" != "n" && "$USE_SAVED_META" != "N" ]]; then
        CUSTOM_META_KEYS=("${SAVED_META_KEYS[@]}")
        echo -e "${GREEN}Using saved meta fields: ${CUSTOM_META_KEYS[*]}${NC}"
        read -rp "Add more meta fields? (y/N): " ADD_MORE_META
        if [[ "$ADD_MORE_META" == "y" || "$ADD_MORE_META" == "Y" ]]; then
            echo "Enter additional meta key names one per line (press Enter twice when done):"
            while true; do
                read -rp "> " meta_key
                if [ -z "$meta_key" ]; then
                    break
                fi
                meta_key=$(echo "$meta_key" | xargs | tr -d ',')
                if [ -n "$meta_key" ] && [[ ! " ${CUSTOM_META_KEYS[*]+${CUSTOM_META_KEYS[*]}} " =~ " ${meta_key} " ]]; then
                    CUSTOM_META_KEYS+=("$meta_key")
                    echo "  Added: $meta_key"
                fi
            done
        fi
    else
        read -rp "Export additional meta fields? (y/N): " ADD_META
        if [[ "$ADD_META" == "y" || "$ADD_META" == "Y" ]]; then
            echo "Enter meta key names one per line (press Enter twice when done):"
            echo "Example: _custom_clean_url, _yoast_wpseo_title"
            while true; do
                read -rp "> " meta_key
                if [ -z "$meta_key" ]; then
                    break
                fi
                meta_key=$(echo "$meta_key" | xargs | tr -d ',')
                if [ -n "$meta_key" ] && [[ ! " ${CUSTOM_META_KEYS[*]+${CUSTOM_META_KEYS[*]}} " =~ " ${meta_key} " ]]; then
                    CUSTOM_META_KEYS+=("$meta_key")
                    echo "  Added: $meta_key"
                fi
            done
        fi
    fi
else
    read -rp "Export additional meta fields? (y/N): " ADD_META
    if [[ "$ADD_META" == "y" || "$ADD_META" == "Y" ]]; then
        echo "Enter meta key names one per line (press Enter twice when done):"
        echo "Example: _custom_clean_url, _yoast_wpseo_title"
        while true; do
            read -rp "> " meta_key
            if [ -z "$meta_key" ]; then
                break
            fi
            meta_key=$(echo "$meta_key" | xargs | tr -d ',')
            if [ -n "$meta_key" ] && [[ ! " ${CUSTOM_META_KEYS[*]+${CUSTOM_META_KEYS[*]}} " =~ " ${meta_key} " ]]; then
                CUSTOM_META_KEYS+=("$meta_key")
                echo "  Added: $meta_key"
            fi
        done
    fi
fi

# Save meta keys for this domain (if any were selected)
if [ ${#CUSTOM_META_KEYS[@]} -gt 0 ]; then
    save_domain_meta_keys "$BASE_DOMAIN" "${CUSTOM_META_KEYS[@]}"
    echo -e "${GREEN}Will export meta fields: ${CUSTOM_META_KEYS[*]}${NC}"
fi

# Dynamic column count: 7 base columns + number of custom meta fields
EXPECTED_COLUMNS=$((7 + EXPORT_PERMALINK_PATH + ${#CUSTOM_META_KEYS[@]}))

#########################################
# Export Posts and Custom Permalink Data
#########################################

# Export posts with all required fields
echo "ID,post_title,post_name,post_date,post_status,post_type" > "$ALL_POSTS_FILE"

echo -e "\n${YELLOW}Exporting all posts...${NC}"
if [ "$REMOTE_MODE" -eq 1 ]; then
    echo "Note: Remote hosts may close connections during large exports. This is normal."
fi

FIRST=1
for post_type in "${POST_TYPES[@]}"; do
    echo "  Exporting post type: $post_type"
    
    if [ "$REMOTE_MODE" -eq 0 ]; then
        # Local export
        if [ "$FIRST" -eq 1 ]; then
            # First type - include headers
            wp post list --post_type="$post_type" --post_status=any \
                --fields=ID,post_title,post_name,post_date,post_status,post_type \
                --format=csv --allow-root >> "$ALL_POSTS_FILE"
            FIRST=0
        else
            # Subsequent types - skip headers
            wp post list --post_type="$post_type" --post_status=any \
                --fields=ID,post_title,post_name,post_date,post_status,post_type \
                --format=csv --allow-root | tail -n +2 >> "$ALL_POSTS_FILE"
        fi
        
        if [ $? -eq 0 ]; then
            POST_COUNT=$(wp post list --post_type="$post_type" --post_status=any --format=count --allow-root)
            echo "    ✓ Exported $POST_COUNT $post_type(s)"
        else
            echo "    ❌ Error: WP-CLI export failed for post type $post_type" >&2
            exit 1
        fi
    else
        # Remote export
        REMOTE_CMD=$(build_remote_cmd "cd \"$WP_PATH\" && wp post list --post_type=$post_type --post_status=any --fields=ID,post_title,post_name,post_date,post_status,post_type --format=csv 2>/dev/null")
        [ "$VERBOSE" -eq 1 ] && echo -e "    ${YELLOW}[SSH] $REMOTE_CMD${NC}"
        EXPORT_OUTPUT=$(ssh $SSH_OPTS "$SSH_CONNECTION" "$REMOTE_CMD" 2>"$SSH_STDERR" || echo "FAILED")
        
        if [[ "$EXPORT_OUTPUT" != "FAILED" ]] && [[ -n "$EXPORT_OUTPUT" ]]; then
            echo "$EXPORT_OUTPUT" | tail -n +2 >> "$ALL_POSTS_FILE"
            POST_COUNT=$(echo "$EXPORT_OUTPUT" | wc -l)
            echo "    ✓ Exported $((POST_COUNT - 1)) $post_type(s)"
        else
            echo "    ✗ Failed to export $post_type - connection closed or type doesn't exist"
        fi
    fi
done

if [ ! -s "$ALL_POSTS_FILE" ]; then
    echo "❌ Error: $ALL_POSTS_FILE is empty. Exiting." >&2
    exit 1
fi

# Export custom permalinks
echo "ID,custom_permalink" > "$CUSTOM_PERMALINKS_FILE"

echo -e "\n${YELLOW}Exporting custom permalinks...${NC}"
for post_type in "${POST_TYPES[@]}"; do
    echo "  Checking custom permalinks for $post_type..."
    
    if [ "$REMOTE_MODE" -eq 0 ]; then
        # Local export
        wp post list --post_type="$post_type" --post_status=any \
            --fields=ID,custom_permalink --meta_key=custom_permalink \
            --format=csv --allow-root | tail -n +2 >> "$CUSTOM_PERMALINKS_FILE"
        if [ $? -ne 0 ]; then
            echo "    ❌ Error: WP-CLI export (custom_permalink) failed for post type $post_type" >&2
            exit 1
        fi
    else
        # Remote export
        REMOTE_CMD=$(build_remote_cmd "cd \"$WP_PATH\" && wp post list --post_type=\"$post_type\" --post_status=any --fields=ID,custom_permalink --meta_key=custom_permalink --format=csv --quiet 2>/dev/null | tail -n +2")
        ssh $SSH_OPTS "$SSH_CONNECTION" "$REMOTE_CMD" >> "$CUSTOM_PERMALINKS_FILE" 2>"$SSH_STDERR" || true
    fi
done

if [ ! -s "$CUSTOM_PERMALINKS_FILE" ]; then
    echo "Warning: $CUSTOM_PERMALINKS_FILE is empty. No custom permalinks found." >&2
fi

#########################################
# Export Full Permalink Paths (if needed)
#########################################

if [ "$EXPORT_PERMALINK_PATH" -eq 1 ]; then
    echo "ID,url" > "$PERMALINK_PATH_FILE"

    echo -e "\n${YELLOW}Exporting full permalink paths (non-simple permalink structure)...${NC}"
    for post_type in "${POST_TYPES[@]}"; do
        echo "  Exporting permalink paths for $post_type..."

        if [ "$REMOTE_MODE" -eq 0 ]; then
            wp post list --post_type="$post_type" --post_status=any \
                --fields=ID,url \
                --format=csv --allow-root 2>/dev/null | tail -n +2 >> "$PERMALINK_PATH_FILE" || true
        else
            REMOTE_CMD=$(build_remote_cmd "cd \"$WP_PATH\" && wp post list --post_type=\"$post_type\" --post_status=any --fields=ID,url --format=csv --quiet 2>/dev/null | tail -n +2")
            ssh $SSH_OPTS "$SSH_CONNECTION" "$REMOTE_CMD" >> "$PERMALINK_PATH_FILE" 2>"$SSH_STDERR" || true
        fi
    done

    permalink_path_count=$(( $(wc -l < "$PERMALINK_PATH_FILE") - 1 ))
    echo -e "  ${GREEN}✓ Exported $permalink_path_count permalink path entries${NC}"
fi

#########################################
# Export Custom Meta Fields
#########################################

if [ ${#CUSTOM_META_KEYS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Exporting custom meta fields...${NC}"

    for meta_key in "${CUSTOM_META_KEYS[@]}"; do
        # Sanitize meta key for filename (replace non-alphanumeric with _)
        META_KEY_SAFE=$(echo "$meta_key" | tr -c 'a-zA-Z0-9_' '_')
        META_FILE="$EXPORT_DIR/export_meta_${META_KEY_SAFE}.csv"
        echo "ID,$meta_key" > "$META_FILE"

        for post_type in "${POST_TYPES[@]}"; do
            echo "  Checking $meta_key for $post_type..."

            if [ "$REMOTE_MODE" -eq 0 ]; then
                # Local export
                wp post list --post_type="$post_type" --post_status=any \
                    --fields="ID,$meta_key" --meta_key="$meta_key" \
                    --format=csv --allow-root 2>/dev/null | tail -n +2 >> "$META_FILE" || true
            else
                # Remote export
                REMOTE_CMD=$(build_remote_cmd "cd \"$WP_PATH\" && wp post list --post_type=\"$post_type\" --post_status=any --fields=\"ID,$meta_key\" --meta_key=\"$meta_key\" --format=csv --quiet 2>/dev/null | tail -n +2")
                ssh $SSH_OPTS "$SSH_CONNECTION" "$REMOTE_CMD" >> "$META_FILE" 2>"$SSH_STDERR" || true
            fi
        done

        meta_entry_count=$(( $(wc -l < "$META_FILE") - 1 ))
        if [ "$meta_entry_count" -gt 0 ]; then
            echo -e "  ${GREEN}✓ Found $meta_entry_count entries for $meta_key${NC}"
        else
            echo -e "  ${YELLOW}No entries found for $meta_key (column will be empty)${NC}"
        fi

        META_FILES+=("$META_FILE")
    done
fi

#########################################
# Merge and Process Data
#########################################

echo -e "\n${YELLOW}Merging posts data using improved CSV parser...${NC}"

# Build dynamic header: ID,post_title,post_name,custom_permalink,[permalink_path],[meta fields],post_date,post_status,post_type
MERGE_HEADER="ID,post_title,post_name,custom_permalink"
if [ "$EXPORT_PERMALINK_PATH" -eq 1 ]; then
    MERGE_HEADER="$MERGE_HEADER,permalink_path"
fi
for meta_key in ${CUSTOM_META_KEYS[@]+"${CUSTOM_META_KEYS[@]}"}; do
    MERGE_HEADER="$MERGE_HEADER,$meta_key"
done
MERGE_HEADER="$MERGE_HEADER,post_date,post_status,post_type"
echo "$MERGE_HEADER" > "$TEMP_FILE"

# Use perl for reliable CSV parsing (perl is always available on macOS)
# ARGV[0] = custom permalinks file
# ARGV[1] = all posts file
# ARGV[2] = permalink paths file (or /dev/null when not needed)
# ARGV[3+] = additional meta field files (one per custom meta key)
export WP_HOME_URL="$HOME_URL"
export EXPORT_PERMALINK_PATH="$EXPORT_PERMALINK_PATH"
perl -e '
use strict;
use warnings;

# Simple CSV parser that handles quoted fields
sub parse_csv_line {
    my $line = shift;
    my @fields = ();
    my $field = "";
    my $in_quotes = 0;

    for (my $i = 0; $i < length($line); $i++) {
        my $char = substr($line, $i, 1);

        if ($char eq "\"") {
            if ($in_quotes && $i + 1 < length($line) && substr($line, $i + 1, 1) eq "\"") {
                $field .= "\"";
                $i++;
            } else {
                $in_quotes = !$in_quotes;
            }
        } elsif ($char eq "," && !$in_quotes) {
            push @fields, $field;
            $field = "";
        } else {
            $field .= $char;
        }
    }
    push @fields, $field;

    return @fields;
}

# Read custom permalinks (ARGV[0])
my %permalinks;
open(my $perm_fh, "<", $ARGV[0]) or die "Cannot open permalinks file: $!";
my $header = <$perm_fh>;
while (my $line = <$perm_fh>) {
    chomp $line;
    my @fields = parse_csv_line($line);
    $permalinks{$fields[0]} = $fields[1] if @fields >= 2;
}
close($perm_fh);

# Read full permalink paths (ARGV[2]) — only when EXPORT_PERMALINK_PATH=1
my %permalink_paths;
my $home_url = $ENV{WP_HOME_URL} || "";
my $export_permalink_path = $ENV{EXPORT_PERMALINK_PATH} || 0;

if ($export_permalink_path && defined $ARGV[2] && -f $ARGV[2]) {
    open(my $pp_fh, "<", $ARGV[2]) or warn "Cannot open permalink paths file: $!";
    if ($pp_fh) {
        my $pp_header = <$pp_fh>;  # skip header
        while (my $line = <$pp_fh>) {
            chomp $line;
            my @fields = parse_csv_line($line);
            if (@fields >= 2) {
                my $full_url = $fields[1];
                # Strip home_url prefix, then trim leading/trailing slashes
                $full_url =~ s|^\Q$home_url\E/?||;
                $full_url =~ s|^/||;
                $full_url =~ s|/$||;
                $permalink_paths{$fields[0]} = $full_url;
            }
        }
        close($pp_fh);
    }
}

# Read additional meta field files (ARGV[3+])
my @meta_names;
my %meta_data;  # meta_data{field_name}{post_id} = value

for (my $i = 3; $i < scalar(@ARGV); $i++) {
    open(my $fh, "<", $ARGV[$i]) or next;
    my $meta_header = <$fh>;
    chomp $meta_header;
    my @hcols = parse_csv_line($meta_header);
    my $field_name = $hcols[1] || "meta_$i";  # Column name from header
    push @meta_names, $field_name;

    while (my $line = <$fh>) {
        chomp $line;
        my @fields = parse_csv_line($line);
        if (@fields >= 2) {
            my $val = $fields[1];
            $val =~ s/,//g;  # Remove commas from values
            $meta_data{$field_name}{$fields[0]} = $val;
        }
    }
    close($fh);
}

# Process posts (ARGV[1])
open(my $posts_fh, "<", $ARGV[1]) or die "Cannot open posts file: $!";
$header = <$posts_fh>;  # Skip header
while (my $line = <$posts_fh>) {
    chomp $line;
    my @fields = parse_csv_line($line);

    if (@fields >= 6) {
        my $id = $fields[0];
        my $title = $fields[1];
        my $post_name = $fields[2];
        my $post_date = $fields[3];
        my $post_status = $fields[4];
        my $post_type = $fields[5];

        # Remove commas from title
        $title =~ s/,//g;

        # Get custom permalink (always included)
        my $custom = $permalinks{$id} || "";

        # Get full permalink path (if enabled)
        my $ppath = $export_permalink_path ? ($permalink_paths{$id} || "") : "";

        # Get additional meta field values
        my @extras = map { $meta_data{$_}{$id} || "" } @meta_names;
        my $extras_str = join(",", @extras);

        # Output: ID,title,name,custom_permalink,[permalink_path],[extras],date,status,type
        my @out = ($id, $title, $post_name, $custom);
        push @out, $ppath if $export_permalink_path;
        push @out, @extras if @extras;
        push @out, ($post_date, $post_status, $post_type);
        print join(",", @out) . "\n";

        print STDERR "Processed row: $id\n" if $ENV{DEBUG};
    }
}
close($posts_fh);
' "$CUSTOM_PERMALINKS_FILE" "$ALL_POSTS_FILE" "${PERMALINK_PATH_FILE:-/dev/null}" ${META_FILES[@]+"${META_FILES[@]}"} >> "$TEMP_FILE"

if [ ! -s "$TEMP_FILE" ]; then
    echo "❌ ERROR: Merging step failed. See $DEBUG_FILE for details." >&2
    exit 1
fi

echo "Validating CSV data for posts export..."
awk -F',' -v cols=$EXPECTED_COLUMNS 'NF == cols' "$TEMP_FILE" | tr -d "\r" > "$VALIDATED_FILE"

if [ ! -s "$VALIDATED_FILE" ]; then
    echo "❌ Error: Validated posts file is empty after enforcing column count." >&2
    exit 1
fi

# Create a timestamped final merged posts file
mv "$VALIDATED_FILE" "$FINAL_CSV_FILE"
rm -f "$TEMP_FILE"

# Count results and gather statistics
merged_count=$(( $(wc -l < "$FINAL_CSV_FILE") - 1 ))
custom_count=$(( $(wc -l < "$CUSTOM_PERMALINKS_FILE") - 1 ))

#########################################
# Export Users with Post Counts
#########################################

if [[ "$EXPORT_USERS" == "y" || "$EXPORT_USERS" == "Y" ]]; then
    USERS_FILE="$EXPORT_DIR/export_users.csv"
    USERS_WITH_COUNT_FILE="$EXPORT_DIR/export_users_with_post_counts.csv"
    
    echo -e "\n${YELLOW}Exporting user data...${NC}"
    
    if [ "$REMOTE_MODE" -eq 0 ]; then
        # Local user export with post counts
        wp user list --fields=ID,user_login,user_email,first_name,last_name,display_name,roles --format=csv --allow-root > "$USERS_FILE"
        
        if [ $? -eq 0 ] && [ -s "$USERS_FILE" ]; then
            echo "✓ User data exported"
            
            # Add post counts
            echo "Appending post counts to user data..."
            {
                read -r header
                echo "$header,post_count"
                while IFS=, read -r ID user_login user_email first_name last_name display_name roles; do
                    post_count=$(wp post list --author="$ID" --post_type="$POST_TYPES_LIST" --format=count --allow-root)
                    echo "$ID,$user_login,$user_email,$first_name,$last_name,$display_name,$roles,$post_count"
                done
            } < "$USERS_FILE" > "$USERS_WITH_COUNT_FILE"
            
            user_count=$(( $(wc -l < "$USERS_WITH_COUNT_FILE") - 1 ))
            echo "Users exported: $user_count (with post counts)"
        else
            echo "❌ Error: WP-CLI user list export failed." >&2
            exit 1
        fi
    else
        # Remote user export
        REMOTE_CMD=$(build_remote_cmd "cd \"$WP_PATH\" && wp user list --fields=ID,user_login,user_email,first_name,last_name,display_name,roles --format=csv 2>/dev/null")
        [ "$VERBOSE" -eq 1 ] && echo -e "  ${YELLOW}[SSH] $REMOTE_CMD${NC}"
        USER_DATA=$(ssh $SSH_OPTS "$SSH_CONNECTION" "$REMOTE_CMD" 2>"$SSH_STDERR" || echo "")
        
        if [ -n "$USER_DATA" ] && [[ "$USER_DATA" != *"closed"* ]]; then
            echo "$USER_DATA" > "$USERS_FILE"
            echo "✓ User data exported"
            
            echo -e "${YELLOW}Note: Skipping individual post counts due to connection limits${NC}"
            
            # Just add a post_count column with placeholder
            {
                read -r header
                echo "$header,post_count"
                while IFS=, read -r ID user_login user_email first_name last_name display_name roles; do
                    echo "$ID,$user_login,$user_email,$first_name,$last_name,$display_name,$roles,N/A"
                done
            } < "$USERS_FILE" > "$USERS_WITH_COUNT_FILE"
            
            user_count=$(( $(wc -l < "$USERS_WITH_COUNT_FILE") - 1 ))
            echo "Users exported: $user_count (post counts not available due to connection limits)"
        else
            echo "Failed to export users - connection closed"
            user_count="N/A"
        fi
    fi
else
    user_count="N/A"
fi

#########################################
# Generating Excel Output
#########################################

echo -e "\n${YELLOW}Generating Excel output...${NC}"

# Try to find Python with openpyxl installed
PYTHON_CMD=""

# Check various Python installations
for cmd in python3 /usr/bin/python3 /usr/local/bin/python3 /opt/homebrew/bin/python3; do
    if command -v $cmd &> /dev/null; then
        # Set PYTHONPATH to include user site-packages
        export PYTHONPATH="$HOME/.local/lib/python3.*/site-packages:${PYTHONPATH:-}"
        # Check if openpyxl is available (system, user, or any location)
        if $cmd -c "import openpyxl" 2>/dev/null; then
            PYTHON_CMD=$cmd
            echo "Using Python with openpyxl: $cmd"
            break
        fi
    fi
done

if [ -n "$PYTHON_CMD" ]; then
    # Build Python list of custom meta field names
    PYTHON_META_LIST="[]"
    if [ ${#CUSTOM_META_KEYS[@]} -gt 0 ]; then
        PYTHON_META_LIST="["
        for meta_key in "${CUSTOM_META_KEYS[@]}"; do
            PYTHON_META_LIST="$PYTHON_META_LIST\"$meta_key\","
        done
        PYTHON_META_LIST="$PYTHON_META_LIST]"
    fi

    cat > "$EXPORT_DIR/convert_to_excel.py" << EOF
import csv
from openpyxl import Workbook
from openpyxl.styles import Font
from openpyxl.utils import get_column_letter

wb = Workbook()
ws = wb.active
# Excel sheet names: max 31 chars, no \/:*?[]
import re
sheet_name = re.sub(r'[\\\/:*?\[\]]', '-', "${DOMAIN_SAFE}_${sheet_timestamp}")[:31]
ws.title = sheet_name

# Custom meta field names (injected from bash)
custom_meta_keys = ${PYTHON_META_LIST}

# Whether permalink_path column is present (injected from bash)
export_permalink_path = bool(${EXPORT_PERMALINK_PATH})

# Build dynamic headers
# Fixed: url, ID, post_title, post_name, custom_permalink, [permalink_path], [meta fields], post_date, post_status, post_type, edit WP Admin
headers = ["url", "ID", "post_title", "post_name", "custom_permalink"]
if export_permalink_path:
    headers.append("permalink_path")
headers.extend(custom_meta_keys)
headers.extend(["post_date", "post_status", "post_type", "edit WP Admin"])

# Column positions (1-indexed for openpyxl)
# A=url(1), B=ID(2), C=title(3), D=post_name(4), E=custom_permalink(5)
# F=permalink_path(6) when present, then meta fields, then post_date, post_status, post_type, edit link
PERMALINK_PATH_COL = 6 if export_permalink_path else None
META_START_COL = 6 + (1 if export_permalink_path else 0)
DATE_COL = META_START_COL + len(custom_meta_keys)
STATUS_COL = DATE_COL + 1
TYPE_COL = STATUS_COL + 1
EDIT_COL = TYPE_COL + 1
TOTAL_COLS = EDIT_COL

# Add base domain
ws["A1"] = "$BASE_DOMAIN"
ws["A1"].font = Font(bold=True)

# Add headers
ws.append(headers)

# Base URL formula fragment: prepend https:// only if A1 doesn't already start with it
# This lets users put either "example.com" or "https://example.com" in A1 and get correct URLs
BASE = 'IF(LEFT(\$A\$1,8)="https://",\$A\$1,IF(LEFT(\$A\$1,7)="http://",\$A\$1,"https://" & \$A\$1))'

# Read CSV and add data with formulas
with open("$FINAL_CSV_FILE", 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    row_num = 3
    for row in reader:
        # URL formula — priority: custom_permalink > permalink_path > post_name
        if export_permalink_path:
            # Col E=custom_permalink, Col F=permalink_path, Col D=post_name
            ws.cell(row=row_num, column=1).value = (
                f'=IF(E{row_num}<>"",{BASE} & "/" & E{row_num},'
                f'IF(F{row_num}<>"",{BASE} & "/" & F{row_num},'
                f'{BASE} & "/" & D{row_num}))'
            )
        else:
            ws.cell(row=row_num, column=1).value = f'=IF(E{row_num}<>"",{BASE} & "/" & E{row_num}, {BASE} & "/" & D{row_num})'
        # Fixed data columns
        ws.cell(row=row_num, column=2).value = row.get('ID', '')
        ws.cell(row=row_num, column=3).value = row.get('post_title', '')
        ws.cell(row=row_num, column=4).value = row.get('post_name', '')
        ws.cell(row=row_num, column=5).value = row.get('custom_permalink', '')
        # Permalink path column (only when present)
        if export_permalink_path and PERMALINK_PATH_COL:
            ws.cell(row=row_num, column=PERMALINK_PATH_COL).value = row.get('permalink_path', '')
        # Custom meta field columns
        for i, meta_key in enumerate(custom_meta_keys):
            ws.cell(row=row_num, column=META_START_COL + i).value = row.get(meta_key, '')
        # Remaining fixed columns
        ws.cell(row=row_num, column=DATE_COL).value = row.get('post_date', '')
        ws.cell(row=row_num, column=STATUS_COL).value = row.get('post_status', '')
        ws.cell(row=row_num, column=TYPE_COL).value = row.get('post_type', '')
        # Edit link formula
        ws.cell(row=row_num, column=EDIT_COL).value = f'=HYPERLINK({BASE} & "/wp-admin/post.php?post=" & B{row_num} & "&action=edit", "edit")'
        row_num += 1

# Auto-size columns
for col in range(1, TOTAL_COLS + 1):
    max_len = 0
    for row in ws.iter_rows(min_row=1, max_row=ws.max_row, min_col=col, max_col=col):
        try:
            if row[0].value:
                max_len = max(max_len, len(str(row[0].value)))
        except:
            pass
    ws.column_dimensions[get_column_letter(col)].width = min(max_len + 2, 50)

wb.save("$EXCEL_FILE")
print("✅ Excel file created successfully!")
EOF
    
    if $PYTHON_CMD "$EXPORT_DIR/convert_to_excel.py" 2>/dev/null; then
        echo -e "${GREEN}✅ Excel file created: export_wp_posts_${timestamp}.xlsx${NC}"
        rm -f "$EXPORT_DIR/convert_to_excel.py"
    else
        echo -e "${YELLOW}❌ Excel generation failed. Check Python and dependencies.${NC}" >&2
        rm -f "$EXPORT_DIR/convert_to_excel.py"
    fi
else
    echo -e "${YELLOW}Excel support not configured.${NC}"
    echo ""
    echo "To enable automatic Excel generation, run:"
    echo -e "  ${GREEN}./enable_excel.sh${NC}"
    echo ""
    echo "Or manually install openpyxl:"
    echo "  python3 -m pip install --user --break-system-packages openpyxl"
    echo ""
    echo "The CSV file contains all data and can be opened in Excel/Google Sheets."
fi

#########################################
# Update Configuration
#########################################

# Domain history already saved earlier (right after domain selection)

# If remote mode, save SSH connection
if [ "$REMOTE_MODE" -eq 1 ]; then
    add_ssh_to_favorites "$SSH_CONNECTION" "$WP_PATH"
fi

# Update export statistics
update_export_stats "$BASE_DOMAIN"

#########################################
# Final Cleanup and Summary 
#########################################

# Determine Excel status
if [ -f "$EXCEL_FILE" ]; then
    EXCEL_STATUS="$EXCEL_FILE"
else
    EXCEL_STATUS="Not created (install openpyxl for Excel export)"
fi

# Display final report (8 lines as in original)
echo -e "\n${GREEN}✅ Export complete!${NC}"
echo "  - Merged posts file: $FINAL_CSV_FILE"
echo "  - Excel file created: $EXCEL_STATUS"
echo "  - Total posts merged: $merged_count"
echo "  - Custom permalink entries found: $custom_count"
if [ "$EXPORT_PERMALINK_PATH" -eq 1 ] && [ -f "$PERMALINK_PATH_FILE" ]; then
    ppath_count=$(( $(wc -l < "$PERMALINK_PATH_FILE") - 1 ))
    echo "  - Permalink path entries exported: $ppath_count"
fi
for meta_key in ${CUSTOM_META_KEYS[@]+"${CUSTOM_META_KEYS[@]}"}; do
    META_KEY_SAFE=$(echo "$meta_key" | tr -c 'a-zA-Z0-9_' '_')
    META_FILE="$EXPORT_DIR/export_meta_${META_KEY_SAFE}.csv"
    if [ -f "$META_FILE" ]; then
        meta_count=$(( $(wc -l < "$META_FILE") - 1 ))
        echo "  - Meta field '$meta_key' entries: $meta_count"
    fi
done
echo "  - Total users count: $user_count"
[ "$DEBUG" -eq 1 ] && [ -f "$DEBUG_FILE" ] && echo "  - Debug log available at: $DEBUG_FILE"