# Wave v151 lane DFMA: the form rules that read more than one file.
#
# What it pins (fixtures under tests\autotest\fixtures\v151-DFMA):
#   inherit\  inherited-form-handler-without-inherited: TChildForm -> TMidForm (inherited
#             form file, no handlers) -> TBaseForm (assigns btnSaveClick / btnHelpClick /
#             FormShow). Only btnSaveClick (no inherited) fires; the chain is walked through
#             the middle form.
#   proj\     ProjForms.dpr creates MainForm, dmMain, ReportForm in that order.
#             form-access-before-create: FormCreate of MainForm reads dmMain (created later);
#             the guarded ReportForm read stays silent.
#             form-autocreate-and-manual: ShowReport assigns ReportForm := TReportForm.Create;
#             the Assigned-guarded ShowReportOnce stays silent.
#             foreign-form-control-access (OFF by default): ReportForm.edtTitle fires,
#             ReportForm.Caption (not a field) and a local of the form type do not.
#             unit-missing-from-uses, form-file side: UOrphan.dfm references dmMain.qryItems
#             and UOrphan does not use UDm; UMain.dfm does the same but uses UDm.
# Each case runs twice: `lint <file>` with no index (the same-folder fallback) and
# `lint-all` over a private index of the fixture folder (the index path).
# Positive control: `--disable <id>` (or, for the OFF rule, no --enable) removes the finding.
param(
  [string]$Exe = "third_party\dll-win64\drag-lint.exe"
)
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
[Environment]::CurrentDirectory = $repo
$exe = (Resolve-Path $Exe).Path
$fx = Join-Path $repo 'tests\autotest\fixtures\v151-DFMA'
$fail = 0
function Assert($name, $cond) {
  if ($cond) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ }
}

function Get-Findings([string[]]$ArgList) {
  $raw = & $exe @ArgList 2>$null
  $text = ($raw -join "`n").Trim()
  if ($text -eq '') { return @() }
  try { $j = $text | ConvertFrom-Json } catch { return @() }
  if ($null -eq $j) { return @() }
  return @($j)
}

