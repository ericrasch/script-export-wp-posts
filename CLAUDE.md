# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Bash shell script project that exports WordPress data using WP-CLI. The main script `export_wp_posts.sh` generates CSV and Excel files containing posts, custom permalinks, and optionally user data for SEO audits and data analysis.

## Key Commands

### Running the Script
```bash
# Make executable (if needed)
chmod +x export_wp_posts.sh

# Run from WordPress root directory
./export_wp_posts.sh

# Run with user export disabled
EXPORT_USERS=false ./export_wp_posts.sh
```

### Development and Testing
```bash
# Check script syntax
bash -n export_wp_posts.sh

# Run with debug output
bash -x export_wp_posts.sh

# Test in a WordPress directory
cd /path/to/wordpress && /path/to/script/export_wp_posts.sh
```

## Architecture and Key Components

### Script Structure
The `export_wp_posts.sh` script follows this execution flow:
1. **Environment Validation**: Checks for WP-CLI installation and WordPress directory
2. **Post Type Discovery**: Dynamically identifies all public post types (excluding attachments)
3. **Data Export**: Uses WP-CLI to export posts with ID, title, URL, and custom permalinks
4. **Data Processing**: Merges posts data with custom permalinks using AWK
5. **Excel Generation**: Converts CSV to Excel with Python, adding formulas for URL concatenation
6. **User Export**: Optionally exports user statistics with post counts

### Key Technical Decisions
- Uses AWK for efficient in-memory data processing instead of temporary files
- Implements proper error handling with exit codes
- Creates outputs in `!export_wp_posts/` directory for easy organization
- Uses HYPERLINK formula in Excel for clickable URLs while maintaining clean CSV format
- Dynamically discovers post types rather than hardcoding them

### Dependencies and Requirements
- **WP-CLI**: Must be installed and accessible in PATH
- **Python 3.x**: Required with pandas and openpyxl libraries
- **Environment**: Must run from WordPress root directory
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
Complex data merging is done in-memory:
```bash
awk -F',' 'NR==FNR && FNR>1 {url[$1]=$2; next} ...'
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
5. **Directory Names**: The `!export_wp_posts/` prefix can be changed throughout the script