# collect-lsp-diagnostic.ps1
# Gather every DelphiLSP log/artefact written since arm-lsp-diagnostic.ps1 ran,
# plus the environment facts needed to interpret them, into one folder.

$ErrorActionPreference = 'Continue'
$marker = Join-Path $PSScriptRoot 'armed.marker'
$since  = if (Test-Path $marker) { [datetime]::Parse((Get-Content $marker -Raw).Trim()) }
          else { (Get-Date).AddHours(-8) }
"collecting artefacts written since $since"

$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$out   = Join-Path $PSScriptRoot "capture-$stamp"
New-Item -ItemType Directory $out -Force | Out-Null

# --- 1. sweep the places Sanctuary.Logger / DelphiLSP are known to write ---------
$roots = @(
    $env:TEMP,
    "$env:LOCALAPPDATA\Embarcadero\BDS\37.0",
    "$env:APPDATA\Embarcadero\BDS\37.0",
    "$env:LOCALAPPDATA\Temp",
    'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin',
    'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin64'
)
$patterns = @('*lsp*.log','*sanct*.log','*.trace.log','DelphiLSP*.*','*codeinsight*.log')

$found = @()
foreach ($r in $roots) {
    if (-not (Test-Path $r)) { continue }
    foreach ($pat in $patterns) {
        Get-ChildItem $r -Filter $pat -File -Recurse -Depth 2 -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $since -and $_.Length -gt 0 } |
            ForEach-Object { $found += $_ }
    }
}
$found = $found | Sort-Object FullName -Unique

if ($found) {
    "found $($found.Count) log file(s):"
    foreach ($f in $found) {
        "  {0,10} bytes  {1}  {2}" -f $f.Length, $f.LastWriteTime.ToString('HH:mm:ss'), $f.FullName
        $safe = ($f.FullName -replace '[:\\/]','_')
        Copy-Item $f.FullName (Join-Path $out $safe) -ErrorAction SilentlyContinue
    }
} else {
    "NO log files found since $since."
    "  -> If the IDE was started from an existing shell it did not inherit DelphiLSPLog."
    "     Re-arm, then launch the IDE fresh from the Start Menu."
}

# --- 2. environment facts -------------------------------------------------------
$facts = [ordered]@{
    CollectedUtc              = (Get-Date).ToUniversalTime().ToString('o')
    DelphiLSPLog_User         = [Environment]::GetEnvironmentVariable('DelphiLSPLog','User')
    DelphiLSPLog_Process      = $env:DelphiLSPLog
    CodeInsightUse64BitBinary = (Get-ItemProperty 'HKCU:\Software\Embarcadero\BDS\37.0\Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal' -Name 'CodeInsightUse64BitBinary' -ErrorAction SilentlyContinue).CodeInsightUse64BitBinary
    LSPBehavior               = (Get-ItemProperty 'HKCU:\Software\Embarcadero\BDS\37.0\Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal' -Name 'LSP Behavior' -ErrorAction SilentlyContinue).'LSP Behavior'
    LiveDelphiLSPProcesses    = @(Get-Process DelphiLSP -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
    LogFilesFound             = @($found | ForEach-Object { $_.FullName })
}
$facts | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $out 'environment.json') -Encoding UTF8

# --- 3. reminder for the human-observed part ------------------------------------
@"
PASTE THE EXACT ERROR TEXT HERE
==============================================
(the dialog / Messages-pane / Error Insight wording you saw with the 64-bit server enabled)


Which project was open:
What action triggered it (open unit / hover / Ctrl+Space / build):
Did Code Insight work at all, or fail completely:
"@ | Set-Content (Join-Path $out 'OBSERVED-ERROR.txt') -Encoding UTF8

""
"capture folder: $out"
"  -> fill in OBSERVED-ERROR.txt with the exact wording, then hand the folder over."
