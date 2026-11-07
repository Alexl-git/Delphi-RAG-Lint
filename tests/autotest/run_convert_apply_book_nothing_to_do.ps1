<#
  run_convert_apply_book_nothing_to_do.ps1 -- E-MIGRATE-T-TO-T (wave 146, C1).

  THE DEFECT. convert-apply answered every book with no #convert block the way
  it answers a book of #convert blocks: "sibling .dfm not found: X.dfm (every
  #convert rule needs .dfm instances to locate)", or, beside a .dfm, "no
  convertible instances found (no #convert rule matched ...)". The book named no
  #convert rule, so both sentences send the reader after the wrong thing:
    * an empty or comment-only rules file (the real fault: it holds no rules);
    * a stray `Unit X` line or an unknown directive with no .dfm: the .dfm
      refusal fired first and HID the parse error validation names;
    * `#migrate T -> T` with no site in the unit, or an identity `#migrate T -> T`;
    * a book of #note lines and raw `A -> B` lines only.

  THE CONTRACT this guard pins (exit code stays 1, nothing is written):
    * no rules              : "holds no rules", no ".dfm", no "#convert rule".
    * a parse error, no .dfm: "failed validation" and the line, also in a book
                              that has a #convert block.
    * #migrate, no site     : "no #migrate line" and the unit, with or without a
                              sibling .dfm.
    * nothing convert-apply acts on: "no #convert block".
    * JSON: the same sentence in `error`, ok false, refused false (batch too).
  CONTROLS (the refusals that were right stay byte-identical, the work still runs):
    * a #convert book, no .dfm       : the old "sibling .dfm not found" text.
    * a #convert book, .dfm no match : the old "no convertible instances" text.
    * `#migrate T -> T` WITH a site  : exit 0 under --apply and the bytes change.

  Fixture written fresh under $WorkDir. Nothing shared is touched.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_nothing_$PID"
)
try {
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir -Force | Out-Null
function P([string]$n) { return (Join-Path $WorkDir $n) }
function W([string]$n, [string]$t) { [IO.File]::WriteAllText((P $n), ($t -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII) }

W 'MLib.pas' "unit MLib;`ninterface`nuses`n  System.Classes;`ntype`n  TOldK = (okA, okB);`n  TNewK = (nkA, nkB);`n  TOldC = class(TComponent)`n  end;`n  TNewC = class(TComponent)`n  end;`nimplementation`nend.`n"
W 'MUse.pas' "unit MUse;`ninterface`nuses`n  MLib;`nvar`n  V: TOldK;`nimplementation`nend.`n"
W 'MNoSite.pas' "unit MNoSite;`ninterface`nimplementation`nend.`n"
W 'MForm.pas' "unit MForm;`ninterface`nuses`n  System.Classes;`ntype`n  TMForm = class(TComponent)`n  end;`nimplementation`n{`$R *.dfm}`nend.`n"
W 'MForm.dfm' "object MForm: TMForm`nend`n"
W 'empty.rules' ''
W 'comments.rules' "// nothing here`n`n"
W 'unitword.rules' "Unit MLib`n"
W 'unknown.rules' "#unit MLib`n"
W 'convbad.rules' "Unit MLib`n#convert MLib.TOldC -> MLib.TNewC`n"
W 'tt.rules' "#migrate TOldK -> TNewK`n"
W 'identity.rules' "#migrate TOldK -> TOldK`n"
W 'note.rules' "#note a note`nTOldK -> TNewK`n"
W 'conv.rules' "#convert MLib.TOldC -> MLib.TNewC`n"
$db = P 'm.sqlite'
& $Exe index $WorkDir --db $db *> (P 'index.log')
Check 'V the fixture index was built' (Test-Path $db)

function Run([string]$Unit, [string]$Book, [string[]]$Extra = @()) {
  $o = (& $Exe convert-apply --unit (P "$Unit.pas") --rules (P "$Book.rules") --db $db @Extra 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function NotOld($r) { return ($r.Out -notmatch 'sibling \.dfm') -and ($r.Out -notmatch '#convert rule') }

foreach ($b in 'empty', 'comments') {
  foreach ($u in 'MUse', 'MForm') {
    $r = Run $u $b
    Check "E $b / $u : exit 1, says the file holds no rules, not the #convert sentence" (($r.Code -eq 1) -and ($r.Out -match 'holds no rules') -and (NotOld $r)) $r.Out
  }
}
foreach ($b in 'unitword', 'unknown', 'convbad') {
  $r = Run 'MUse' $b
  Check "P $b / no .dfm : exit 1, the parse error is named, not the .dfm" (($r.Code -eq 1) -and ($r.Out -match 'failed validation') -and ($r.Out -match 'line 1:') -and (NotOld $r)) $r.Out
}
$r = Run 'MNoSite' 'tt'
Check 'S #migrate T -> T, no site, no .dfm : exit 1, "no #migrate line", the unit named' (($r.Code -eq 1) -and ($r.Out -match 'no #migrate line') -and ($r.Out -match 'MNoSite') -and (NotOld $r)) $r.Out
$r = Run 'MForm' 'tt'
Check 'S #migrate T -> T, no site, .dfm : exit 1, "no #migrate line"' (($r.Code -eq 1) -and ($r.Out -match 'no #migrate line') -and (NotOld $r)) $r.Out
$r = Run 'MUse' 'identity'
Check 'S identity #migrate T -> T, no .dfm : exit 1, "no #migrate line"' (($r.Code -eq 1) -and ($r.Out -match 'no #migrate line') -and (NotOld $r)) $r.Out
$r = Run 'MUse' 'note'
Check 'N only #note and raw lines : exit 1, "no #convert block"' (($r.Code -eq 1) -and ($r.Out -match 'no #convert block') -and (NotOld $r)) $r.Out

$r = Run 'MUse' 'empty' @('--format', 'json')
$j = $null; try { $j = $r.Out.Substring($r.Out.IndexOf('{')) | ConvertFrom-Json } catch {}
Check 'J JSON, no .dfm, single unit: a document, ok false, refused false, the sentence in error' (($null -ne $j) -and ($j.ok -eq $false) -and ($j.refused -eq $false) -and ($j.error -match 'holds no rules')) $r.Out
$o = (& $Exe convert-apply --unit (P 'MUse.pas') --unit (P 'MForm.pas') --rules (P 'empty.rules') --db $db --format json 2>&1) -join "`n"
$j = $null; try { $j = $o.Substring($o.IndexOf('{')) | ConvertFrom-Json } catch {}
Check 'J batch: both units carry the sentence' (($null -ne $j) -and (@($j.units | Where-Object { $_.error -match 'holds no rules' }).Count -eq 2)) $o

# ---- controls -----------------------------------------------------------------
$r = Run 'MUse' 'conv'
Check 'C1 CONTROL #convert book, no .dfm : the old refusal, exit 1' (($r.Code -eq 1) -and ($r.Out -match 'sibling \.dfm not found') -and ($r.Out -match 'every #convert rule')) $r.Out
$r = Run 'MForm' 'conv'
Check 'C2 CONTROL #convert book, .dfm, no match : the old refusal, exit 1' (($r.Code -eq 1) -and ($r.Out -match 'no convertible instances found')) $r.Out
$before = [IO.File]::ReadAllText((P 'MUse.pas'))
$r = Run 'MUse' 'tt' @('--apply', '--no-backup')
$after = [IO.File]::ReadAllText((P 'MUse.pas'))
Check 'C3 CONTROL #migrate T -> T with a site: exit 0, the bytes changed' (($r.Code -eq 0) -and ($before -match 'V: TOldK;') -and ($after -match 'V: TNewK;')) $r.Out

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if ($WorkDir -like 'C:\TEMP\draglint_convert_apply_nothing_*' -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
