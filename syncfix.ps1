# Spelunky 2 (1.28, Steam) online "Syncing" freeze fix. See README.md for the details.
#
# Changes 19 bytes in Spel2.exe so the sync barrier after a level transition runs the
# next tick right away instead of pushing it 1/60 s into the future on every frame.
#
#   install.cmd                                   install (double-click)
#   powershell -File syncfix.ps1 -Check           read only, show whether it is installed
#   powershell -File syncfix.ps1 -Uninstall       put the original bytes back
#   powershell -File syncfix.ps1 -Exe "D:\...\Spel2.exe"   use this exe instead of searching Steam
param(
    [string]$Exe,
    [switch]$Check,
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'

$Rva = 0x22CBF261  # WinMain, sync barrier success
$Original = [byte[]](0x66,0x41,0x0f,0x28,0xc0,0xf2,0x0f,0x58,0xc1,0xf2,0x0f,0x11,0x05,0xbe,0xf4,0x15,0x00,0xeb,0x08)
$Patched  = [byte[]](0x66,0x41,0x0f,0x28,0xc0,0xf2,0x0f,0x5c,0xc3,0xf2,0x0f,0x5c,0xc3,0xeb,0x0c,0x0f,0x1f,0x40,0x00)

function Find-Game {
    $candidates = @(Join-Path $PSScriptRoot 'Spel2.exe')
    $steam = 'C:\Program Files (x86)\Steam'
    try { $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam').SteamPath } catch {}
    $libs = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
            $libs += $m.Groups[1].Value -replace '\\\\', '\'
        }
    }
    foreach ($lib in $libs) { $candidates += Join-Path $lib 'steamapps\common\Spelunky 2\Spel2.exe' }
    $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Get-FileOffset([System.IO.FileStream]$f, [long]$rva) {
    # translate the RVA to a file offset with the PE section table
    $r = New-Object System.IO.BinaryReader($f)
    $f.Position = 0x3C; $pe = $r.ReadInt32()
    $f.Position = $pe + 6; $sections = $r.ReadUInt16()
    $f.Position = $pe + 20; $optSize = $r.ReadUInt16()
    $f.Position = $pe + 24 + $optSize
    for ($i = 0; $i -lt $sections; $i++) {
        $null = $r.ReadBytes(8)
        $vsize = $r.ReadUInt32(); $vaddr = $r.ReadUInt32(); $rawSize = $r.ReadUInt32(); $rawPtr = $r.ReadUInt32()
        $null = $r.ReadBytes(16)
        if ($rva -ge $vaddr -and $rva -lt $vaddr + [Math]::Max($vsize, $rawSize)) { return $rva - $vaddr + $rawPtr }
    }
    throw 'patch address is not inside any section'
}

function Same([byte[]]$a, [byte[]]$b) { -not (Compare-Object $a $b -SyncWindow 0) }

if (-not $Exe) { $Exe = Find-Game }
if (-not $Exe -or -not (Test-Path $Exe)) { throw 'Spel2.exe not found. Put these files in the game folder or pass -Exe "path\to\Spel2.exe"' }
Write-Host "game: $Exe"

$f = [System.IO.File]::Open($Exe, 'Open', 'Read', 'ReadWrite')
try {
    $offset = Get-FileOffset $f $Rva
    $f.Position = $offset
    $current = New-Object byte[] $Original.Length
    $null = $f.Read($current, 0, $current.Length)
} finally { $f.Close() }

if (Same $current $Original) { $state = 'not installed' }
elseif (Same $current $Patched) { $state = 'installed' }
else { throw ('unexpected bytes at the patch site (not Spelunky 2 1.28 Steam?), nothing changed: ' + (($current | ForEach-Object { $_.ToString('x2') }) -join ' ')) }

if ($Check) { Write-Host "sync fix is $state"; return }

$want = if ($Uninstall) { $Original } else { $Patched }
if (Same $current $want) { Write-Host "nothing to do, sync fix is already $state"; return }

try { $f = [System.IO.File]::Open($Exe, 'Open', 'ReadWrite', 'Read') }
catch { throw 'cannot write Spel2.exe, close the game first' }
try {
    $f.Position = $offset
    $f.Write($want, 0, $want.Length)
    $f.Flush()
    $f.Position = $offset
    $null = $f.Read($current, 0, $current.Length)
} finally { $f.Close() }
if (-not (Same $current $want)) { throw 'verify failed' }

if ($Uninstall) { Write-Host 'original bytes restored' } else { Write-Host 'sync fix installed, you can play normally now' }
