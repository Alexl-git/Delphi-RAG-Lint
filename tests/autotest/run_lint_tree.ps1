<#
run_lint_tree.ps1 -- `lint-tree` answers the question `lint-all` cannot.

WHAT THIS PINS. Removing an interface symbol that dependents still reference
produces ZERO lint-all findings. MEASURED 2026-09-10 on this very fixture: three
interface symbols removed from uB while uA still used all three gave 3 findings,
all [info], none about the broken references -- and the TOTAL WENT DOWN from 4
to 3, because the deleted routine's own empty-body finding disappeared. A
developer watching the count would see it improve. That is the hole lint-tree
fills, and case 1 below re-measures it rather than trusting this paragraph.

THE ASSERTION THIS SUITE EXISTS FOR IS CASE 4. The plan keyed routine findings
on `kind='call' AND symbol_id`, from a spec conclusion that symbol_id is
populated for call edges only. docs\INDEX-SCHEMA.md:231 had always said `call`
AND `member-access`, and a PARENLESS function call (`I := W.Value;`) resolves as
member-access. Under the plan's filter that finding vanishes silently -- half
the routine findings on this fixture. Case 4 asserts the member-access row is
PRESENT BY KIND, so a future "tidy-up" that reintroduces a kind filter goes red
here instead of shipping an all-clear.

EVERY POSITIVE HAS A NEGATIVE. A suite that only asserts "the finding appears"
passes against a verb that reports everything, which would be worse than useless
in an editor -- it would fire on every keystroke and be switched off in a week.
So cases 2 and 3 assert SILENCE on an unchanged buffer and on an
implementation-only edit, and case 6 asserts silence WITH A COUNT when a name is
ambiguous.

WHY THE ERROR CASES CHECK STDERR. An unknown verb writes
`ERROR: unknown command: X` to STDERR and then floods ~305 lines of help to
STDOUT, exiting 2. A guard that greps STDOUT for the error text finds nothing
and passes for the wrong reason. Case 8 asserts on the stream and the exit code.

Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){
  Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''}))
  if(-not $ok){ $script:fail = $true }
}

Check 'engine present' (Test-Path $Exe) $Exe
if(-not (Test-Path $Exe)){ Write-Host 'LINT-TREE GUARD: FAIL' -ForegroundColor Red; exit 1 }

