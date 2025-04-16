Okay, here are the instructions translated into English and formatted in Markdown.

---

## Deploying Monitoring Scripts and Configuration to Production Server

**IMPORTANT NOTE FOR PRODUCTION SERVER:**

*   **Changes on Production:** Perform all changes (installation, configuration, service restarts) carefully. If possible, perform them during off-peak hours when website traffic is lower.
*   **Backup:** Although these changes are relatively safe, it's always good practice to have a recent backup before making any modifications to a production server.
*   **Service Restarts:** Restarting PHP-FPM and MySQL/MariaDB services will cause a very brief interruption in their availability (fraction of a second to a few seconds). Plan this accordingly, preferably outside of peak load times.

---

### Steps for Production Server Setup:

1.  **Connect to the Production Server via SSH:**
    ```bash
    ssh forge@[YOUR_PRODUCTION_SERVER_IP]
    ```

2.  **(If needed) Install `bc`:**
    ```bash
    sudo apt update && sudo apt install bc -y
    ```

3.  **Create the script `/usr/local/bin/log_high_load.sh`:**
    ```bash
    sudo nano /usr/local/bin/log_high_load.sh
    ```
    *   Paste the same script code we used on the test server:

        ```bash
        #!/bin/bash

        # --- Configuration ---
        LOG_FILE="/var/log/process_snapshots.log"
        # !! IMPORTANT: ADJUST THIS THRESHOLD (LOAD_THRESHOLD) !!
        # Set the load average threshold (1-minute) above which the script will log details.
        # A good starting value is 1.5 to 2 times the number of CPU cores on your server.
        # Check the number of cores with: nproc
        # Example: If you have 4 cores, a threshold of 6.0 or 8.0 might be a good start.
        # If you have 2 cores, try 3.0 or 4.0. Adjust as needed.
        LOAD_THRESHOLD="6.0" # <-- ADJUST THIS!
        # --- End Configuration ---

        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        # Get the 1-minute load average
        CURRENT_LOAD_AVG=$(uptime | awk -F'load average:' '{ print $2 }' | awk '{ print $1 }' | sed 's/,//')

        # Check if the load exceeds the threshold using bc for floating point comparison
        # Use 'scale=2' to ensure decimal comparison
        if (( $(echo "scale=2; $CURRENT_LOAD_AVG > $LOAD_THRESHOLD" | bc -l) )); then
          echo "--- High Load Detected at $TIMESTAMP (Load: $CURRENT_LOAD_AVG) ---" >> "$LOG_FILE"

          # System Overview (vmstat) - 1 snapshot, 2 seconds interval for a better average
          echo "VMStat Output (wait 2s for sample):" >> "$LOG_FILE"
          vmstat 1 2 | tail -n 1 >> "$LOG_FILE"
          echo "" >> "$LOG_FILE"

          # Optional: Check and add iostat if it exists
          if command -v iostat &> /dev/null; then
            echo "IOStat Output (Disk & CPU - wait 2s for sample):" >> "$LOG_FILE"
            # -x: extended stats, -d: disk stats, -c: cpu stats, -t: timestamp, -N: LVM mapping, 1 2: 1 sec interval, 2 counts
            iostat -xtcdN 1 2 | tail -n +3 >> "$LOG_FILE" # Tail skips headers
             echo "" >> "$LOG_FILE"
          else
            echo "IOStat command not found." >> "$LOG_FILE"
             echo "" >> "$LOG_FILE"
          fi

          # Top CPU Processes
          echo "Top CPU Processes:" >> "$LOG_FILE"
          ps -eo pid,ppid,%cpu,%mem,user,etime,cmd --sort=-%cpu | head -n 20 >> "$LOG_FILE" # Increased to 20
          echo "" >> "$LOG_FILE"

          # Top Memory Processes
          echo "Top Memory Processes:" >> "$LOG_FILE"
          ps -eo pid,ppid,%cpu,%mem,user,etime,cmd --sort=-%mem | head -n 20 >> "$LOG_FILE" # Increased to 20
          echo "" >> "$LOG_FILE"

          # Processes in Disk Wait (State D)
          echo "Processes in Disk Wait (State D):" >> "$LOG_FILE"
          ps -eo pid,stat,user,cmd | grep " D " >> "$LOG_FILE"
          echo "" >> "$LOG_FILE"

          # Optional: PHP-FPM Status (if status page is configured)
          # echo "PHP-FPM Status (if configured):" >> "$LOG_FILE"
          # curl -s 'http://localhost/status?full&json' >> "$LOG_FILE" # Example, needs adjustment
          # echo "" >> "$LOG_FILE"

          echo "--- End High Load Snapshot ---" >> "$LOG_FILE"
        fi

        exit 0
        ```
    *   **!! VERY IMPORTANT: ADJUST `LOAD_THRESHOLD` !!** Run `nproc` on the **production** server to see the number of CPU cores. Set `LOAD_THRESHOLD` to 1.5x to 2x the number of cores (e.g., if production has 4 cores, set it to `6.0` or `8.0`). **Do not leave the test value!**
    *   Save and close (`Ctrl+X`, then `Y`, then `Enter`).

