<#
  run_completion_detail_type_guard.ps1 -- a completion item's `detail` must
  carry the symbol's TYPE, and must never carry its qualified name instead.

  THE ASK (owner, live IDE, 2026-08-19): "We have to show the type of the result
  (be it property or something else)."

  WHAT WAS MEASURED before writing this, rather than assumed -- the ask turned
  out to be mostly already satisfied, and the guard records which half is which:

    FCount   field     detail='[private] Integer'          already correct
    FName    field     detail='string'                     already correct
    Count    property  detail='Integer'                    already correct
    Caption  property  detail='[read-only] string'         already correct
    Total    function  detail='(const A: Integer): Int64'  already correct
    DoIt     procedure detail='uDetail.TThing.DoIt'        *** THE DEFECT ***

  THE DEFECT. MakeCompletionItem falls back to ASym.QualifiedName whenever
  ASym.Signature is blank -- so a parameterless procedure is described by its
  own name, in the slot the popup reads a TYPE out of. The popup draws that slot
  green after a colon, which reads as `DoIt: uDetail.TThing.DoIt`.

  WHY IT LOOKS FINE IN THE IDE ANYWAY, and why that is not a reason to leave it:
  the plugin scrubs it client-side with

      if SameText(DetailStr, LabelStr) or (Pos('.' + LabelStr, DetailStr) > 0)

  -- a heuristic that ALSO blanks a genuine signature which happens to contain
  '.' + the label (a parameter typed `TRec.Value` on a member named `Value`).
  Making the engine send nothing rather than a name removes both the junk and
  the need to guess at it. So this guard asserts the ENGINE's output, where the
  fact is decided, not the popup's, where it is patched over.

  NOT COVERED, DELIBERATELY: a `const` carries no type in the index at all
  (measured -- signature is empty for all 106 consts in this repo's own DB).
  Filling it is an EXTRACTOR change and would force a DRAGLINT_EXTRACTOR_VERSION
  bump, re-parsing every database. That is a separate, costed decision.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-completion-detail"
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
function Frame($o) {
  $j = $o | ConvertTo-Json -Compress -Depth 10
  $n = [Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$Src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $Src | Out-Null

# One class carrying every member shape whose `detail` the popup renders.
$File = Join-Path $Src 'uDetail.pas'
WriteAnsi $File @'
unit uDetail;

interface

type
  TThing = class
  private
    FCount: Integer;
  public
    FName    : string;
    procedure DoIt;
    function  Total(const A: Integer): Int64;
    property  Count: Integer read FCount write FCount;
    property  Caption: string read FName;
  end;

procedure Go;

implementation

procedure TThing.DoIt; begin end;
function TThing.Total(const A: Integer): Int64; begin Result := A; end;

procedure Go;
var
  T: TThing;
begin
  T := TThing.Create;
  T.DoIt;
end;

end.
'@

$Db = Join-Path $WorkDir 'detail.sqlite'
& $Exe index $Src --db $Db 2>&1 | Out-Null
Check 'built the fixture index' (Test-Path $Db)

$lines = [System.IO.File]::ReadAllLines($File)
$ln = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains('T.DoIt;')) { $ln = $i; break } }
Check 'located the member-access probe' ($ln -ge 0) "line0=$ln"
if ($ln -lt 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
$col = $lines[$ln].IndexOf('.') + 1
$uri = 'file:///' + ($File -replace '\\', '/')

$m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
$m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
$m += Frame @{ jsonrpc='2.0'; id=2; method='textDocument/completion';
               params=@{ textDocument=@{ uri=$uri }; position=@{ line=$ln; character=$col } } }
$m += Frame @{ jsonrpc='2.0'; id=3; method='shutdown'; params=@{} }
$inF = Join-Path $WorkDir 'in.txt'; $outF = Join-Path $WorkDir 'out.txt'
[System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
Start-Process $Exe -ArgumentList @('lsp', '--db', $Db) -WorkingDirectory $WorkDir `
  -RedirectStandardInput $inF -RedirectStandardOutput $outF `
  -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null

$items = @()
foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
  try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
  if ($o.id -eq 2 -and $null -ne $o.result) { $items = @($o.result.items) }
}
Check 'the member completion answered' ($items.Count -gt 0) "count=$($items.Count)"
if ($items.Count -eq 0) { Write-Host 'FAIL -- nothing to assert against.' -ForegroundColor Red; exit 1 }
function DetailOf([string]$label) {
  $it = $items | Where-Object { $_.label -eq $label } | Select-Object -First 1
  if ($null -eq $it) { return '<absent>' }
  return [string]$it.detail
}

# ---- THE DEFECT ------------------------------------------------------------
Write-Host ''
Write-Host 'THE DEFECT: a qualified name is not a type' -ForegroundColor Cyan
$doIt = DetailOf 'DoIt'
Check 'a parameterless procedure does not report its own qualified name' `
  ($doIt -notmatch '\.DoIt') "detail='$doIt'"

# ---- POSITIVE CONTROLS -----------------------------------------------------
# These already passed before the fix. They are here because the cheapest wrong
# way to satisfy the assertion above is to blank `detail` for everything, and
# that would take the property and field types down with it -- which is exactly
# what the owner asked to SEE.
Write-Host ''
Write-Host 'CONTROLS: the types that already worked must keep working' -ForegroundColor Cyan
foreach ($p in @(
  @{ n = 'FCount' ; want = 'Integer'; note = 'private field'       },
  @{ n = 'FName'  ; want = 'string' ; note = 'public field'        },
  @{ n = 'Count'  ; want = 'Integer'; note = 'read/write property' },
  @{ n = 'Caption'; want = 'string' ; note = 'read-only property'  },
  @{ n = 'Total'  ; want = 'Int64'  ; note = 'function return'     }
)) {
  $got = DetailOf $p.n
  Check ("CONTROL: {0} ({1}) reports its type" -f $p.n, $p.note) ($got -match [regex]::Escape($p.want)) "detail='$got'"
}
# The qualifiers that decide usability share this field -- they must survive too.
Check 'CONTROL: the [private] qualifier survives'   ((DetailOf 'FCount')  -match '\[private\]')   "detail='$(DetailOf 'FCount')'"
Check 'CONTROL: the [read-only] qualifier survives' ((DetailOf 'Caption') -match '\[read-only\]') "detail='$(DetailOf 'Caption')'"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
