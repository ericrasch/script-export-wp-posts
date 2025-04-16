
#!/bin/bash
################################################################################
# Script Name: export_wp_posts.sh
#
# Description:
#   Exports WordPress posts and custom permalink information using wp-cli,
#   then merges the data into a final CSV with columns in the order:
#   ID, post_title, post_name, custom_permalink, post_date, post_status, post_type.
#
#   Additionally, this script can export a comprehensive list of WordPress users
#   with their details and appends each user's post count across all public
#   post types (excluding attachments). User export is optional and prompted at runtime.
#
#   The script also generates a final Excel (.xlsx) file with the following:
#     - Row 1: editable base domain
#     - Row 2: headers
#     - Column A: formula-generated URLs
#     - Column J: WP Admin edit links
#
# Author: Eric Rasch
#   GitHub: https://github.com/ericrasch/reset-wp-symlinks
# Date Created: 2025-02-26
# Last Modified: 2025-04-16
# Version: 1.3
#
# Usage:
#   1. Place this script in your working folder.
#   2. Make it executable: chmod +x export_wp_posts.sh
#   3. Run the script: ./export_wp_posts.sh
#      - You will be prompted for a base domain and user export preference.
#
# Output Files (in the "!export_wp_posts" folder):
#   - export_all_posts.csv: Exported post details.
#   - export_custom_permalinks.csv: Exported custom_permalink data.
#   - export_wp_posts_<timestamp>.csv: Final merged posts file.
#   - export_wp_posts_<timestamp>.xlsx: Final Excel file with formulas.
#   - export_users.csv: Raw export of user details.
#   - export_users_with_post_counts.csv: User export with appended post counts.
#   - export_debug_log.txt: Debug log (if DEBUG mode is enabled).
################################################################################

# Set a consistent locale
export LC_ALL=C

# Enable DEBUG mode (set to 1 to enable debug logging)
DEBUG=1

# Define export folder and create it if it doesn't exist
EXPORT_DIR="!export_wp_posts"
mkdir -p "$EXPORT_DIR"

# Define file names (all with "export_" prefix inside the export folder)
timestamp=$(date +"%Y%m%d_%H%M%S")
ALL_POSTS_FILE="$EXPORT_DIR/export_all_posts.csv"
CUSTOM_PERMALINKS_FILE="$EXPORT_DIR/export_custom_permalinks.csv"
TEMP_FILE="$EXPORT_DIR/export_wp_posts_temp.csv"
VALIDATED_FILE="$EXPORT_DIR/export_wp_posts_validated.csv"
FINAL_CSV_FILE="$EXPORT_DIR/export_wp_posts_${timestamp}.csv"
EXCEL_FILE="$EXPORT_DIR/export_wp_posts_${timestamp}.xlsx"
DEBUG_FILE="$EXPORT_DIR/export_debug_log.txt"

# Expected final columns for merged posts:
# 1: ID, 2: post_title, 3: post_name, 4: custom_permalink, 5: post_date, 6: post_status, 7: post_type
EXPECTED_COLUMNS=7

read -p "Enter the base domain (default: example.com): " BASE_DOMAIN
BASE_DOMAIN=${BASE_DOMAIN:-example.com}
read -p "Include user export and post counts? (y/n, default: y): " EXPORT_USERS
EXPORT_USERS=${EXPORT_USERS:-y}

# Dynamically generate public post types (excluding "attachment")
POST_TYPES=($(wp post-type list --fields=name,public --allow-root --format=csv | tail -n +2 | awk -F, '$2=="1" && $1!="attachment" {print $1}'))
# Create a comma-separated list of public post types for user post counts
POST_TYPES_LIST=$(IFS=,; echo "${POST_TYPES[*]}")

# Clear previous export files
> "$ALL_POSTS_FILE"
> "$CUSTOM_PERMALINKS_FILE"
[ "$DEBUG" -eq 1 ] && > "$DEBUG_FILE"

#########################################
# Export Posts and Custom Permalink Data
#########################################

echo "Exporting all posts..."
FIRST=1
for POST_TYPE in "${POST_TYPES[@]}"; do
    echo "  Exporting post type: $POST_TYPE"
    if [ "$FIRST" -eq 1 ]; then
        wp post list --post_type="$POST_TYPE" --post_status=any           --fields=ID,post_title,post_name,post_date,post_status,post_type           --format=csv --allow-root >> "$ALL_POSTS_FILE"
        FIRST=0
    else
        wp post list --post_type="$POST_TYPE" --post_status=any           --fields=ID,post_title,post_name,post_date,post_status,post_type           --format=csv --allow-root | tail -n +2 >> "$ALL_POSTS_FILE"
    fi
    if [ $? -ne 0 ]; then
      echo "❌ Error: WP-CLI export failed for post type $POST_TYPE" >&2
      exit 1
    fi
done

if [ ! -s "$ALL_POSTS_FILE" ]; then
    echo "❌ Error: $ALL_POSTS_FILE is empty. Exiting." >&2
    exit 1
fi

echo "Exporting custom permalinks..."
for POST_TYPE in "${POST_TYPES[@]}"; do
    echo "  Exporting custom_permalink for post type: $POST_TYPE"
    wp post list --post_type="$POST_TYPE" --post_status=any       --fields=ID,custom_permalink --meta_key=custom_permalink       --format=csv --allow-root | tail -n +2 >> "$CUSTOM_PERMALINKS_FILE"
    if [ $? -ne 0 ]; then
      echo "❌ Error: WP-CLI export (custom_permalink) failed for post type $POST_TYPE" >&2
      exit 1
    fi
