<#
  run_classref_kind.ps1 -- E1 of docs\superpowers\specs\2026-10-26-extract-polymorphic-form-launches.md:
  every `X = class of Y` declaration is symbols.kind = 'classref', signature
  'class of Y', heritage 'Y' (so ResolveAncestry writes ONE ordinal-0
  type_ancestors row naming Y).

  BEFORE: the declaration was a kind='type' row with signature 'class of Y'
  and NULL heritage, indistinguishable by kind from any other alias, so a
  reader asking "is this parameter a class reference" had to parse text.

  WHAT THIS GUARD PINS (fixture tests\fixtures\dispatch-forms)
    CR-UNIT    unit-level  TFormClass = class of TForm   -> classref
    CR-NESTED  TLauncher.TFormClass  (nested type)       -> classref
    CR-NOCLASS zero kind='class' rows named TFormClass
    CR-ANC     each classref has exactly one ordinal-0 type_ancestors row 'TForm'
    NEG-*      EFoo = class(EBar) end; and EBar = class(Exception); stay kind 'class'
               (positive control: a rule that turned EVERY one-line class into
               classref fails here)

  Usage: pwsh -File tests\autotest\run_classref_kind.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}
$exePath = (Resolve-Path $Exe).Path
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot '..\fixtures\dispatch-forms')).Path
$scratch = Join-Path C:\TEMP "draglint_classref_kind_$PID"
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*') $scratch
$db = Join-Path $scratch 'classref.sqlite'

function Sql([string]$Query) {
  $raw = (& $exePath sql --db $db --json --limit 1000 --query $Query 2>$null) -join "`n"
  $b = $raw.IndexOf('{')
  if ($b -lt 0) { throw "sql returned no JSON for: $Query" }
  $o = $raw.Substring($b) | ConvertFrom-Json
  $names = @($o.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($r in @($o.rows)) {
    $h = @{}
    for ($i = 0; $i -lt $names.Count; $i++) { $h[$names[$i]] = $r[$i] }
    $out += $h
  }
  return ,@($out)
}

& $exePath index $scratch --db $db 2>&1 | Out-Null
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

$cr = (Sql "SELECT id, kind, qualified_name AS q, signature AS sig, heritage AS her FROM symbols WHERE name = 'TFormClass' ORDER BY qualified_name")
Check 'two TFormClass declarations indexed' ($cr.Count -eq 2) "rows=$($cr.Count)"
foreach ($p in @(@('CR-UNIT', 'DF.Main.TFormClass'), @('CR-NESTED', 'DF.Main.TLauncher.TFormClass'))) {
  $r = @($cr | Where-Object { $_.q -eq $p[1] })
  $k = if ($r.Count -eq 1) { [string]$r[0].kind } else { "rows=$($r.Count)" }
  Check "$($p[0]) $($p[1]) kind=classref" ($k -eq 'classref') "got=$k"
  if ($r.Count -eq 1) {
    Check "$($p[0]) signature 'class of TForm'" ([string]$r[0].sig -eq 'class of TForm') "got=[$($r[0].sig)]"
    Check "$($p[0]) heritage 'TForm'" ([string]$r[0].her -eq 'TForm') "got=[$($r[0].her)]"
    $anc = (Sql "SELECT ordinal, ancestor_name AS an FROM type_ancestors WHERE symbol_id = $($r[0].id)")
    Check "$($p[0]) CR-ANC one ordinal-0 ancestor TForm" (($anc.Count -eq 1) -and ([int]$anc[0].ordinal -eq 0) -and ($anc[0].an -eq 'TForm')) `
      ("rows=$($anc.Count)" + $(if ($anc.Count) { " first=$($anc[0].an)@$($anc[0].ordinal)" } else { '' }))
  }
}
$cls = (Sql "SELECT id FROM symbols WHERE name = 'TFormClass' AND kind = 'class'")
Check 'CR-NOCLASS zero kind=class rows named TFormClass' ($cls.Count -eq 0) "rows=$($cls.Count)"
foreach ($n in 'EFoo', 'EBar') {
  $r = (Sql "SELECT kind FROM symbols WHERE qualified_name = 'DF.Base.$n'")
  $k = if ($r.Count -eq 1) { [string]$r[0].kind } else { "rows=$($r.Count)" }
  Check "NEG-$n stays kind=class" ($k -eq 'class') "got=$k"
}

if ($script:fail) { Write-Host 'run_classref_kind: FAIL'; exit 1 }
Write-Host 'run_classref_kind: PASS'
exit 0
} catch {
  Write-Host "FATAL: $_"
  exit 2
}
