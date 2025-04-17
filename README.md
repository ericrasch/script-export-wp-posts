# **Export WordPress Posts & Users with WP-CLI**

## **Overview**  
This script automates the export of **WordPress posts, custom permalinks, and optional user data** using **WP-CLI** and produces both CSV and Excel (.xlsx) files ready for import into tools like Google Sheets.

It is designed to:
- Merge all post-related data into a single master file
- Include hyperlinks and formulas
- Optionally append users and their post counts across public post types
- Run reliably with built-in validation and logging

---

## **Why Use This Script?**  
✔ **Exports posts and custom permalinks for SEO audits**  
✔ **Optional user data export with post counts**  
✔ **Validates structure and merges all output cleanly**  
✔ **Creates a Google Sheets-friendly `.xlsx` file with formulas**  
✔ **Built-in safety checks (WP-CLI installed, empty files, debug logs)**  
✔ **Saves hours of tedious data collection**

---

## **Dependencies**

This script assumes the following are available on your system:

### 📦 Required:
- [WP-CLI](https://wp-cli.org/#installing)
- Python 3.x with:
  ```bash
  pip install pandas openpyxl
  ```

If running on macOS with system restrictions, use:
```bash
python3 -m venv venv
source venv/bin/activate
pip install pandas openpyxl
```

---

## **How It Works**

1. ✅ Verifies `wp` is installed  
2. ✅ Prompts for your base domain (e.g., `example.com` or `your-domain.com`)  
3. ✅ Prompts to include user data (defaults to **yes**)  
4. ✅ Gathers post data for all public post types (excluding attachments)  
5. ✅ Retrieves `custom_permalink` meta (if used)  
6. ✅ Merges and cleans post data using `awk`  
7. ✅ Generates a **CSV** and **Excel** file:
   - `$A$1` becomes the editable domain base in Excel
   - Column A: full post URL formula  
   - Column J: WP Admin edit link
8. ✅ Exports users and post counts (if selected)
9. ✅ Prints summary and stores debug logs

---

## **Installation & Usage**

### 🔧 1. Save and Make Executable
```bash
chmod +x export_wp_posts.sh
```

### 🚀 2. Run the Script
```bash
./export_wp_posts.sh
```

You will be prompted for:
- Base domain (for Excel URL formulas)
- Whether to export user data (y/n)

---

## **Output Files**

All files are saved to the `!export_wp_posts/` folder:

| File | Description |
|------|-------------|
| `export_all_posts.csv` | Raw post data from all public post types |
| `export_custom_permalinks.csv` | Custom permalinks if available |
| `export_wp_posts_<timestamp>.csv` | Final validated & merged post CSV |
| `export_wp_posts_<timestamp>.xlsx` | Excel file with formulas and hyperlinks |
| `export_users.csv` | List of all WordPress users (if selected) |
| `export_users_with_post_counts.csv` | Users with appended post counts |
| `export_debug_log.txt` | Debug messages for troubleshooting |

---

## **Quick Tips**

### 🧪 Test WP-CLI
```bash
wp --info
```

### 🧰 Customize export directory
Edit this line in the script:
```bash
EXPORT_DIR="!export_wp_posts"
```

---

## **Automation (Optional)**

### ⏰ Schedule via `cron`
```bash
crontab -e
```

Add:
```bash
0 1 * * * /path/to/export_wp_posts.sh
```

---

## **Final Thoughts**

This script gives you total control over WordPress data exports — with formulas and structure built in for teams using Google Sheets or Excel.

🔄 Whether you're debugging permalinks, cleaning up old content, or running user audits — this tool has you covered.

**Happy exporting!** 🚀  
