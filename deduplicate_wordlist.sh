#!/bin/bash

# Usage: ./deduplicate_wordlist.sh new_wordlist.txt --master <reference_name_here>

# Check if a new wordlist file is provided
if [ -z "$1" ]; then
    echo "Usage: $0 new_wordlist.txt --master <reference_name>"
    exit 1
fi

# Define the input file
NEW_WORDLIST="$1"

# Check for the --master flag and set the master wordlist based on the reference name
if [ "$2" == "--master" ] && [ -n "$3" ]; then
    REFERENCE_NAME="$3"
    MASTER_WORDLIST="deduplicate_${REFERENCE_NAME}_master.txt"
    FILTERED_WORDLIST="deduplicate_${REFERENCE_NAME}_filtered.txt"
else
    echo "Error: Missing or incorrect usage of --master <reference_name>"
    echo "Usage: $0 new_wordlist.txt --master <reference_name>"
    exit 1
fi

# Check if the master wordlist exists; if not, create it from the first wordlist
if [ ! -f "$MASTER_WORDLIST" ]; then
    echo "Master wordlist ($MASTER_WORDLIST) not found. Creating it from $NEW_WORDLIST..."
    cp "$NEW_WORDLIST" "$MASTER_WORDLIST"
    echo "Master wordlist created: $MASTER_WORDLIST"
    exit 0
fi

# Use awk to filter out duplicates and save unique lines to the filtered wordlist
awk 'NR==FNR{seen[$0]=1; next} !($0 in seen)' "$MASTER_WORDLIST" "$NEW_WORDLIST" > "$FILTERED_WORDLIST"

# Count the number of lines that were already in the master wordlist
ALREADY_USED=$(awk 'NR==FNR{seen[$0]=1; next} ($0 in seen)' "$MASTER_WORDLIST" "$NEW_WORDLIST" | wc -l)

# Count the number of new unique lines added to the filtered wordlist
NEW_LINES=$(wc -l < "$FILTERED_WORDLIST")

# Append the new unique lines to the master wordlist
cat "$FILTERED_WORDLIST" >> "$MASTER_WORDLIST"

# Display results to the user with improved formatting
echo -e "======================================"
echo -e "Filtered unique lines saved to: \033[1;32m$FILTERED_WORDLIST\033[0m"
echo -e "======================================"
echo "Lines already present in $MASTER_WORDLIST: $ALREADY_USED"
echo "New unique lines added to filtered wordlist: $NEW_LINES"
echo "Master wordlist updated with new unique lines."
