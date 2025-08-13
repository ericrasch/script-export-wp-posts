# New Configuration Features in export_wp_posts.sh v4.0

## Overview

The updated script (v4.0) includes several new features for improved user experience:

1. **Configuration File Support**: Stores settings in `.config/wp-export-config.json` (in script directory)
2. **Interactive Mode Selection**: Choose between local and remote WordPress at startup
3. **Domain History**: Remembers last 10 domains for quick selection
4. **SSH Favorites**: Saves frequently used SSH connections with their WordPress paths
5. **Export Statistics**: Tracks total exports and last export date

## Key Changes

### 1. Mode Selection
- Removed the `--remote` flag requirement
- Now prompts users to select mode interactively:
  - Option 1: Local WordPress
  - Option 2: Remote WordPress (SSH)

### 2. Domain History
- Shows recent domains when prompting for domain input
- Allows quick selection by number
- Automatically deduplicates and maintains order (most recent first)
- Limits to 10 most recent domains

### 3. SSH Connection Management
- Saves SSH connections as favorites with their WordPress paths
- Shows favorites first when selecting SSH connections
- Allows quick selection with F1, F2, etc.
- Still shows SSH config hosts as numbered options
- Maintains up to 10 favorite connections

### 4. Configuration Functions

The script includes these new functions:

- `init_config()` - Creates config directory and initial file
- `load_config()` - Loads current configuration
- `save_config()` - Saves configuration to disk
- `add_domain_to_history()` - Adds domain to recent list (with deduplication)
- `add_ssh_to_favorites()` - Saves SSH connection and path
- `get_recent_domains()` - Returns array of recent domains
- `get_ssh_favorites()` - Returns SSH favorites with paths
- `update_export_stats()` - Updates export count and timestamp

### 5. Configuration File Structure

The config file at `.config/wp-export-config.json` (located in the same directory as the script) has this structure:

```json
{
  "recent_domains": [
    "example.com",
    "test.org",
    "demo.net"
  ],
  "ssh_favorites": [
    {
      "connection": "user@host.com",
      "path": "/home/user/public_html"
    }
  ],
  "export_stats": {
    "total_exports": 5,
    "last_export": "2025-08-12T10:30:00Z",
    "last_domain": "example.com"
  }
}
```

## Usage Examples

### First Run
```bash
$ ./export_wp_posts.sh
=== WordPress Export Script v4.0 ===

Select export mode:
  1) Local WordPress
  2) Remote WordPress (SSH)

Enter choice (1 or 2): 2

Remote Mode Selected
This script exports all post types and custom permalinks via SSH.

SSH Connection Options:

SSH config hosts:
  1. mysite-staging
  2. client-prod
  0. Enter custom connection

Select a host (1-2) or 0 for custom: 1
```

### Subsequent Runs (with history)
```bash
$ ./export_wp_posts.sh
=== WordPress Export Script v4.0 ===

Select export mode:
  1) Local WordPress
  2) Remote WordPress (SSH)

Enter choice (1 or 2): 2

Remote Mode Selected
This script exports all post types and custom permalinks via SSH.

SSH Connection Options:

Recent SSH connections:
  F1. mysite-staging (path: /home/user/public_html)
  F2. client-prod (path: /var/www/html)

SSH config hosts:
  1. mysite-staging
  2. client-prod
  0. Enter custom connection

Select an option (F1-F2, 1-2, or 0): F1
Using favorite: mysite-staging (path: /home/user/public_html)

Recent domains:
  1. example.com
  2. staging.example.com
  3. client.com

Select a recent domain (1-3) or enter new domain: 1
Using: example.com
```

## Benefits

1. **Faster repeated exports**: No need to re-enter domains or SSH details
2. **Reduced errors**: Pre-validated paths and connections
3. **Better organization**: Track export history and statistics
4. **Improved workflow**: Quick selection from favorites
5. **Persistent settings**: Configuration survives between sessions

## Backwards Compatibility

The script maintains full backwards compatibility:
- All original features work exactly as before
- Output format remains unchanged
- Directory structure is the same
- Can still be used without the config file (it will create one automatically)