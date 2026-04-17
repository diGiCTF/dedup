# dedup

A wordlist deduplicator for password-cracking workflows. Keeps a running **master** list of every word you've ever tried against a given engagement, and emits a **filtered** list containing only the words that are genuinely new.

The point is simple: don't waste GPU time re-hashing words you've already tried.

---

## Install

```bash
git clone https://github.com/diGiCTF/dedup.git
cd dedup
./install.sh              # installs to ~/.local/bin (no sudo)
# or
./install.sh --system     # installs to /usr/local/bin (sudo)
# or
./install.sh --prefix /opt/tools
```

The installer drops a symlink named `dedup` into the chosen `bin` directory, so you can call it from anywhere:

```bash
dedup -m ncl2026 new_list.txt
```

Uninstall with `./install.sh --uninstall` (add `--system` or `--prefix` if that's where you installed it).

---

## Usage

```
dedup [-m <reference_name>] [-d <dir>] [-q] <new_wordlist | ->
```

| Flag | Description |
|------|-------------|
| `-m`, `--master <name>` | Reference namespace. Each engagement gets its own master file. Default: `default`. |
| `-d`, `--dir <path>` | Directory for master/filtered files. Falls back to `$DEDUP_DIR`, then the current directory. |
| `-q`, `--quiet` | Suppress the summary output. |
| `-h`, `--help` | Show help. |
| `-` | Read the new wordlist from stdin. |

### Files produced

For a given reference name, two files live in `<dir>`:

- `dedup_<name>_master.txt` — the cumulative history of every unique word you've ever fed through this namespace.
- `dedup_<name>_filtered.txt` — the **delta** from the most recent run: only words not already in master. This is what you feed to hashcat.

---

## Workflow: NCL password cracking

A typical scenario across an NCL season or CTF engagement.

### 1. Seed the master

Prime it with the lists you've already tried (or plan to skip):

```bash
dedup -m ncl2026 /wordlists/rockyou.txt
```

Master is now rockyou. On a first run, there is no filtered output — there's nothing yet to subtract against.

### 2. Filter a new themed wordlist

A new challenge drops. You build a themed list — say, Star Wars names with common leet transformations applied:

```bash
dedup -m ncl2026 starwars_leet.txt
```

`dedup_ncl2026_filtered.txt` now contains only the Star Wars leet variants that weren't already in rockyou. Feed that to hashcat:

```bash
hashcat -m 1000 hashes.txt dedup_ncl2026_filtered.txt \
        -r /rules/OneRuleToRuleThemAll.rule
```

### 3. Fold cracked passwords back in

When hashcat cracks something, add those plaintexts to the master so they're never re-tried:

```bash
hashcat -m 1000 hashes.txt --show | cut -d: -f2- | dedup -m ncl2026 -
```

### 4. Repeat for each new challenge

Every new wordlist gets subtracted against the ever-growing master. Over the course of a season, `filtered.txt` keeps shrinking to just the novel candidates, and hashcat runs keep getting shorter.

---

## Namespaces

Use `-m` to keep engagements isolated:

- `-m ncl2026` — current NCL season
- `-m client_acme` — a client pentest
- `-m ctf_htb` — HTB boxes

No cross-contamination: what you tried against client A doesn't get skipped against client B.

---

## Storing state in one place

If you want all masters to live somewhere central instead of whatever directory you `cd`'d into, export `DEDUP_DIR`:

```bash
export DEDUP_DIR="$HOME/.dedup"
dedup -m ncl2026 new_list.txt
# writes to ~/.dedup/dedup_ncl2026_master.txt
```

Override per-invocation with `-d`.

---

## Output example

```
======================================
Filtered unique lines saved to: /home/user/.dedup/dedup_ncl2026_filtered.txt
======================================
Already in master:         14203
Duplicates within input:   47
New unique lines added:    1829
Master updated:            /home/user/.dedup/dedup_ncl2026_master.txt
```

- **Already in master** — words you'd have re-tried without this tool.
- **Duplicates within input** — the new wordlist itself had repeats.
- **New unique lines added** — the size of the filtered file and what got appended to master.

---

## Notes

- Line-exact comparison. `Password1` and `password1` are different words.
- Atomic master update: a crash mid-run won't corrupt your master.
- TTY-aware: ANSI color when interactive, plain text when piped.
- Reads stdin via `-`, so it composes with `hashcat --show`, `cut`, `awk`, `sort -u`, etc.
