# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Bash shell script project that exports WordPress data using WP-CLI. The main script `export_wp_posts_unified.sh` can run either locally or remotely via SSH, generating CSV and Excel files containing posts, custom permalinks, and optionally user data for SEO audits and data analysis.

## Key Commands

### Running the Script

The unified script (`export_wp_posts_unified.sh`) supports both local and remote exports:

```bash
# Make executable (if needed)
chmod +x export_wp_posts_unified.sh

# Local export (run from WordPress root directory)
./export_wp_posts_unified.sh

# Remote export (via SSH)
./export_wp_posts_unified.sh --remote
# or
./export_wp_posts_unified.sh -r

# Run with user export disabled (answer 'n' when prompted)
./export_wp_posts_unified.sh
```

### Development and Testing
```bash
# Check script syntax
bash -n export_wp_posts_unified.sh

# Run with debug output
bash -x export_wp_posts_unified.sh

# Test locally in a WordPress directory
cd /path/to/wordpress && /path/to/script/export_wp_posts_unified.sh

# Test remote export
./export_wp_posts_unified.sh --remote
```

### Setup Excel Support
```bash
# Install openpyxl for Excel generation
./enable_excel.sh
```

## Architecture and Key Components

### Script Structure
The `export_wp_posts_unified.sh` script follows this execution flow:
1. **Environment Validation**: Checks for WP-CLI installation and WordPress directory
2. **Post Type Discovery**: Dynamically identifies all public post types (excluding attachments)
3. **Data Export**: Uses WP-CLI to export posts with ID, title, URL, and custom permalinks
4. **Data Processing**: Merges posts data with custom permalinks using AWK
5. **Excel Generation**: Converts CSV to Excel with Python, adding formulas for URL concatenation
6. **User Export**: Optionally exports user statistics with post counts

### Key Technical Decisions
- Uses AWK for efficient in-memory data processing instead of temporary files
- Implements proper error handling with exit codes
- Creates outputs in timestamped directories with domain names (e.g., `!export_wp_posts_20250811_143244_example-com/`)
- Supports both local and remote (SSH) exports with automatic host detection
- Handles titles with commas by reassembling split fields intelligently
- Uses HYPERLINK formula in Excel for clickable URLs while maintaining clean CSV format
- Dynamically discovers post types rather than hardcoding them

### Dependencies and Requirements
- **WP-CLI**: Must be installed and accessible in PATH
- **Python 3.x**: Required with openpyxl library (install with `./enable_excel.sh`)
- **Environment**: For local mode, must run from WordPress root directory
- **SSH Access**: For remote mode, requires SSH access with WP-CLI on remote server
- **Shell**: Bash-compatible shell environment

## Important Patterns

### Error Handling
The script uses consistent error handling:
```bash
if ! command_exists wp; then
    echo "Error: WP-CLI is not installed" >&2
    exit 1
fi
```

### Data Processing with AWK
Complex data merging handles titles with commas:
```bash
awk -F',' '{
    n = NF;
    # Fields: 1: ID, 2 to (n-4): post_title, (n-3): post_name, (n-2): post_date, (n-1): post_status, n: post_type
    # Reassemble title from multiple fields if it contains commas
    title = $2;
    for(i = 3; i <= n-4; i++){
        title = title " " $i;
    }
    gsub(/,/, "", title); # Remove commas after reassembly
}'
```

### Excel Generation
Python is used for Excel conversion with formula support:
```python
df.to_excel(writer, sheet_name='Posts', index=False)
```

## Customization Points

When modifying the script:
1. **Post Types**: Modify the `--post_type` parameter in WP-CLI commands
2. **Export Fields**: Adjust the `--fields` parameter to include additional post data
3. **Output Format**: The Excel generation section can be customized for different formatting
4. **User Export**: Toggle with `EXPORT_USERS` environment variable
5. **Directory Names**: Export directories include timestamp and domain name
6. **SSH Hosts**: The script auto-detects SSH hosts from `~/.ssh/config`
7. **Remote Paths**: Automatically suggests paths for known hosts (Pressable, WP Engine, Kinsta)