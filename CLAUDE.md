# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Bash shell script project that exports WordPress data using WP-CLI. The main script `export_wp_posts.sh` can run either locally or remotely via SSH, generating CSV and Excel files containing posts, custom permalinks, and optionally user data for SEO audits and data analysis.

**Important Note**: The script was previously named `export_wp_posts_unified_v2.sh` but has been renamed to `export_wp_posts.sh` as the primary script. The original local-only script is preserved as `export_wp_posts_legacy.sh`.

## Key Commands

### Running the Script

The main script (`export_wp_posts.sh`) supports both local and remote exports:

```bash
# Make executable (if needed)
chmod +x export_wp_posts.sh

# Local export (run from WordPress root directory)
./export_wp_posts.sh

# Remote export (via SSH)
./export_wp_posts.sh --remote
# or
./export_wp_posts.sh -r

# Run with user export disabled (answer 'n' when prompted)
./export_wp_posts.sh
```

### Development and Testing
```bash
# Check script syntax
bash -n export_wp_posts.sh

# Run with debug output
bash -x export_wp_posts.sh

# Test locally in a WordPress directory
cd /path/to/wordpress && /path/to/script/export_wp_posts.sh

# Test remote export
./export_wp_posts.sh --remote
```

### Setup Excel Support
```bash
# Install openpyxl for Excel generation
./enable_excel.sh
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

### Data Processing with Perl
Robust CSV parsing that properly handles quoted fields:
```perl
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
```

This parser correctly handles:
- Fields with commas inside quotes (e.g., "Sleep, Work, and COVID-19: In-Depth Study")
- Escaped quotes within quoted fields
- Mixed quoted and unquoted fields

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