<#
  run_v1523_GH21.ps1 -- GitHub #21: `wiring --qname <Unit.TForm>` and MCP get_wiring listed the DFM
  event bindings of EVERY form whose DFM binds the same handler name (OnShow = FormShow).
  Same fixture as run_v152_GH15 (TFormA, TFormB unrelated; TFormA2 = class(TFormA); Orphan.dfm root unknown).
  1. wiring FormA.TFormA (CLI json): FormA.dfm + FormA2.dfm (descendant) + Orphan.dfm (unknown root, kept); NOT FormB.dfm.
  2. wiring FormB.TFormB: FormB.dfm only.
  3. MCP get_wiring answers the same lists as the CLI.
  4. text output of the CLI wiring has no FormB line for TFormA.
  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n)
  if (-not $ok) { if ($d) { Write-Host "      $d" }; $script:fail = $true }
}
$exe = (Resolve-Path $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ("dl_gh21_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$fx = Join-Path $work 'fx'
[void][IO.Directory]::CreateDirectory($fx)
function W($n, $t) { [IO.File]::WriteAllText((Join-Path $fx $n), ($t -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII) }
foreach ($x in 'A', 'B') {
  W "Form$x.pas" @"
unit Form$x;
interface
uses Forms;
type
  TForm$x = class(TForm)
    procedure FormShow(Sender: TObject);
  end;
implementation
{`$R *.dfm}
procedure TForm$x.FormShow(Sender: TObject); begin end;
end.
"@
  W "Form$x.dfm" @"
object Form${x}: TForm$x
  Left = 0
  Top = 0
  Caption = 'Form$x'
  OnShow = FormShow
end
"@
}
W 'FormA2.pas' @'
unit FormA2;
interface
uses Forms, FormA;
type
  TFormA2 = class(TFormA)
  end;
implementation
{$R *.dfm}
end.
'@
W 'FormA2.dfm' @'
inherited FormA2: TFormA2
  Caption = 'FormA2'
  OnShow = FormShow
end
'@
# a DFM with no matching unit in the index: its root class is unknown, so it must be kept
W 'Orphan.dfm' @'
object Orphan: TOrphanForm
  Caption = 'Orphan'
  OnShow = FormShow
end
'@
function Invoke-Serve([string[]]$Requests, [string]$Tag) {
  $in = Join-Path $work "$Tag.in.jsonl"; $out = Join-Path $work "$Tag.out.jsonl"; $err = Join-Path $work "$Tag.err.txt"
  $all = @('{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}') + $Requests
  [IO.File]::WriteAllText($in, (($all -join "`n") + "`n"), [Text.Encoding]::ASCII)
  $p = Start-Process $exe -ArgumentList 'serve', '--db', "`"$db`"" -WorkingDirectory $work `
         -RedirectStandardInput $in -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru; $null = $p.Handle
  if (-not $p.WaitForExit(60000)) { $p.Kill() }
  $replies = @{}
  foreach ($line in (Get-Content $out -ErrorAction SilentlyContinue)) {
    if ($line.Trim() -eq '') { continue }
    try { $j = $line | ConvertFrom-Json | ForEach-Object { $_ } } catch { continue }
    if ($null -ne $j.id) { $replies[[string]$j.id] = $j }
  }
  $replies
}
function Call([int]$Id, [string]$Tool, [hashtable]$Arguments) {
  (@{ jsonrpc = '2.0'; id = $Id; method = 'tools/call'; params = @{ name = $Tool; arguments = $Arguments } } | ConvertTo-Json -Compress -Depth 6)
}
function Text($Reply) { if ($Reply -and $Reply.result -and $Reply.result.content.Count -gt 0) { [string]$Reply.result.content[0].text } else { '' } }
function DfmSet($json) { try { (($json | ConvertFrom-Json | ForEach-Object { $_ }).event_handlers | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.file) } | Sort-Object -Unique) -join ',' } catch { "unparsed: $json" } }
$db = Join-Path $work 'fx.sqlite'
Push-Location $work
try {
  & { $ErrorActionPreference = 'Continue'; & $exe index $fx --db $db *> $null }
  Check 'fixture indexed' ($LASTEXITCODE -eq 0 -and (Test-Path $db)) "exit $LASTEXITCODE"
  $ja = (& { $ErrorActionPreference = 'Continue'; & $exe wiring --qname FormA.TFormA --format json --db $db 2>$null } | Out-String)
  $sa = DfmSet $ja
  Check 'CLI wiring TFormA: FormA, FormA2 (descendant), Orphan (unknown root) kept' ($sa -eq 'FormA,FormA2,Orphan') $sa
  Check 'CLI wiring TFormA: FormB.dfm NOT listed' ($sa -notmatch 'FormB') $sa
  $jb = (& { $ErrorActionPreference = 'Continue'; & $exe wiring --qname FormB.TFormB --format json --db $db 2>$null } | Out-String)
  $sb = DfmSet $jb
  Check 'CLI wiring TFormB: FormB and Orphan only (no FormA / FormA2)' ($sb -eq 'FormB,Orphan') $sb
  $ta = (& { $ErrorActionPreference = 'Continue'; & $exe wiring --qname FormA.TFormA --db $db 2>&1 | ForEach-Object { "$_" } } | Out-String)
  Check 'CLI wiring TFormA text: no FormB.dfm line' ($ta -notmatch 'FormB\.dfm' -and $ta -match 'FormA\.dfm') $ta
  $r = Invoke-Serve @((Call 1 'get_wiring' @{ qname = 'FormA.TFormA' }), (Call 2 'get_wiring' @{ qname = 'FormB.TFormB' })) 'gh21'
  $ma = DfmSet (Text $r['1']); $mb = DfmSet (Text $r['2'])
  Check 'MCP get_wiring TFormA = CLI set' ($ma -eq 'FormA,FormA2,Orphan') $ma
  Check 'MCP get_wiring TFormB = CLI set' ($mb -eq 'FormB,Orphan') $mb
}
finally {
  Pop-Location
  try { [IO.Directory]::Delete($work, $true) } catch { }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'; exit 0
