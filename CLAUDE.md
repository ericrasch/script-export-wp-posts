# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Bash shell script project that exports WordPress data using WP-CLI. The main script `export_wp_posts.sh` (v5.0) can run either locally or remotely via SSH, generating CSV and Excel files containing posts, custom permalinks, custom meta fields, and optionally user data for SEO audits and data analysis.

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

# Verbose mode (show SSH debug output)
./export_wp_posts.sh --verbose
# or
./export_wp_posts.sh -v

# Debug mode (verbose + debug log file)
./export_wp_posts.sh --debug

# Combine flags
./export_wp_posts.sh -r -v
```

### Development and Testing
```bash
# Check script syntax
bash -n export_wp_posts.sh

# Run with bash debug output
bash -x export_wp_posts.sh

# Test locally in a WordPress directory
cd /path/to/wordpress && /path/to/script/export_wp_posts.sh

# Test remote export with verbose SSH output
./export_wp_posts.sh --remote --verbose
```

### Setup Excel Support
```bash
# Install openpyxl for Excel generation
./enable_excel.sh
```

## Architecture and Key Components

### Script Structure
The `export_wp_posts.sh` script follows this execution flow:
1. **CLI Argument Parsing**: Handles `--remote`/`-r`, `--verbose`/`-v`, `--debug` flags
2. **Environment Setup**: Configures SSH options, stderr routing, sudo prefix
3. **SSH Connection Setup** (remote mode):
   a. Lists SSH favorites (F1-F5, pre-fill connection + path) and config hosts
   b. Path recall from favorites or hostname pattern detection
   c. RemoteCommand/RequestTTY detection and override via `ssh -G`
   d. Sudo user extraction from RemoteCommand pattern
   e. Pre-flight validation (connectivity, path, WP-CLI)
4. **Post Type Discovery**: Dynamically identifies all public post types (excluding attachments), with 3 fallback methods
5. **Domain Selection**: Recent domain recall with immediate config save (not deferred to end of script)
6. **Custom Meta Field Prompt**: Recalls previously used meta keys per domain, with option to reuse or enter new ones
7. **Data Export**: Uses WP-CLI to export posts, custom permalinks, and any custom meta fields
8. **Data Processing**: Merges all data using Perl with proper CSV parsing (handles quoted fields, commas in titles)
9. **Excel Generation**: Converts CSV to Excel with Python, dynamic column count, clickable URLs and admin links
10. **User Export**: Optionally exports user statistics with post counts
11. **Configuration Update**: Saves SSH favorites and export statistics

### Key Functions

- **`build_remote_cmd()`**: Wraps commands with `sudo -iu <user>` when RemoteCommand is detected in SSH config. Called at every SSH command site to transparently handle multi-user setups (e.g., SSH as `ubuntu`, WP files owned by `blog`).
- **`load_config()` / `save_config()`**: JSON configuration persistence using Python for parsing/writing. `save_config` validates JSON before writing to prevent data loss.
- **`add_domain_to_history()`**: Adds/promotes domains in the recent history list. Called immediately after domain selection (not at end of script) to prevent loss on early exit.
- **`add_ssh_to_favorites()`**: Saves SSH connection + WordPress path pairs for path recall.
- **`get_domain_meta_keys()` / `save_domain_meta_keys()`**: Recalls and persists custom meta field choices per domain.
- **`update_export_stats()`**: Tracks export counts and dates per domain.

### Key Technical Decisions
- Uses `set -euo pipefail` with `|| true` guards on grep pipelines to prevent silent exits
- Uses Perl for CSV merging — robust parser handles quoted fields, commas in titles, and N meta field files
- SSH options (`SSH_OPTS`) are centralized and consistent across all SSH calls
- SSH stderr routes to `/dev/stderr` in verbose mode, `/dev/null` otherwise
- RemoteCommand detection uses `ssh -G <host>` to resolve effective SSH config
- Empty bash arrays use `${array[@]+"${array[@]}"}` pattern for `set -u` compatibility
- Creates outputs in timestamped directories with domain names (e.g., `!export_wp_posts_20250811_143244_example-com/`)
- Dynamic `EXPECTED_COLUMNS` computed as 7 base + number of custom meta fields
- Uses HYPERLINK formula in Excel for clickable URLs while maintaining clean CSV format
- Dynamically discovers post types rather than hardcoding them
- Domain history saved immediately after selection (not end of script) to survive early exits
- Config save functions validate JSON before writing to prevent data loss from Python failures
- All config-modifying functions use `|| true` on Python and `|| echo "Warning"` on save to avoid crashing the export
- SSH favorite selection is case-insensitive (`f1`/`F1` both work) using `tr` for Bash 3.x compatibility (macOS)
- Meta field choices stored per domain in `domain_stats.<domain>.meta_keys` for recall on subsequent exports
- Y/n prompts capitalize the default choice (e.g., `Y/n` means default yes, `y/N` means default no)

### Dependencies and Requirements
- **WP-CLI**: Must be installed and accessible in PATH (local) or on remote server
- **Python 3.x**: Required with openpyxl library (install with `./enable_excel.sh`)
- **Perl**: Used for CSV data merging (typically pre-installed on macOS/Linux)
- **Environment**: For local mode, must run from WordPress root directory
- **SSH Access**: For remote mode, requires SSH access with WP-CLI on remote server
- **Shell**: Bash-compatible shell environment

## Important Patterns

### Error Handling
The script uses `set -euo pipefail` with careful `|| true` guards:
```bash
# Grep pipelines that might return empty results use || true to prevent pipefail exit
POST_TYPES_RAW=$(echo "$POST_TYPES_RAW" | tr -d '\r' | grep -v "^$" | grep -v "^Connection to" || true)
```

### SSH Command Wrapping
All remote commands go through `build_remote_cmd()`:
```bash
REMOTE_CMD=$(build_remote_cmd "cd \"$WP_PATH\" && wp post-type list --public --format=names")
RESULT=$(ssh $SSH_OPTS "$SSH_CONNECTION" "$REMOTE_CMD" 2>>"$SSH_STDERR")
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

