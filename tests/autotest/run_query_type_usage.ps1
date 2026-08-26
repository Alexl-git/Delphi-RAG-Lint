<#
  run_query_type_usage.ps1 -- `query type-usage --in <f> --names A,B,C` answers
  "which of these type names does this file actually REFERENCE?"

  WHAT THIS VERB IS FOR, and why the negative assertions carry the weight:
    The question is asked of a LIST (an RTL surface, say 30 names), of one file.
    Grep answers a different question -- it cannot tell a reference from the same
    word inside a comment or a string literal, and across a list that size the
    difference IS most of the output. So the interesting assertions here are not
    "the used type was found"; they are "the type named ONLY in a comment, and
    the one named ONLY in a string literal, were NOT found" -- while a real
    reference in the same file still is.

  THE FOUR SHAPES A REFERENCE TAKES, all verified against the live index before
  the verb was written:
    * declaration  `V: TUsedInDecl`        -> refs.kind = 'type_use'
    * construction `TUsedInCreate.Create`  -> a 'read' of the name PLUS a
      'member-access' whose RECEIVER_TEXT is the type. The member-access row
      carries 'Create' in name_text, so a scan that reads only name_text misses
      every construction site. That is not hypothetical: it is exactly what this
      verb reported until GetReferencesFromFile was fixed to surface
      receiver_text, which it had been selecting and discarding.
    * inheritance  `class(TUsedAsAncestor)` -> also a plain 'type_use' ref in the
      same file, so type_ancestors needs no joining.
    * absent       -> nothing.

  NAME-KEYED, and the verb says so in its own output: refs.symbol_id is NULL for
  every type_use row, so a project type sharing an RTL name is indistinguishable.
  That limitation is asserted here rather than left to be rediscovered.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-type-usage"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Text) {
  $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir -Force | Out-Null

Write-Ascii (Join-Path $WorkDir 'uTypes.pas') @'
unit uTypes;
interface
type
  TUsedInDecl     = class end;
  TUsedInCreate   = class constructor Create; end;
  TUsedAsAncestor = class end;
  TNeverUsed      = class end;
  TOnlyInComment  = class end;
  TOnlyInLiteral  = class end;
implementation
constructor TUsedInCreate.Create;
begin
end;
end.
'@

Write-Ascii (Join-Path $WorkDir 'uProbe.pas') @'
unit uProbe;
interface
uses uTypes;
type
  TChild = class(TUsedAsAncestor)
  end;
procedure Run;
implementation
// TOnlyInComment is named here and NOWHERE else -- a comment is not a reference.
procedure Run;
var
  D: TUsedInDecl;
  C: TUsedInCreate;
  S: string;
begin
  D := nil;
  C := TUsedInCreate.Create;
  S := 'TOnlyInLiteral';   // a string literal is not a reference either
  Writeln(S, Integer(D <> nil), Integer(C <> nil));
end;
end.
'@

Write-Ascii (Join-Path $WorkDir 'App.dpr') @'
program App;
uses
  uTypes in 'uTypes.pas',
  uProbe in 'uProbe.pas';
begin
  Run;
end.
'@

$db    = Join-Path $WorkDir 'app.sqlite'
$probe = Join-Path $WorkDir 'uProbe.pas'
& $Exe index $WorkDir --db $db 2>&1 | Out-Null

$names = 'TUsedInDecl,TUsedInCreate,TUsedAsAncestor,TNeverUsed,TOnlyInComment,TOnlyInLiteral'
# STDOUT ONLY. The '(loaded defaults ...)' banner goes to stderr, which is
# correct -- merging the streams here would corrupt the document and blame the
# verb for the test's own mistake. Asserting on raw stdout is also what keeps
# this honest if a human line ever DOES land in the JSON.
$json  = & $Exe query type-usage --in $probe --names $names --db $db --json 2>$null | Out-String
$rows  = $null
try { $rows = $json | ConvertFrom-Json } catch {}
Check 'JSON output parses' ($null -ne $rows) (($json -split "`r?`n" | Select-Object -First 1))
Check 'stdout is the JSON document and nothing else' ($json.TrimStart().StartsWith('['))
if ($null -eq $rows) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

function Ref([string]$n) { ($rows | Where-Object { $_.name -eq $n }).referenced }
function Kinds([string]$n) {
  $k = ($rows | Where-Object { $_.name -eq $n }).kinds
  if ($null -eq $k) { return '' }
  ($k.PSObject.Properties | ForEach-Object { $_.Name }) -join ','
}

Write-Host 'POSITIVE CONTROLS: a real reference in each shape IS found' -ForegroundColor Cyan
# Without these, every "not referenced" assertion below passes on a dead verb.
Check 'declaration is a reference'  ((Ref 'TUsedInDecl')     -eq $true) (Kinds 'TUsedInDecl')
Check 'inheritance is a reference'  ((Ref 'TUsedAsAncestor') -eq $true) (Kinds 'TUsedAsAncestor')
Check 'construction is a reference' ((Ref 'TUsedInCreate')   -eq $true) (Kinds 'TUsedInCreate')

Write-Host ''
Write-Host 'THE POINT OF THE VERB: comment and literal mentions are NOT references' -ForegroundColor Cyan
Check 'a type named only in a COMMENT is not reported' ((Ref 'TOnlyInComment') -eq $false)
Check 'a type named only in a STRING LITERAL is not reported' ((Ref 'TOnlyInLiteral') -eq $false)
Check 'a type never mentioned at all is not reported' ((Ref 'TNeverUsed') -eq $false)

Write-Host ''
Write-Host 'X.Create must be seen THROUGH receiver_text, not name_text' -ForegroundColor Cyan
# The member-access row carries 'Create' in name_text and the TYPE only in
# receiver_text. A regression that stops reading receiver_text leaves
# TUsedInCreate still "referenced" (its declaration is a type_use), so asserting
# `referenced` alone would NOT catch it -- the KIND is what bites.
Check 'construction contributes a member-access kind' `
  ((Kinds 'TUsedInCreate') -match 'member-access') (Kinds 'TUsedInCreate')

Write-Host ''
Write-Host 'Text output and error paths' -ForegroundColor Cyan
$txt = & $Exe query type-usage --in $probe --names 'TUsedInDecl,TNeverUsed' --db $db 2>&1 | Out-String
Check 'text output marks the referenced one' ($txt -match 'TUsedInDecl\s+REFERENCED')
Check 'text output states the name-keyed limitation' ($txt -match 'name-keyed')

& $Exe query type-usage --in $probe --db $db 2>&1 | Out-Null
Check 'missing --names exits 2' ($LASTEXITCODE -eq 2) "exit $LASTEXITCODE"
& $Exe query type-usage --names 'TUsedInDecl' --db $db 2>&1 | Out-Null
Check 'missing --in exits 2' ($LASTEXITCODE -eq 2) "exit $LASTEXITCODE"

# --names-file is the practical form once the list is an RTL surface.
$nf = Join-Path $WorkDir 'names.txt'
Write-Ascii $nf "# comment lines and blanks are skipped`r`n`r`nTUsedInDecl`r`nTNeverUsed`r`n"
$jf = & $Exe query type-usage --in $probe --names-file $nf --db $db --json 2>$null | Out-String
$rf = $null; try { $rf = $jf | ConvertFrom-Json } catch {}
Check '--names-file is read (and # / blank lines skipped)' `
  (($null -ne $rf) -and ($rf.Count -eq 2) -and (($rf | Where-Object { $_.name -eq 'TUsedInDecl' }).referenced -eq $true)) `
  ("rows: {0}" -f $(if ($rf) { $rf.Count } else { 'none' }))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
