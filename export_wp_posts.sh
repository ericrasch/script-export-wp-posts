
#!/bin/bash
################################################################################
# Script Name: export_wp_posts.sh
#
# Description:
#   Exports WordPress posts and custom permalink information using wp-cli,
#   then merges the data into a final CSV with columns in the order:
#   ID, post_title, post_name, custom_permalink, post_date, post_status, post_type.
#
#   Additionally, this script exports a comprehensive list of WordPress users
#   with their details and appends each user's post count across all public
#   post types (excluding attachments).
#
# Author: Eric Rasch
#   GitHub: https://github.com/ericrasch/reset-wp-symlinks
# Date Created: 2025-02-26
# Last Modified: 2025-03-11
# Version: 1.2
#
# Usage:
#   1. Place this script in your working folder.
#   2. Make it executable: chmod +x export_wp_posts.sh
#   3. Run the script: ./export_wp_posts.sh
#
# Output Files (in the "!export_wp_posts" folder):
#   - export_all_posts.csv: Exported post details.
#   - export_custom_permalinks.csv: Exported custom_permalink data.
#   - Final merged posts file: export_wp_posts_<timestamp>.csv
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
ALL_POSTS_FILE="$EXPORT_DIR/export_all_posts.csv"
CUSTOM_PERMALINKS_FILE="$EXPORT_DIR/export_custom_permalinks.csv"
TEMP_FILE="$EXPORT_DIR/export_wp_posts_temp.csv"
VALIDATED_FILE="$EXPORT_DIR/export_wp_posts_validated.csv"
DEBUG_FILE="$EXPORT_DIR/export_debug_log.txt"

# Expected final columns for merged posts:
# 1: ID, 2: post_title, 3: post_name, 4: custom_permalink, 5: post_date, 6: post_status, 7: post_type
EXPECTED_COLUMNS=7

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
        wp post list --post_type="$POST_TYPE" --post_status=any \
          --fields=ID,post_title,post_name,post_date,post_status,post_type \
          --format=csv --allow-root >> "$ALL_POSTS_FILE"
        FIRST=0
    else
        wp post list --post_type="$POST_TYPE" --post_status=any \
          --fields=ID,post_title,post_name,post_date,post_status,post_type \
          --format=csv --allow-root | tail -n +2 >> "$ALL_POSTS_FILE"
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
    wp post list --post_type="$POST_TYPE" --post_status=any \
      --fields=ID,custom_permalink --meta_key=custom_permalink \
      --format=csv --allow-root | tail -n +2 >> "$CUSTOM_PERMALINKS_FILE"
    if [ $? -ne 0 ]; then
      echo "❌ Error: WP-CLI export (custom_permalink) failed for post type $POST_TYPE" >&2
      exit 1
    fi
done

if [ ! -s "$CUSTOM_PERMALINKS_FILE" ]; then
    echo "Warning: $CUSTOM_PERMALINKS_FILE is empty. No custom permalinks found." >&2
fi

echo "Merging posts data using AWK (reassembling post_title)..."
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
timestamp=$(date +%Y%m%d_%H%M%S)
mv "$VALIDATED_FILE" "$EXPORT_DIR/export_wp_posts_${timestamp}.csv"
rm -f "$TEMP_FILE"

FINAL_POSTS_OUTPUT="$EXPORT_DIR/export_wp_posts_${timestamp}.csv"

#########################################
# Export Users with Post Counts
#########################################

echo "Exporting user data..."
wp user list --fields=ID,user_login,user_email,first_name,last_name,display_name,roles --format=csv --allow-root > "$EXPORT_DIR/export_users.csv"
if [ $? -ne 0 ]; then
    echo "❌ Error: WP-CLI user list export failed." >&2
    exit 1
fi

if [ ! -s "$EXPORT_DIR/export_users.csv" ]; then
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
} < "$EXPORT_DIR/export_users.csv" > "$EXPORT_DIR/export_users_with_post_counts.csv"

if [ ! -s "$EXPORT_DIR/export_users_with_post_counts.csv" ]; then
    echo "❌ Error: User export with post counts is empty." >&2
    exit 1
fi

#########################################
# Final Summary
#########################################

# Summary output: count number of merged posts entries and user export entries
merged_count=$(wc -l < "$FINAL_POSTS_OUTPUT")
custom_count=$(wc -l < "$CUSTOM_PERMALINKS_FILE")
user_count=$(($(wc -l < "$EXPORT_DIR/export_users_with_post_counts.csv") - 1))

echo "✅ Export complete!"
echo "  - Merged posts file: $FINAL_POSTS_OUTPUT"
echo "  - Total posts merged: $merged_count"
echo "  - Custom permalink entries found: $custom_count"
echo "  - Total users count: $user_count"
[ "$DEBUG" -eq 1 ] && echo "  - Debug log available at: $DEBUG_FILE"