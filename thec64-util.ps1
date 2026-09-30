Set-StrictMode -Version Latest

$cjm = "THEC64-default.cjm"

$c64DreamsArchive = "C64 Dreams v0.60.7z"
$c64DreamsSrc = "C64 Dreams/C64 Dreams/Games"

$csdbDemosArchive = "CSDB Demos Jan2020.zip"
$csdbDemosSrc = "CSDB Demos Jan2020/Top200"

$oneload64Archive = "OneLoad64-Games-Collection-v5.7z"
$onneLoad64Src = "OneLoad64-Games-Collection-v5"

# Maximum length (including any extension) of a sanitized file/folder name.
$maxNameLen = 64

if (-not (Test-Path $cjm -PathType Leaf)) {
    Write-Error "Joystick mapping file not found: $cjm"
    exit 1
}

$cjmJoystickLines = Get-Content -Path $cjm | Select-Object -Skip 1

function Assert-7z {
    $sevenZip = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if (-not $sevenZip) {
        Write-Error "7z.exe not found. Install 7-Zip from https://www.7-zip.org/ and ensure 7z.exe is on PATH."
        exit 1
    }
    return $sevenZip.Source
}

# Extracts only the paths needed for $SrcDir out of $Archive into $DestDir, if
# $SrcDir doesn't already exist locally and $Archive is present. Falls back to
# a full extraction (with a warning) if the scoped extraction didn't produce
# $SrcDir. $ScopedPaths are archive-internal paths, relative to the archive
# root (not to $DestDir) - they may differ from $SrcDir if the archive doesn't
# itself contain a wrapping folder matching $DestDir.
function Assert-Extracted {
    param(
        [string]$SrcDir,
        [string]$Archive,
        [string]$Tool,
        [string]$DestDir,
        [string[]]$ScopedPaths
    )

    if (Test-Path $SrcDir -PathType Container) { return }
    if (-not (Test-Path $Archive -PathType Leaf)) { return }

    Write-Host "Extracting $Archive..."
    if ($Tool -eq "7z") {
        $sevenZipPath = Assert-7z
        & $sevenZipPath x $Archive @ScopedPaths "-o$DestDir" -y | Out-Null
        if (-not (Test-Path $SrcDir -PathType Container)) {
            Write-Warning "Scoped extraction of $Archive did not produce $SrcDir; extracting entire archive instead."
            & $sevenZipPath x $Archive "-o$DestDir" -y | Out-Null
        }
    } else {
        try {
            Expand-Archive -Path $Archive -DestinationPath $DestDir -Force -ErrorAction Stop
        } catch {
            Write-Error "Failed to extract $Archive`: $_"
            exit 1
        }
    }

    if (-not (Test-Path $SrcDir -PathType Container)) {
        Write-Error "Extraction of $Archive did not produce expected folder $SrcDir"
        exit 1
    }
}

function Write-Cjm {
    param(
        [string]$Dest,
        [bool]$IncludeAccuratedisk
    )
    $xLine = "X:64,pal"
    if ($IncludeAccuratedisk) { $xLine += ",accuratedisk" }

    $hasDisk = Get-ChildItem -Path $Dest -Include *.d64, *.g64, *.d81, *.d82 -ErrorAction SilentlyContinue
    if ($hasDisk) { $xLine += ",driveicon" }

    @($xLine) + $cjmJoystickLines | Set-Content -Path "$Dest\THEC64-default.cjm"
}