# --- fixture -----------------------------------------------------------------
# ASCII + CRLF, per this repo's encoding rule. A unique directory per run so two
# concurrent battery runs cannot fight over one index.
$work = Join-Path $env:TEMP ("dl-linttree-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
$src  = Join-Path $work 'src'
$buf  = Join-Path $work 'buf'
New-Item -ItemType Directory -Force -Path $src | Out-Null
New-Item -ItemType Directory -Force -Path $buf | Out-Null

function Write-Pas([string]$path, [string[]]$lines){
  $text = ($lines -join "`r`n") + "`r`n"
  [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
}

Write-Pas (Join-Path $src 'uB.pas') @(
  'unit uB;','','interface','','const','  BConst = 42;','','var','  BVar: Integer;','',
  'type','  TWidget = class(TObject)','  public','    procedure DoThing;',
  '    function Value: Integer;','  end;','','procedure FreeProc;','','implementation','',
  'procedure TWidget.DoThing;','begin','end;','','function TWidget.Value: Integer;',
  'begin','  Result := 0;','end;','','procedure FreeProc;','begin','end;','','end.')

Write-Pas (Join-Path $src 'uA.pas') @(
  'unit uA;','','interface','','uses','  uB;','','procedure UseIt;','','implementation','',
  'procedure UseIt;','var','  W: TWidget;','  I: Integer;','begin','  W := TWidget.Create;',
  '  try','    W.DoThing;','    I := W.Value;','    I := I + BConst + BVar;','    Writeln(I);',
  '  finally','    W.Free;','  end;','  FreeProc;','end;','','end.')

# the same unit with FreeProc, TWidget.Value and BConst REMOVED from the interface
Write-Pas (Join-Path $buf 'uB.reduced.pas') @(
  'unit uB;','','interface','','var','  BVar: Integer;','',
  'type','  TWidget = class(TObject)','  public','    procedure DoThing;','  end;','',
  'implementation','','procedure TWidget.DoThing;','begin','end;','','end.')

# identical interface, different implementation body
Write-Pas (Join-Path $buf 'uB.implonly.pas') @(
  'unit uB;','','interface','','const','  BConst = 42;','','var','  BVar: Integer;','',
  'type','  TWidget = class(TObject)','  public','    procedure DoThing;',
  '    function Value: Integer;','  end;','','procedure FreeProc;','','implementation','',
  'procedure TWidget.DoThing;','begin','end;','','function TWidget.Value: Integer;',
  'begin','  Result := 0;','end;','','procedure FreeProc;','begin','  Writeln(99);','end;','','end.')

$db   = Join-Path $work 'fx.sqlite'
$unit = Join-Path $src  'uB.pas'
$base = Join-Path $work 'uB.base.json'

& $Exe index $src --db $db --rebuild *> $null
Check 'fixture indexed' (Test-Path $db) $db

function Run-Tree([string[]]$xs){
  $o = & $Exe lint-tree @xs --format json 2>$null
  $code = $LASTEXITCODE
  $json = $null
  try { $json = ($o | Out-String) | ConvertFrom-Json } catch { }
  [pscustomobject]@{ Exit=$code; Json=$json; Raw=($o | Out-String) }
}

# --- case 1: the premise -- lint-all is SILENT on this break ------------------
# Re-measured rather than asserted from the header. If a future rule DOES catch
# stale cross-unit references, this goes red and the whole feature needs
# rethinking -- which is exactly the signal we want.
$reduced = Join-Path $src 'uB.pas'
$saved   = Get-Content $reduced -Raw
[System.IO.File]::WriteAllText($reduced, [System.IO.File]::ReadAllText((Join-Path $buf 'uB.reduced.pas')))
& $Exe index $src --db $db *> $null
$la = (& $Exe lint-all --db $db --quiet 2>$null | Out-String)
$staleRows = ([regex]::Matches($la, 'stale-interface-reference|no longer declares')).Count
Check 'PREMISE: lint-all reports nothing about the broken references' ($staleRows -eq 0) `
      "if this fails, a rule now covers this and lint-tree's justification changed"
[System.IO.File]::WriteAllText($reduced, $saved)
& $Exe index $src --db $db *> $null

# --- baseline ----------------------------------------------------------------
$r = Run-Tree @('--unit', $unit, '--db', $db, '--write-baseline', $base)
Check 'baseline written' ($r.Exit -eq 0 -and (Test-Path $base)) $r.Raw
$bytes = [System.IO.File]::ReadAllBytes($base)
Check 'baseline has NO UTF-8 BOM' `
      (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) `
      'a Delphi reader strips it silently while every strict JSON parser fails on byte 0'
$bj = [System.IO.File]::ReadAllText($base) | ConvertFrom-Json
Check 'baseline carries both version stamps' `
      ($bj.extractor_version -and $bj.schema_version -gt 0) `
      'without them a v21 baseline diffs against a v22 parse and marks every routine changed'
Check 'baseline symbols carry index ids' `
      (($bj.symbols | Where-Object { $_.id -gt 0 }).Count -eq $bj.symbols.Count) `
      'the routine rule joins refs on symbol_id; a zero id matches nothing'

# --- case 2: unchanged buffer ------------------------------------------------
$r = Run-Tree @('--unit', $unit, '--db', $db, '--baseline', $base)
Check 'NEG unchanged buffer -> changed=false' ($r.Json.changed -eq $false) $r.Raw
Check 'NEG unchanged buffer -> no findings' ($r.Json.findings.Count -eq 0) ''
Check 'NEG unchanged buffer -> closure NOT computed' ($null -eq $r.Json.closure) `
      'paying for a recursive CTE on every idle keystroke is how a background feature earns a reputation'

# --- case 3: implementation-only edit ----------------------------------------
$r = Run-Tree @('--unit', $unit, '--db', $db, '--buffer', (Join-Path $buf 'uB.implonly.pas'), '--baseline', $base)
Check 'NEG implementation-only edit -> changed=false' ($r.Json.changed -eq $false) $r.Raw
Check 'NEG implementation-only edit -> no findings' ($r.Json.findings.Count -eq 0) ''

# --- case 4: THE REGRESSION FENCE --------------------------------------------
$r = Run-Tree @('--unit', $unit, '--db', $db, '--buffer', (Join-Path $buf 'uB.reduced.pas'), '--baseline', $base)
Check 'POS removing interface symbols -> changed=true' ($r.Json.changed -eq $true) $r.Raw
$kinds = @($r.Json.findings | ForEach-Object { $_.ref_kind })
Check 'POS a call-kind reference is reported' ($kinds -contains 'call') "kinds: $($kinds -join ',')"
Check 'POS a MEMBER-ACCESS reference is reported' ($kinds -contains 'member-access') `
      'a kind=call filter drops every PARENLESS function call -- half the routine findings here'
Check 'POS a read-kind (const) reference is reported' ($kinds -contains 'read') `
      'consts carry no symbol_id and must come through the gated name join'
Check 'POS three interface symbols are listed as removed' ($r.Json.removed_symbols.Count -eq 3) `
      "got $($r.Json.removed_symbols.Count)"
Check 'POS the closure names the one dependent' `
      ($r.Json.closure.total -eq 1 -and $r.Json.closure.direct -eq 1) `
      "total=$($r.Json.closure.total) direct=$($r.Json.closure.direct)"

# --- case 5: the output schema has no duplicate key --------------------------
# The plan named both the boolean and the delta array `changed`; a strict parser
# keeps the LAST, so the primary answer silently became an array.
Check 'the delta arrays do NOT collide with the changed boolean' `
      ($r.Json.changed -is [bool]) "changed is $($r.Json.changed.GetType().Name)"

# --- case 6: the ambiguity gate ----------------------------------------------
Write-Pas (Join-Path $src 'uC.pas') @('unit uC;','','interface','','const','  BConst = 99;','','implementation','','end.')
& $Exe index $src --db $db --rebuild *> $null
$base2 = Join-Path $work 'uB.base2.json'
Run-Tree @('--unit', $unit, '--db', $db, '--write-baseline', $base2) | Out-Null
$r2 = Run-Tree @('--unit', $unit, '--db', $db, '--buffer', (Join-Path $buf 'uB.reduced.pas'), '--baseline', $base2)
$k2 = @($r2.Json.findings | ForEach-Object { $_.ref_kind })
Check 'GATE an ambiguous name is suppressed' ($r2.Json.suppressed_ambiguous -ge 1) `
      "suppressed=$($r2.Json.suppressed_ambiguous)"
Check 'GATE the suppression is COUNTED, not silent' ($r2.Json.PSObject.Properties.Name -contains 'suppressed_ambiguous') `
      'an uncounted suppression is the all-clear this verb exists to prevent'
Check 'GATE the const finding is gone' (-not ($k2 -contains 'read')) "kinds: $($k2 -join ',')"
Check 'GATE routine findings are UNAFFECTED by a name collision' `
      (($k2 -contains 'call') -and ($k2 -contains 'member-access')) `
      'a resolved symbol_id is unambiguous however many units share the name'

# --- case 7: a baseline from another extraction is REFUSED -------------------
$stale = Join-Path $work 'uB.stale.json'
$sj = [System.IO.File]::ReadAllText($base2) | ConvertFrom-Json
$sj.extractor_version = '0.0.0-not-this-one'
[System.IO.File]::WriteAllText($stale, ($sj | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
$r3 = Run-Tree @('--unit', $unit, '--db', $db, '--baseline', $stale)
Check 'STAMP a foreign baseline is refused' ($r3.Json.reason -like 'baseline_version*') $r3.Raw
Check 'STAMP refusing is exit 0, not an error' ($r3.Exit -eq 0) `
      'the verb RAN, it declined the comparison; exit 2 means it could not run'
Check 'STAMP a refused run reports no findings' ($r3.Json.findings.Count -eq 0) ''

# --- case 8: argument errors go to STDERR and exit 2 -------------------------
$err = Join-Path $work 'err.txt'
$out = Join-Path $work 'out.txt'
$p = Start-Process -FilePath $Exe -ArgumentList 'lint-tree' -Wait -NoNewWindow -PassThru `
      -RedirectStandardError $err -RedirectStandardOutput $out
$errText = Get-Content $err -Raw
Check 'ARGS a missing --unit exits 2' ($p.ExitCode -eq 2) "exit=$($p.ExitCode)"
Check 'ARGS the message goes to STDERR' ($errText -match 'needs --unit') `
      'asserting on STDOUT would pass for the wrong reason -- help floods it'

Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue

if($fail){ Write-Host 'LINT-TREE GUARD: FAIL' -ForegroundColor Red; exit 1 }
else     { Write-Host 'LINT-TREE GUARD: PASS' -ForegroundColor Green; exit 0 }
