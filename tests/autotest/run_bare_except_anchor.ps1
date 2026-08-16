# Guard: bare-except anchors on the `except` KEYWORD, and no comment silences it.
#
# docs\INBOX-bare-except-anchor-defeats-a-hand-written-marker.md.
#
# The rule used to capture @warn on the (statements) inside the handler, so the
# reported line was the handler's FIRST STATEMENT. That is where a reviewer then
# had to write an accountable `dl:ok bare-except` marker -- not on the construct
# the rule is about, and nowhere at all in an empty handler. The obvious
# placement (trailing the `except`) silently failed AND was then reported as an
# unused marker, telling the reviewer to delete the very thing they had just
# written. Every sibling rule in this family already anchored on its own keyword
# (empty-except/kExcept, empty-finally/kFinally, empty-on-handler/kDo,
# empty-conditional/kThen+kElse, empty-loop-body/kDo+kRepeat); bare-except was
# the lone outlier.
#
# THE ARM THAT MATTERS MOST IS "a comment does not silence the rule".
#
# The first fix wrote `(kExcept) @warn . except: (statements)`. The '.' anchor
# looks tighter and quietly destroyed the feature: a trailing comment on the
# `except` line is a node BETWEEN those two, so immediate-adjacency failed and
# the rule stopped firing the moment a marker was added. The marker then
# SILENCED the rule instead of accounting for it, and review-marker-unused told
# the reviewer to remove it -- the exact no-exit loop COMMENT_SENSITIVE exists
# to break. It presents as "suppression works", because the finding is gone
# either way. Only an arm that adds a NON-marker comment and demands the finding
# SURVIVE can tell the two apart.
#
# Marker suppression itself is covered by tests/reviewmarker/run_review_marker_prose.ps1.
#
# Usage: pwsh -File tests/autotest/run_bare_except_anchor.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $RulesDir = "$PSScriptRoot\..\..\rules",
    [string] $WorkDir = "$env:TEMP\drag-lint-bare-except-anchor"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$FixtureBody = @'
unit uBareExceptAnchor;
interface
procedure Bare;
procedure BareLineComment;
procedure BareBraceComment;
procedure EmptyHandler;
procedure TypedHandler;
implementation

procedure Bare;
begin
  try
    Writeln('a');
  except
    Writeln('b');
  end;
end;

procedure BareLineComment;
begin
  try
    Writeln('a');
  except // an ordinary comment, NOT a dl:ok marker
    Writeln('b');
  end;
end;

procedure BareBraceComment;
begin
  try
    Writeln('a');
  except { an ordinary brace comment }
    Writeln('b');
  end;
end;

procedure EmptyHandler;
begin
  try
    Writeln('a');
  except
  end;
end;

procedure TypedHandler;
begin
  try
    Writeln('a');
  except
    on E: Exception do Writeln('b');
  end;
end;

end.
'@
$file = Join-Path $WorkDir 'uBareExceptAnchor.pas'
$norm = ($FixtureBody -replace "`r`n", "`n") -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($file, $norm, [System.Text.Encoding]::ASCII)

# Rows are DERIVED, never hard-coded: a hard-coded number retargets silently the
# moment the fixture is edited, which is how an anchor test can pass forever
# while measuring the wrong line.
$src = Get-Content $file
function Row-Of([string]$Needle) {
  ($src | Select-String -Pattern $Needle -SimpleMatch | Select-Object -First 1).LineNumber
}
# Regex + case-sensitive, NOT a plain 'except' substring: Select-String is
# case-INsensitive by default, so a bare needle matched line 1 -- the unit is
# named uBareExceptAnchor. The anchor then pointed at the unit header and the
# assertion failed for a reason that had nothing to do with the rule.
function Row-OfRe([string]$Pattern) {
  ($src | Select-String -Pattern $Pattern -CaseSensitive | Select-Object -First 1).LineNumber
}
$rowBare      = Row-OfRe '^\s*except\s*$'                                # first bare `except`
$rowLineCmt   = Row-Of 'except // an ordinary comment'
$rowBraceCmt  = Row-Of 'except { an ordinary brace comment }'
$rowEmptyStmt = Row-Of "Writeln('b');"                                   # statement under the first handler
foreach ($p in @(@('bare',$rowBare), @('linecmt',$rowLineCmt), @('bracecmt',$rowBraceCmt))) {
  if (-not $p[1]) { Write-Host "FATAL: fixture anchor '$($p[0])' not found" -ForegroundColor Red; exit 2 }
}

$out = & $Exe lint $file --rules-dir $RulesDir 2>&1 | Out-String
$bareRows = [regex]::Matches($out, 'uBareExceptAnchor\.pas:(\d+):\d+\s+\[info\]\s+bare-except') |
            ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object

Write-Host ("  bare-except rows: {0}  (except={1}, //={2}, {{}}={3}, stmt={4})" -f `
    ($bareRows -join ','), $rowBare, $rowLineCmt, $rowBraceCmt, $rowEmptyStmt) -ForegroundColor DarkGray

# THE DEFECT -- the finding lands on the `except` keyword, not the statement.
Check "anchored on the 'except' keyword (row $rowBare)" ($bareRows -contains $rowBare)
Check "NOT anchored on the handler's first statement (row $rowEmptyStmt)" `
    (-not ($bareRows -contains $rowEmptyStmt))

# POSITIVE CONTROLS -- an ordinary comment must not silence the rule. Without
# these, re-adding a '.' anchor between kExcept and the statements looks fine.
Check "a trailing // comment does not silence the rule (row $rowLineCmt)" ($bareRows -contains $rowLineCmt)
Check "a trailing { } comment does not silence the rule (row $rowBraceCmt)" ($bareRows -contains $rowBraceCmt)

# NOT OVER-BROADENED -- exactly the three bare handlers, so the empty and typed
# handlers below have not started matching.
Check 'exactly 3 bare-except findings (empty + typed handlers excluded)' ($bareRows.Count -eq 3) `
    ("got {0}" -f $bareRows.Count)
Check 'empty handler still reported as empty-except, not bare-except' `
    ($out -match '\[warning\]\s+empty-except')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