function Has($findings, [string]$rule, [int]$line, [string]$fileEnd) {
  return @($findings | Where-Object { $_.rule -eq $rule -and [int]$_.start_line -eq $line -and ([string]$_.file_path).EndsWith($fileEnd, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
}
function CountOf($findings, [string]$rule) {
  return @($findings | Where-Object { $_.rule -eq $rule }).Count
}

$ON_FOREIGN = @('--enable', 'foreign-form-control-access')

# ---- 1. lint, no index ----
$child = Join-Path $fx 'inherit\UChildForm.pas'
$f = Get-Findings @('lint', $child, '--json')
# positive-control: inherited-form-handler-without-inherited
Assert "lint: inherited-form-handler-without-inherited at UChildForm.pas:21" (Has $f 'inherited-form-handler-without-inherited' 21 'UChildForm.pas')
Assert "lint: only that handler fires (got $(CountOf $f 'inherited-form-handler-without-inherited'))" ((CountOf $f 'inherited-form-handler-without-inherited') -eq 1)
$f = Get-Findings @('lint', $child, '--json', '--disable', 'inherited-form-handler-without-inherited')
Assert "control: --disable removes it" (-not (Has $f 'inherited-form-handler-without-inherited' 21 'UChildForm.pas'))

$main = Join-Path $fx 'proj\UMain.pas'
$f = Get-Findings (@('lint', $main, '--json') + $ON_FOREIGN)
# positive-control: form-access-before-create
Assert "lint: form-access-before-create at UMain.pas:30" (Has $f 'form-access-before-create' 30 'UMain.pas')
Assert "lint: one form-access-before-create (got $(CountOf $f 'form-access-before-create'))" ((CountOf $f 'form-access-before-create') -eq 1)
# positive-control: form-autocreate-and-manual
Assert "lint: form-autocreate-and-manual at UMain.pas:37" (Has $f 'form-autocreate-and-manual' 37 'UMain.pas')
Assert "lint: one form-autocreate-and-manual (got $(CountOf $f 'form-autocreate-and-manual'))" ((CountOf $f 'form-autocreate-and-manual') -eq 1)
# positive-control: foreign-form-control-access
Assert "lint: foreign-form-control-access at UMain.pas:52" (Has $f 'foreign-form-control-access' 52 'UMain.pas')
Assert "lint: one foreign-form-control-access (got $(CountOf $f 'foreign-form-control-access'))" ((CountOf $f 'foreign-form-control-access') -eq 1)
Assert "lint: UMain.dfm reference to dmMain is covered by uses UDm" (@($f | Where-Object { $_.rule -eq 'unit-missing-from-uses' -and ([string]$_.file_path).EndsWith('UMain.dfm') }).Count -eq 0)
$f = Get-Findings @('lint', $main, '--json', '--disable', 'form-access-before-create,form-autocreate-and-manual')
Assert "control: --disable removes form-access-before-create" (-not (Has $f 'form-access-before-create' 30 'UMain.pas'))
Assert "control: --disable removes form-autocreate-and-manual" (-not (Has $f 'form-autocreate-and-manual' 37 'UMain.pas'))
# 1.52 DEFAULTS (2235e5a17) turned foreign-form-control-access ON by default: the run without $ON_FOREIGN reports it too.
Assert "default: foreign-form-control-access is ON by default (1.52 DEFAULTS)" ((CountOf $f 'foreign-form-control-access') -eq 1)
$f = Get-Findings @('lint', $main, '--json', '--disable', 'foreign-form-control-access')
Assert "control: --disable removes foreign-form-control-access" ((CountOf $f 'foreign-form-control-access') -eq 0)

$orphan = Join-Path $fx 'proj\UOrphan.pas'
$f = Get-Findings @('lint', $orphan, '--json')
Assert "lint: unit-missing-from-uses at UOrphan.dfm:7" (Has $f 'unit-missing-from-uses' 7 'UOrphan.dfm')
$f = Get-Findings @('lint', $orphan, '--json', '--disable', 'unit-missing-from-uses')
Assert "control: --disable removes it" (-not (Has $f 'unit-missing-from-uses' 7 'UOrphan.dfm'))

# ---- 2. lint-all over a private index ----
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("dl-v151-dfma-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  foreach ($sub in 'inherit', 'proj') {
    $db = Join-Path $tmp "$sub.sqlite"
    & $exe index (Join-Path $fx $sub) --db $db *> (Join-Path $tmp "$sub-index.log")
    Assert "index $sub exit 0" ($LASTEXITCODE -eq 0)
  }
  $f = Get-Findings @('lint-all', '--db', (Join-Path $tmp 'inherit.sqlite'), '--json')
  Assert "lint-all: inherited-form-handler-without-inherited at UChildForm.pas:21" (Has $f 'inherited-form-handler-without-inherited' 21 'UChildForm.pas')
  Assert "lint-all: only that handler fires (got $(CountOf $f 'inherited-form-handler-without-inherited'))" ((CountOf $f 'inherited-form-handler-without-inherited') -eq 1)
  $f = Get-Findings (@('lint-all', '--db', (Join-Path $tmp 'proj.sqlite'), '--json') + $ON_FOREIGN)
  Assert "lint-all: form-access-before-create at UMain.pas:30" (Has $f 'form-access-before-create' 30 'UMain.pas')
  Assert "lint-all: form-autocreate-and-manual at UMain.pas:37" (Has $f 'form-autocreate-and-manual' 37 'UMain.pas')
  Assert "lint-all: foreign-form-control-access at UMain.pas:52" (Has $f 'foreign-form-control-access' 52 'UMain.pas')
  Assert "lint-all: unit-missing-from-uses at UOrphan.dfm:7" (Has $f 'unit-missing-from-uses' 7 'UOrphan.dfm')
  $n1 = CountOf $f 'form-access-before-create'
  $n2 = CountOf $f 'form-autocreate-and-manual'
  $n3 = CountOf $f 'foreign-form-control-access'
  Assert "lint-all: counts 1/1/1 (got $n1/$n2/$n3)" (($n1 -eq 1) -and ($n2 -eq 1) -and ($n3 -eq 1))
}
finally {
  [IO.Directory]::Delete($tmp, $true)
}

if ($fail -gt 0) { Write-Host "$fail check(s) FAILED" -ForegroundColor Red; exit 1 }
Write-Host "all checks passed"
exit 0
