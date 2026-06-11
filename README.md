# WordPress Export Script

A powerful shell script that exports WordPress posts, custom permalinks, custom meta fields, and users from WordPress sites - either locally or remotely via SSH. Generates both CSV and Excel files for SEO audits and data analysis.

## Key Features
- ✅ **Proper CSV Handling**: Correctly handles posts with commas, quotes, and special characters in titles
- 🔄 **Unified Operation**: Single script for both local and remote exports
- 📊 **Excel Generation**: Automatic conversion with clickable URLs and admin links
- 🔍 **Dynamic Discovery**: Automatically finds all public post types
- 🌐 **Multi-Host Support**: Works with Pressable, WP Engine, Kinsta, AWS, and more
- 🔧 **SSH Debugging**: Built-in verbose mode, pre-flight validation, and RemoteCommand detection
- 📋 **Custom Meta Fields**: Export any WordPress meta key as additional spreadsheet columns
- 💾 **Configuration Memory**: Remembers recent domains, SSH connections, paths, and meta field choices per domain

![CleanShot 2025-04-16 at 11 52 09](https://github.com/user-attachments/assets/0289ce1c-5d1e-4fd7-92ee-23c87546e33d)

## Features

- **Unified Script**: Single script handles both local and remote (SSH) exports
- **Post Export**: Exports all public post types (posts, pages, custom post types)
- **Custom Permalinks**: Captures custom permalink structures if set (always included)
- **Custom Meta Fields**: Export additional meta keys (e.g., `_yoast_wpseo_title`) as extra columns
- **User Export**: Optional export of users with their post counts
- **Excel Generation**: Automatically converts CSV to Excel with formulas for clickable URLs
- **SEO-Ready**: Includes all necessary data for SEO audits and migration planning
- **Smart SSH**: Auto-detects SSH hosts from config and suggests appropriate paths
- **SSH Favorites with Pre-fill**: Selecting a favorite pre-fills connection and path (editable, just hit Enter to accept)
- **Path Recall**: Remembers previously used paths for each SSH host
- **SSH Pre-Flight Validation**: Tests connectivity, path existence, and WP-CLI availability before exporting
- **RemoteCommand Detection**: Automatically handles SSH configs with `RemoteCommand` and `RequestTTY` directives
- **Sudo Wrapping**: Detects `sudo -iu <user>` patterns in SSH config and wraps commands accordingly
- **Meta Field Recall**: Remembers previously used meta keys per domain and offers to reuse them
- **Domain-Named Folders**: Export folders include the domain name for easy identification
- **Host Detection**: Recognizes common hosts and adapts accordingly
- **Verbose/Debug Modes**: CLI flags for troubleshooting SSH and export issues

## Usage

### Command-Line Flags

```bash
# Local export (run from WordPress root directory)
./export_wp_posts.sh

# Remote export (via SSH)
./export_wp_posts.sh --remote
./export_wp_posts.sh -r

# Verbose mode (show SSH debug output)
./export_wp_posts.sh --verbose
./export_wp_posts.sh -v

# Debug mode (verbose + debug log file)
./export_wp_posts.sh --debug

# Combine flags
./export_wp_posts.sh --remote --verbose
./export_wp_posts.sh -r -v
```

### Setup Excel Support
```bash
./enable_excel.sh
```

### How It Works

The script will:
1. Auto-detect available SSH hosts from your `~/.ssh/config` (remote mode)
2. Show SSH favorites (F1-F5) with saved paths — select to pre-fill connection and path
3. Suggest appropriate WordPress paths based on the host type or saved history
4. Run pre-flight SSH validation (connectivity, path, WP-CLI)
5. Discover all public post types dynamically
6. Prompt for domain name (with recent domain recall) and user export preference
7. Recall previously used meta fields for the domain, or prompt for new ones
8. Generate all files locally in a timestamped, domain-named folder

## Output

All files are created in a timestamped folder that includes the domain name:

```
!export_wp_posts_20250811_143244_example-com/
├── export_all_posts.csv              # Raw post export
├── export_custom_permalinks.csv      # Custom permalink data
├── export_meta_[key].csv            # Custom meta field data (one per key)
├── export_wp_posts_[timestamp].csv   # Final merged CSV
├── export_wp_posts_[timestamp].xlsx  # Excel file with formulas
├── export_users.csv                  # Raw user export (if enabled)
├── export_users_with_post_counts.csv # Users with post counts (if enabled)
└── export_debug_log.txt             # Debug information (if --debug)
```

### Excel File Structure

The generated Excel file includes:
- **Row 1**: Editable base domain (change this to update all URLs)
- **Row 2**: Column headers
- **Column A**: Formula-generated full URLs (uses custom permalink if exists, otherwise post_name)
- **Custom Meta Columns**: Inserted between custom_permalink and post_date (if any meta fields were exported)
- **Last Column**: Clickable WP Admin edit links

The number of columns adjusts dynamically based on how many custom meta fields are exported. The base is 8 columns (ID, title, name, custom_permalink, date, modified, status, type) plus one column per meta field, plus the URL formula and edit link columns.

## Requirements

- **Bash**: Compatible shell environment
- **For Local Mode**:
  - WP-CLI installed and accessible
  - Run from WordPress root directory
- **For Remote Mode**:
  - SSH access to the target server
  - WP-CLI installed on the remote server
- **For Excel Generation**:
  - Python 3
  - openpyxl package (installed via `enable_excel.sh`)

### Installing Excel Support

Run the included setup script:
```bash
./enable_excel.sh
```

This will install openpyxl in your user directory without affecting system Python.

### Supported Hosts (Remote Mode)

The script recognizes and adapts to:
- **Pressable**: Auto-suggests `/htdocs` path
- **WP Engine**: Auto-detects site path from hostname
- **Kinsta**: Suggests standard Kinsta paths
- **AWS/EC2**: Suggests `/var/www/html`
- **AWS Lightsail / Bitnami**: Suggests `/opt/bitnami/wordpress`
- **Cloudways**: Suggests `~/public_html`
- **Flywheel**: Suggests `~/public_html`
- **SiteGround**: Suggests `~/public_html`
- **Generic hosts**: Default to `~/public_html`

If a host has been used before via SSH favorites, the previously used path is suggested instead.

## Configuration

The script stores configuration in `.config/wp-export-config.json` (gitignored) in the script directory:

- **Recent Domains**: Up to 10 recently exported domains, shown as selectable options. Domain is saved immediately on selection (not after export completes)
- **SSH Favorites**: Recently used SSH connections with their WordPress paths, shown as F1-F5 at the top of the host list. Selecting a favorite pre-fills both connection and path (editable)
- **Export Statistics**: Tracks export count, last export date, and post counts per domain
- **Meta Field Memory**: Remembers custom meta keys per domain. On subsequent exports, offers to reuse previous selections with option to add more
- **Path Recall**: When selecting an SSH host by number, if that host was previously used as a favorite, its saved path is suggested automatically
- **Config Safety**: Configuration saves validate JSON before writing, preventing data loss from failed saves

## Exported Data

### Posts Export (8+ columns)
1. **ID**: Post ID
2. **post_title**: Title (sanitized, commas removed)
3. **post_name**: URL slug
4. **custom_permalink**: Custom permalink if set
5. *[Custom meta fields]*: Any additional meta keys requested during export
6. **post_date**: Publication date
7. **post_modified**: Last modified date
8. **post_status**: Status (publish, draft, etc.)
9. **post_type**: Type (post, page, custom types)

### Custom Meta Fields

When prompted, you can export any WordPress meta key as an additional column. Enter meta key names one at a time (press Enter on an empty line when done):

```
Export additional meta fields? (y/N): y
Enter meta key names one per line (press Enter twice when done):
Example: _custom_clean_url, _yoast_wpseo_title
> _yoast_wpseo_title
  Added: _yoast_wpseo_title
> _custom_clean_url
  Added: _custom_clean_url
>
```

On subsequent exports for the same domain, previously used meta keys are recalled:

```
Previous meta fields for example.com: _yoast_wpseo_title _custom_clean_url
Use previous meta fields? (Y/n):
Using saved meta fields: _yoast_wpseo_title _custom_clean_url
Add more meta fields? (y/N):
```

Each meta field is exported to its own intermediate CSV, then merged into the final output. The `custom_permalink` column is always present regardless of custom meta field choices.

### Users Export (8 columns if enabled)
1. **ID**: User ID
2. **user_login**: Username
3. **user_email**: Email address
4. **first_name**: First name
5. **last_name**: Last name
6. **display_name**: Display name
7. **roles**: User roles
8. **post_count**: Number of posts authored (N/A for remote exports)

## Troubleshooting

### SSH Pre-Flight Validation

The script runs three validation tests before attempting an export:
1. **SSH Connectivity**: Can we connect to the host?
2. **WordPress Path**: Does the specified directory exist?
3. **WP-CLI**: Is WP-CLI installed and accessible?

Each test provides specific troubleshooting guidance on failure.

### RemoteCommand / sudo Detection

Some SSH configs (e.g., AWS setups) include `RemoteCommand` or `RequestTTY` directives that prevent scripted command execution. The script:
1. Detects `RemoteCommand` via `ssh -G <host>`
2. Overrides it with `-o RemoteCommand=none -o RequestTTY=no`
3. If the RemoteCommand uses `sudo -iu <user>`, wraps all WP-CLI commands with the same sudo prefix

This is fully automatic — no manual configuration needed.

### Verbose and Debug Modes

```bash
# Show SSH stderr output for connection debugging
./export_wp_posts.sh --verbose

# Full debug mode (verbose + debug log file in export directory)
./export_wp_posts.sh --debug
```

### SSH Connection Issues
- The script uses `-T` flag to disable pseudo-terminal allocation
- Connection keepalive is enabled with 5-second intervals
- SSH timeout set to 30 seconds
- If you see "Cannot execute command-line and remote command", the RemoteCommand detection should handle this automatically
- For manual debugging: `ssh -v <host> 'echo test'`

### Excel Generation
- If Excel generation fails, ensure Python and openpyxl are installed
- Run `./enable_excel.sh` to set up Excel support
- CSV files can always be imported into Excel/Google Sheets manually

## Examples

### Local WordPress Export
```bash
cd /var/www/mysite
./export_wp_posts.sh
# Enter domain: mysite.com
# Include users? y
```

### Remote Pressable Export
```bash
./export_wp_posts.sh --remote
# Select host: 1 (pressable-site)
# Confirm path: /htdocs
# Enter domain: client-site.com
# Include users? n
```

### Remote AWS Export with Meta Fields
```bash
./export_wp_posts.sh -r -v
# Select host: my-aws-host
# Path: /var/www/blog/public_html/blog/
# Domain: example.com
# Export additional meta fields? y
# > _yoast_wpseo_title
# > _custom_clean_url
# >
# Include users? y
```

### Legacy Script
The original local-only script is preserved as `export_wp_posts_legacy.sh` for reference.

## Contributing

Feel free to submit issues and enhancement requests!

## License

MIT License - see LICENSE file for details

## Author

Eric Rasch
GitHub: https://github.com/ericrasch/script-export-wp-posts

## Future Enhancements (TODO)

### ~~1. Configuration File Support~~ ✅ Implemented in v5.0
- ~~Save settings the first time a user runs the script~~
- ~~Incrementally add domains to the configuration file as they're used~~
- ~~Present previously used domains as options when script is rerun~~
- ~~Save SSH favorites from recently used connections~~
- ~~Include last exported date for each domain~~

### 2. Export Profiles/Templates
- Add ability to save and reuse export configurations (e.g., `--profile seo-audit`)
- Different profiles for different use cases (migration, audit, backup)

### 3. Incremental/Delta Exports
- Export only posts modified since last export
- Options like `--since "2025-08-01"` or `--since-last-export`

### 4. Additional Export Formats
- JSON export for programmatic processing
- SQL export for direct database dumps
- Markdown export for documentation

### 5. Enhanced Error Recovery
- Automatic retry on SSH connection failures
- Resume capability for interrupted exports
- Better timeout handling for large sites

### 6. Export Validation & Reports
- Check for broken internal links
- Identify missing featured images
- Find duplicate slugs/permalinks
- Generate summary reports with potential issues

### 7. Bulk Operations Support
- Export from multiple sites in one run
- Support for batch configuration files

### ~~8. Custom Field Support~~ ✅ Implemented in v5.0
- ~~Export specific custom fields/meta data~~
- ~~Option like `--meta-keys "seo_title,seo_description"`~~

### 9. Performance Enhancements
- Parallel processing for large exports
- Compression of export files
- Option to exclude post content for faster exports
- Option to exclude specific post-types

### 10. Integration Features
- Webhook notifications on completion
- Direct upload to Google Drive/Dropbox
- Email export results

### 11. Data Transformation Options
- Convert relative URLs to absolute
- Strip HTML from titles/content
- Normalize date formats

### 12. Security Enhancements
- Encrypted exports for sensitive data
- Audit log of exports
- Option to redact personal data
