<#
  run_lint_stage1_store_parity.ps1 -- docs\PLAN-SESSION-47.md T1
  (docs\INBOX-ide-per-unit-view-omits-79pct-of-lint-all.md)

  `DoLint` resolves a flow store and hands it ONLY to TFlowChecker. Three other
  per-file checkers are called store-less, while `DoLintAll` passes
  (Store, fid) to all three:

      CLI.pas:8571  CheckTypeAware(EffPath)                 vs 12863 (Store, fid)
      CLI.pas:8615  CheckVirtualInConstructor(EffPath)      vs 12885 (Store, fid)
      CLI.pas:8711  TNamingChecker.Check(EffPath, Naming)   vs 12888 (Store, fid)

  All three signatures ALREADY take an optional store -- verified, not assumed
  (AstChecks.pas 322/833, NamingChecks.pas 79-80). Nothing but the argument is
  missing.

  THE REVERSE GAP IS WHAT THIS GUARD PINS. The parity note is about findings the
  IDE never SEES; this is the other direction -- a finding the IDE INVENTS.
  NamingChecks.pas:616-617 reads:

      IsExcClass:= False;
      if (AStore <> nil) and (ANaming.ExceptionPrefix <> '') then
        IsExcClass:= AStore.IsDescendantOf(TypeName, 'Exception', AFileId);

  With a store, `EFoo = class(Exception)` resolves as an exception class and the
  'E' prefix is CORRECT -> silence. Store-free, IsExcClass stays False, control
  falls to the else branch, and the class is reported as needing a 'T' prefix.
  That is a false positive shown in the editor gutter on correct code.

  WHY THE ANCESTRY RESOLVES FROM THE PROJECT DB ALONE (checked, not hoped):
  type_ancestors stores DIRECT parent edges as (child symbol_id -> ancestor
  NAME), and IsDescendantOf walks them comparing names
  (Storage.SQLite.pas:10018-10027). EFoo derives from Exception DIRECTLY, so the
  edge is in the fixture's own index and no library store is needed.

  Defaults confirmed at Config.pas:470-471 -- ClassPrefix 'T', ExceptionPrefix 'E'.

  RED FIRST: against the unfixed build A1 FAILS (the per-file verb reports EFoo)
  while A2/A3/A4 pass. A2 is the live positive control -- a mis-prefixed class
  BOTH verbs must keep reporting -- so a "fix" that merely switched the rule off
  would turn A2 red rather than sneak through. A4 pins the deliberate store-free
  fallback (NamingChecks.pas:613 "conservative -- no guessing") so the change
  cannot be mistaken for making the rule unconditionally quiet.

  INDEX ABSOLUTE. A relative index target writes relative path rows, the
  membership probe in DoLint then misses, and the store is SILENTLY dropped --
  the run looks store-backed and answers store-free, which is exactly the bug
  under test passing itself.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_stage1_store_parity"
)
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

# EFoo derives from Exception DIRECTLY so the ancestry edge lands in this
# fixture's own index. Foo is the control: mis-prefixed under every branch,
# store or no store, so it must be reported by BOTH verbs on BOTH paths.
$fixture = @'
unit uStage1Parity;

interface

uses
  System.SysUtils;

type
  /// <summary>Correctly E-prefixed exception class. Store-backed runs must be
  /// SILENT about it; only a store-free run mistakes it for a plain class.</summary>
  EFoo = class(Exception)
  end;

  /// <summary>The positive control: no prefix at all, wrong under every
  /// branch. Every path must keep reporting this one.</summary>
  Foo = class
  end;

implementation

end.
'@

$file = Join-Path $WorkDir 'uStage1Parity.pas'
Write-Ascii $file $fixture
$db = Join-Path $WorkDir 'stage1.sqlite'

# ABSOLUTE target -- see the header note.
$idx = & $exePath index $WorkDir --db $db 2>&1 | Out-String
Check 'SANITY: fixture indexed with no errors' `
      ($LASTEXITCODE -eq 0 -and $idx -notmatch '\b[1-9]\d* errors\b') $idx

# The membership probe must actually have found the file, or every store-backed
# assertion below degrades to the store-free answer and the guard tests nothing.
$env:DRAGLINT_DEBUG = '1'
$dbg = & $exePath lint $file --db $db --rules-dir $rules 2>&1 | Out-String
Remove-Item Env:\DRAGLINT_DEBUG
Check 'SANITY: the per-file verb actually resolved the store for this file' `
      ($dbg -match 'store=True' -and $dbg -notmatch 'fid=0\b') `
      (($dbg -split "`n" | Where-Object { $_ -match '\[flowdb\]' }) -join ' ')

function TypeNamePrefixHits($text, $name) {
  @($text -split "`r?`n" | Where-Object { $_ -match 'type-name-prefix' -and $_ -match ("\b" + [regex]::Escape($name) + "\b") }).Count
}

# --- the per-file verb, store-backed: this is the surface the IDE spawns ------
$perFile = & $exePath lint $file --db $db --rules-dir $rules 2>&1 | Out-String

Check 'A1  store-backed `lint <file> --db` does NOT report the E-prefixed exception class' `
      ((TypeNamePrefixHits $perFile 'EFoo') -eq 0) `
      "expected silence for EFoo; got: $(($perFile -split "`r?`n" | Where-Object { $_ -match 'EFoo' }) -join ' | ')"

Check 'A2  CONTROL: the same run still reports the genuinely mis-prefixed class' `
      ((TypeNamePrefixHits $perFile 'Foo') -ge 1) `
      "expected a type-name-prefix finding for Foo -- if this is red the rule died instead of getting more precise"

# --- lint-all over the same file: the reference the per-file verb must match --
$all = & $exePath lint-all --db $db --rules-dir $rules --output (Join-Path $WorkDir 'all.txt') 2>&1 | Out-String
$allTxt = if (Test-Path (Join-Path $WorkDir 'all.txt')) { Get-Content (Join-Path $WorkDir 'all.txt') -Raw } else { $all }

Check 'A3  PARITY: lint-all agrees -- silent on EFoo, reports Foo' `
      ((TypeNamePrefixHits $allTxt 'EFoo') -eq 0 -and (TypeNamePrefixHits $allTxt 'Foo') -ge 1) `
      "lint-all EFoo=$(TypeNamePrefixHits $allTxt 'EFoo') Foo=$(TypeNamePrefixHits $allTxt 'Foo')"

# --- store-FREE stays deliberately conservative -------------------------------
$noStore = & $exePath lint $file --rules-dir $rules 2>&1 | Out-String

Check 'A4  store-free `lint <file>` still reports EFoo (documented fallback, unchanged)' `
      ((TypeNamePrefixHits $noStore 'EFoo') -ge 1) `
      "NamingChecks.pas:613 says fall back to requiring the class prefix -- no guessing. If this is red the change went further than the store."

Write-Host ''
if ($fail) { Write-Host 'run_lint_stage1_store_parity: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_lint_stage1_store_parity: PASS' -ForegroundColor Green
exit 0
