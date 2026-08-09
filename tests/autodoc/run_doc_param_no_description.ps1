<#
  run_doc_param_no_description.ps1 -- a <param> tag that is PRESENT but has an
  EMPTY body is reported as a `hint`.

  WHY THIS EXISTS (user ruling, 2026-08-07)
  ---------------------------------------------------------------------------
  Ruling D-3 says an automatic generator supplies STRUCTURE, not invented
  meaning: since PHASE A3 `document` emits a <param> for every signature
  parameter, and fills the body only where the source carried a comment beside
  that parameter. So the ordinary generated result is

      /// <param name="APath"><!-- drag-lint:auto -->the folder to scan</param>
      /// <param name="AFlag"><!-- drag-lint:auto --></param>

  and until now nothing said anything about AFlag. PHASE A4 deliberately made a
  PRESENT tag satisfy doc-drift whether or not it had a body, and left the
  question of the empty body open because answering it adds findings to every
  consumer's run. The user chose: report it, as a `hint`, ON by default. The
  volume was put to them explicitly first -- inline param comments are rare, so
  this is roughly one hint per undocumented parameter across a codebase.

  IT IS ITS OWN RULE, NOT doc-drift. doc-drift is a `warning` and means "the doc
  and the code moved APART". An empty body is not drift -- nothing moved; the
  description was never written. Folding it into doc-drift would have made every
  freshly generated file look like it had regressed.

  AND IT IS NOT GATED ON HUMAN AUTHORSHIP, which is the one place this rule
  deliberately parts company with doc-drift's ddParamMissing. That gate exists so
  the tool does not grade its own output; here, grading its own output is the
  entire point -- the engine wrote an empty body precisely because it had nothing
  to say, and the to-do is for a human. Gating it would have silenced the rule on
  exactly the files it is meant to annotate.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-param-nodesc"
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

$src = @'
unit paramnodesc;

interface

{ APath carries a comment beside it, so the engine can fill its body.
  AFlag carries nothing, so its tag is written with an EMPTY body. }
function Scan(const APath { the folder to scan }: string; AFlag: Boolean): Boolean;

{ no parameters at all -- must never produce a <param> finding of any kind }
function NoParamsAtAll: Boolean;

implementation

function Scan(const APath { the folder to scan }: string; AFlag: Boolean): Boolean;
begin
  result:= AFlag and (APath <> '');
end;

function NoParamsAtAll: Boolean;
begin
  result:= True;
end;

end.
'@ -replace "`r`n", "`n" -replace "`n", "`r`n"
$pas = Join-Path $WorkDir 'paramnodesc.pas'
[System.IO.File]::WriteAllText($pas, $src, [System.Text.Encoding]::ASCII)

$db = Join-Path $WorkDir 'p.sqlite'
& $Exe index $WorkDir --db $db --quiet 2>&1 | Out-Null
& $Exe document --qname paramnodesc.Scan --db $db --apply --no-backup 2>&1 | Out-Null
& $Exe index $WorkDir --db $db --quiet 2>&1 | Out-Null

$doc = [System.IO.File]::ReadAllText($pas)
Write-Host 'The generated block' -ForegroundColor Cyan
Check 'APath got a body harvested from its inline comment' ($doc -match 'name="APath">.*the folder to scan')
# USER RULING 2026-08-09: "Autodocument has to produce the param section ...
# Warnings and errors is what Linter produces." <param> is STRUCTURAL, so the tag
# is written for every signature parameter whether or not the source describes it
# (ruling D-3 stands); what changed is that the linter now says so at WARNING.
Check 'AFlag got a tag with an EMPTY body (structure is not meaning)' `
  ($doc -match 'name="AFlag"><!-- drag-lint:auto --></param>')

$raw  = & $Exe lint-all --db $db --json 2>$null
$find = @()
try { $find = ($raw -join "`n" | ConvertFrom-Json) } catch { $find = @() }
if ($null -eq $find) { $find = @() }
$nd = @($find | Where-Object { $_.rule -eq 'doc-param-no-description' })

Write-Host ''
Write-Host 'doc-param-no-description' -ForegroundColor Cyan
Check 'it fires for the param with no description' (@($nd | Where-Object { $_.message -match 'AFlag' }).Count -ge 1) `
  "(got $($nd.Count) finding(s) of this rule)"
Check 'it does NOT fire for the param that has one'  (@($nd | Where-Object { $_.message -match 'APath' }).Count -eq 0)
# RAISED from hint to warning by the 2026-08-09 ruling: "If method has params and
# they are not documented it should be reported as warning."
Check 'its severity is warning' (($nd.Count -gt 0) -and (@($nd | Where-Object { $_.severity -ne 'warning' }).Count -eq 0)) `
  "(severities: $((@($nd | ForEach-Object { $_.severity }) | Sort-Object -Unique) -join ','))"
Check 'a routine with no parameters produces none of these' `
  (@($nd | Where-Object { $_.message -match 'NoParamsAtAll' }).Count -eq 0)
Check 'it is NOT reported as doc-drift' `
  (@($find | Where-Object { $_.rule -eq 'doc-drift' -and $_.message -match 'no description' }).Count -eq 0) `
  'doc-drift is a warning and means the doc and the code moved apart'

Write-Host ''
Write-Host 'Rule catalogue' -ForegroundColor Cyan
$cat = (& $Exe rules --json 2>$null) -join "`n"
Check 'the rule is in the catalogue' ($cat -match 'doc-param-no-description')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
