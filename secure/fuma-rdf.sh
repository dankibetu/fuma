#!/bin/bash

# 1. Force Headless Environment for Oracle Toolkit (Fixes REP-3000)
unset DISPLAY
export RECON_HEADLESS_X11=True
export TK_PRINTER_DEFAULT=pdf

# Ensure Oracle environment variables are loaded
if [ -z "$ORACLE_HOME" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] ORACLE_HOME is not set. Please source your environment."
    exit 1
fi

# Check if at least one RDF file is provided
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 file1.rdf [file2.rdf ...]"
    exit 1
fi

# Define your password here. Leave it blank "" to force a prompt.
APPS_PASS="M0b#r3AmJustycE"
rdf_files=("$@")

# If APPS_PASS is blank, securely prompt the user
if [ -z "$APPS_PASS" ]; then
    read -s -p "APPS_PASS is blank. Enter Oracle APPS password: " APPS_PASS
    echo "" 
fi

# Setup working directories
mkdir -p rwconverter xdo logs

# Loop through the files array
for rdffile in "${rdf_files[@]}"; do
    filename=$(basename "$rdffile")
    base_name="${filename%.*}"
    log_file="logs/${base_name}.log"
    
    echo "==========================================================" | tee -a "$log_file"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Processing File: $filename" | tee -a "$log_file"
    echo "==========================================================" | tee -a "$log_file"
    
    if [ ! -f "$rdffile" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] Source file $rdffile not found! Skipping..." | tee -a "$log_file"
        continue
    fi

    # Step 1: rwconverter
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [1/2] Starting rwconverter..." | tee -a "$log_file"
    
    $ORACLE_HOME/bin/rwconverter userid=APPS/"$APPS_PASS" \
        stype=rdffile \
        source="./$rdffile" \
        dtype=xmlfile \
        dest="rwconverter/${base_name}.xml" \
        batch=yes \
        overwrite=yes >> "$log_file" 2>&1

    # Text-based error validation against Oracle Toolkit/Segfault exceptions
    if grep -q "REP-" "$log_file" || grep -q "Segmentation fault" "$log_file"; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] rwconverter failed. Check $log_file" | tee -a "$log_file"
        continue
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] --> rwconverter completed successfully." | tee -a "$log_file"

    # Step 2: BIPBatchConversion
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [2/2] Starting BIPBatchConversion..." | tee -a "$log_file"
    
    java oracle.apps.xdo.rdfparser.BIPBatchConversion \
        -source "./rwconverter/${base_name}.xml" \
        -target ./xdo \
        -debug >> "$log_file" 2>&1

    if grep -q "no action was performed" "$log_file"; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] Java completed but no action was performed." | tee -a "$log_file"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] --> BIPBatchConversion completed successfully." | tee -a "$log_file"
    fi
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Finished processing: $filename" | tee -a "$log_file"
    echo "Log file saved to: $log_file"
    echo ""
done

echo "[$(date '+%Y-%m-%d %H:%M:%S')] All tasks processed successfully."
