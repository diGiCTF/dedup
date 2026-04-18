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

During install you'll be asked two questions:

1. **Where should dedup store wordlists?** (default: `~/.dedup`) — saved to `~/.config/dedup/config` so every `dedup` invocation resolves to the same directory no matter where you `cd`.
2. **Add `dcd` shell helper?** (default: yes) — appends `dcd() { cd "$(dedup -p)"; }` to your `~/.bashrc` or `~/.zshrc` so you can jump to your wordlist directory with `dcd`.

Non-interactive install:

```bash
./install.sh --dir ~/.dedup --no-dcd -y
```

The installer drops a symlink named `dedup` into the chosen `bin` directory, so you can call it from anywhere:

```bash
dedup -m ncl2026 new_list.txt
```

Uninstall with `./install.sh --uninstall` (add `--system` or `--prefix` if that's where you installed it).

---

## Usage

```
dedup [options] <new_wordlist | ->
dedup -l [<name>] [-d <dir>]
dedup -p
dedup --set-path <dir>
dedup --normalize [<name>] [--case <mode>]
```

| Flag | Description |
|------|-------------|
| `-m`, `--master <name>` | Reference namespace. Each engagement gets its own master file. Default: `default`. |
| `-d`, `--dir <path>` | Directory for master/filtered files. Overrides the resolved default for this invocation only. |
| `-l`, `--locate [name]` | With a name: print the master's path to stdout (scriptable). Without a name: list all namespaces in `<dir>` with line counts and case mode. Exits non-zero if the named master does not exist. |
| `-p`, `--path` | Print the currently resolved dedup directory (source annotation on stderr). |
| `--set-path <dir>` | Persist `<dir>` as the default dedup directory (written to `~/.config/dedup/config`). |
| `--case <mode>` | Case normalization mode: `lower` (default), `upper`, `proper`, `preserve`. |
| `-L` / `-U` / `-P` / `-K` | Short toggles for `--case lower` / `upper` / `proper` / `preserve`. |
| `--force-case` | Override the case mode recorded in the namespace's metadata (otherwise a mismatch errors out). |
| `--normalize [name]` | Rewrite the master in-place using its recorded case (or `--case`). Dedups after transform. |
| `-q`, `--quiet` | Suppress the summary output. |
| `-h`, `--help` | Show help. |
| `-` | Read the new wordlist from stdin. |

### Directory resolution order

Each invocation resolves the dedup directory in this priority:

1. `-d <dir>` — per-invocation override
2. `$DEDUP_DIR` — environment variable
3. `~/.config/dedup/config` — persistent config (written by installer / `--set-path`)
4. Current directory — last resort

### Locating masters

```bash
# Print the path of a specific master (stdout is just the path — scriptable)
dedup -l ncl2026
# → /home/user/.dedup/dedup_ncl2026_master.txt

# Use it in a pipeline
wc -l "$(dedup -l ncl2026)"
grep -i admin "$(dedup -l ncl2026)"

# Guard clause: "have I started this namespace?"
if dedup -l ncl2026 >/dev/null 2>&1; then echo "exists"; fi

# List every namespace in the directory
dedup -l
# NAMESPACE             CASE          LINES  PATH
# ncl2026               lower         14203  /home/user/.dedup/dedup_ncl2026_master.txt
# client_acme           proper         8821  /home/user/.dedup/dedup_client_acme_master.txt
```

### Files produced

For a given reference name, three files live in `<dir>`:

- `dedup_<name>_master.txt` — the cumulative history of every unique word you've ever fed through this namespace.
- `dedup_<name>_filtered.txt` — the **delta** from the most recent run: only words not already in master. This is what you feed to hashcat.
- `dedup_<name>_master.meta` — namespace metadata (currently just the case mode). Managed automatically; safe to edit by hand.

---

## Case normalization

By default, `dedup` lowercases every line before comparing and storing it. That means `PRESIDENT47`, `President47`, and `president47` all collapse to a single `president47` entry in the master — so you get a clean, consistent wordlist to feed back into tools later.

### Modes

| Mode | Short flag | Effect |
|---|---|---|
| `lower` | `-L` | `tolower` the entire line (default) |
| `upper` | `-U` | `toupper` the entire line |
| `proper` | `-P` | `tolower`, then uppercase the first character (`president47` → `President47`) |
| `preserve` | `-K` | Keep as-is; case-sensitive compare |

```bash
# Default — case-insensitive + clean lowercase master
dedup -m ncl2026 list.txt

# Case-sensitive: treat Password1 and password1 as different words
dedup -m ncl2026 -K list.txt

# Proper case — useful for name-based lists
dedup -m starwars -P names.txt
```

### One mode per namespace

The first write pins the namespace's case mode into `dedup_<name>_master.meta`. Subsequent runs must match — if you try to mix modes, `dedup` refuses with a clear error:

```
Error: namespace 'ncl2026' is recorded as case=lower but --case upper was requested.
       Pass --force-case to change it, or run:
         dedup --normalize ncl2026 --case upper
```

This prevents a fat-fingered flag from silently contaminating a master built with a different case convention.

### Migrating or switching a namespace

If you want to change an existing namespace's case mode — or clean up a master built before case metadata existed — use `--normalize`:

```bash
# Rewrite the master using its recorded case (dedups after transform)
dedup --normalize ncl2026

# Or switch to a new case mode in one go
dedup --normalize ncl2026 --case proper
```

The master is rewritten atomically, duplicates that collapse under the new case are removed, and the meta file is updated.

### Seeing a namespace's case mode

`dedup -l` now shows the case column:

```
NAMESPACE             CASE          LINES  PATH
ncl2026               lower         14203  /home/user/.dedup/dedup_ncl2026_master.txt
starwars              proper          812  /home/user/.dedup/dedup_starwars_master.txt
legacy                -              4120  /home/user/.dedup/dedup_legacy_master.txt
```

A `-` in the `CASE` column means no meta file exists yet (pre-metadata master); run `--normalize` to adopt a mode.

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

## Managing the storage directory

The installer sets a persistent directory in `~/.config/dedup/config`. Inspect or change it at any time:

```bash
# Show the currently resolved directory (and why)
dedup -p
# → /home/user/.dedup
#   (source: config)  ← on stderr

# Switch to a different directory (e.g. moving to a new CTF workspace)
dedup --set-path ~/ctfs/ncl2026

# One-off override without touching the config
DEDUP_DIR=/tmp/throwaway dedup -m scratch list.txt
dedup -d /some/other/dir -m scratch list.txt
```

If you said "yes" to the `dcd` helper at install time, you can jump to the directory from any shell:

```bash
dcd   # cd into whatever `dedup -p` resolves to
```

---

## Output example

```
======================================
Filtered unique lines saved to: /home/user/.dedup/dedup_ncl2026_filtered.txt
======================================
Case mode:                 lower
Already in master:         14203
Duplicates within input:   47
New unique lines added:    1829
Master updated:            /home/user/.dedup/dedup_ncl2026_master.txt
```

- **Case mode** — which normalization was applied to the input lines before comparison.
- **Already in master** — words you'd have re-tried without this tool.
- **Duplicates within input** — the new wordlist itself had repeats (after case normalization).
- **New unique lines added** — the size of the filtered file and what got appended to master.

---

## Notes

- Default case mode is `lower` — `PRESIDENT47` and `president47` collapse to one entry. Override per-invocation with `-K` (preserve), `-U`, `-P`, or `--case <mode>`.
- Atomic master update: a crash mid-run won't corrupt your master.
- TTY-aware: ANSI color when interactive, plain text when piped.
- Reads stdin via `-`, so it composes with `hashcat --show`, `cut`, `awk`, `sort -u`, etc.
