#!/bin/bash
shopt -s nullglob
shopt -s nocaseglob

cjm="THEC64-default.cjm"

c64_dreams_archive="C64 Dreams v0.60.7z"
c64_dreams_src="C64 Dreams/C64 Dreams/Games"

csdb_demos_archive="CSDB Demos Jan2020.zip"
csdb_demos_src="CSDB Demos Jan2020/Top200"

oneload64_archive="OneLoad64-Games-Collection-v5.7z"
oneload64_src="OneLoad64-Games-Collection-v5"

# Maximum length (including any extension) of a sanitized file/folder name.
max_name_len=64

if [[ ! -f "$cjm" ]]; then
    echo "Error: joystick mapping file not found: $cjm" >&2
    exit 1
fi

cjm_joystick_lines=$(tail -n +2 "$cjm")

require_7z() {
    if command -v 7z >/dev/null 2>&1; then
        echo 7z
    elif command -v 7zz >/dev/null 2>&1; then
        echo 7zz
    else
        echo "Error: 7z/7zz not found. Install p7zip to extract archives:" >&2
        echo "  macOS:         brew install p7zip" >&2
        echo "  Debian/Ubuntu: sudo apt install p7zip-full" >&2
        exit 1
    fi
}

require_unzip() {
    if ! command -v unzip >/dev/null 2>&1; then
        echo "Error: unzip not found. Install it to extract archives:" >&2
        echo "  macOS:         brew install unzip (usually preinstalled)" >&2
        echo "  Debian/Ubuntu: sudo apt install unzip" >&2
        exit 1
    fi
}

# Extracts only the paths needed for $src_dir out of $archive into $dest_dir,
# if $src_dir doesn't already exist locally and $archive is present. Falls
# back to a full extraction (with a warning) if the scoped extraction didn't
# produce $src_dir. $scoped_paths are archive-internal paths, relative to the
# archive root (not to $dest_dir) - they may differ from $src_dir if the
# archive doesn't itself contain a wrapping folder matching $dest_dir.
require_extracted() {
    local src_dir="$1"
    local archive="$2"
    local tool="$3"
    local dest_dir="$4"
    shift 4
    local scoped_paths=("$@")

    [[ -d "$src_dir" ]] && return 0
    [[ -f "$archive" ]] || return 0

    echo "Extracting $archive..."
    if [[ "$tool" == "7z" ]]; then
        local sevenzip
        sevenzip=$(require_7z)
        "$sevenzip" x "$archive" "${scoped_paths[@]}" -o"$dest_dir" -y >/dev/null
        if [[ ! -d "$src_dir" ]]; then
            echo "Warning: scoped extraction of $archive did not produce $src_dir; extracting entire archive instead." >&2
            "$sevenzip" x "$archive" -o"$dest_dir" -y >/dev/null
        fi
    else
        require_unzip
        if ! unzip -q -o "$archive" "${scoped_paths[@]}" -d "$dest_dir"; then
            if command -v 7z >/dev/null 2>&1 || command -v 7zz >/dev/null 2>&1; then
                echo "Warning: unzip reported errors extracting $archive (e.g. a non-UTF-8 filename in the archive); retrying the same paths with 7z." >&2
                local sevenzip
                sevenzip=$(require_7z)
                "$sevenzip" x "$archive" "${scoped_paths[@]}" -o"$dest_dir" -y >/dev/null
            fi
        fi
        if [[ ! -d "$src_dir" ]]; then
            echo "Warning: scoped extraction of $archive did not produce $src_dir; extracting entire archive instead." >&2
            unzip -q -o "$archive" -d "$dest_dir"
        fi
    fi

    if [[ ! -d "$src_dir" ]]; then
        echo "Error: extraction of $archive did not produce expected folder $src_dir" >&2
        exit 1
    fi
}