# Returns $Name (a name without its extension) made safe for a FAT32 USB drive
# and THEC64: non-printable-ASCII and FAT-reserved characters become "_" (runs
# collapsed), leading spaces/dots and trailing spaces/dots are stripped,
# Windows reserved device names get a "_" suffix, and the result is truncated
# so that it plus $Extension fits within $maxNameLen.
function Get-SanitizedName {
    param(
        [string]$Name,
        [string]$Extension = ""
    )
    $Name = $Name -replace '[^\x20-\x7E]|[<>:"\\|?*]', '_' -replace '_+', '_'
    $Name = $Name.TrimStart(' ', '.').TrimEnd(' ', '.')
    if ($Name -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { $Name += '_' }
    $maxLen = $maxNameLen - $Extension.Length
    if ($Name.Length -gt $maxLen) { $Name = $Name.Substring(0, $maxLen) }
    $Name = $Name.TrimEnd(' ', '.')
    if (-not $Name) { $Name = '_' }
    return $Name
}

# Returns a path $Dir\$Base$Extension that doesn't exist yet, appending " (n)"
# to $Base - truncated to stay within $maxNameLen - on collision.
function Get-UniquePath {
    param(
        [string]$Dir,
        [string]$Base,
        [string]$Extension = ""
    )
    $candidate = "$Dir\$Base$Extension"
    $n = 2
    while (Test-Path -LiteralPath $candidate) {
        $suffix = " ($n)"
        $len = [math]::Min($Base.Length, $maxNameLen - $Extension.Length - $suffix.Length)
        $candidate = "$Dir\$($Base.Substring(0, $len))$suffix$Extension"
        $n++
    }
    return $candidate
}

# Moves file $Item into directory $Dir under a sanitized, non-colliding name.
function Move-Sanitized {
    param(
        [System.IO.FileInfo]$Item,
        [string]$Dir
    )
    $ext = $Item.Extension
    $base = Get-SanitizedName -Name $Item.BaseName -Extension $ext
    Move-Item -LiteralPath $Item.FullName -Destination (Get-UniquePath -Dir $Dir -Base $base -Extension $ext)
}

function Invoke-ProcessSource {
    param(
        [string]$Src,
        [string]$Namespace,
        [bool]$IncludeAccuratedisk
    )

    if (-not (Test-Path $Src -PathType Container)) {
        Write-Error "Source directory not found: $Src"
        exit 1
    }

    $folder = ""
    $folder_ext = 0
    Get-ChildItem -Directory -Path $Src | ForEach-Object {
        $name = $_.Name
        if ($name.StartsWith('!')) { return }
        $file = Get-SanitizedName -Name $name
        $firstChar = $file.Substring(0, 1)
        $letter = if ($firstChar -match '\d') { '#' } else { $firstChar.ToUpper() }
        if ($folder -ne $letter) {
            $count = 0
            $folder = $letter
        }
        $folder_ext = [math]::Floor($count / 256)
        $count++
        $dest = Get-UniquePath -Dir "THEC64\$Namespace\$folder$folder_ext" -Base $file
        Write-Host "Processing: $name"
        if ((Split-Path -Leaf $dest) -cne $name) { Write-Host "  Renamed to: $(Split-Path -Leaf $dest)" }
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Get-ChildItem -Path "$($_.FullName)\*" -Include *.crt, *.d64, *.g64, *.d81, *.d82, *.crt, *.tap, *.t64, *.prg -ErrorAction SilentlyContinue | ForEach-Object {
            if (Test-Path -LiteralPath $_.FullName) {
                Move-Sanitized -Item $_ -Dir $dest
            }
        }
        if (-not (Get-ChildItem -Path $dest -Force)) {
            Remove-Item -Path $dest
        } else {
            Write-Cjm -Dest $dest -IncludeAccuratedisk $IncludeAccuratedisk
        }
    }
}

function Invoke-ProcessFlat {
    param(
        [string]$Src,
        [string]$Namespace,
        [bool]$IncludeAccuratedisk
    )

    if (-not (Test-Path $Src -PathType Container)) {
        Write-Error "Source directory not found: $Src"
        exit 1
    }

    Get-ChildItem -Directory -Path $Src | ForEach-Object {
        $name = $_.Name
        if ($name.StartsWith('!')) { return }
        $dest = Get-UniquePath -Dir "THEC64\$Namespace" -Base (Get-SanitizedName -Name $name)
        Write-Host "Processing: $name"
        if ((Split-Path -Leaf $dest) -cne $name) { Write-Host "  Renamed to: $(Split-Path -Leaf $dest)" }
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Get-ChildItem -Path "$($_.FullName)\*" -Include *.crt, *.d64, *.g64, *.d81, *.d82, *.crt, *.tap, *.t64, *.prg -ErrorAction SilentlyContinue | ForEach-Object {
            if (Test-Path -LiteralPath $_.FullName) {
                Move-Sanitized -Item $_ -Dir $dest
            }
        }
        if (-not (Get-ChildItem -Path $dest -Force)) {
            Remove-Item -Path $dest
        } else {
            Write-Cjm -Dest $dest -IncludeAccuratedisk $IncludeAccuratedisk
        }
    }
}

# OneLoad64 is flat: *.crt files sit directly in $Src, with additional
# multi-part files in a shared $Src\MultiLoad64\ folder. Each file (root or
# MultiLoad64) is treated as its own game, named after its own filename.
function Invoke-ProcessOneLoad64 {
    param(
        [string]$Src,
        [string]$Namespace,
        [bool]$IncludeAccuratedisk
    )

    if (-not (Test-Path $Src -PathType Container)) {
        Write-Error "Source directory not found: $Src"
        exit 1
    }

    $files = @(Get-ChildItem -Path "$Src\*.crt" -ErrorAction SilentlyContinue)
    $files += @(Get-ChildItem -Path "$Src\MultiLoad64\*.crt" -ErrorAction SilentlyContinue)

    $folder = ""
    $folder_ext = 0
    $count = 0
    $seen = @{}
    foreach ($item in $files) {
        $base = $item.BaseName
        if ($base.StartsWith('!')) { continue }

        $name = Get-SanitizedName -Name $base
        $nameLc = $name.ToLower()
        if ($seen.ContainsKey($nameLc)) {
            Write-Warning "'$name' found more than once across the OneLoad64 root and MultiLoad64 folder; merging into the same destination folder."
        }
        $seen[$nameLc] = $true

        $firstChar = $name.Substring(0, 1)
        $letter = if ($firstChar -match '\d') { '#' } else { $firstChar.ToUpper() }
        if ($folder -ne $letter) {
            $count = 0
            $folder = $letter
        }
        $folder_ext = [math]::Floor($count / 256)
        $count++
        Write-Host "Processing: $base"
        if ($name -cne $base) { Write-Host "  Renamed to: $name" }
        $dest = "THEC64\$Namespace\$folder$folder_ext\$name"
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Move-Sanitized -Item $item -Dir $dest
        Write-Cjm -Dest $dest -IncludeAccuratedisk $IncludeAccuratedisk
    }
}

Assert-Extracted -SrcDir $c64DreamsSrc -Archive $c64DreamsArchive -Tool "7z" -DestDir "." -ScopedPaths @("C64 Dreams/C64 Dreams/Games/*")
Invoke-ProcessSource -Src $c64DreamsSrc -Namespace "C64-Dreams" -IncludeAccuratedisk $false

Assert-Extracted -SrcDir $csdbDemosSrc -Archive $csdbDemosArchive -Tool "zip" -DestDir "CSDB Demos Jan2020" -ScopedPaths @("Top200/*")
Invoke-ProcessFlat -Src $csdbDemosSrc -Namespace "CSDB-Demos" -IncludeAccuratedisk $true

Assert-Extracted -SrcDir $onneLoad64Src -Archive $oneload64Archive -Tool "7z" -DestDir "OneLoad64-Games-Collection-v5" -ScopedPaths @("*.crt", "MultiLoad64/*.crt")
Invoke-ProcessOneLoad64 -Src $onneLoad64Src -Namespace "One-Load-64" -IncludeAccuratedisk $false
