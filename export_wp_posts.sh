#!/bin/bash
################################################################################
# Script Name: export_wp_posts_unified.sh
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
# Last Modified: 2025-08-11
# Version: 3.0-unified
# 
# Usage:
#   Local:  ./export_wp_posts_unified.sh
#   Remote: ./export_wp_posts_unified.sh --remote
#
# Output Files (in timestamped directory with domain name):
#   - export_all_posts.csv: Exported post details
#   - export_custom_permalinks.csv: Exported custom_permalink data
#   - export_wp_posts_<timestamp>.csv: Final merged posts file
#   - export_wp_posts_<timestamp>.xlsx: Final Excel file with formulas
#   - export_users.csv: Raw export of user details
#   - export_users_with_post_counts.csv: Users with post counts
#   - export_debug_log.txt: Debug log (if DEBUG mode enabled)
################################################################################

set -euo pipefail

# Enable DEBUG mode (set to 1 to enable debug logging)
DEBUG=0

# Expected final columns for merged posts:
# 1: ID, 2: post_title, 3: post_name, 4: custom_permalink, 5: post_date, 6: post_status, 7: post_type
EXPECTED_COLUMNS=7

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if running in remote mode
REMOTE_MODE=0
if [[ "${1:-}" == "--remote" ]] || [[ "${1:-}" == "-r" ]]; then
    REMOTE_MODE=1
fi

#########################################
# Local vs Remote Setup
#########################################

if [ "$REMOTE_MODE" -eq 0 ]; then
    echo -e "${GREEN}=== WordPress Export Script (Local Mode) ===${NC}"
    
    # Check for WP-CLI locally
    if ! command -v wp &> /dev/null; then
        echo "❌ Error: WP-CLI (wp) is not installed or not in PATH."
        echo "Please install WP-CLI before running this script."
        echo ""
        echo "To run this script on a remote server instead, use:"
        echo "  ./export_wp_posts_unified.sh --remote"
        exit 1
    fi
    
    # Set local environment
    export LC_ALL=C
    WP_CMD="wp --allow-root"
    WP_PATH="."
    
else
    echo -e "${GREEN}=== WordPress Export Script (Remote Mode) ===${NC}"
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
            
            # Auto-detect common paths based on hostname patterns
            if [[ "$SSH_CONNECTION" =~ press ]] || [[ "$SSH_CONNECTION" =~ pressable ]]; then
                SUGGESTED_PATH="/htdocs"
            elif [[ "$SSH_CONNECTION" =~ wpe ]] || [[ "$SSH_CONNECTION" =~ wpengine ]]; then
                SITE_NAME="${SSH_CONNECTION#wpe-}"
                SITE_NAME="${SITE_NAME%%.*}"
                SUGGESTED_PATH="/home/wpe-user/sites/$SITE_NAME"
            elif [[ "$SSH_CONNECTION" =~ kinsta ]]; then
                SUGGESTED_PATH="/www/[sitename]_[id]/public"
            elif [[ "$SSH_CONNECTION" =~ siteground ]]; then
                SUGGESTED_PATH="~/public_html"
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
        # Show detected host type for clarity
        if [[ "$SSH_CONNECTION" =~ press ]]; then
            echo -e "${YELLOW}Detected: Pressable host${NC}"
        elif [[ "$SSH_CONNECTION" =~ wpe ]]; then
            echo -e "${YELLOW}Detected: WP Engine host${NC}"
        elif [[ "$SSH_CONNECTION" =~ kinsta ]]; then
            echo -e "${YELLOW}Detected: Kinsta host${NC}"
        fi
        
        read -rp "Enter WordPress path (suggested: $SUGGESTED_PATH): " WP_PATH
        WP_PATH=${WP_PATH:-$SUGGESTED_PATH}
    else
        read -rp "Enter WordPress path (e.g., ~/htdocs): " WP_PATH
    fi
    
    # Set up remote WP command
    WP_CMD="ssh -T -o ServerAliveInterval=5 -o ServerAliveCountMax=3 $SSH_CONNECTION cd $WP_PATH && wp"
fi

#########################################
# Common Setup for Both Modes
#########################################

echo ""
read -rp "Enter base domain: " BASE_DOMAIN
BASE_DOMAIN=${BASE_DOMAIN:-example.com}

read -rp "Include user export? (y/n, default: y): " EXPORT_USERS
EXPORT_USERS=${EXPORT_USERS:-y}

# Create local directory with domain name
timestamp=$(date +"%Y%m%d_%H%M%S")
# Create sheet-friendly timestamp format
sheet_timestamp=$(date +"%Y-%m-%d_%H%M%S")
# Sanitize domain name for filesystem (replace . with -, remove protocol if present)
DOMAIN_SAFE=$(echo "$BASE_DOMAIN" | sed 's|https\?://||' | sed 's|/.*||' | tr '.' '-' | tr '[:upper:]' '[:lower:]')
EXPORT_DIR="!export_wp_posts_${timestamp}_${DOMAIN_SAFE}"
mkdir -p "$EXPORT_DIR"

# Define file paths
ALL_POSTS_FILE="$EXPORT_DIR/export_all_posts.csv"
CUSTOM_PERMALINKS_FILE="$EXPORT_DIR/export_custom_permalinks.csv"
TEMP_FILE="$EXPORT_DIR/export_wp_posts_temp.csv"
VALIDATED_FILE="$EXPORT_DIR/export_wp_posts_validated.csv"
FINAL_CSV_FILE="$EXPORT_DIR/export_wp_posts_${timestamp}.csv"
EXCEL_FILE="$EXPORT_DIR/export_wp_posts_${timestamp}.xlsx"
DEBUG_FILE="$EXPORT_DIR/export_debug_log.txt"

