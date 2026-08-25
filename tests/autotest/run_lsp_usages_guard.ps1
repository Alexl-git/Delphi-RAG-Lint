<#
  run_lsp_usages_guard.ps1 -- `draglint/usages` must answer with EXACTLY the
  payload `usages --format json` prints.

  WHY THE METHOD EXISTS. The IDE's Find Usages shelled `drag-lint usages` once
  per invocation: measured 1,678 ms with the platform library index in the set
  against 163 ms without it, nearly all of it opening databases the LSP server
  ALREADY holds open. Same argument as draglint/hoverBundle (four spawns per
  tooltip) and draglint/callerCounts (77 spawns to label one file).

  WHY IT IS NOT THE OTHER FIX. Dropping the library DB from the query is ~10x
  for one line, but it CHANGES WHAT IS FOUND -- usages in RTL/VCL/third-party
  code stop being reported. That is a decision about what Find Usages MEANS and
  it was not taken; this method keeps the answer identical and removes the spawn.

  WHY THIS GUARD IS THE POINT, not a formality. Two code paths now produce the
  same payload from the same stores. Nothing forces them to stay equal -- a
  bucket renamed, a key added on one side, the ref-kind catch-all changed, and
  both still "work" while disagreeing. A client that falls back to spawning the
  CLI would then silently see two shapes. So the guard does not check the LSP
  reply against a hand-written expectation; it checks it against THE CLI'S OWN
  OUTPUT, byte for byte after a JSON round-trip.

  ONE DB ON PURPOSE. The CLI iterates its --db list and the server iterates
  FStores; with a single index both orders are trivially identical, so an array
  ordering difference cannot make a real disagreement look like noise (or hide
  one). Multi-store ordering is a separate question and not what this pins.

  NON-VACUITY IS ASSERTED. Comparing two empty payloads passes trivially and
  would still pass if the method returned nothing at all -- which is exactly the
  shape of a guard that never fails. So the fixture guarantees real content and
  assertions 2 and 3 REQUIRE non-zero declarations and calls before the equality
  in 4 means anything.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-usages"
)

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory $WorkDir | Out-Null

function WriteAscii([string]$Path, [string]$Text) {
  $t = $Text -replace "`r`n","`n" -replace "`n","`r`n"
  [System.IO.File]::WriteAllText($Path, $t, (New-Object System.Text.ASCIIEncoding))
}

WriteAscii (Join-Path $WorkDir 'uLib.pas') @'
unit uLib;

interface

function Compute(const A: Integer): Integer;

implementation

function Compute(const A: Integer): Integer;
begin
  Result := A * 2;
end;

end.
'@

WriteAscii (Join-Path $WorkDir 'uApp.pas') @'
unit uApp;

interface

procedure Run;
procedure RunTwice;

implementation

uses
  uLib;

procedure Run;
var
  N: Integer;
begin
  N := Compute(21);
end;

procedure RunTwice;
var
  N: Integer;
begin
  N := Compute(1) + Compute(2);
end;

end.
'@

$db = Join-Path $WorkDir 'app.sqlite'

# LSP framing, as run_lsp_caller_counts_guard.ps1 does it.
function Frame($obj) {
  $j = ($obj | ConvertTo-Json -Depth 12 -Compress)
  $n = [System.Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}

Push-Location C:\TEMP
try {
  & $exePath index $WorkDir --db $db 2>&1 | Out-Null
  Check '1. SANITY: the index exists' (Test-Path $db)

  # --- the CLI's own answer -------------------------------------------------
  # NOT 2>&1: stderr carries the banner and the FTS5 probe, and merging it
  # INTERLEAVES those lines into the middle of the pretty-printed JSON.
  $cliRaw = (& $exePath usages --name Compute --db $db --format json 2>$null | Out-String)
  # The verb prints a banner line and a trailing FTS5 probe around the JSON, so
  # take the object's own span rather than "everything from the first brace".
  $cliJson = $cliRaw.Substring($cliRaw.IndexOf('{'))
  $cliJson = $cliJson.Substring(0, $cliJson.LastIndexOf('}') + 1)
  $cli = $cliJson | ConvertFrom-Json

  # --- the LSP's answer -----------------------------------------------------
  $inF  = Join-Path $WorkDir 'in.txt'
  $outF = Join-Path $WorkDir 'out.txt'
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='draglint/usages'; params=@{ name='Compute' } }
  $m += Frame @{ jsonrpc='2.0'; id=3; method='shutdown'; params=@{} }
  [System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.UTF8Encoding $false))

  $p = Start-Process $exePath -ArgumentList @('lsp','--db',$db) -WorkingDirectory $WorkDir `
        -RedirectStandardInput $inF -RedirectStandardOutput $outF -NoNewWindow -Wait -PassThru

  $lsp = $null
  foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 2 -and $o.result) { $lsp = $o.result }
  }

  Check '2. draglint/usages answered at all' ($null -ne $lsp) `
        'an engine without the method replies -32601 and this stays null'

  if ($null -ne $lsp) {
    # NON-VACUITY FIRST. Without these, assertion 4 compares two empties and
    # would pass against a method that returns nothing.
    Check '3. the payload is NON-EMPTY (decls + calls), so 4 means something' `
          ((@($lsp.declarations).Count -gt 0) -and (@($lsp.calls).Count -gt 0)) `
          ("decls=$(@($lsp.declarations).Count) calls=$(@($lsp.calls).Count)")

    # All ten keys, so a partial implementation cannot pass by omission.
    $keys = @('name','width','declarations','reads','writes','calls','types','attributes','events','impact')
    $have = $lsp.PSObject.Properties.Name
    $missing = @($keys | Where-Object { $_ -notin $have })
    Check '4. every key the CLI emits is present' ($missing.Count -eq 0) `
          ("missing: " + ($missing -join ', '))

    # THE COMPARISON. Round-trip both so formatting/ordering of the writer
    # cannot masquerade as a difference.
    $cliNorm = ($cli | ConvertTo-Json -Depth 12 -Compress)
    $lspNorm = ($lsp | ConvertTo-Json -Depth 12 -Compress)
    Check '5. the LSP payload EQUALS the CLI payload' ($cliNorm -eq $lspNorm) `
          'if this fails the two shapes have drifted -- diff printed below'

    if ($cliNorm -ne $lspNorm) {
      Write-Host '      --- CLI ---' -ForegroundColor DarkGray
      Write-Host "        $cliNorm" -ForegroundColor DarkGray
      Write-Host '      --- LSP ---' -ForegroundColor DarkGray
      Write-Host "        $lspNorm" -ForegroundColor DarkGray
    }
  }
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
