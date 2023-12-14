#!/bin/bash
set -e

#!/usr/bin/env bash
# fail if any commands fails
set -e
# make pipelines' return status equal the last command to exit with a non-zero status, or zero if all commands exit successfully
set -o pipefail
# debug log

bitrise plugin install https://github.com/bitrise-io/bitrise-plugins-annotations.git
export BITRISEIO_BUILD_ANNOTATIONS_SERVICE_URL=https://build-annotations.services.bitrise.io

# Check the operating system
if [[ "$(uname)" == "Darwin" ]]; then
    # macOS - Install gnuplot using brew
    echo "Detected macOS"
    if ! command -v brew &> /dev/null; then
        echo "Homebrew is not installed. Please install Homebrew and rerun the script."
        exit 1
    fi
    brew install gnuplot

elif [[ "$(uname)" == "Linux" ]]; then
    # Linux (assuming apt-get package manager)
    echo "Detected Linux"
    if ! command -v apt-get &> /dev/null; then
        echo "apt-get package manager not found. Please install gnuplot manually."
        exit 1
    fi
   # export DEBIAN_FRONTEND=noninteractive
     sudo DEBIAN_FRONTEND=noninteractive apt-get -qq install -y gnuplot

else
    echo "Unsupported operating system."
    exit 1
fi

cpu_output_file="cpu_usage.csv"
memory_output_file="memory_usage.csv"

# Write headers to the CSV files
echo "Timestamp,User CPU (%),Sys CPU (%),Idle CPU (%)" > "$cpu_output_file"
echo "Timestamp,Used PhysMem (MB),Unused PhysMem (MB)" > "$memory_output_file"

generate_charts() {
    # Create an HTML file to display the charts
    cat << HTML > index.html
<!DOCTYPE html>
<html>
<head>
    <title>System Usage Charts</title>
</head>
<body>
HTML

touch cpu.html
touch mem.html

    # Generate CPU usage chart
    gnuplot << EOF
set datafile separator ","
set terminal svg size 800,600
set output "cpu.html"
set title "CPU Usage"
set xdata time
set xlabel "Timestamp"
set timefmt "%Y-%m-%d %H:%M:%S"
set ylabel "Usage (%)"
plot "$cpu_output_file" using 1:2 with lines lw 2 title "User CPU (%)", \
     "$cpu_output_file" using 1:3 with lines lw 2 title "Sys CPU (%)", \
     "$cpu_output_file" using 1:4 with lines lw 2 title "Idle CPU (%)"
EOF

cat cpu.html >> index.html

    # Generate memory usage chart
    gnuplot << EOF
set datafile separator ","
set terminal svg size 800,600
set output "mem.html"
set title "Memory Usage"
set xlabel "Timestamp"
set xdata time
set timefmt "%Y-%m-%d %H:%M:%S"
set ylabel "Memory (MB)"
plot "$memory_output_file" using 1:2 with lines lw 2 title "Used PhysMem (MB)", \
     "$memory_output_file" using 1:3 with lines lw 2 title "Unused PhysMem (MB)"
EOF

cat mem.html >> index.html


    # Create an HTML file to display the charts
    cat << HTML >> index.html
</body>
</html>
HTML


# Copy HTML and chart files to the desired location
    cp cpu.html "$BITRISE_DEPLOY_DIR/cpu_chart.html"
    cp mem.html "$BITRISE_DEPLOY_DIR/memory_chart.html"

# Check if Env Var directory exists, if not set, the Env Var and copy the desired html report into the env var and chart files to the desired location
# NEED TO FIGURE OUT HOW TO SET THE ENV VAR
if [ -z "$BITRISE_HTML_REPORT_DIR" ]; then
    # If BITRISE_HTML_REPORT_DIR is not set, create a default directory
    TEMP_DIR=$(mktemp -d)
    export BITRISE_HTML_REPORT_DIR=$TEMP_DIR
    echo this is a marker for the env vars
    echo $BITRISE_HTML_REPORT_DIR
    envman add --key BITRISE_HTML_REPORT_DIR --value "$TEMP_DIR"
fi

# Copy index.html to the determined directory
mkdir -p "$BITRISE_HTML_REPORT_DIR/hardware-utilization/hardware_utilization_graphs.html"
cp index.html "$BITRISE_HTML_REPORT_DIR/hardware-utilization-graphs/index.html"

}

looper() {
while true; do
    # Get the current timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    top_info=$(top -l 1 -n 0)

    # Capture `top` output for CPU usage
    top_output=$(top -l 1 -n 0 | awk '/CPU usage:/ {print $3 "," $5 "," $7}')

    # Extract used and unused memory values and convert GB to MB if necessary
        used_mem=$(top -l 1 -n 0 | awk '/PhysMem:/ {print $2}')
        unused_mem=$(top -l 1 -n 0 | awk '/PhysMem:/ {print $6}')

        # Convert GB to MB if the value is in gigabytes
        if [[ $used_mem == *G ]]; then
            used_mem=$(echo "$used_mem" | tr -d 'G' | awk '{printf "%.0f\n", $1 * 1024}')
        fi

        if [[ $unused_mem == *G ]]; then
            unused_mem=$(echo "$unused_mem" | tr -d 'G' | awk '{printf "%.0f\n", $1 * 1024}')
        fi

        memory_output="$used_mem,$unused_mem"

        info=$(top -l 1 -n 0 | grep --line-buffered -e '.*CPU\susage.*\|PhysMem.*')

        bitrise :annotations annotate -s info -c top "$info"

        # Append data to the CSV files
        echo "$timestamp,$top_output" >> "$cpu_output_file"
        echo "$timestamp,$memory_output" >> "$memory_output_file"

        cp memory_usage.csv $BITRISE_DEPLOY_DIR/memory_usage.csv
        cp cpu_usage.csv $BITRISE_DEPLOY_DIR/cpu_usage.csv

        generate_charts

        # Wait for 5 seconds
        sleep 5
    done
}

looper &