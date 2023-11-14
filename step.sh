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

brew install gnuplot

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
plot "$cpu_output_file" using 1:2 with lines title "User CPU (%)", \
     "$cpu_output_file" using 1:3 with lines title "Sys CPU (%)", \
     "$cpu_output_file" using 1:4 with lines title "Idle CPU (%)"
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
plot "$memory_output_file" using 1:2 with lines title "Used PhysMem (MB)", \
     "$memory_output_file" using 1:3 with lines title "Unused PhysMem (MB)"
EOF

cat mem.html >> index.html


    # Create an HTML file to display the charts
    cat << HTML >> index.html
</body>
</html>
HTML

    echo "Charts generated in $cpu_html and $memory_html. Open index.html in a web browser to view the charts."

# Copy HTML and chart files to the desired location
    cp index.html "$BITRISE_DEPLOY_DIR/TOP.xcresult.index.html"
    cp cpu.html "$BITRISE_DEPLOY_DIR/cpu_chart.html"
    cp mem.html "$BITRISE_DEPLOY_DIR/memory_chart.html"
    # Commenting this out as it is not needed anymore due to the logic below
    # cp index.html "$BITRISE_DEPLOY_DIR/graph.html"

# Check if Env Var directory exists, if not set, the Env Var and copy the desired html report into the env var and chart files to the desired location

if [ -z "$BITRISE_HTML_REPORT_DIR" ]; then
    # If BITRISE_HTML_REPORT_DIR is not set, define a default directory
    HTML_REPORT_DIR="$BITRISE_DEPLOY_DIR"
else
    # If BITRISE_HTML_REPORT_DIR is set, use the specified directory
    HTML_REPORT_DIR="$BITRISE_HTML_REPORT_DIR"
fi

# Copy index.html to the determined directory
cp index.html "$HTML_REPORT_DIR/graph.html"

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