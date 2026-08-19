<#
  run_lsp_live_buffer_guard.ps1 -- position requests must answer about the
  CLIENT'S BUFFER, not the file on disk.

  THE DEFECT THIS PINS (owner, 2026-08-18, live IDE):

      var S:= AExceptionInfo.Assign      <- typed, NOT saved

  Hover over `Assign` returned null and the popup showed only that line's lint
  finding, while RAD Studio's own Help Insight described the method correctly.
  Cause: the server implemented neither textDocument/didChange nor any document
  overlay, so IdentifierAtPosition read the file FROM DISK. Disk still held
  `AExceptionInfo.;`, the column landed past end-of-line, the identifier
  resolved to '' and the reply was a well-formed `null`.

  Two properties make this worth a dedicated guard rather than a case bolted
  onto the hover suite:

  1. IT IS SILENT AND INVERTED. The answer is not stale, it is ABSENT, and
     absence renders as "drag-lint knows nothing about this symbol". Nothing
     errors, nothing logs, and the reply arrives fast.
  2. IT SCALES WITH EDITING. The blindness is exactly proportional to how much
     the user has typed since the last save -- so it is worst precisely when
     hover and completion are most wanted, and it disappears the moment anyone
     tries to reproduce it after hitting Ctrl+S.

  Property 2 is why the fixture below NEVER writes the buffer text to disk. The
  disk copy is deliberately left holding a truncated line; if a future change
  makes the guard pass by reading disk, case NC1 catches it.

  CONTROLS (both required -- see the repo rule that a guard asserting only "the
  bad thing stopped" also passes with the feature switched off):
    PC1  a position that IS on disk resolves in every build -> the harness works
    NC1  the buffer-only position WITHOUT didChange stays null -> the overlay,
         not an accidental disk read, is what makes the positive cases pass
    NC2  after didClose the buffer-only position is null again -> the overlay is
         actually released rather than leaking for the process lifetime

  RUN RED FIRST: against a build without the overlay, every "live" assertion
  fails and PC1/NC1/NC2 still pass. That combination is the signature of a
  correct probe pointed at an unfixed engine.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-live-buffer-guard"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}
function Frame($obj) {
  $j = $obj | ConvertTo-Json -Compress -Depth 12
  $n = [System.Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

# ---------------------------------------------------------------- fixtures --
WriteAnsi (Join-Path $WorkDir 'LiveLib.pas') @'
unit LiveLib;

interface

type
  TLiveSource = class
  public
    SourceMark: Integer;
  end;

  TLiveThing = class
  public
    LiveField: Integer;
    procedure Assign(ASource: TLiveSource);
    procedure AlreadySavedMethod;
  end;

implementation

procedure TLiveThing.Assign(ASource: TLiveSource);
begin
end;

procedure TLiveThing.AlreadySavedMethod;
begin
end;

end.
'@

# THE DISK COPY. The live probe line holds `Src := nil;` -- a line with NO DOT
# ANYWHERE. That detail is load-bearing and was got wrong on the first attempt:
# the original fixture left `  Thing.;` on disk, so the dot that triggers member
# completion was present in BOTH copies and the completion case passed against
# the unfixed build. It read as a green assertion while testing nothing. The
# probe must require the buffer for the TRIGGER as well as for the identifier.
# `  Thing.AlreadySavedMethod;` is complete in both copies -- that is PC1's
# anchor, the one position every build must resolve.
$diskText = @'
unit LiveApp;

interface

procedure UseLive;

implementation

uses
  LiveLib;

procedure UseLive;
var
  Thing: TLiveThing;
  Src: TLiveSource;
begin
  Thing.AlreadySavedMethod;
  Src := nil;
end;

end.
'@
$appFile = Join-Path $WorkDir 'LiveApp.pas'
WriteAnsi $appFile $diskText

# THE BUFFER. Identical except the dotless line has become a member access.
# This string is sent over LSP and is NEVER written to $appFile.
$bufferText = $diskText -replace '  Src := nil;', '  Thing.Assign(Src);'

$db = Join-Path $WorkDir 'live.sqlite'
& $Exe index $WorkDir --db $db 2>&1 | Out-Null
Check 'built the fixture index' (Test-Path $db)

# Positions are 0-based for LSP.
$diskLines = $diskText -split "`r?`n"
$bufLines  = $bufferText -split "`r?`n"
$savedLine = [Array]::FindIndex($diskLines, [Predicate[string]]{ param($x) $x -like '*AlreadySavedMethod;*' })
$liveLine  = [Array]::FindIndex($bufLines,  [Predicate[string]]{ param($x) $x -like '*Thing.Assign(Src);*' })
$savedCol  = $diskLines[$savedLine].IndexOf('AlreadySavedMethod') + 4
$liveCol   = $bufLines[$liveLine].IndexOf('Assign') + 3
$dotCol    = $bufLines[$liveLine].IndexOf('.') + 1        # caret just past the dot
Check 'located both probe lines' (($savedLine -ge 0) -and ($liveLine -ge 0)) "saved=$savedLine live=$liveLine"

# Confirm the premise: the buffer column does not exist on disk. If this ever
# stops being true the whole guard is measuring nothing.
Check 'PREMISE: the identifier is absent from the disk line' `
  ($diskLines[$liveLine] -notmatch 'Assign') `
  "disk line = [$($diskLines[$liveLine])]"
# The second half of the premise, and the one the first draft of this guard got
# wrong: the TRIGGER must be missing from disk too, or completion can succeed
# without ever consulting the buffer.
Check 'PREMISE: the disk line contains no dot at all' `
  ($diskLines[$liveLine] -notmatch '\.') `
  "disk line = [$($diskLines[$liveLine])]"

$uri = 'file:///' + ($appFile -replace '\\', '/')

# $Sync: 'none' = never tell the server about the buffer (disk-only behaviour)
#        'change' = didOpen bare, then didChange with the full buffer
#        'close'  = as 'change', then didClose before the request
function Invoke-Lsp([string]$Method, [int]$Line0, [int]$Char0, [string]$Sync) {
  $msgs  = Frame @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ processId = $null; rootUri = $null; capabilities = @{} } }
  $msgs += Frame @{ jsonrpc = '2.0'; method = 'initialized'; params = @{} }
  $msgs += Frame @{ jsonrpc = '2.0'; method = 'textDocument/didOpen';
                    params = @{ textDocument = @{ uri = $uri; languageId = 'pascal'; version = 1; text = $diskText } } }
  if ($Sync -ne 'none') {
    $msgs += Frame @{ jsonrpc = '2.0'; method = 'textDocument/didChange';
                      params = @{ textDocument = @{ uri = $uri; version = 2 };
                                  contentChanges = @( @{ text = $bufferText } ) } }
  }
  if ($Sync -eq 'close') {
    $msgs += Frame @{ jsonrpc = '2.0'; method = 'textDocument/didClose'; params = @{ textDocument = @{ uri = $uri } } }
  }
  $msgs += Frame @{ jsonrpc = '2.0'; id = 2; method = $Method;
                    params = @{ textDocument = @{ uri = $uri }; position = @{ line = $Line0; character = $Char0 } } }
  $msgs += Frame @{ jsonrpc = '2.0'; id = 3; method = 'shutdown'; params = @{} }

  $inF = Join-Path $WorkDir 'in.txt'; $outF = Join-Path $WorkDir 'out.txt'; $errF = Join-Path $WorkDir 'err.txt'
  [System.IO.File]::WriteAllText($inF, $msgs, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF -RedirectStandardError $errF `
    -NoNewWindow -Wait | Out-Null

  $raw = [System.IO.File]::ReadAllText($outF)
  foreach ($m in [regex]::Matches($raw, '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $m.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 2) { return $o }
  }
  return $null
}
function HoverText($o) {
  if ($null -eq $o -or $null -eq $o.result) { return '' }
  return [string]$o.result.contents.value
}
function CompletionLabels($o) {
  if ($null -eq $o -or $null -eq $o.result) { return @() }
  return @($o.result.items | ForEach-Object { $_.label })
}

# ---- PC1: the harness itself works ----
Write-Host ''
Write-Host 'PC1: POSITIVE CONTROL -- a position that exists on disk' -ForegroundColor Cyan
$pc1 = HoverText (Invoke-Lsp 'textDocument/hover' $savedLine $savedCol 'none')
Check 'disk-backed hover resolves AlreadySavedMethod' ($pc1 -match 'AlreadySavedMethod') "got: [$pc1]"

# ---- NC1: without didChange the server must still be blind ----
Write-Host ''
Write-Host 'NC1: NEGATIVE CONTROL -- buffer-only position, no didChange' -ForegroundColor Cyan
$nc1 = HoverText (Invoke-Lsp 'textDocument/hover' $liveLine $liveCol 'none')
Check 'unsynced buffer position yields nothing' ($nc1 -eq '') "got: [$nc1]"

# ---- case 1: hover sees the unsaved edit ----
Write-Host ''
Write-Host 'CASE 1: hover after didChange' -ForegroundColor Cyan
$h = HoverText (Invoke-Lsp 'textDocument/hover' $liveLine $liveCol 'change')
Check 'hover returns content for the unsaved symbol' ($h -ne '') "got: [$h]"
Check 'names TLiveThing.Assign' ($h -match 'TLiveThing') "got: [$h]"
Check 'shows the real parameter ASource' ($h -match 'ASource') "got: [$h]"

# ---- case 2: completion sees the unsaved edit ----
# The dot that TRIGGERS completion is itself part of the unsaved text, so this
# path cannot work at all without the overlay.
Write-Host ''
Write-Host 'CASE 2: completion after didChange' -ForegroundColor Cyan
$labels = CompletionLabels (Invoke-Lsp 'textDocument/completion' $liveLine $dotCol 'change')
Check 'completion returns items at the unsaved dot' ($labels.Count -gt 0) "count=$($labels.Count)"
Check 'offers Assign'             ($labels -contains 'Assign')             "got: $($labels -join ',')"
Check 'offers AlreadySavedMethod' ($labels -contains 'AlreadySavedMethod') "got: $($labels -join ',')"
Check 'offers LiveField'          ($labels -contains 'LiveField')          "got: $($labels -join ',')"

# ---- NC2: didClose releases the overlay ----
Write-Host ''
Write-Host 'NC2: NEGATIVE CONTROL -- didClose drops the buffer' -ForegroundColor Cyan
$nc2 = HoverText (Invoke-Lsp 'textDocument/hover' $liveLine $liveCol 'close')
Check 'closed document falls back to disk (null again)' ($nc2 -eq '') "got: [$nc2]"

# ---- case 3: the server must ADVERTISE sync, or no client will ever send it ----
Write-Host ''
Write-Host 'CASE 3: initialize advertises textDocumentSync' -ForegroundColor Cyan
$inF = Join-Path $WorkDir 'cap-in.txt'; $outF = Join-Path $WorkDir 'cap-out.txt'
$msgs  = Frame @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ processId = $null; rootUri = $null; capabilities = @{} } }
$msgs += Frame @{ jsonrpc = '2.0'; id = 3; method = 'shutdown'; params = @{} }
[System.IO.File]::WriteAllText($inF, $msgs, (New-Object System.Text.ASCIIEncoding))
Start-Process $Exe -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $WorkDir `
  -RedirectStandardInput $inF -RedirectStandardOutput $outF -RedirectStandardError (Join-Path $WorkDir 'cap-err.txt') `
  -NoNewWindow -Wait | Out-Null
$capRaw = [System.IO.File]::ReadAllText($outF)
$syncVal = $null
foreach ($m in [regex]::Matches($capRaw, '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
  try { $o = $m.Value.Trim() | ConvertFrom-Json } catch { continue }
  if ($o.id -eq 1 -and $o.result) { $syncVal = $o.result.capabilities.textDocumentSync }
}
Check 'capabilities carry textDocumentSync' ($null -ne $syncVal) "got: [$syncVal]"
Check 'textDocumentSync is Full (1)' ($syncVal -eq 1) "got: [$syncVal]"

# ---- case 4: disk stayed untouched ----
# If any of this ever passes because something WROTE the buffer to disk, that is
# a far worse bug than the one being fixed -- the server would be editing the
# user's source.
Write-Host ''
Write-Host 'CASE 4: the server never wrote the buffer to disk' -ForegroundColor Cyan
$onDisk = [System.IO.File]::ReadAllText($appFile)
Check 'disk file still holds the dotless line' ($onDisk -match '\r?\n  Src := nil;\r?\n') `
  $(if ($onDisk -match 'Thing\.Assign') { 'THE SERVER WROTE TO THE SOURCE FILE' } else { '' })

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
