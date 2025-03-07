# **Export WordPress Posts & Users with WP-CLI**

## **Overview**  
This script automates the export of **WordPress posts, pages, and all [public] custom post types, as well as custom permalinks (if you're using the [Custom Permalinks plugin](https://wordpress.org/plugins/custom-permalinks/)), and user data** using **WP-CLI**. It generates structured CSV files containing post details, user data, and post counts per user.

## **Why did I make this?**  
I work on a lot of WordPress sites with a lot of post/pages/post_types and having all of this info in a spreadsheet really helps me organize and find issues (like duplicate permalinks). Gathering all of the data for a site and uploading it to Google Sheets used to be a real chore. This script automates all the data gathering and allow me to upload and manage a single sheet, saving me hours of work. 

## **Why Use This Script?**  
✔ **Exports all WordPress posts & their metadata**  
✔ **Captures custom permalinks for accurate SEO mapping**  
✔ **Exports a complete list of WordPress users**  
✔ **Appends post counts per user across all public post types**  
✔ **Formats data into clean, structured CSV files**  

---

## **How It Works**  
1. **Retrieves all posts** from the WordPress database using WP-CLI  
2. **Fetches custom permalinks** for posts (if they exist)  
3. **Cleans and merges post data** into a single structured CSV file  
4. **Extracts user data**, including email, roles, and post count  
5. **Generates multiple output CSV files** for easy analysis or migration  

---

## **Installation & Setup**  
### **1️⃣ Save the Script**  
- Place the script in a directory, e.g., `~/scripts/export_wp_posts.sh`
- Ensure it has **execute permissions**:
  ```bash
  chmod +x ~/scripts/export_wp_posts.sh
  ```

### **2️⃣ Run the Script Manually**  
```bash
~/scripts/export_wp_posts.sh
```

---

## **Customizing for Your System**  
To use this script on your own system, you may need to adjust the following:

1. **Ensure WP-CLI is installed**  
   - Run `wp --info` to confirm WP-CLI is available. If not, install it from: [WP-CLI Installation Guide](https://wp-cli.org/#installing).

2. **Run WP-CLI as the correct user**  
   - If your WordPress install runs under a different user (e.g., `www-data`), you may need to prefix commands with:
     ```bash
     sudo -u www-data wp post list --allow-root
     ```

3. **Modify export folder location**  
   - By default, the script saves files in `!export_wp_posts/`. Change `EXPORT_DIR` in the script if needed.

---

## **Output Files**  
All exported files are stored in the `!export_wp_posts/` directory:

- `export_all_posts.csv`: Contains all WordPress posts and metadata.
- `export_custom_permalinks.csv`: Captures custom permalinks (if they exist).
- `export_wp_posts_<timestamp>.csv`: Final merged post export.
- `export_users.csv`: Raw list of WordPress users.
- `export_users_with_post_counts.csv`: Users with post counts appended.
- `export_debug_log.txt`: Debug log (if DEBUG mode is enabled).

---

## **Automating the Process**  
Instead of running this script manually, you can **automate it using different methods**:

### **1️⃣ Schedule Automatic Execution (Using `cron`)**  
Run the script **every day at midnight**:

```bash
crontab -e
```

Add this line to **run the script daily**:
```bash
0 0 * * * ~/scripts/export_wp_posts.sh
```
✅ **Fully automated daily exports!**  

---

### **2️⃣ Quick Terminal Command (Using an Alias)**  
Create a **shortcut command** for easy execution:

```bash
echo 'alias exportposts="~/scripts/export_wp_posts.sh"' >> ~/.bashrc
source ~/.bashrc
```
Now, simply type:
```bash
exportposts
```
✅ **Quick & easy manual execution!**  

---

## **Customization & Expansion**  
You can **modify this script** to support additional functionality:  
🛠 **Export WooCommerce product data** by adding `wp post list --post_type=product`  
🛠 **Sync exported files to cloud storage** (e.g., AWS S3, Google Drive)  
🛠 **Trigger automatic imports into another WordPress site**  

---

## **License**  
This project is licensed under the **MIT License**. You are free to use, modify, and distribute it as needed. See the `LICENSE.md` file for full details.  

---

## **Final Thoughts**  
🔥 This script **simplifies WordPress data exports** and ensures you have structured backups of your posts and users. Whether you're migrating, analyzing content, or auditing users, this tool makes the process fast and efficient.  

🎯 **Ready to automate your WordPress data exports?** Give it a try! 🚀