The Perl merge script accepts N additional meta field files via `ARGV[2+]`, loading each into `%meta_data{field_name}{post_id}`. Output column order: `ID, post_title, post_name, custom_permalink, [meta fields...], post_date, post_status, post_type`.

### Excel Generation
Python heredoc builds headers dynamically based on `custom_meta_keys` list. Column positions for date, status, type, and edit link adjust automatically based on meta field count.

### Empty Array Safety
Under `set -u`, empty bash arrays cause "unbound variable" errors. The pattern used throughout:
```bash
for item in ${CUSTOM_META_KEYS[@]+"${CUSTOM_META_KEYS[@]}"}; do
    # safe even when CUSTOM_META_KEYS is empty
done
```

## Customization Points

When modifying the script:
1. **Post Types**: Modify the `--post_type` parameter in WP-CLI commands
2. **Export Fields**: Adjust the `--fields` parameter to include additional post data
3. **Output Format**: The Excel generation section can be customized for different formatting
4. **User Export**: Toggle with `EXPORT_USERS` environment variable
5. **Directory Names**: Export directories include timestamp and domain name
6. **SSH Hosts**: The script auto-detects SSH hosts from `~/.ssh/config`
7. **Remote Paths**: Automatically suggests paths for known hosts (Pressable, WP Engine, Kinsta, AWS/EC2, Bitnami, Lightsail, Cloudways, Flywheel)
8. **Path Recall**: Previously used paths are recalled from SSH favorites
9. **Meta Fields**: Users can add any number of custom meta keys at export time; previously used keys are recalled per domain
10. **SSH Options**: Centralized in `SSH_OPTS` variable for easy modification
11. **Config Safety**: `save_config` validates JSON before writing; all config functions handle errors gracefully
