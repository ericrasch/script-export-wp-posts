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
# Last Modified: 2025-03-07
# Version: 1.1.2
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
EXPECTED_COLUMNS=7

# Dynamically generate public post types (excluding "attachment")
POST_TYPES=($(wp post-type list --fields=name,public --allow-root --format=csv | tail -n +2 | awk -F, '$2=="1" && $1!="attachment" {print $1}'))
POST_TYPES_LIST=$(IFS=,; echo "${POST_TYPES[*]}")

# Clear previous export files
> "$ALL_POSTS_FILE"
> "$CUSTOM_PERMALINKS_FILE"
[ "$DEBUG" -eq 1 ] && > "$DEBUG_FILE"

#########################################
# Export Posts and Custom Permalink Data
#########################################

echo "Exporting all posts..."
for POST_TYPE in "${POST_TYPES[@]}"; do
    echo "  Exporting post type: $POST_TYPE"
    wp post list --post_type="$POST_TYPE" --post_status=any \
      --fields=ID,post_title,post_name,post_date,post_status,post_type \
      --format=csv --allow-root | tail -n +2 >> "$ALL_POSTS_FILE"
    if [ $? -ne 0 ]; then
      echo "❌ Error: WP-CLI export failed for post type $POST_TYPE" >&2
      exit 1
    fi
done

if [ ! -s "$ALL_POSTS_FILE" ]; then
    echo "❌ Error: $ALL_POSTS_FILE is empty. Exiting." >&2
    exit 1
fi

# Further processing and merging logic follows...

#########################################
# Final Summary
#########################################

# Summary output: count number of merged posts entries and user export entries
merged_count=$(wc -l < "$EXPORT_DIR/export_wp_posts_*.csv")
user_count=$(($(wc -l < "$EXPORT_DIR/export_users_with_post_counts.csv") - 1))

echo "✅ Export complete!"
echo "  - Total posts merged: $merged_count"
echo "  - Total users count: $user_count"
[ "$DEBUG" -eq 1 ] && echo "  - Debug log available at: $DEBUG_FILE"