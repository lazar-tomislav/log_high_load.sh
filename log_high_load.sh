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