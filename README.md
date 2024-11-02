# dedup

The dedup script is a command-line tool for managing wordlists by removing duplicate entries efficiently. It compares a new wordlist against a specified master wordlist, filtering out any lines already present in the master. Unique lines from the new wordlist are saved to a standardized filtered output file, and then appended to the master wordlist to keep it up-to-date. The script provides a summary after each run, showing how many lines were duplicates and how many were new. With the --master <name> option, you can manage multiple master wordlists by using different keywords, keeping files organized and deduplicated with ease.


Usage:
dedup wordlist.txt --master <name>

```
mv deduplicate_wordlist.sh dedup
chmod +x dedup

sudo mv dedup /usr/local/bin/


```
