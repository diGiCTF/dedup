# Deduplicate Wordlist Script

This script helps manage and deduplicate wordlists by comparing a new wordlist with an existing master wordlist. Unique entries from the new wordlist are appended to the master wordlist, and a filtered wordlist of new unique lines is created.

## Features
- Checks if a master wordlist exists and creates one if it doesn't.
- Filters out duplicates from the new wordlist.
- Saves unique lines to a filtered wordlist and appends them to the master wordlist.
- Provides detailed output about the deduplication process.

## Usage

```bash
./deduplicate_wordlist.sh new_wordlist.txt --master <reference_name>
```
