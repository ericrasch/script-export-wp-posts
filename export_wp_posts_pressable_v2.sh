#!/bin/bash
################################################################################
# Script Name: export_wp_posts_pressable_v2.sh
#
# Description:
#   Improved version for Pressable and restricted hosts that exports all
#   columns and post types from the original script.
#
# Version: 2.0-pressable
################################################################################

set -euo pipefail

# Enable DEBUG mode (set to 1 to enable debug logging)
DEBUG=0

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

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

echo -e "${GREEN}=== WordPress Export for Restricted Hosts (v2) ===${NC}"
echo "This script exports all post types and custom permalinks."

# Check for SSH config hosts
SSH_HOSTS=($(parse_ssh_config))

if [ ${#SSH_HOSTS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Available SSH hosts:${NC}"
    for i in "${!SSH_HOSTS[@]}"; do
        echo "  $((i+1)). ${SSH_HOSTS[$i]}"
    done
    echo "  0. Enter custom connection"
    
    read -rp $'\nSelect a host (1-'${#SSH_HOSTS[@]}') or 0 for custom: ' HOST_CHOICE
    
    if [[ "$HOST_CHOICE" =~ ^[1-9][0-9]*$ ]] && [ "$HOST_CHOICE" -le "${#SSH_HOSTS[@]}" ]; then
        SSH_CONNECTION="${SSH_HOSTS[$((HOST_CHOICE-1))]}"
        echo -e "${GREEN}Using: $SSH_CONNECTION${NC}"
        
        # Auto-detect common paths
        if [[ "$SSH_CONNECTION" =~ pressable ]]; then
            SUGGESTED_PATH="/htdocs"
        elif [[ "$SSH_CONNECTION" =~ wpengine ]]; then
            SUGGESTED_PATH="/home/wpe-user/sites/${SSH_CONNECTION%%.*}"
        else
            SUGGESTED_PATH="~/public_html"
        fi
    else
        read -rp "Enter SSH user@host: " SSH_CONNECTION
        SUGGESTED_PATH=""
    fi
else
    read -rp "Enter SSH user@host: " SSH_CONNECTION
    SUGGESTED_PATH=""
fi

# Get WordPress path
if [ -n "$SUGGESTED_PATH" ]; then
    read -rp "Enter WordPress path (suggested: $SUGGESTED_PATH): " WP_PATH
    WP_PATH=${WP_PATH:-$SUGGESTED_PATH}
else
    read -rp "Enter WordPress path (e.g., ~/htdocs): " WP_PATH
fi

read -rp "Enter base domain: " BASE_DOMAIN
BASE_DOMAIN=${BASE_DOMAIN:-example.com}

read -rp "Include user export? (y/n, default: y): " EXPORT_USERS
EXPORT_USERS=${EXPORT_USERS:-y}

# Create local directory
timestamp=$(date +"%Y%m%d_%H%M%S")
EXPORT_DIR="!export_wp_posts_${timestamp}"
mkdir -p "$EXPORT_DIR"

# Define file paths
FINAL_CSV_FILE="$EXPORT_DIR/export_wp_posts_${timestamp}.csv"
DEBUG_FILE="$EXPORT_DIR/export_debug_log.txt"
[ "$DEBUG" -eq 1 ] && > "$DEBUG_FILE"

echo -e "\n${YELLOW}Discovering post types...${NC}"

# Initialize POST_TYPES array
POST_TYPES=()

# Try different methods to get post types
echo "Attempting to discover post types..."

# Method 1: Simple approach - just get the names column
echo "Method 1: Trying standard discovery..."
POST_TYPES_RAW=$(ssh -T -o ServerAliveInterval=5 -o ServerAliveCountMax=3 "$SSH_CONNECTION" \
    "cd $WP_PATH && wp post-type list --field=name --public=true --format=csv 2>/dev/null" 2>/dev/null || echo "")

# Clean output
POST_TYPES_RAW=$(echo "$POST_TYPES_RAW" | tr -d '\r' | grep -v "^$" | grep -v "Connection")

if [ -z "$POST_TYPES_RAW" ] || [[ "$POST_TYPES_RAW" == *"Error"* ]]; then
    echo "Method 2: Trying with simpler format..."
    # Try just listing without filters
    POST_TYPES_RAW=$(ssh -T "$SSH_CONNECTION" \
        "cd $WP_PATH && wp post-type list --field=name 2>/dev/null | grep -v attachment" 2>/dev/null || echo "")
    POST_TYPES_RAW=$(echo "$POST_TYPES_RAW" | tr -d '\r' | grep -v "^$")
fi

if [ -z "$POST_TYPES_RAW" ] || [[ "$POST_TYPES_RAW" == *"Error"* ]]; then
    echo "Method 3: Trying PHP evaluation..."
    # Method 3: Use wp eval to get post types
    POST_TYPES_RAW=$(ssh -T "$SSH_CONNECTION" \
        "cd $WP_PATH && wp eval 'foreach(get_post_types(array(\"public\"=>true)) as \$t) if(\$t!=\"attachment\") echo \$t.\"\n\";'" 2>/dev/null || echo "")
    POST_TYPES_RAW=$(echo "$POST_TYPES_RAW" | tr -d '\r' | grep -v "^$")
fi

if [ -n "$POST_TYPES_RAW" ] && [[ "$POST_TYPES_RAW" != *"closed"* ]] && [[ "$POST_TYPES_RAW" != *"Error"* ]]; then
    # Parse discovered post types
    echo "Raw output: $POST_TYPES_RAW" # Debug line
    while IFS= read -r type; do
        # Clean up the type name
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
    
    # Show what command the user can run manually
    echo -e "\n${YELLOW}Tip: You can check post types manually by SSHing in and running:${NC}"
    echo "  wp post-type list --public=true"
    echo ""
    
    # Ask if user wants to add custom post types
    read -rp "Do you know your custom post types? (y/n): " ADD_CUSTOM
    if [[ "$ADD_CUSTOM" == "y" || "$ADD_CUSTOM" == "Y" ]]; then
        echo "Enter post types one per line (press Enter twice when done):"
        echo "Example: commercial, article, press_release, etc."
        
        while true; do
            read -rp "> " type
            if [ -z "$type" ]; then
                break
            fi
            type=$(echo "$type" | xargs | tr -d ',') # clean up
            if [ -n "$type" ] && [[ ! " ${POST_TYPES[@]} " =~ " ${type} " ]]; then
                POST_TYPES+=("$type")
                echo "  Added: $type"
            fi
        done
    fi
fi

# Ensure we have at least some post types
if [ ${#POST_TYPES[@]} -eq 0 ]; then
    echo -e "${RED}Error: No post types defined. Using defaults.${NC}"
    POST_TYPES=("post" "page")
fi

echo "Will export post types: ${POST_TYPES[*]}"

# Export posts with all required fields
POST_FILE="$EXPORT_DIR/export_all_posts.csv"
echo "ID,post_title,post_name,post_date,post_status,post_type" > "$POST_FILE"

echo -e "\n${YELLOW}Exporting posts...${NC}"
echo "Note: Pressable may close connections during large exports. This is normal."

for post_type in "${POST_TYPES[@]}"; do
    echo "  Exporting $post_type..."
    
    # Use shorter SSH sessions with keepalive settings and -T to disable terminal
    EXPORT_OUTPUT=$(ssh -T -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -o ConnectTimeout=30 "$SSH_CONNECTION" \
        "cd $WP_PATH && wp post list --post_type=$post_type --post_status=any --fields=ID,post_title,post_name,post_date,post_status,post_type --format=csv 2>/dev/null" 2>/dev/null || echo "FAILED")
    
    if [[ "$EXPORT_OUTPUT" != "FAILED" ]] && [[ -n "$EXPORT_OUTPUT" ]]; then
        # Skip the header line and append to file
        echo "$EXPORT_OUTPUT" | tail -n +2 >> "$POST_FILE"
        POST_COUNT=$(echo "$EXPORT_OUTPUT" | wc -l)
        echo "    ✓ Exported $((POST_COUNT - 1)) $post_type(s)"
    else
        echo "    ✗ Failed to export $post_type - connection closed or type doesn't exist"
    fi
done

# Export custom permalinks
PERMALINK_FILE="$EXPORT_DIR/export_custom_permalinks.csv"
echo "ID,custom_permalink" > "$PERMALINK_FILE"

echo -e "\n${YELLOW}Exporting custom permalinks...${NC}"
for post_type in "${POST_TYPES[@]}"; do
    echo "  Checking custom permalinks for $post_type..."
    ssh -T "$SSH_CONNECTION" "cd $WP_PATH && wp post list --post_type=$post_type --post_status=any --fields=ID,custom_permalink --meta_key=custom_permalink --format=csv --quiet 2>/dev/null | tail -n +2" >> "$PERMALINK_FILE" 2>/dev/null || true
done

# Process and merge data
echo -e "\n${YELLOW}Processing data...${NC}"

# Create final CSV with all 7 columns
FINAL_CSV="$EXPORT_DIR/export_wp_posts_${timestamp}.csv"
echo "ID,post_title,post_name,custom_permalink,post_date,post_status,post_type" > "$FINAL_CSV"

# Merge using awk (same logic as original script)
awk -F',' '
    NR==FNR && FNR>1 {
        # Read custom permalinks
        perm[$1] = $2;
        next
    }
    FNR>1 {
        # Process posts
        id = $1;
        title = $2;
        post_name = $3;
        post_date = $4;
        post_status = $5;
        post_type = $6;
        
        # Remove commas from title
        gsub(/,/, "", title);
        
        # Get custom permalink if exists
        custom = (id in perm) ? perm[id] : "";
        
        # Output all 7 columns
        print id "," title "," post_name "," custom "," post_date "," post_status "," post_type
    }
' "$PERMALINK_FILE" "$POST_FILE" >> "$FINAL_CSV"

# Count results and gather statistics
merged_count=$(( $(wc -l < "$FINAL_CSV") - 1 ))
custom_count=$(( $(wc -l < "$PERMALINK_FILE") - 1 ))

# Note: Will set user_count later if users are exported
echo -e "\n${YELLOW}Preparing final report...${NC}"

# Export users if requested
if [[ "$EXPORT_USERS" == "y" || "$EXPORT_USERS" == "Y" ]]; then
    USERS_FILE="$EXPORT_DIR/export_users.csv"
    USERS_WITH_COUNT_FILE="$EXPORT_DIR/export_users_with_post_counts.csv"
    
    echo -e "\n${YELLOW}Exporting users...${NC}"
    
    # Use -T flag to disable pseudo-terminal allocation
    USER_DATA=$(ssh -T -o ServerAliveInterval=5 "$SSH_CONNECTION" "cd $WP_PATH && wp user list --fields=ID,user_login,user_email,first_name,last_name,display_name,roles --format=csv 2>/dev/null" 2>/dev/null || echo "")
    
    if [ -n "$USER_DATA" ] && [[ "$USER_DATA" != *"closed"* ]]; then
        echo "$USER_DATA" > "$USERS_FILE"
        echo "✓ User data exported"
        
        # For post counts, we'll skip the individual SSH calls to avoid terminal issues
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
    fi
fi

# Generate Excel file
echo -e "\n${YELLOW}Generating Excel file...${NC}"

# First, let's try to find a working Python with openpyxl
PYTHON_CMD=""
for cmd in python3 python /usr/bin/python3 /usr/local/bin/python3; do
    if command -v $cmd &> /dev/null && $cmd -c "import openpyxl" 2>/dev/null; then
        PYTHON_CMD=$cmd
        break
    fi
done

if [ -n "$PYTHON_CMD" ]; then
    cat > "$EXPORT_DIR/convert_to_excel.py" << EOF
import csv
from openpyxl import Workbook
from openpyxl.styles import Font
from openpyxl.utils import get_column_letter

wb = Workbook()
ws = wb.active
ws.title = "Posts"

# Add base domain
ws["A1"] = "$BASE_DOMAIN"
ws["A1"].font = Font(bold=True)

# Add headers
headers = ["url", "ID", "post_title", "post_name", "custom_permalink", "post_date", "post_status", "post_type", "edit"]
ws.append(headers)

# Read CSV and add data with formulas
with open("$FINAL_CSV", 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    row_num = 3
    for row in reader:
        # URL formula
        ws.cell(row=row_num, column=1).value = f'=IF(E{row_num}<>"","https://" & \$A\$1 & "/" & E{row_num}, "https://" & \$A\$1 & "/" & D{row_num})'
        # Data
        ws.cell(row=row_num, column=2).value = row['ID']
        ws.cell(row=row_num, column=3).value = row['post_title']
        ws.cell(row=row_num, column=4).value = row['post_name']
        ws.cell(row=row_num, column=5).value = row['custom_permalink']
        ws.cell(row=row_num, column=6).value = row['post_date']
        ws.cell(row=row_num, column=7).value = row['post_status']
        ws.cell(row=row_num, column=8).value = row['post_type']
        # Edit link
        ws.cell(row=row_num, column=9).value = f'=HYPERLINK("https://" & \$A\$1 & "/wp-admin/post.php?post=" & B{row_num} & "&action=edit", "edit")'
        row_num += 1

# Auto-size columns
for col in range(1, 10):
    max_len = 0
    for row in ws.iter_rows(min_row=1, max_row=ws.max_row, min_col=col, max_col=col):
        try:
            if row[0].value:
                max_len = max(max_len, len(str(row[0].value)))
        except:
            pass
    ws.column_dimensions[get_column_letter(col)].width = min(max_len + 2, 50)

wb.save("$EXPORT_DIR/export_wp_posts_${timestamp}.xlsx")
print("✅ Excel file created successfully!")
EOF
    
    $PYTHON_CMD "$EXPORT_DIR/convert_to_excel.py" 2>/dev/null && {
        echo -e "${GREEN}Excel file created: export_wp_posts_${timestamp}.xlsx${NC}"
    } || {
        echo -e "${YELLOW}Excel generation skipped (openpyxl not available)${NC}"
        echo "To enable Excel export, install openpyxl:"
        echo "  1. Create a virtual environment: python3 -m venv ~/venv"
        echo "  2. Activate it: source ~/venv/bin/activate"
        echo "  3. Install: pip install openpyxl"
        echo "  4. Run: python ~/venv/bin/python $EXPORT_DIR/convert_to_excel.py"
    }
else
    echo -e "${YELLOW}Python not found. Excel generation skipped.${NC}"
    echo "CSV file contains all data and can be opened in Excel/Google Sheets."
fi

# Final summary report with all details
EXCEL_FILE="$EXPORT_DIR/export_wp_posts_${timestamp}.xlsx"

# Determine user count
if [[ "$EXPORT_USERS" == "y" || "$EXPORT_USERS" == "Y" ]] && [ -f "$USERS_WITH_COUNT_FILE" ]; then
    user_count=$(( $(wc -l < "$USERS_WITH_COUNT_FILE") - 1 ))
else
    user_count="N/A"
fi

# Check if Excel was created
if [ -f "$EXCEL_FILE" ]; then
    EXCEL_STATUS="$EXCEL_FILE"
else
    EXCEL_STATUS="Not created (install openpyxl for Excel export)"
fi

echo -e "\n${GREEN}✅ Export complete!${NC}"
echo "  - Merged posts file: $FINAL_CSV_FILE"
echo "  - Excel file created: $EXCEL_STATUS"
echo "  - Total posts merged: $merged_count"
echo "  - Custom permalink entries found: $custom_count"
echo "  - Total users count: $user_count"
[ "$DEBUG" -eq 1 ] && [ -f "$DEBUG_FILE" ] && echo "  - Debug log available at: $DEBUG_FILE"