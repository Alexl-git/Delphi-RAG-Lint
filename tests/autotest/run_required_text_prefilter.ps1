<#
  run_required_text_prefilter.ps1 -- the .scm literal pre-filter must not change
  which findings are reported.

  WHY IT EXISTS. `gettickcount-wraparound` cost 17.48 s of the 52.82 s all 55
  .scm rules cost together on ORM3 -- a third of the phase -- to produce ONE
  finding on the whole corpus. It matches bare `(identifier)`, so tree-sitter
  visits every identifier in every file and runs a regex on each.

  TQueryRule.RequiredText skips a query when the file text cannot contain what
  its predicate is anchored to. That is provably result-preserving, and it is
  also the exact shape of change that goes wrong SILENTLY: a literal extracted
  slightly wrong does not crash, does not slow anything down, and simply stops a
  rule from ever firing again. Nothing else in the battery would notice.

  So this suite's first assertion is that the rule STILL FIRES, and it fires on
  the form that matters:

    * `GetTickCount` WITHOUT parentheses, passed as an argument -- the ONLY form
      that actually occurs on ORM3 (Pipes.Protocol.pas:695). Narrowing the query
      to `(exprCall ...)`, the obvious "fix", would have deleted exactly this and
      bought 16 s by reporting nothing.
    * `GetTickCount()` WITH parentheses -- the other documented form.
    * A file mentioning it only in a COMMENT and a STRING: the pre-filter passes
      (the text is present) and the QUERY must still decline, so the filter
      cannot be credited with suppression it did not do.
    * A file that never mentions it: no finding, which is the case the filter
      short-circuits.

  CASE-INSENSITIVITY IS LOAD-BEARING. Pascal is case-insensitive and the rule's
  predicate is `(?i)`. The filter lowercases both sides; `GETTICKCOUNT` must be
  found. A filter that compared case-sensitively would silence the rule on any
  file that spelled it differently from the .scm.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_prefilter'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Ascii($p,$t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"),
    (New-Object System.Text.UTF8Encoding($false)))
}

# --- the form that actually occurs in the wild: NO parentheses, as an argument -
Write-Ascii (Join-Path $scratch 'uBare.pas') @'
unit uBare;

interface

function Tag: string;

implementation

uses
  System.SysUtils;

function Tag: string;
begin
  Result := Format('x_%u', [GetTickCount]);
end;

end.
'@

# --- the parenthesised form, and an UPPERCASE spelling ------------------------
Write-Ascii (Join-Path $scratch 'uCalled.pas') @'
unit uCalled;

interface

function Elapsed: Cardinal;

implementation

function Elapsed: Cardinal;
var
  T: Cardinal;
begin
  T := GETTICKCOUNT();
  Result := T;
end;

end.
'@

# --- mentions it ONLY in a comment and a string literal ----------------------
# The pre-filter cannot exclude this file (the text IS present), so whatever
# happens here is the QUERY's answer, not the filter's.
Write-Ascii (Join-Path $scratch 'uProse.pas') @'
unit uProse;

interface

function Note: string;

implementation

function Note: string;
begin
  // GetTickCount wraps after 49.7 days -- prose, not code.
  Result := 'call GetTickCount for a coarse timer';
end;

end.
'@

# --- never mentions it: the case the filter short-circuits -------------------
Write-Ascii (Join-Path $scratch 'uClean.pas') @'
unit uClean;

interface

function Twice(AValue: Integer): Integer;

implementation

function Twice(AValue: Integer): Integer;
begin
  Result := AValue * 2;
end;

end.
'@

function HitsIn([string]$Out, [string]$File) {
  @($Out -split "`r?`n" | Where-Object { $_ -match [regex]::Escape($File) -and $_ -match 'gettickcount-wraparound' }).Count
}

Push-Location C:\TEMP
try {
  $db  = Join-Path $scratch 'idx.sqlite'
  & $exePath index $scratch --db $db 2>&1 | Out-Null
  $out = (& $exePath lint-all --db $db --quiet 2>&1 | Out-String)

  # --- THE POINT OF THE SUITE ---------------------------------------------
  Check 'the paren-LESS form is still reported (the only form ORM3 actually has)' `
        ((HitsIn $out 'uBare.pas') -ge 1) $out
  Check 'the parenthesised + UPPERCASE form is still reported (filter is case-insensitive)' `
        ((HitsIn $out 'uCalled.pas') -ge 1) $out

  # --- and the filter is not credited with suppression it did not do -------
  Check 'a comment/string mention yields no finding (the QUERY declines, not the filter)' `
        ((HitsIn $out 'uProse.pas') -eq 0) $out
  Check 'a file that never mentions it yields no finding' `
        ((HitsIn $out 'uClean.pas') -eq 0) $out

  # --- SANITY: the rule is actually enabled in this run --------------------
  # Without this, every assertion above is satisfied by a rule that never runs.
  Check 'SANITY: gettickcount-wraparound produced at least one finding overall' `
        (($out -split "`r?`n" | Where-Object { $_ -match 'gettickcount-wraparound' }).Count -ge 1) `
        'if this is 0 the rule is disabled or the pre-filter silenced it entirely'
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