# Clear previous export files
> "$ALL_POSTS_FILE"
> "$CUSTOM_PERMALINKS_FILE"
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
    POST_TYPES_RAW=$(ssh -T -o ServerAliveInterval=5 -o ServerAliveCountMax=3 "$SSH_CONNECTION" \
        "cd $WP_PATH && wp post-type list --field=name --public=true --format=csv 2>/dev/null" 2>/dev/null || echo "")
    
    # Clean output
    POST_TYPES_RAW=$(echo "$POST_TYPES_RAW" | tr -d '\r' | grep -v "^$" | grep -v "Connection")
    
    if [ -z "$POST_TYPES_RAW" ] || [[ "$POST_TYPES_RAW" == *"Error"* ]]; then
        echo "Method 2: Trying with simpler format..."
        POST_TYPES_RAW=$(ssh -T "$SSH_CONNECTION" \
            "cd $WP_PATH && wp post-type list --field=name 2>/dev/null | grep -v attachment" 2>/dev/null || echo "")
        POST_TYPES_RAW=$(echo "$POST_TYPES_RAW" | tr -d '\r' | grep -v "^$")
    fi
    
    if [ -z "$POST_TYPES_RAW" ] || [[ "$POST_TYPES_RAW" == *"Error"* ]]; then
        echo "Method 3: Trying PHP evaluation..."
        POST_TYPES_RAW=$(ssh -T "$SSH_CONNECTION" \
            "cd $WP_PATH && wp eval 'foreach(get_post_types(array(\"public\"=>true)) as \$t) if(\$t!=\"attachment\") echo \$t.\"\n\";'" 2>/dev/null || echo "")
        POST_TYPES_RAW=$(echo "$POST_TYPES_RAW" | tr -d '\r' | grep -v "^$")
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
        EXPORT_OUTPUT=$(ssh -T -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -o ConnectTimeout=30 "$SSH_CONNECTION" \
            "cd $WP_PATH && wp post list --post_type=$post_type --post_status=any --fields=ID,post_title,post_name,post_date,post_status,post_type --format=csv 2>/dev/null" 2>/dev/null || echo "FAILED")
        
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
        ssh -T "$SSH_CONNECTION" "cd $WP_PATH && wp post list --post_type=$post_type --post_status=any --fields=ID,custom_permalink --meta_key=custom_permalink --format=csv --quiet 2>/dev/null | tail -n +2" >> "$CUSTOM_PERMALINKS_FILE" 2>/dev/null || true
    fi
done

if [ ! -s "$CUSTOM_PERMALINKS_FILE" ]; then
    echo "Warning: $CUSTOM_PERMALINKS_FILE is empty. No custom permalinks found." >&2
fi

#########################################
# Merge and Process Data  
#########################################

echo -e "\n${YELLOW}Merging posts data using improved CSV parser...${NC}"

# Create the header for the temp file
echo "ID,post_title,post_name,custom_permalink,post_date,post_status,post_type" > "$TEMP_FILE"

# Use perl for reliable CSV parsing (perl is always available on macOS)
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

# Read custom permalinks
my %permalinks;
open(my $perm_fh, "<", $ARGV[0]) or die "Cannot open permalinks file: $!";
my $header = <$perm_fh>;
while (my $line = <$perm_fh>) {
    chomp $line;
    my @fields = parse_csv_line($line);
    $permalinks{$fields[0]} = $fields[1] if @fields >= 2;
}
close($perm_fh);

# Process posts
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
        
        # Get custom permalink
        my $custom = $permalinks{$id} || "";
        
        # Output CSV line
        print "$id,$title,$post_name,$custom,$post_date,$post_status,$post_type\n";
        
        print STDERR "Processed row: $id\n" if $ENV{DEBUG};
    }
}
close($posts_fh);
' "$CUSTOM_PERMALINKS_FILE" "$ALL_POSTS_FILE" >> "$TEMP_FILE"

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
        USER_DATA=$(ssh -T -o ServerAliveInterval=5 "$SSH_CONNECTION" "cd $WP_PATH && wp user list --fields=ID,user_login,user_email,first_name,last_name,display_name,roles --format=csv 2>/dev/null" 2>/dev/null || echo "")
        
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
    cat > "$EXPORT_DIR/convert_to_excel.py" << EOF
import csv
from openpyxl import Workbook
from openpyxl.styles import Font
from openpyxl.utils import get_column_letter

wb = Workbook()
ws = wb.active
ws.title = "${DOMAIN_SAFE}_${sheet_timestamp}"

# Add base domain
ws["A1"] = "$BASE_DOMAIN"
ws["A1"].font = Font(bold=True)

# Add headers
headers = ["url", "ID", "post_title", "post_name", "custom_permalink", "post_date", "post_status", "post_type", "edit WP Admin"]
ws.append(headers)

# Read CSV and add data with formulas
with open("$FINAL_CSV_FILE", 'r', encoding='utf-8') as f:
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
echo "  - Total users count: $user_count"
[ "$DEBUG" -eq 1 ] && [ -f "$DEBUG_FILE" ] && echo "  - Debug log available at: $DEBUG_FILE"