write_cjm() {
    local dest="$1"
    local include_accuratedisk="$2"
    local x_line="X:64,pal"
    local has_disk=0 d

    [[ "$include_accuratedisk" -eq 1 ]] && x_line="${x_line},accuratedisk"

    for d in "$dest"/*.{d64,g64,d81,d82}; do
        [[ -f "$d" ]] && { has_disk=1; break; }
    done
    [[ $has_disk -eq 1 ]] && x_line="${x_line},driveicon"

    { echo "$x_line"; echo "$cjm_joystick_lines"; } > "$dest/THEC64-default.cjm"
}

# Prints $1 (a name without its extension) made safe for a FAT32 USB drive and
# THEC64: non-printable-ASCII and FAT-reserved characters become "_" (runs
# collapsed), leading spaces/dots and trailing spaces/dots are stripped,
# Windows reserved device names get a "_" suffix, and the result is truncated
# so that it plus extension $2 fits within $max_name_len.
sanitize_name() {
    local name="$1" ext="$2" upper
    name=$(printf '%s' "$name" | LC_ALL=C tr -c ' -~' '_' | LC_ALL=C tr '<>:"\\|?*' '_' | LC_ALL=C tr -s '_')
    while [[ "$name" == [\ .]* ]]; do name="${name#?}"; done
    while [[ "$name" == *[\ .] ]]; do name="${name%?}"; done
    upper=$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')
    case "$upper" in
        CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9]) name="${name}_" ;;
    esac
    name="${name:0:$((max_name_len - ${#ext}))}"
    while [[ "$name" == *[\ .] ]]; do name="${name%?}"; done
    [[ -z "$name" ]] && name="_"
    printf '%s\n' "$name"
}

# Prints a path $1/$2$3 (dir, base, extension) that doesn't exist yet,
# appending " (n)" to the base - truncated to stay within $max_name_len - on
# collision.
unique_path() {
    local dir="$1" base="$2" ext="$3" candidate suffix n=2
    candidate="$dir/$base$ext"
    while [[ -e "$candidate" ]]; do
        suffix=" ($n)"
        candidate="$dir/${base:0:$((max_name_len - ${#ext} - ${#suffix}))}$suffix$ext"
        n=$((n + 1))
    done
    printf '%s\n' "$candidate"
}

# Moves file $1 into directory $2 under a sanitized, non-colliding name.
move_sanitized() {
    local f="$1" dir="$2" file ext
    file=$(basename "$f")
    ext=".${file##*.}"
    mv "$f" "$(unique_path "$dir" "$(sanitize_name "${file%.*}" "$ext")" "$ext")"
}

process_source() {
    local src="$1"
    local namespace="$2"
    local include_accuratedisk="$3"
    local folder="" folder_ext="" count=0 name file letter dest f i

    if [[ ! -d "$src" ]]; then
        echo "Error: source directory not found: $src" >&2
        exit 1
    fi

    for i in "$src"/*/; do
        name=$(basename "$i")
        if [[ "${name:0:1}" != "!" ]]; then
            file=$(sanitize_name "$name")
            letter=$(echo "${file:0:1}" | tr '[:digit:]' '#' | tr '[:lower:]' '[:upper:]')
            if [[ "$folder" != "$letter" ]]; then
                count=0
                folder=$letter
            fi
            folder_ext=$((count++ / 256))
            dest=$(unique_path "THEC64/$namespace/$folder$folder_ext" "$file")
            echo "Processing: $name"
            [[ "${dest##*/}" != "$name" ]] && echo "  Renamed to: ${dest##*/}"
            mkdir -p "$dest"
            for f in "$i"*.{crt,d64,g64,d81,d82,crt,tap,t64,prg}; do
                [[ -f "$f" ]] || continue
                move_sanitized "$f" "$dest"
            done
            if [[ -z "$(ls -A "$dest")" ]]; then
                rmdir "$dest"
            else
                write_cjm "$dest" "$include_accuratedisk"
            fi
        fi
    done
}

process_flat() {
    local src="$1"
    local namespace="$2"
    local include_accuratedisk="$3"
    local name dest f i

    if [[ ! -d "$src" ]]; then
        echo "Error: source directory not found: $src" >&2
        exit 1
    fi

    for i in "$src"/*/; do
        name=$(basename "$i")
        if [[ "${name:0:1}" != "!" ]]; then
            dest=$(unique_path "THEC64/$namespace" "$(sanitize_name "$name")")
            echo "Processing: $name"
            [[ "${dest##*/}" != "$name" ]] && echo "  Renamed to: ${dest##*/}"
            mkdir -p "$dest"
            for f in "$i"*.{crt,d64,g64,d81,d82,crt,tap,t64,prg}; do
                [[ -f "$f" ]] || continue
                move_sanitized "$f" "$dest"
            done
            if [[ -z "$(ls -A "$dest")" ]]; then
                rmdir "$dest"
            else
                write_cjm "$dest" "$include_accuratedisk"
            fi
        fi
    done
}

# OneLoad64 is flat: *.crt files sit directly in $src, with additional
# multi-part files in a shared $src/MultiLoad64/ folder. Each file (root or
# MultiLoad64) is treated as its own game, named after its own filename.
process_oneload64() {
    local src="$1"
    local namespace="$2"
    local include_accuratedisk="$3"
    local folder="" folder_ext="" count=0 file base name name_lc letter dest f
    local -A seen

    if [[ ! -d "$src" ]]; then
        echo "Error: source directory not found: $src" >&2
        exit 1
    fi

    for f in "$src"/*.crt "$src"/MultiLoad64/*.crt; do
        [[ -f "$f" ]] || continue
        file=$(basename "$f")
        base="${file%.*}"
        [[ "${base:0:1}" == "!" ]] && continue

        name=$(sanitize_name "$base")
        name_lc=$(echo "$name" | tr '[:upper:]' '[:lower:]')
        if [[ -n "${seen[$name_lc]:-}" ]]; then
            echo "Warning: '$name' found more than once across the OneLoad64 root and MultiLoad64 folder; merging into the same destination folder." >&2
        fi
        seen[$name_lc]=1

        letter=$(echo "${name:0:1}" | tr '[:digit:]' '#' | tr '[:lower:]' '[:upper:]')
        if [[ "$folder" != "$letter" ]]; then
            count=0
            folder=$letter
        fi
        folder_ext=$((count++ / 256))
        dest="THEC64/$namespace/$folder$folder_ext/$name"
        echo "Processing: $base"
        [[ "$name" != "$base" ]] && echo "  Renamed to: $name"
        mkdir -p "$dest"
        move_sanitized "$f" "$dest"
        write_cjm "$dest" "$include_accuratedisk"
    done
}

require_extracted "$c64_dreams_src" "$c64_dreams_archive" "7z" "." "C64 Dreams/C64 Dreams/Games/*"
process_source "$c64_dreams_src" "C64-Dreams" 0

require_extracted "$csdb_demos_src" "$csdb_demos_archive" "zip" "CSDB Demos Jan2020" "Top200/*"
process_flat "$csdb_demos_src" "CSDB-Demos" 1

require_extracted "$oneload64_src" "$oneload64_archive" "7z" "OneLoad64-Games-Collection-v5" "*.crt" "MultiLoad64/*.crt"
process_oneload64 "$oneload64_src" "One-Load-64" 0
