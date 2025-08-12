# WordPress Export Script

A powerful shell script that exports WordPress posts, custom permalinks, and users from WordPress sites - either locally or remotely via SSH. Generates both CSV and Excel files for SEO audits and data analysis.

## Key Features
- ✅ **Proper CSV Handling**: Correctly handles posts with commas, quotes, and special characters in titles
- 🔄 **Unified Operation**: Single script for both local and remote exports
- 📊 **Excel Generation**: Automatic conversion with clickable URLs and admin links
- 🔍 **Dynamic Discovery**: Automatically finds all public post types
- 🌐 **Multi-Host Support**: Works with Pressable, WP Engine, Kinsta, and more

![CleanShot 2025-04-16 at 11 52 09](https://github.com/user-attachments/assets/0289ce1c-5d1e-4fd7-92ee-23c87546e33d)

## Features

- **Unified Script**: Single script handles both local and remote (SSH) exports
- **Post Export**: Exports all public post types (posts, pages, custom post types)
- **Custom Permalinks**: Captures custom permalink structures if set
- **User Export**: Optional export of users with their post counts
- **Excel Generation**: Automatically converts CSV to Excel with formulas for clickable URLs
- **SEO-Ready**: Includes all necessary data for SEO audits and migration planning
- **Smart SSH**: Auto-detects SSH hosts from config and suggests appropriate paths
- **Domain-Named Folders**: Export folders include the domain name for easy identification
- **Host Detection**: Recognizes common hosts (Pressable, WP Engine, Kinsta) and adapts accordingly

## Usage

### Local Export (when you're in the WordPress directory)
```bash
./export_wp_posts.sh
```

### Remote Export (via SSH)
```bash
./export_wp_posts.sh --remote
# or
./export_wp_posts.sh -r
```

### Setup Excel Support
```bash
./enable_excel.sh
```

The script will:
1. Auto-detect available SSH hosts from your `~/.ssh/config` (remote mode)
2. Suggest appropriate WordPress paths based on the host type
3. Prompt for domain name and user export preference
4. Generate all files locally in a timestamped, domain-named folder

## Output

All files are created in a timestamped folder that includes the domain name:

```
!export_wp_posts_20250811_143244_example-com/
├── export_all_posts.csv              # Raw post export
├── export_custom_permalinks.csv      # Custom permalink data
├── export_wp_posts_[timestamp].csv   # Final merged CSV
├── export_wp_posts_[timestamp].xlsx  # Excel file with formulas
├── export_users.csv                  # Raw user export (if enabled)
├── export_users_with_post_counts.csv # Users with post counts (if enabled)
└── export_debug_log.txt             # Debug information (if DEBUG=1)
```

### Excel File Structure

The generated Excel file includes:
- **Row 1**: Editable base domain (change this to update all URLs)
- **Row 2**: Column headers
- **Column A**: Formula-generated full URLs (uses custom permalink if exists, otherwise post_name)
- **Column I**: Clickable WP Admin edit links

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
- **SiteGround**: Suggests `~/public_html`
- **Generic hosts**: Default to `~/public_html`

## Exported Data

### Posts Export (7 columns)
1. **ID**: Post ID
2. **post_title**: Title (sanitized, commas removed)
3. **post_name**: URL slug
4. **custom_permalink**: Custom permalink if set
5. **post_date**: Publication date
6. **post_status**: Status (publish, draft, etc.)
7. **post_type**: Type (post, page, custom types)

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

### SSH Connection Issues
- For Pressable hosts, the script automatically uses `-T` flag to disable pseudo-terminal
- Connection keepalive is enabled with 5-second intervals
- Large exports may cause connections to close - this is normal and handled gracefully

### Excel Generation
- If Excel generation fails, ensure Python and openpyxl are installed
- Run `./enable_excel.sh` to set up Excel support
- CSV files can always be imported into Excel/Google Sheets manually

### Debug Mode
To enable detailed logging, edit the script and set:
```bash
DEBUG=1
```

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

### 1. Configuration File Support
- Save settings the first time a user runs the script
- Incrementally add domains to the configuration file as they're used
- Present previously used domains as options when script is rerun
- Save SSH favorites from recently used connections
- Include last exported date for each domain

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

### 8. Custom Field Support
- Export specific custom fields/meta data
- Option like `--meta-keys "seo_title,seo_description"`

### 9. Performance Enhancements
- Parallel processing for large exports
- Compression of export files
- Option to exclude post content for faster exports

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