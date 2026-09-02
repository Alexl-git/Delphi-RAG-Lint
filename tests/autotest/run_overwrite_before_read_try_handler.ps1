<#
  run_overwrite_before_read_try_handler.ps1 -- C1: a store whose only reader is
  the except handler is NOT a dead store.

  THE BUG (INBOX-flow-analysis-fps-that-are-dangerous-to-act-on.md)
  --------------------------------------------------------------------------------
  DRagLint.Analysis.Cfg wired exactly one edge from the try region into the
  handler:

      Cfg.Blocks[BodyIdx].AddSucc(HdrIdx);   // try entry -> handler

  BodyIdx is the region ENTRY. That models "it threw before anything ran", which
  is the right most-conservative state -- but it is not the only one, and on its
  own it leaves every assignment in a LATER basic block unable to reach the
  handler at all. A local assigned after a branch and read only by the handler
  therefore looked dead:

      LOpened := False;                      // later block, after an if/exit
      ...
      except on E: Exception do
        if LOpened and (not RollBackOutput) then ...   // the reader

  Measured on DataCopy: 11 findings, every one a false positive on a store the
  handler genuinely consumes -- and a DANGEROUS class of FP, because acting on it
  deletes the assignment the error path depends on. After the fix: 2, both
  genuine dead stores (`Str := ''`, and a ReadLine whose result is discarded),
  and NO other rule's count moved.

  WHY THE FIRST ATTEMPT AT THIS FIXTURE PROVED NOTHING, twice over.

  1. The note's own paraphrase (assign before a try, overwrite inside, read in
     the except) was built as a synthetic three-liner in session 56, came back
     silent, and was read as "probably already fixed". It was not. The
     paraphrase dropped the BRANCH, and the branch is the whole mechanism: with
     no branch the assignment stays in the try ENTRY block, which already had
     its edge. `TransferNoBranch` below pins that shape as a control -- it was
     never broken and must stay silent.

  2. Wiring EVERY body block to the handler then broke `double-free`: DivertVia
     emits a COPY of each enclosing finally body on an exit path, those copies
     are created while the try body is being emitted and so fall inside its block
     range, and an edge from one to the handler let the finally's statements be
     analysed twice on a single path. Five phantom double-frees appeared on
     DataCopy CSVRoutines.pas, on objects the index shows are freed exactly once.
     `DoubleFreeShape` below is the minimal form of that regression.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Fixture = "$PSScriptRoot\..\lint\try-handler-reads-body-local.pas",
  [string]$WorkDir = "$env:TEMP\draglint_obr_try_handler"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  [System.IO.File]::WriteAllText($Path, ($Body -replace "`r`n", "`n" -replace "`n", "`r`n"),
                                 [System.Text.Encoding]::ASCII)
}

Write-Host '== overwrite-before-read: the handler is a reader ==' -ForegroundColor Cyan
if (-not (Test-Path $Exe))     { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $Fixture)) { Write-Host "FATAL: fixture not found: $Fixture" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
Copy-Item $Fixture $WorkDir -Force

# The double-free regression this fix had to avoid: try/finally whose body is a
# try/except containing an Exit, so DivertVia inlines the finally on the exit
# path. Each object is freed exactly ONCE.
Write-Ascii (Join-Path $WorkDir 'dfshape.pas') @'
unit dfshape;

interface

type
  TP = class
  public
    function Run(const AFlag: Boolean; out AMess: string): Boolean;
  end;

implementation

uses
  System.Classes, System.SysUtils;

procedure Work;
begin
end;

function TP.Run(const AFlag: Boolean; out AMess: string): Boolean;
var
  A: TStringList;
  B: TStringList;
begin
  Result := False;
  A := TStringList.Create;
  B := TStringList.Create;
  try
    try
      Work;
      if AFlag then Exit;
      Work;
    except
      on E: Exception do
      begin
        Result := False;
        AMess  := E.Message;
      end;
    end;
  finally
    A.Free;
    B.Free;
  end;
end;

end.
'@

$db  = Join-Path $WorkDir 'p.sqlite'
$rep = Join-Path $WorkDir 'rep.txt'
$idx = & $Exe index $WorkDir --db $db 2>&1 | Out-String
& $Exe lint-all --db $db --output $rep --quiet 2>&1 | Out-Null
$out = if (Test-Path $rep) { Get-Content $rep } else { @() }

# Preconditions: without these, a fixture that failed to parse or index would
# produce an empty report and satisfy every "must NOT be reported" arm by silence.
Check 'control: both fixtures parsed with no errors' `
  ($idx -notmatch '-> 0 symbols' -and $idx -notmatch ', [1-9]\d* errors') `
  'a parse failure would make every negative arm pass vacuously'

$obr = @($out | Where-Object { $_ -match 'overwrite-before-read' })
Check 'control: the rule ran and still reports something' ($obr.Count -gt 0) `
  "overwrite-before-read lines=$($obr.Count)"

$obrText = $obr -join "`n"

Check 'a store read ONLY by the except handler is NOT reported (lopened)' `
  (-not ($obrText -match '"lopened"')) 'read at `if LOpened and (not RollBackOutput)`'
Check 'the same, for a second local in the same block (lwritten)' `
  (-not ($obrText -match '"lwritten"')) 'read at `if LWritten then`'

Check 'CONTROL: the no-branch shape stays silent (it was never broken)' `
  (($obrText -split "`n" | Where-Object { $_ -match 'TransferNoBranch' }).Count -eq 0) `
  'assignment sits in the try ENTRY block, which always had its handler edge'

Check 'POSITIVE CONTROL: a genuine dead store in a try body IS still reported' `
  ($obrText -match '"lunread"') `
  'without this, a fix that stopped analysing try bodies would pass'

$dfree = @($out | Where-Object { $_ -match 'double-free' })
Check 'REGRESSION CONTROL: no phantom double-free from the inlined finally' `
  ($dfree.Count -eq 0) `
  ("double-free lines=$($dfree.Count): " + (($dfree | ForEach-Object { ($_ -split '  ')[0] }) -join ' '))

Write-Host ''
if ($script:Failed) { Write-Host 'TRY-HANDLER GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'TRY-HANDLER GUARD: PASS' -ForegroundColor Green
exit 0
