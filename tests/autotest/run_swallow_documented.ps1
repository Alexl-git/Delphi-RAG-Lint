<#
  run_swallow_documented.ps1 -- `try-except-swallowed` must accept a DOCUMENTED
  deliberate swallow, and must keep its teeth everywhere else.

  THE OWNER RULING (2026-08-13)
  -----------------------------
  ~43 findings across DataCopy / YADFOT / YADFSetup are handlers that are silent
  ON PURPOSE and say so in writing, e.g.

      except
        // Deliberately swallowed. This destructor runs during Spring
        // GlobalContainer finalization; a read-only INI directory would
        // otherwise let an exception escape a destructor -- far worse than a
        // lost settings write.
      end;

  Ruling: an except body that runs NO code and carries an explanation is
  accepted. This also lines the rule up with `empty-except`, which already stops
  firing on that exact shape (its .scm anchors kExcept ADJACENT to kEnd, so any
  comment breaks the anchor) -- before this, the same two lines of source
  produced one finding and not the other.

  THE TWO HALVES THAT KEEP IT HONEST
  ----------------------------------
  * COMMENTS ONLY. A handler that DOES run code and merely carries a trailing
    `// retry backoff` still fires. That is the more dangerous shape -- the
    exception vanishes while something else happens -- and it is not what was
    ruled on. Case 4 asserts it.
  * NOT A TOOL MARKER. `// dl:ok <rule>@<hash>` is written BY drag-lint. If it
    counted as documentation the marker would be self-fulfilling: allow the
    finding, the marker silences the rule, the marker is then reported UNUSED,
    removing it brings the finding back. Case 3 asserts the rule still fires
    through a marker-only comment -- which is precisely what keeps
    try-except-swallowed OUT of COMMENT_SENSITIVE.

  NOTE ON THE FIXTURE: the case tags sit on the `try` line, never on `except`.
  A comment on the `except` line is itself inside the handler and would document
  every case, including the ones that must fire.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-swallow-documented"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$fixture = Join-Path $WorkDir 'SwallowDocumented.pas'
$body = @"
unit SwallowDocumented;

interface

procedure Documented;
procedure Bare;
procedure MarkerOnly;
procedure CodeWithComment;
procedure BraceComment;

implementation

procedure Work;
begin
end;

procedure Documented;
begin
  try // A1-documented
    Work;
  except
    // Deliberately swallowed. This runs during finalization; an exception
    // escaping here is worse than the work being skipped.
  end;
end;

procedure Bare;
begin
  try // A2-bare
    Work;
  except
  end;
end;

procedure MarkerOnly;
begin
  try // A3-marker
    Work;
  except
    // dl:ok try-except-swallowed@0badc0de -- reviewed
  end;
end;

procedure CodeWithComment;
begin
  try // A4-code
    Work;
  except
    Work; // retry once, best effort
  end;
end;

procedure BraceComment;
begin
  try // A5-brace
    Work;
  except
    { Swallowed on purpose: the caller polls for the result instead. }
  end;
end;

end.
"@
$norm = $body -replace "`r`n", "`n" -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($fixture, $norm, [System.Text.Encoding]::ASCII)

# Anchor each case to its tagged `try`, then take the next `except` line -- the
# rule reports at the `except` keyword. Editing the fixture cannot decouple them.
$lines = [System.IO.File]::ReadAllLines($fixture)
function ExceptLineAfter([string]$Tag) {
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match [regex]::Escape($Tag)) {
      for ($j = $i + 1; $j -lt $lines.Count; $j++) {
        if ($lines[$j].Trim() -eq 'except') { return $j + 1 }
      }
    }
  }
  return -1
}
$lnDocumented = ExceptLineAfter 'A1-documented'
$lnBare       = ExceptLineAfter 'A2-bare'
$lnMarker     = ExceptLineAfter 'A3-marker'
$lnCode       = ExceptLineAfter 'A4-code'
$lnBrace      = ExceptLineAfter 'A5-brace'
Check 'all five fixture cases located' (
  @($lnDocumented,$lnBare,$lnMarker,$lnCode,$lnBrace) -notcontains -1) `
  ("lines {0}" -f (@($lnDocumented,$lnBare,$lnMarker,$lnCode,$lnBrace) -join ', '))

$fired = @()
foreach ($line in (& $Exe lint $fixture 2>$null)) {
  if ("$line" -match ':(\d+):\d+\s+\[\w+\]\s+try-except-swallowed:') { $fired += [int]$Matches[1] }
}
$fired = @($fired | Sort-Object -Unique)
Write-Host ("  fired on lines: {0}" -f ($fired -join ', ')) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'A documented, code-free swallow is ACCEPTED' -ForegroundColor Cyan
Check "// prose, no code (line $lnDocumented)"      (-not ($fired -contains $lnDocumented))
Check "brace prose, no code (line $lnBrace)"        (-not ($fired -contains $lnBrace))

Write-Host ''
Write-Host 'Everything else still FIRES' -ForegroundColor Cyan
Check "no comment at all (line $lnBare)"                    ($fired -contains $lnBare)
Check "dl:ok marker is not documentation (line $lnMarker)"  ($fired -contains $lnMarker) `
  'keeps the rule out of COMMENT_SENSITIVE'
Check "code + trailing comment (line $lnCode)"              ($fired -contains $lnCode) `
  'the handler RUNS something -- not the ruled-on shape'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