done

if [ ! -s "$CUSTOM_PERMALINKS_FILE" ]; then
    echo "Warning: $CUSTOM_PERMALINKS_FILE is empty. No custom permalinks found." >&2
fi

echo "Merging posts data using AWK..."
awk -F',' -v debug="$DEBUG" '
    NR==FNR {
        # Read custom permalinks: key = post ID, value = custom_permalink
        perm[$1] = $2;
        next;
    }
    {
        id = $1;
        n = NF;
        # Assume fields are:
        # 1: ID, 2 to (n-4): post_title, (n-3): post_name, (n-2): post_date, (n-1): post_status, n: post_type
        post_name   = $(n-3);
        post_date   = $(n-2);
        post_status = $(n-1);
        post_type   = $(n);
        # Reassemble post_title from fields 2 through (n-4)
        title = $2;
        for(i = 3; i <= n-4; i++){
            title = title " " $i;
        }
        # Remove any commas from post_title (sanitizing special characters)
        gsub(/,/, "", title);
        # Retrieve custom_permalink (if any)
        custom = (id in perm) ? perm[id] : "";
        if(debug=="1") {
            print "DEBUG: Processing ID: " id > "/dev/stderr"
        } else {
            print "Processed row: " id > "/dev/stderr"
        }
        # Output merged row: ID, post_title, post_name, custom_permalink, post_date, post_status, post_type
        print id "," title "," post_name "," custom "," post_date "," post_status "," post_type;
    }
' "$CUSTOM_PERMALINKS_FILE" "$ALL_POSTS_FILE" > "$TEMP_FILE"

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

# Create a timestamped final merged posts file; remove the un-timestamped version
mv "$VALIDATED_FILE" "$FINAL_CSV_FILE"
rm -f "$TEMP_FILE"
#########################################
# Export Users with Post Counts
#########################################

echo "Exporting user data..."
wp user list --fields=ID,user_login,user_email,first_name,last_name,display_name,roles --format=csv --allow-root > "$USERS_FILE"
if [ $? -ne 0 ]; then
    echo "❌ Error: WP-CLI user list export failed." >&2
    exit 1
fi

if [ ! -s "$USERS_FILE" ]; then
    echo "❌ Error: User export file is empty. Exiting." >&2
    exit 1
fi

echo "Appending post counts to user data..."
{
  read -r header
  echo "$header,post_count"
  while IFS=, read -r ID user_login user_email first_name last_name display_name roles; do
      # Count posts for this user across all public post types using the comma-separated list
      post_count=$(wp post list --author="$ID" --post_type="$POST_TYPES_LIST" --format=count --allow-root)
      echo "$ID,$user_login,$user_email,$first_name,$last_name,$display_name,$roles,$post_count"
  done
} < "$USERS_FILE" > "$USERS_WITH_COUNT_FILE"

if [ ! -s "$USERS_WITH_COUNT_FILE" ]; then
    echo "❌ Error: User export with post counts is empty." >&2
    exit 1
fi

#########################################
# Generating Excel Output
#########################################
echo "Generating Excel output..."
python3 - <<EOF
try:
    import pandas as pd
    from openpyxl import Workbook
    from openpyxl.styles import Font
    from openpyxl.utils import get_column_letter

    df = pd.read_csv("$FINAL_CSV_FILE")
    wb = Workbook()
    ws = wb.active
    ws.title = "export_wp_posts"
    ws["A1"] = "$BASE_DOMAIN"
    ws["A1"].font = Font(bold=True)
    headers = ["url", "ID", "post_title", "post_name", "custom_permalink", "post_date", "post_status", "post_type", "edit WP Admin"]
    ws.append(headers)

    for idx, row in enumerate(df.itertuples(index=False), start=3):
        ws.cell(row=idx, column=1).value = f'=IF($E{idx}<>"","https://" & $A$1 & "/" & $E{idx}, "https://" & $A$1 & "/" & $D{idx})'
        for j, val in enumerate(row, start=2):
            ws.cell(row=idx, column=j, value=val)
        ws.cell(row=idx, column=9).value = f'=IF($B{idx}<>"", HYPERLINK("https://" & $A$1 & "/wp-admin/post.php?post=" & $B{idx} & "&action=edit", "edit post " & $B{idx}), "")'

    for col in range(1, 11):
        max_len = 0
        for row in ws.iter_rows(min_row=1, max_row=ws.max_row, min_col=col, max_col=col):
            val = str(row[0].value) if row[0].value else ""
            if len(val) > max_len:
                max_len = len(val)
        ws.column_dimensions[get_column_letter(col)].width = max_len + 2

    wb.save("$EXCEL_FILE")
except Exception as e:
    print("❌ Excel generation failed:", e)
    exit(1)
EOF

if [ $? -ne 0 ]; then
    echo "❌ Error: Excel export failed. Check Python and dependencies." >&2
    exit 1
fi

merged_count=$(wc -l < "$FINAL_CSV_FILE")
custom_count=$(wc -l < "$CUSTOM_PERMALINKS_FILE")
user_count=$(($(wc -l < "$USERS_WITH_COUNT_FILE") - 1))

echo "✅ Export complete!"
echo "  - Merged posts file: $FINAL_CSV_FILE"
echo "  - Excel file created: $EXCEL_FILE"
echo "  - Total posts merged: $merged_count"
echo "  - Custom permalink entries found: $custom_count"
echo "  - Total users count: $user_count"
[ "$DEBUG" -eq 1 ] && echo "  - Debug log available at: $DEBUG_FILE"
