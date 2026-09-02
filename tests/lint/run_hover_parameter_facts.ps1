<#
  run_hover_parameter_facts.ps1 -- hovering a PARAMETER must describe that
  parameter, not the routine it belongs to.

  TWO DEFECTS, ONE CAUSE (measured on DataCopy, 2026-09-01)

    hover TransferFile         -> params carry modifier "const" / "out"
    hover TransferFile.AFile   -> signature "string"      (modifier DROPPED)
                                  summary = the ROUTINE's summary, verbatim

    An skParam symbol stores only its declared TYPE -- EmitRoutineParams
    excludes the modifier tokens deliberately, because they are siblings of the
    type field rather than part of it -- and its doc lookup resolves to the
    OWNING routine's block. So the engine knew the modifier and never showed it,
    and both AFile and AMess described something else.

    Fixed by COMPOSITION from the parent at hover time: no new index field, no
    extractor bump, no reindex.

  THE TRAP INSIDE THE FIX
    GetSymbolDoc fills ParamsJsonRaw and leaves the parsed Params array EMPTY
    (its own comment: "v0.16 renderers read these directly; v0.17 may parse").
    Reading .Params returned nothing and looked exactly like "this routine
    documents no parameters" -- a silent wrong answer. The assertion on the
    <param> text below is what catches that coming back.

  POSITIVE CONTROL
    The ROUTINE's own hover must be unchanged -- it is the thing the parameter
    hover was wrongly copying, so if it broke, these assertions could pass for
    the wrong reason.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  # NOTE: not $Db -- CmdletBinding reserves that as an alias of -Debug.
  [string]$Database = "$PSScriptRoot\..\..\src\cli\_D-RAG\drag-lint.sqlite"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $Database))  { Write-Host "FATAL: self-index not found: $Database" -ForegroundColor Red; exit 2 }

function Hover($qname) {
  # -Width, and slice from the first '{' to the last '}'. Out-String wraps at
  # the CONSOLE width by default, which split the JSON across lines; a filter
  # that kept only lines starting with '{' then silently dropped the
  # continuations and handed ConvertFrom-Json a truncated object. That failed as
  # "no model returned", which reads like an engine defect and is not one.
  $raw = (& $Exe hover --qname $qname --db $Database --format json 2>&1 | Out-String -Width 100000)
  $a = $raw.IndexOf('{'); $b = $raw.LastIndexOf('}')
  if (($a -lt 0) -or ($b -le $a)) { return $null }
  try { return $raw.Substring($a, $b - $a + 1) | ConvertFrom-Json } catch { return $null }
}

# The subject is drag-lint's OWN source, so the fixture cannot drift away from
# the repo: TReviewMarkers.Parse documents its parameter.
# NOTE: PowerShell variables are CASE-INSENSITIVE. This was $P while the
# parameter-hover result was $p -- the same variable -- so the second Hover call
# received a parsed object instead of a qname and returned $null, which read as
# an engine defect.
$Routine = 'DRagLint.Lint.ReviewMarker.TReviewMarkers.Parse'

Write-Host 'A PARAMETER describes ITSELF' -ForegroundColor Cyan
$par = Hover "$Routine.ALineText"
Check 'parameter hover returns a model' ([bool]$par)
if ($par) {
  Check 'kind is parameter' ($par.kind -eq 'parameter') $par.kind
  # The whole point: the modifier the routine hover already knew.
  Check 'signature carries the const modifier' ($par.signature -eq 'const ALineText: string') $par.signature
  # The ParamsJsonRaw trap: an empty summary here means the <param> text was
  # not found, which is indistinguishable from "undocumented" without this.
  Check 'summary is the <param> text' ($par.summary -like 'One source line*') $par.summary
}

Write-Host 'It does NOT borrow the routine''s words' -ForegroundColor Cyan
$r = Hover $Routine
Check 'routine hover returns a model' ([bool]$r)
if ($par -and $r) {
  Check 'the routine has a summary of its own' ([bool]$r.summary) $r.summary
  Check 'the parameter summary is NOT the routine summary' ($par.summary -ne $r.summary)
}

Write-Host 'POSITIVE CONTROL -- the routine hover is unchanged' -ForegroundColor Cyan
if ($r) {
  Check 'routine kind is a method'        ($r.kind -in @('method','function','procedure')) $r.kind
  Check 'routine signature is the full one' ($r.signature -like '*ALineText*') $r.signature
  Check 'routine still lists its params'  ($r.params.Count -ge 1) ("count=" + $r.params.Count)
}

if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
