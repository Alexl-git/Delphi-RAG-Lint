<#
  run_hover_inherited_prop_type.ps1 -- hover shows the TYPE of a bare
  re-published property, found on the ancestor that declares it.

  Defect (docs/INBOX-ide-hang-on-slow-engine.md section 3): hovering
  `edtZoom.Text` (TdxBarEdit) showed `property Text` -- the `property Text;`
  re-publication carries an EMPTY Signature, so no type. The converter's
  property tree already climbs ancestors for exactly this
  (DRagLint.Convert.PropTree); hover did not use it.

  Fixture: TBase declares `property Text: string read FText write FText`,
  TMid adds nothing, TDerived re-publishes `property Text;`.

  ORDER:
    (1) PREMISE    -- the index really holds an EMPTY signature on TDerived.Text
                      and 'string' on TBase.Text (else the guard tests nothing).
    (2) CLI hover  -- json carries type 'string' + declared_in 'uPropBase.TBase';
                      md and plain say the same.
    (3) CONTROL    -- TBase.Text (declares its own type) reports NO declared_in.
    (4) OTHER KINDS -- field / var / const / param / local var report their
                      declared type in the model and the LSP hover.
    (5) READ-ONLY  -- a default hover never writes the DB (row stays empty).
    (6) MEMOIZE    -- `hover --write-back` stamps ': string' onto the row; a
                      SECOND hover (fresh process, no session cache) reads the
                      stored type, still names the ancestor, and never renders
                      a doubled colon.
    (7) LSP        -- textDocument/hover on the re-publication and on a use site
                      shows `property Text: string` + the ancestor; hoverBundle's
                      model carries the same type / declared_in.

  RED (pre-change engine): (2), (4) type fields, (6), (7) fail; (1), (3)
  declared_in-absent, (5) pass.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-hover-inh-prop-$PID"
)
try {
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
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null

$text = @'
unit uPropBase;

interface

const
  CMax: Integer = 5;

var
  GVal: Double;

type
  TBase = class(TObject)
  private
    FText: string;
  protected
    property Text: string read FText write FText;
  end;

  TMid = class(TBase)
  end;

  TDerived = class(TMid)
  public
    FCount: Integer;
    procedure Run(const AName: string);
  published
    property Text;
  end;

implementation

procedure TDerived.Run(const AName: string);
var
  L: Integer;
begin
  L:= Length(AName);
  Text:= AName;
end;

end.
'@
$file = Join-Path $src 'uPropBase.pas'
WriteAnsi $file $text
# A USE site in another unit -- the shape of the reported `edtZoom.Text`.
$useText = @"
unit uPropUse;

interface

uses uPropBase;

procedure Touch(E: TDerived);

implementation

procedure Touch(E: TDerived);
begin
  E.Text:= 'x';
end;

end.
"@
$useFile = Join-Path $src 'uPropUse.pas'
WriteAnsi $useFile $useText
$db = Join-Path $WorkDir 'hov.sqlite'
$null = & $Exe index $src --db $db 2>$null
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

function SigOf([string]$qn) {
  $r = (& $Exe sql --db $db --json --query "select signature from symbols where qualified_name = '$qn'" 2>$null) -join "`n" | ConvertFrom-Json
  if ($null -eq $r.rows -or @($r.rows).Count -eq 0) { return '<no row>' }
  $v = @($r.rows)[0][0]
  if ($null -eq $v) { return '' } else { return [string]$v }
}
function HoverJson([string]$qn, [string[]]$extra = @()) {
  $raw = (& $Exe hover --qname $qn --db $db --format json @extra 2>$null) -join "`n"
  try { return ($raw | ConvertFrom-Json) } catch { return $null }
}

Write-Host ''
Write-Host '(1) PREMISE: the re-publication has no signature of its own' -ForegroundColor Cyan
Check 'TDerived.Text signature is empty in the index' ((SigOf 'uPropBase.TDerived.Text') -eq '') "got: [$(SigOf 'uPropBase.TDerived.Text')]"
Check 'TBase.Text signature is string in the index' ((SigOf 'uPropBase.TBase.Text') -eq 'string') "got: [$(SigOf 'uPropBase.TBase.Text')]"

Write-Host ''
Write-Host '(2) CLI hover on the re-published property' -ForegroundColor Cyan
$j = HoverJson 'uPropBase.TDerived.Text'
Check 'json parses' ($null -ne $j)
Check 'json type = string' ($j.type -eq 'string') "got: [$($j.type)]"
Check 'json declared_in = uPropBase.TBase' ($j.declared_in -eq 'uPropBase.TBase') "got: [$($j.declared_in)]"
Check 'json signature = string (the plugin renders signature)' ($j.signature -eq 'string') "got: [$($j.signature)]"
$md = (& $Exe hover --qname uPropBase.TDerived.Text --db $db --format md 2>$null) -join "`n"
Check 'md shows Text: string' ($md -match 'Text: string') "got: [$md]"
Check 'md names the declaring ancestor' ($md -match 'declared in `?uPropBase\.TBase') "got: [$md]"
$pl = (& $Exe hover --qname uPropBase.TDerived.Text --db $db 2>$null) -join "`n"
Check 'plain shows Text: string + the ancestor' (($pl -match 'Text: string') -and ($pl -match 'declared in uPropBase\.TBase')) "got: [$pl]"

Write-Host ''
Write-Host '(3) CONTROL: a property that declares its own type' -ForegroundColor Cyan
$jb = HoverJson 'uPropBase.TBase.Text'
Check 'TBase.Text json type = string' ($jb.type -eq 'string') "got: [$($jb.type)]"
Check 'TBase.Text has NO declared_in' ([string]::IsNullOrEmpty($jb.declared_in)) "got: [$($jb.declared_in)]"

Write-Host ''
Write-Host '(4) other kinds with a declared type' -ForegroundColor Cyan
foreach ($pair in @(@('uPropBase.TDerived.FCount', 'Integer'), @('uPropBase.GVal', 'Double'),
                    @('uPropBase.CMax', 'Integer'), @('uPropBase.TDerived.Run.AName', 'string'),
                    @('uPropBase.TDerived.Run.L', 'Integer'))) {
  $k = HoverJson $pair[0]
  Check ("$($pair[0]) json type = $($pair[1])") ($k.type -eq $pair[1]) "got: [$($k.type)]"
}
$jm = HoverJson 'uPropBase.TDerived.Run'
Check 'NEGATIVE: a method has no type field value' ([string]::IsNullOrEmpty($jm.type)) "got: [$($jm.type)]"

Write-Host ''
Write-Host '(5) a default hover never writes' -ForegroundColor Cyan
Check 'TDerived.Text row still empty after read-only hovers' ((SigOf 'uPropBase.TDerived.Text') -eq '') "got: [$(SigOf 'uPropBase.TDerived.Text')]"

Write-Host ''
Write-Host '(6) --write-back memoizes; the next hover reads the stored type' -ForegroundColor Cyan
$jw = HoverJson 'uPropBase.TDerived.Text' @('--write-back')
Check 'write-back hover still answers string' ($jw.type -eq 'string') "got: [$($jw.type)]"
Check 'row now carries the memoized type' ((SigOf 'uPropBase.TDerived.Text') -match '^:?\s*string$') "got: [$(SigOf 'uPropBase.TDerived.Text')]"
$j2 = HoverJson 'uPropBase.TDerived.Text'
Check 'second hover: type = string' ($j2.type -eq 'string') "got: [$($j2.type)]"
Check 'second hover: still declared in uPropBase.TBase' ($j2.declared_in -eq 'uPropBase.TBase') "got: [$($j2.declared_in)]"
Check 'second hover: signature normalised (no leading colon)' ($j2.signature -eq 'string') "got: [$($j2.signature)]"
$md2 = (& $Exe hover --qname uPropBase.TDerived.Text --db $db --format md 2>$null) -join "`n"
Check 'second hover md: no doubled colon' (($md2 -match 'Text: string') -and ($md2 -notmatch ':\s*:')) "got: [$md2]"

$lines = $text -split "`r?`n"
function Pos0([string]$needle, [string]$word, [string[]]$in = $lines) {
  for ($i = 0; $i -lt $in.Count; $i++) {
    if ($in[$i] -like $needle) { return @($i, $in[$i].IndexOf($word)) }
  }
  return @(0, 0)
}
function Invoke-Lsp([int]$Line0, [int]$Char0, [string]$file = $file) {
  $uri = 'file:///' + ($file -replace '\\', '/')
  $pos = @{ textDocument = @{ uri = $uri }; position = @{ line = $Line0; character = $Char0 } }
  $msgs  = Frame @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ processId = $null; rootUri = $null; capabilities = @{} } }
  $msgs += Frame @{ jsonrpc = '2.0'; method = 'initialized'; params = @{} }
  $msgs += Frame @{ jsonrpc = '2.0'; method = 'textDocument/didOpen';
                    params = @{ textDocument = @{ uri = $uri; languageId = 'pascal'; version = 1; text = [System.IO.File]::ReadAllText($file) } } }
  $msgs += Frame @{ jsonrpc = '2.0'; id = 2; method = 'textDocument/hover'; params = $pos }
  $msgs += Frame @{ jsonrpc = '2.0'; id = 3; method = 'draglint/hoverBundle'; params = $pos }
  $msgs += Frame @{ jsonrpc = '2.0'; id = 4; method = 'shutdown'; params = @{} }
  $inF = Join-Path $WorkDir 'in.txt'; $outF = Join-Path $WorkDir 'out.txt'; $errF = Join-Path $WorkDir 'err.txt'
  [System.IO.File]::WriteAllText($inF, $msgs, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF -RedirectStandardError $errF -NoNewWindow -Wait | Out-Null
  $raw = [System.IO.File]::ReadAllText($outF)
  $res = @{ md = '<NO REPLY>'; model = $null }
  foreach ($m in [regex]::Matches($raw, '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $m.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 2) { $res.md = if ($null -eq $o.result) { '' } else { [string]$o.result.contents.value } }
    if ($o.id -eq 3 -and $null -ne $o.result) { $res.model = $o.result.model }
  }
  return $res
}

Write-Host ''
Write-Host '(7) LSP hover + hoverBundle' -ForegroundColor Cyan
# Fresh index: the LSP must climb for itself (the row above is memoized now).
$null = & $Exe index $src --db $db --rebuild 2>$null
Check 'reindex resets the row (premise for the LSP leg)' ((SigOf 'uPropBase.TDerived.Text') -eq '') "got: [$(SigOf 'uPropBase.TDerived.Text')]"
# The reported shape: a use site whose LHS type (TDerived) owns the bare
# re-publication, so the hover's chosen symbol IS uPropBase.TDerived.Text.
$p = Pos0 '*E.Text:=*' 'Text' ($useText -split "`r?`n")
$r = Invoke-Lsp $p[0] $p[1] $useFile
Check 'LSP use-site hover chose the re-publication (premise)' ($r.md -match 'uPropBase\.TDerived\.Text') "got: [$($r.md)]"
Check 'LSP hover on the re-publication shows property Text: string' ($r.md -match 'property Text: string') "got: [$($r.md)]"
Check 'LSP hover names the declaring ancestor' ($r.md -match 'declared in `?uPropBase\.TBase') "got: [$($r.md)]"
Check 'hoverBundle model type = string' ($null -ne $r.model -and $r.model.type -eq 'string') "got: [$($r.model.type)]"
Check 'hoverBundle model declared_in = uPropBase.TBase' ($null -ne $r.model -and $r.model.declared_in -eq 'uPropBase.TBase') "got: [$($r.model.declared_in)]"
$p = Pos0 '*Text:= AName;*' 'Text'
$r = Invoke-Lsp $p[0] $p[1]
Check 'LSP hover at a same-class use site shows Text: string' ($r.md -match 'Text: string') "got: [$($r.md)]"
$p = Pos0 '*L:= Length(AName);*' 'L:='
$r = Invoke-Lsp $p[0] $p[1]
Check 'LSP hover on a local var shows L: Integer' ($r.md -match 'L: Integer') "got: [$($r.md)]"
$p = Pos0 '*property Text: string read*' 'Text'
$r = Invoke-Lsp $p[0] $p[1]
Check 'CONTROL: LSP hover on TBase.Text shows its own type' ($r.md -match 'property Text: string') "got: [$($r.md)]"
Check 'CONTROL: TBase.Text names no ancestor' ($r.md -notmatch 'declared in') "got: [$($r.md)]"
Check 'LSP never wrote the read-only DB' ((SigOf 'uPropBase.TDerived.Text') -eq '') "got: [$(SigOf 'uPropBase.TDerived.Text')]"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if ($WorkDir -and (Test-Path $WorkDir)) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { $null = $_ } }
}