4.  **Make the script executable:**
    ```bash
    sudo chmod +x /usr/local/bin/log_high_load.sh
    ```

5.  **Add the script to Cron (root's crontab):**
    ```bash
    sudo crontab -e
    ```
    *   Add the following line:
        ```crontab
        */1 * * * * /usr/local/bin/log_high_load.sh >> /var/log/cron_script_runner.log 2>&1
        ```
    *   Save and close.

6.  **Set up Log Rotation:** **Do not skip this step on production!**
    ```bash
    sudo nano /etc/logrotate.d/process_snapshots
    ```
    *   Paste the same rotation configuration content as on the test server (rotates `process_snapshots.log` and `cron_script_runner.log`):
        ```
        /var/log/process_snapshots.log
        /var/log/cron_script_runner.log {
            daily
            rotate 7
            compress
            delaycompress
            missingok
            notifempty
            create 0640 root adm
            sharedscripts
            postrotate
                # No actions needed after rotation
            endscript
        }
        ```
    *   Save and close.

7.  **Enable PHP-FPM Slow Log:**
    *   Find the FPM pool configuration for `hrturizam.hr` on production (e.g., `/etc/php/[version]/fpm/pool.d/www.conf` or via Forge UI).
    *   Check if `request_slowlog_timeout` and `slowlog` directives already exist. If not, add them:
        ```ini
        request_slowlog_timeout = 10s ; Or 5s if you want to catch shorter delays
        slowlog = /var/log/php-fpm/www-slow.log
        ```
    *   Save the changes.
    *   **Restart PHP-FPM:** `sudo systemctl restart php[version]-fpm` (replace `[version]` with your actual PHP version). **Perform this during off-peak hours if possible.**

8.  **Enable MySQL/MariaDB Slow Query Log:**
    *   Edit the MySQL configuration (e.g., `/etc/mysql/my.cnf` or `/etc/mysql/mysql.conf.d/mysqld.cnf`).
    *   Within the `[mysqld]` section, add or ensure these lines exist:
        ```ini
        slow_query_log = 1
        slow_query_log_file = /var/log/mysql/mysql-slow.log
        long_query_time = 2  ; Adjust as needed (e.g., 1 or 3 seconds)
        # log_queries_not_using_indexes = 1 ; Useful, but can generate many logs
        ```
    *   Save the changes.
    *   **Restart MySQL/MariaDB:** `sudo systemctl restart mysql` (or `mariadb`). **Also, perform this during off-peak hours if possible.**

---

The production server is now equipped with the same diagnostic tools. Monitor the situation, and the next time an incident occurs, you will have the necessary logs for analysis:

*   `/var/log/process_snapshots.log` (System state during high load)
*   `/var/log/php-fpm/www-slow.log` (Slow PHP scripts/URLs)
*   `/var/log/mysql/mysql-slow.log` (Slow SQL queries)
*   Nginx access/error logs (Traffic context)

Good luck with the setup on production! Let me know the results or if you get stuck.