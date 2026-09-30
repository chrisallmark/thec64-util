# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

A cross-platform shell utility that converts three curated Commodore 64 collections — [C64 Dreams](https://www.c64-wiki.com/wiki/C64_Dreams), CSDB Demos Jan2020, and OneLoad64 Games Collection — into a folder structure compatible with THEC64 retro consoles. Users run the script, then copy the output `THEC64/` folder to a USB drive for use with the console.

## Running the Scripts

**Zsh (primary — macOS/Linux):**
```zsh
./thec64-util.zsh
```

**Bash:**
```bash
./thec64-util.bash
```

**PowerShell (Windows):**
```powershell
powershell.exe -ExecutionPolicy Bypass .\thec64-util.ps1
```

There are no build, test, or lint steps — the scripts run directly.

## Architecture

Three parallel implementations (`.zsh`, `.bash`, `.ps1`) share the same logic, applied independently to three sources via three shared per-script helper functions: `process_source`/`Invoke-ProcessSource` (bucketed, alphabetic split, one subfolder per game), `process_flat`/`Invoke-ProcessFlat` (no split, one subfolder per demo), and `process_oneload64`/`Invoke-ProcessOneLoad64` (bucketed, alphabetic split, but the source is flat files rather than subfolders).

| Collection | Source | Destination | Helper | File selection |
|---|---|---|---|---|
| C64 Dreams | `C64 Dreams/C64 Dreams/Games/` | `THEC64/C64-Dreams/` | `process_source` | all supported extensions, one subfolder per game |
| CSDB Demos | `CSDB Demos Jan2020/Top200/` | `THEC64/CSDB-Demos/` | `process_flat` | all supported extensions, one subfolder per demo |
| OneLoad64 | `OneLoad64-Games-Collection-v5/` | `THEC64/One-Load-64/` | `process_oneload64` | only `*.crt` files sitting directly in the source root, plus `*.crt` files in a shared `MultiLoad64/` subfolder — each file is its own game, named after the file |

### Automatic extraction

Before each collection is processed, a `require_extracted`/`Assert-Extracted` helper checks whether the collection's source folder already exists; if not, and the collection's archive file is present next to the script, it extracts **only the paths that collection needs** (not the whole archive) into an explicit destination directory, then falls back to a full extraction into that same destination (with a warning) if the scoped extraction didn't produce the expected folder. If neither the source folder nor the archive exists, the existing "source directory not found" validation error fires as before.

In the Zsh/Bash `unzip` path only, if `unzip` exits non-zero (e.g. a `checkdir error: ... Illegal byte sequence` from a non-UTF-8 or malformed-UTF-8 filename stored in the archive — a real issue hit with the CSDB Demos `.zip`, which has at least one double-UTF-8-encoded entry that macOS's native `unzip` refuses to create), the same scoped paths are retried with `7z`/`7zz` (if installed) into the same destination directory before falling through to the existing full-extraction fallback. This is a Zsh/Bash-only workaround: PowerShell's `Expand-Archive` (.NET) doesn't do the strict filesystem-level UTF-8 validation that trips up native `unzip`, so it isn't affected by this failure mode and extracts such entries (with a garbled name, since the archive's own filename bytes are corrupt) without erroring.

Scoped paths are archive-internal paths, relative to the archive root — they are **not** the same as the local source folder path when the archive itself doesn't contain a wrapping folder matching that convention. This was the cause of two real bugs found in testing: both the CSDB Demos `.zip` and the OneLoad64 `.7z` turned out to hold their content (`Top200/`, and `.crt`/`MultiLoad64/` respectively) directly at the archive root with no wrapping folder inside, so extracting them straight into the working directory (the original, incorrect implementation) dumped their contents loose at the top level instead of into the expected nested source folder. The fix: pass an explicit destination directory to the extraction tool (`7z -o`, `unzip -d`, `Expand-Archive -DestinationPath`) matching the local wrapping folder, and scope extraction paths to the archive's actual root-relative layout.

| Collection | Archive filename | Tool | Destination dir | Scoped extraction paths (relative to archive root) |
|---|---|---|---|---|
| C64 Dreams | `C64 Dreams v0.60.7z` | `7z`/`7zz` | `.` (archive already nests `C64 Dreams/C64 Dreams/Games` internally) | `C64 Dreams/C64 Dreams/Games/*` |
| CSDB Demos | `CSDB Demos Jan2020.zip` | `unzip` / `Expand-Archive` | `CSDB Demos Jan2020` | `Top200/*` |
| OneLoad64 | `OneLoad64-Games-Collection-v5.7z` | `7z`/`7zz` | `OneLoad64-Games-Collection-v5` | `*.crt`, `MultiLoad64/*.crt` |

`require_7z`/`Assert-7z` and `require_unzip` check for the extraction tool and print install instructions (no auto-install) if missing. PowerShell's zip extraction uses the built-in `Expand-Archive`, so no tool check is needed there.

Pipeline stages (once a source is available):

1. **Validation** — exits early with an error if a source directory or `THEC64-default.cjm` are not found
2. **Input** — `process_source`/`process_flat` read immediate subdirectories of the source root, one game/demo per subdirectory; `process_oneload64` instead reads `.crt` files directly (root and `MultiLoad64/`), one game per file
3. **Exclusion** — entries whose names begin with `!` are skipped (C64 Dreams uses this prefix to mark disabled/broken entries; applied to all three collections)
4. **Sorting** (`process_source` and `process_oneload64` only) — entries are grouped by first letter (A–Z); names starting with a digit all map to the `#` bucket
5. **Folder-size cap** (`process_source` and `process_oneload64` only) — each output folder holds at most 256 entries; if a letter's entries exceed this, they are split into numbered sub-buckets (e.g. `A0`, `A1`); the sub-bucket index is appended directly to the letter, so `#0`, `A0`, `B0`, etc. CSDB Demos is processed flat (no letter/number bucket layer) since it fits under the 256 cap as-is
6. **Supported extensions** — `d64 g64 d81 d82 crt tap t64 prg`, matched case-insensitively, except OneLoad64 which only matches `.crt`
7. **Name sanitization** — every output folder name and moved file name is passed through `sanitize_name` so it's safe on a FAT32 USB drive and on THEC64 (see "Name sanitization" below). Bucket letters are derived from the *sanitized* name, not the original
8. **Output** — **moves** (not copies) ROM files into the destination folder (via `move_sanitized`) and generates a `THEC64-default.cjm` there; subfolders that end up empty (no matching ROM files) are removed instead. Collisions never overwrite: `unique_path` appends ` (2)`, ` (3)`, … to the base name. For C64 Dreams/CSDB Demos this applies to game/demo folders (two source folders that sanitize to the same name get `Name` and `Name (2)`) and to files within a folder. In `process_oneload64`, if two source files (root and/or `MultiLoad64/`) sanitize to the same name (compared case-insensitively), a warning is logged, both are merged into the same destination folder, and the second file is renamed (e.g. `Game (2).crt`). When a name changes, a `  Renamed to: …` line is printed under `Processing: …`

### Name sanitization

`sanitize_name <name> [ext]` (name passed without extension) applies, in order:
1. Any byte outside printable ASCII (space–`~`) and the FAT-reserved characters `< > : " \ | ? *` become `_`; runs of `_` are then collapsed to one (note: this also collapses underscores that were already in the original name)
2. Leading spaces/dots and trailing spaces/dots are stripped
3. Windows reserved device names (`CON`, `PRN`, `AUX`, `NUL`, `COM1`–`COM9`, `LPT1`–`LPT9`, case-insensitive) get a `_` suffix
4. Truncated so that name + extension fits within `max_name_len` (64) characters, then trailing spaces/dots are stripped again
5. An empty result becomes `_`

`unique_path` also respects `max_name_len`, truncating the base further to make room for the ` (n)` suffix. File extensions are preserved as-is (not lowercased).

PowerShell equivalents are `Get-SanitizedName`, `Get-UniquePath`, `Move-Sanitized` and `$maxNameLen`. The Zsh/Bash `LC_ALL=C tr` pipeline replaces each non-ASCII *byte*, while PowerShell's `-replace '[^\x20-\x7E]|[<>:"\\|?*]', '_'` replaces each UTF-16 *char*; because runs of `_` are then collapsed, both produce identical output (e.g. `Café: Déjà vu?` → `Caf_ D_j_ vu_`). The Zsh and Bash helper/process function bodies are byte-identical, so a change to one can be copied verbatim to the other.

Each of the three collections is processed with entirely independent bucket/count state (fresh per call), so entries in different collections never share a bucket even if they start with the same letter.

The 256-entries-per-folder limit is a hard THEC64 hardware constraint, not an implementation choice.

### `.cjm` generation

`THEC64-default.cjm` is no longer copied verbatim — it's generated per output folder by a shared `write_cjm`/`Write-Cjm` helper, built from the template's joystick-mapping (`J:`) lines plus a computed `X:` line:
- `X:64,pal` is always present
- `,accuratedisk` is appended only when the destination namespace is CSDB Demos
- `,driveicon` is appended only when the folder ends up containing at least one d64/g64/d81/d82 file

## Key Files

| File | Purpose |
|------|---------|
| `thec64-util.zsh` | Primary script (Zsh) |
| `thec64-util.bash` | Bash equivalent |
| `thec64-util.ps1` | Windows/PowerShell equivalent |
| `THEC64-default.cjm` | Joystick mapping template; its `J:` lines are reused verbatim in every generated output `.cjm` |

When modifying logic, all three implementations must stay in sync.
