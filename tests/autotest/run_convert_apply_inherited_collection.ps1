<#
  run_convert_apply_inherited_collection.ps1 -- 1.42 MIG-TYPE (INBOX
  converter-to-engine-migrate-type-and-inherited-headers, Q4): the D5
  inherited-.dfm shapes, pinned in one child unit.

  THE CONTRACT this guard pins (ancestor CvBase already converted):
    * `inherited Q: TOldQuery` is retyped to TNewQuery, the `inherited`
      keyword and the child's own name kept;
    * an order-only entry `inherited F: TOldField [5]` is retyped with its
      `[5]` child position kept;
    * a collection streamed WHOLE in the child (ParamData) is carried, each
      item's members mapped through `#link Params.Items.<X>`
      (DataType -> ParamType), one reemit note says so;
    * a file-scope `#migrate TScreenCursorOld -> TScreenCursorNew` renames the
      child's code in the same run (enum members by name: scoWait -> scnWait).
    * POSITIVE CONTROL / PRECONDITION: with the ancestor NOT converted, both
      inherited entries are skipped (ancestor_state unconverted) and the child
      .dfm is byte-unchanged -- so the retype checks above cannot pass by a
      blind header rewrite.

  Fixtures: tests\autotest\fixtures\inherited_collection, COPIED to a $PID
  scratch folder and indexed there. Nothing shared is touched.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_inherited_collection_$PID"
)
try {
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'fixtures\inherited_collection\*') $WorkDir

function P([string]$n) { return (Join-Path $WorkDir $n) }
function Text([string]$n) { return [IO.File]::ReadAllText((P $n), [Text.Encoding]::ASCII) }
$orig = @{}
foreach ($f in 'CvBase.pas', 'CvBase.dfm', 'CvChild.pas', 'CvChild.dfm') { $orig[$f] = [IO.File]::ReadAllBytes((P $f)) }
function Restore { foreach ($k in $orig.Keys) { [IO.File]::WriteAllBytes((P $k), $orig[$k]) } }

$db = P 'fx.sqlite'
function Reindex { & $Exe index $WorkDir --db $db 2>&1 | Out-Null }
function Apply([string[]]$Extra) {
  $o = (& $Exe @(@('convert-apply', '--unit', (P 'CvChild.pas'), '--rules', (P 'child.rules'), '--db', $db) + $Extra) 2>&1) -join "`n"
  $j = $null
  if ($Extra -contains 'json') { try { $j = $o.Substring($o.IndexOf('{')) | ConvertFrom-Json } catch {} }
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o; J = $j }
}
Reindex
Check 'V the fixture index was built' (Test-Path $db)

# ---- ancestor converted: dry run ------------------------------------------------
$r = Apply @('--format', 'json')
$inh = if ($r.J) { @($r.J.inherited) } else { @() }
Check 'Q1 dry run: exit 0, ok' (($r.Code -eq 0) -and ($null -ne $r.J) -and $r.J.ok) $r.Out
Check 'Q2 ... Q and F retyped (ancestor CvBase, converted)' `
  ((@($inh | Where-Object { $_.ancestor_state -eq 'converted' -and $_.action -eq 'retyped' -and $_.ancestor_unit -eq 'CvBase' }).Count -eq 2) -and
   ((@($r.J.converted) -join '|') -match 'Q: inherited TOldQuery -> TNewQuery') -and ((@($r.J.converted) -join '|') -match 'F: inherited TOldField -> TNewField')) ($inh | ConvertTo-Json -Compress)
Check 'Q3 ... one reemit note: collection ParamData carried, 1 item' `
  (@($r.J.reemit_notes | Where-Object { $_ -match '^Q: collection ParamData carried \(1 item' }).Count -eq 1) (@($r.J.reemit_notes) -join ' | ')

# ---- ancestor converted: --apply ------------------------------------------------
$r = Apply @('--apply', '--no-backup')
$dfm = Text 'CvChild.dfm'
$pas = Text 'CvChild.pas'
Check 'Q4 --apply exits 0' ($r.Code -eq 0) $r.Out
Check 'Q5 root header kept: inherited CvChild: TCvChild' $dfm.StartsWith("inherited CvChild: TCvChild`r`n") $dfm
Check 'Q6 inherited Q retyped, keyword kept: inherited Q: TNewQuery' $dfm.Contains("  inherited Q: TNewQuery`r`n") $dfm
Check 'Q7 order-only entry retyped, [5] kept: inherited F: TNewField [5]' $dfm.Contains("  inherited F: TNewField [5]`r`n") $dfm
Check 'Q8 ParamData item carried: Name kept, DataType -> ParamType' `
  (($dfm -match "ParamData = <\s+item\s+Name = 'A'\s+ParamType = 3\s+end>") -and -not $dfm.Contains('DataType')) $dfm
Check 'Q9 the child F keeps its own Size = 8' ($dfm -match "inherited F: TNewField \[5\]\s+Size = 8\s+end") $dfm
Check 'Q10 file-scope #migrate renamed the child code: C: TScreenCursorNew; C:= scnWait;' `
  ($pas.Contains('  C: TScreenCursorNew;') -and $pas.Contains('  C:= scnWait;') -and -not ($pas -match '\bTScreenCursorOld\b|\bscoWait\b')) $pas

# ---- POSITIVE CONTROL: ancestor NOT converted -> both skipped, .dfm unchanged ---
Restore
[IO.File]::WriteAllText((P 'CvBase.pas'), (Text 'CvBase.pas').Replace('TNewQuery', 'TOldQuery').Replace('TNewField', 'TOldField'), [Text.Encoding]::ASCII)
[IO.File]::WriteAllText((P 'CvBase.dfm'), (Text 'CvBase.dfm').Replace('TNewQuery', 'TOldQuery').Replace('TNewField', 'TOldField'), [Text.Encoding]::ASCII)
Reindex
$r = Apply @('--format', 'json')
$inh = if ($r.J) { @($r.J.inherited) } else { @() }
Check 'C1 CONTROL unconverted ancestor: Q and F skipped, ancestor_state unconverted' `
  ((@($inh | Where-Object { $_.ancestor_state -eq 'unconverted' -and $_.action -eq 'skipped' }).Count -eq 2) -and
   (@($inh | Where-Object { $_.action -eq 'retyped' }).Count -eq 0)) "$($r.Out)"
$r = Apply @('--apply', '--no-backup')
Check 'C2 CONTROL ... --apply leaves the child .dfm byte-unchanged' `
  ([Convert]::ToBase64String([IO.File]::ReadAllBytes((P 'CvChild.dfm'))) -eq [Convert]::ToBase64String($orig['CvChild.dfm'])) (Text 'CvChild.dfm')

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
