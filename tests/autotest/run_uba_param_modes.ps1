<#
  run_uba_param_modes.ps1 -- SHAPE C of
  docs\INBOX-used-before-assignment-false-positives.md.

  THE DEFECT. `ReadFile(H, Buf[0], SizeOf(Buf) - 1, N, nil)` reported Buf as
  used-before-assignment ON THE LINE THAT FILLS IT, at error severity. Cause:
  CollectReadsAndCallDefs treated a BARE identifier argument as a possible
  var/out def, but an INDEXED one (`Buf[0]`) took the generic read walk and
  landed in AReads. Nothing SYNTACTIC separates that from `Writeln(Arr[0])`,
  which must keep firing -- only the CALLEE'S SIGNATURE does, and it is already
  in the index. So a KNOWN var/out parameter now withdraws the spurious read.

  WHAT THIS DELIBERATELY DOES NOT DO, and why -- each learned from the ORM3 A/B
  rather than reasoned out, and each one a false ERROR that reached a real file:

   1. It never WITHDRAWS a possible-def, even when the signature says "by
      value". In Delphi a by-value POINTER is the standard Win32 out-buffer:
        GetTempFileName(PathBuf, 'mco', 0, NameBuf)   -- lpTempFileName: LPWSTR
      is written through a parameter declared by value, and there is no `@` to
      notice because Delphi takes the array's address implicitly. Honouring
      "by value" reported NameBuf as unassigned on the line that fills it.
   2. It never turns a bare by-value argument into a READ, which would have
      closed the mirror-image `Writeln(Y)` false negative. That needs
      `absolute` modelled first -- `Overlay: cardinal absolute InVal` is
      assigned through its alias, and reporting it is a false ERROR.
   3. Intrinsics answer only in the var/out direction. IntrinsicSignature is
      documented "for display": `SizeOf(X)` parses as a value parameter but is a
      COMPILE-TIME TYPE QUERY that does not read X. Trusting it added 402
      findings, including `FillChar(StartupInfo, SizeOf(StartupInfo), 0)`.
   4. Only a FREE ROUTINE may answer a bare-name call. Allowing methods made
      this a NAME MATCH, not a resolution: `New(Data)` matched
      PDFlibSmartAccess.TSmartPDFWriter.New. Note the "all matches must agree"
      rule did NOT save that -- there was exactly one match and it was wrong.

  NET EFFECT, MEASURED: ORM3 lint-all is BYTE-IDENTICAL across this change
  (19003 findings before and after; used-before-assignment 197 on both sides).
  ORM3 contains no instance of shape C, which is exactly why the fixture below
  CONSTRUCTS the shape instead of hunting for it.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_uba_parammodes"
)
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null

# Four callees differing ONLY in parameter mode, so the mode is the sole
# variable. The locals are `array[0..7] of Integer` -- an UNMANAGED element
# type, so the rule applies at all: a managed one is zero-initialised and never
# reported (see run_used_before_assignment_arrays.ps1).
Write-Ascii (Join-Path $src 'uCallee.pas') @'
unit uCallee;

interface

procedure FillIt(var pBuf: Integer);
procedure OutIt(out pBuf: Integer);
procedure ReadConst(const pBuf: Integer);
procedure ReadVal(pBuf: Integer);

implementation

procedure FillIt(var pBuf: Integer);
begin
  pBuf := 1;
end;

procedure OutIt(out pBuf: Integer);
begin
  pBuf := 2;
end;

procedure ReadConst(const pBuf: Integer);
begin
  if pBuf = 0 then Exit;
end;

procedure ReadVal(pBuf: Integer);
begin
  if pBuf = 0 then Exit;
end;

end.
'@

Write-Ascii (Join-Path $src 'uConsumer.pas') @'
unit uConsumer;

interface

procedure P;

implementation

uses
  uCallee;

procedure P;
var
  AVar   : array[0..7] of Integer;
  AOut   : array[0..7] of Integer;
  AConst : array[0..7] of Integer;
  AVal   : array[0..7] of Integer;
begin
  FillIt(AVar[0]);
  OutIt(AOut[0]);
  ReadConst(AConst[0]);
  ReadVal(AVal[0]);
end;

end.
'@

# ABSOLUTE index target, and that is load-bearing. The index stores paths as
# given, while `lint <file>` decides whether a db covers a file by comparing
# against ExpandFileName -- so a RELATIVE index target writes relative rows, the
# membership probe misses, the store is SILENTLY dropped, and every case below
# reverts to the store-free answer while still looking like a store run.
$db = Join-Path $WorkDir 'uba.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null
$consumer = Join-Path $src 'uConsumer.pas'

function Reported([string]$Text) {
  ,@([regex]::Matches($Text, 'used-before-assignment: Local "(\w+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}

Push-Location C:\TEMP
try {
  $allOut = (& $exePath lint-all --db $db --rules-dir $rules --quiet 2>&1 | Out-String)
  $all    = Reported $allOut
  Write-Host ("  lint-all reported: {0}" -f $(if($all){$all -join ','}else{'(none)'})) -ForegroundColor DarkGray

  # ---- THE FIX: a known by-reference parameter is a def, not a read.
  Check 'A1 a `var` parameter arg is NOT reported'  (-not ($all -contains 'avar')) ($all -join ',')
  Check 'A2 an `out` parameter arg is NOT reported' (-not ($all -contains 'aout')) ($all -join ',')

  # ---- THE CONTROLS. Without these, switching the rule off for every call
  #      argument -- or dropping the read for ANY indexed arg, which is the fix
  #      the note explicitly REFUSES -- would pass A1/A2 just as well.
  Check 'C1 CONTROL a `const` parameter arg IS still reported' ($all -contains 'aconst') ($all -join ',')
  Check 'C2 CONTROL a value parameter arg IS still reported'   ($all -contains 'aval')   ($all -join ',')
  Check 'C3 VACUITY the run reported something at all' ([bool]$all) 'no findings -- the fixture is measuring nothing'

  # ---- THE STORE IS THE MECHANISM. With no --db there is no signature to
  #      consult, so all four must STILL be reported. This pins that the fix is
  #      store-driven and that the bare `lint <file>` path is untouched.
  $bare = Reported ((& $exePath lint $consumer --rules-dir $rules 2>&1 | Out-String))
  foreach ($v in @('avar','aout','aconst','aval')) {
    Check "C4 store-free ``lint <file>`` still reports $v" ($bare -contains $v) ($bare -join ',')
  }

  # ---- lint <file> --db and lint-all must not disagree. run_lint_file_flow_
  #      matches_lintall pins that generally; it cannot see THIS shape, because
  #      its fixture has no call whose parameter mode matters.
  $one = Reported ((& $exePath lint $consumer --db $db --rules-dir $rules 2>&1 | Out-String))
  Check 'C5 `lint <file> --db` agrees with `lint-all`' `
        (($one -join ',') -eq ($all -join ',')) "lint=$($one -join ','); lint-all=$($all -join ',')"
}
finally { Pop-Location }

Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
