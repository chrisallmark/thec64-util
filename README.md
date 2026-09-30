![THEC64 Util](THEC64.png)

<p align="center">THEC64 Utility Script</p>

<hr/>

A shell script to convert the [C64 Dreams](https://www.zombs-lair.com/blog/categories/c64-dreams) curated collection of C64 games, the Top 200 [CSDB Demos](https://archive.org/details/CSDB_Demo_Collection_January_2020), and the [OneLoad64](https://oneload64.github.io/) Games Collection, into a structure suitable for use with [THEC64](https://retrogames.biz/products/thec64/) games consoles.

## Running The Script

- Clone this repo or copy the most appropriate `thec64-util` script for your OS
- For each collection you want to process, either:
  - unzip/extract it yourself into the same folder as the script so the expected source folder exists (see table below), **or**
  - just drop the downloaded archive file next to the script — the script will extract only the files it needs from it automatically (see "Automatic extraction" below)
- Only the collections you actually want processed need to be present; any collection whose source folder and archive are both missing is skipped with an error for that collection

| Collection | Expected source folder | Expected archive filename |
|---|---|---|
| C64 Dreams | `C64 Dreams/C64 Dreams/Games` | `C64 Dreams v0.60.7z` |
| CSDB Demos | `CSDB Demos Jan2020/Top200` | `CSDB Demos Jan2020.zip` |
| OneLoad64 | `OneLoad64-Games-Collection-v5` | `OneLoad64-Games-Collection-v5.7z` |

### Automatic extraction

If a collection's source folder doesn't exist yet but its archive is present, the script extracts it automatically before processing — only pulling out the specific paths that collection needs (not the whole archive) to save time and disk space, into the expected source folder shown above. Note that the archives for CSDB Demos and OneLoad64 don't contain a wrapping folder internally (their `.zip`/`.7z` root holds `Top200/`, `.crt` files, and `MultiLoad64/` directly) — the script creates the wrapping folder itself as the extraction destination. If a scoped extraction doesn't produce the expected folder (e.g. the archive's internal layout doesn't match what's expected), the script falls back to extracting the entire archive into that same destination folder and prints a warning.

This requires an archive tool to be installed:
- `.7z` archives (C64 Dreams, OneLoad64) need `7z`/`7zz` on PATH (macOS/Linux: `brew install p7zip` or `apt install p7zip-full`; Windows: install [7-Zip](https://www.7-zip.org/) and ensure `7z.exe` is on PATH)
- `.zip` archives (CSDB Demos) need `unzip` on macOS/Linux (usually preinstalled); PowerShell uses its built-in `Expand-Archive`, no extra install needed

### Linux

#### BASH Shell:

```
chmod +x thec64-util.bash
./thec64-util.bash
```

#### Z Shell:

```
chmod +x thec64-util.zsh
./thec64-util.zsh
```

### Windows

#### Powershell:

Run (⊞+R) `powershell.exe -ExecutionPolicy Bypass`

```
.\thec64-util.ps1
```

---

Each collection is processed independently into its own folder under `/THEC64`:

| Collection | Source | Destination | Layout |
|---|---|---|---|
| C64 Dreams | `C64 Dreams/C64 Dreams/Games` | `THEC64/C64-Dreams` | one folder per game, split alphabetically (#, A...Z) and numerically (A0...A3) — max 256 games per folder |
| CSDB Demos | `CSDB Demos Jan2020/Top200` | `THEC64/CSDB-Demos` | one folder per demo, flat — no alphabetic split |
| OneLoad64 | `OneLoad64-Games-Collection-v5` | `THEC64/One-Load-64` | source is flat: `.crt` files sit directly in the collection root, with additional multi-part files in a shared `MultiLoad64` subfolder; each file becomes its own output game folder (named after the file), split alphabetically and numerically like C64 Dreams |

All supported extensions (d64, g64, d81, d82, crt, tap, t64, prg) are matched case-insensitively, except for OneLoad64 which only ever moves `.crt` files as described above.

Folder and file names are cleaned up so they're safe on a FAT32-formatted USB drive and readable on THEC64:
- accented/non-ASCII characters and characters FAT32 doesn't allow (`< > : " \ | ? *`) are replaced with `_`
- leading/trailing spaces and dots are removed
- Windows reserved names such as `CON` or `AUX` get a trailing `_`
- names are shortened to a maximum of 64 characters (including the extension)

Any renamed entry is logged as `Renamed to: …` under its `Processing: …` line. If two entries end up with the same name, whether they already matched or matched after clean-up, nothing is overwritten: the later one gets a numbered suffix, e.g. `Game (2)` / `Game (2).crt`. For OneLoad64, same-named files are merged into one game folder with a warning.

[NOTE!] A `THEC64-default.cjm` Commodore Joystick Mapping file is generated in each output folder, based on the settings in the template `THEC64-default.cjm` in this repo:

```
X:64,pal
J:2*:JU,JD,JL,JR,JF,JF,SP,1,SP,2,3,4,JF
J:1:JU,JD,JL,JR,JF,JF,F1,F2,JF,1,2,3,JF,F3,F4
```

Two options on the `X:` line are added conditionally per output folder rather than always being present:
- `accuratedisk` is only added for folders under `THEC64/CSDB-Demos`
- `driveicon` is only added when the folder contains at least one d64, g64, d81, or d82 file

Copy THEC64 folder to a suitable USB, plug in to your [THEC64](https://www.youtube.com/watch?v=4yOch48SScs) & enjoy!
