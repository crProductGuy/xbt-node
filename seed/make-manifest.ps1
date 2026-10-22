# make-manifest.ps1: hash the Bitcoin data on C: after a clean shutdown, and write the
# manifests that travel to the ext4 drive.
#
#   to-drive\chainstate.sha256   chainstate\*, blocks\index\*, blocks\xor.dat  (checked at copy time)
#   to-drive\blocks.sha256       every other file under blocks\                 (checked on the target machine)
#   to-drive\snapshot-info.txt   counts, sizes and the last tip lines from debug.log
#
# Both manifests are in sha256sum format with forward slashes and LF line endings.
# Run it only after Bitcoin has been shut down. It refuses while a bitcoin process exists.
#
#   pwsh -NoProfile -File make-manifest.ps1
#   pwsh -NoProfile -File make-manifest.ps1 -BitcoinDir <dir> -OutDir <dir> -Test    (tests)

param(
    [string]$BitcoinDir = "$env:APPDATA\Bitcoin",
    [string]$OutDir = (Join-Path $PSScriptRoot 'to-drive'),
    [int]$Throttle = 6,
    [switch]$Test
)

$ErrorActionPreference = 'Stop'
$BitcoinDir = (Get-Item -LiteralPath $BitcoinDir).FullName.TrimEnd('\')

if (-not $Test) {
    $running = Get-Process | Where-Object { $_.ProcessName -match '^bitcoin' }
    if ($running) { throw "Bitcoin is still running (pid $($running.Id -join ', ')). Shut it down first." }
    $tail = Get-Content -LiteralPath (Join-Path $BitcoinDir 'debug.log') -Tail 3
    if (-not ($tail -match 'Shutdown: done')) { throw "debug.log does not end with 'Shutdown: done'. The last shutdown was not clean." }
}

foreach ($d in 'blocks\index', 'chainstate') {
    if (-not (Test-Path -LiteralPath (Join-Path $BitcoinDir $d))) { throw "$d is missing under $BitcoinDir" }
}
New-Item -ItemType Directory -Force $OutDir | Out-Null

# Each file carries its path relative to the Bitcoin directory, taken from the top
# directory it was listed under, so an 8.3 short form of -BitcoinDir cannot skew it.
$files = @(foreach ($top in 'blocks', 'chainstate') {
    $topPath = (Get-Item -LiteralPath (Join-Path $BitcoinDir $top)).FullName.TrimEnd('\')
    Get-ChildItem -LiteralPath $topPath -Recurse -File -Force | ForEach-Object {
        if (-not $_.FullName.StartsWith("$topPath\", [StringComparison]::OrdinalIgnoreCase)) { throw "$($_.FullName) is not under $topPath" }
        [pscustomobject]@{ Full = $_.FullName; Length = $_.Length; Rel = ($top + $_.FullName.Substring($topPath.Length)).Replace('\', '/') }
    }
})
$bytes = ($files | Measure-Object Length -Sum).Sum

# Check the file set before hashing, so a surprise fails in seconds, not after the full run.
# blocks/.lock is the node's empty lock file; it travels with the rest.
$isSmall = { $_.Rel -like 'chainstate/*' -or $_.Rel -like 'blocks/index/*' -or $_.Rel -eq 'blocks/xor.dat' }
$odd = @($files | Where-Object { -not (& $isSmall) -and $_.Rel -notmatch '^blocks/((blk|rev)\d+\.dat|\.lock)$' })
if ($odd) { throw "unexpected files under blocks\: $($odd.Rel -join ', ')" }
"hashing $($files.Count) files, $([math]::Round($bytes / 1GB, 1)) GB ..."

$started = Get-Date
$rows = $files | ForEach-Object -ThrottleLimit $Throttle -Parallel {
    [pscustomobject]@{
        Rel  = $_.Rel
        Hash = (Get-FileHash -LiteralPath $_.Full -Algorithm SHA256).Hash.ToLower()
    }
}
$rows = @($rows | Sort-Object Rel -CaseSensitive)
if ($rows.Count -ne $files.Count) { throw "hashed $($rows.Count) of $($files.Count) files" }

$small = @($rows | Where-Object $isSmall)
$big = @($rows | Where-Object { -not (& $isSmall) })

$utf8 = [System.Text.UTF8Encoding]::new($false)
function Write-Manifest($path, $set) {
    [System.IO.File]::WriteAllText($path, (($set | ForEach-Object { "$($_.Hash)  $($_.Rel)" }) -join "`n") + "`n", $utf8)
}
Write-Manifest (Join-Path $OutDir 'chainstate.sha256') $small
Write-Manifest (Join-Path $OutDir 'blocks.sha256') $big

$info = @(
    "manifests made   $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')) UTC",
    "source           $BitcoinDir",
    "files            $($files.Count)  ($($small.Count) in chainstate.sha256, $($big.Count) in blocks.sha256)",
    "bytes            $bytes",
    "last tip lines in debug.log:"
)
$log = Join-Path $BitcoinDir 'debug.log'
if (Test-Path -LiteralPath $log) {
    $info += @(Get-Content -LiteralPath $log -Tail 4000 | Where-Object { $_ -match 'UpdateTip' } | Select-Object -Last 2)
}
[System.IO.File]::WriteAllText((Join-Path $OutDir 'snapshot-info.txt'), ($info -join "`n") + "`n", $utf8)

"done in $([math]::Round(((Get-Date) - $started).TotalMinutes, 1)) min: $($small.Count) + $($big.Count) lines written to $OutDir"
