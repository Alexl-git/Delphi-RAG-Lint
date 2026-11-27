# Guard for the 1.56 tranche-2 scaffold (lane W2FRAME): the stub units and the registration lines the tranche-2
# lanes build on. It reads SOURCE only; the Win64 build is the compile check. Counts (verbs, flags, questions,
# rules) are pinned by docs-sync and by INT, not here. run_v156_frame_guard.ps1 (FRAME-3) keeps the tranche-1 frame.
#
# What it pins:
#   1. every tranche-2 stub unit exists, declares the unit its file name says, and is listed in BOTH
#      drag-lint.dpr and drag-lint.dproj.
#   2. verbs metrics / sbom / happens-before: one dispatch line each in DRagLint.CLI.Run, the verb in the
#      self-parsing list of ParseArgs, the verb unit in the uses clause, and the Run<X>Verb function the line calls.
#   3. flags --changed-since and --place: the ParseArgs arm and the TArgs field it fills.
#   4. lint-all --changed-since: the two calls from DoLintAll into DRagLint.CLI.ChangedSince, and both functions.
#   5. the six chart questions: a V156_QUESTIONS row each in DRagLint.Charts.Question, read by QuestionIds,
#      QuestionPhrase and QuestionVocab through LiveV156Row; each Q unit names its id.
#   6. POSITIVE CONTROL (-NoSelfTest skips it): the same checks run on a deliberately broken copy in the temp
#      folder, one break per kind of registration, and every break must be reported; a guard that cannot fail
#      proves nothing.
# A lane that fills its stub keeps this guard GREEN: the checks read only what the W2FRAME call sites depend on.
# When INT drops a cut lane's verb (dispatch line removed), it removes that verb from $verbs here in the same commit.
param(
  [string]$Repo = "",
  [switch]$NoSelfTest
)
$ErrorActionPreference = "Stop"
$repoRoot = if ($Repo -ne "") { (Resolve-Path $Repo).Path } else { (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path }

# unit files relative to src\ ; the dpr / dproj form is ..\<rel> (cli units: the bare file name)
$srcUnits = @()
foreach ($n in 'PlaceRows','Regions','Metrics','Vcs','HappensBefore.Verb') { $srcUnits += "query\DRagLint.Query.$n.pas" }
foreach ($n in 'CycloneDx','MapFile') { $srcUnits += "report\DRagLint.Report.$n.pas" }
foreach ($n in 'Lineage','DfmReadDerived') { $srcUnits += "sql\DRagLint.FieldRepo.$n.pas" }
$srcUnits += 'charts\DRagLint.Charts.Adapter.Grid.pas'
# chart question id -> Q unit
$questions = [ordered]@{
  'class-diagram' = 'ClassDiagram'; 'sequence' = 'Sequence'; 'control-flow' = 'ControlFlow'
  'sent-not-handled' = 'SentNotHandled'; 'dependency-matrix' = 'DepMatrix'; 'main-sequence' = 'MainSequence'
}
foreach ($q in $questions.Values) { $srcUnits += "charts\DRagLint.Charts.Q.$q.pas" }
# verb -> CLI unit suffix (the function is Run<suffix>Verb)
$verbs = [ordered]@{ 'metrics' = 'Metrics'; 'sbom' = 'Sbom'; 'happens-before' = 'HappensBefore' }
$cliUnits = @($verbs.Values) + 'ChangedSince'
# flag -> TArgs field
$flags = [ordered]@{ '--changed-since' = 'ChangedSince'; '--place' = 'Place' }

# Returns the list of problems found under $root (empty = the scaffold holds).
function Get-W2FrameProblems([string]$root) {
  $p = New-Object System.Collections.Generic.List[string]
  function Src($rel) { [IO.File]::ReadAllText((Join-Path $root $rel)) }
  $dpr = Src 'src\cli\drag-lint.dpr'
  $dproj = Src 'src\cli\drag-lint.dproj'
  # 1. units
  $all = @($srcUnits | ForEach-Object { @{ Rel = "src\$_"; Proj = "..\$_" } }) +
         @($cliUnits | ForEach-Object { @{ Rel = "src\cli\DRagLint.CLI.$_.pas"; Proj = "DRagLint.CLI.$_.pas" } })
  foreach ($u in $all) {
    $f = Join-Path $root $u.Rel
    $name = [IO.Path]::GetFileNameWithoutExtension($u.Rel)
    if (-not (Test-Path $f)) { $p.Add("file:$name") }
    elseif ([IO.File]::ReadAllText($f) -notmatch "(?m)^unit\s+$([regex]::Escape($name))\s*;") { $p.Add("unit-name:$name") }
    if (-not $dpr.Contains("$name in '$($u.Proj)'")) { $p.Add("dpr:$name") }
    if (-not $dproj.Contains("Include=""$($u.Proj)""")) { $p.Add("dproj:$name") }
  }
  # 2. verbs
  $cli = Src 'src\cli\DRagLint.CLI.pas'
  $selfParsing = [regex]::Match($cli, "(?s)var SelfParsing:= MatchStr\(Result\.Command, \[(.*?)\]\);")
  if (-not $selfParsing.Success) { $p.Add('cli-selfparsing-list') }
  foreach ($v in $verbs.Keys) {
    $fn = "Run$($verbs[$v])Verb"
    $hits = [regex]::Matches($cli, "(?m)^[^\r\n]*Args\.Command = '$([regex]::Escape($v))'[^\r\n]*Result:= $fn\b")
    if ($hits.Count -ne 1) { $p.Add("cli-dispatch:$v x$($hits.Count)") }
    if ($selfParsing.Success -and -not $selfParsing.Groups[1].Value.Contains("'$v'")) { $p.Add("cli-selfparsing:$v") }
    if ($cli -notmatch "(?m)^\s*,\s*DRagLint\.CLI\.$($verbs[$v])\b") { $p.Add("cli-uses:$($verbs[$v])") }
    $unit = Join-Path $root "src\cli\DRagLint.CLI.$($verbs[$v]).pas"
    if ((Test-Path $unit) -and ([IO.File]::ReadAllText($unit) -notmatch "(?m)^function\s+$fn\s*:\s*Integer\s*;")) { $p.Add("verb-function:$fn") }
  }
  # 3. flags
  $common = Src 'src\cli\DRagLint.CLI.Common.pas'
  foreach ($f in $flags.Keys) {
    $field = $flags[$f]
    if ($cli -notmatch "\(A = '$([regex]::Escape($f))'\) and \(i < ParamCount\) then\s+begin\s+Inc\(i\);\s+Result\.$field\s*:=\s*ParamStr\(i\);") { $p.Add("cli-flag-arm:$f") }
    if ($common -notmatch "(?m)^\s+$field\s*:\s*string\s*;") { $p.Add("targs-field:$field") }
  }
  # 4. lint-all --changed-since
  if ($cli -notmatch "(?m)^\s*,\s*DRagLint\.CLI\.ChangedSince\b") { $p.Add('cli-uses:ChangedSince') }
  $lintAll = [regex]::Match($cli, "(?ms)^function DoLintAll\(const AArgs: TArgs\): Integer;.*?^end; // function")
  if (-not $lintAll.Success) { $p.Add('cli-dolintall-span') }
  else {
    if (-not $lintAll.Value.Contains('if not CheckChangedSince(SinceRequest, SinceRefusal) then')) { $p.Add('lintall-call:CheckChangedSince') }
    if (-not $lintAll.Value.Contains('if not KeepFindingsChangedSince(SinceRequest, Findings, SinceMessage) then')) { $p.Add('lintall-call:KeepFindingsChangedSince') }
  }
  $since = Join-Path $root 'src\cli\DRagLint.CLI.ChangedSince.pas'
  if (Test-Path $since) {
    $st = [IO.File]::ReadAllText($since)
    if ($st -notmatch "(?m)^function CheckChangedSince\(const pRequest: TChangedSinceRequest; out pRefusal: string\): Boolean;") { $p.Add('since-function:CheckChangedSince') }
    if ($st -notmatch "(?ms)^function KeepFindingsChangedSince\(const pRequest: TChangedSinceRequest; var pFindings: TArray<TLintFinding>;\s+out pMessage: string\): Boolean;") { $p.Add('since-function:KeepFindingsChangedSince') }
  }
  # 5. chart questions
  $question = Src 'src\charts\DRagLint.Charts.Question.pas'
  $table = [regex]::Match($question, "(?s)V156_QUESTIONS: array\[0\.\.(\d+)\] of array\[V156_ID\.\.V156_RIGHT\] of string = \((.*?)\)\);")
  if (-not $table.Success) { $p.Add('question-table') }
  foreach ($id in $questions.Keys) {
    if ($table.Success -and $table.Groups[2].Value -notmatch "\('$([regex]::Escape($id))', '[^']+\.\.\.', '[^']+', '[^']+'") { $p.Add("question-row:$id") }
    $qf = Join-Path $root "src\charts\DRagLint.Charts.Q.$($questions[$id]).pas"
    if ((Test-Path $qf) -and -not [IO.File]::ReadAllText($qf).Contains("'$id'")) { $p.Add("question-unit-id:$id") }
  }
  foreach ($fn in 'QuestionPhrase','QuestionIds','QuestionVocab') {
    $body = [regex]::Match($question, "(?ms)^function $fn\b[^\r\n]*\r?\nbegin.*?^end;")
    if (-not ($body.Success -and $body.Value.Contains('LiveV156Row('))) { $p.Add("question-reader:$fn") }
  }
  return ,$p
}

$fail = 0
function Assert($name, $cond) {
  if ($cond) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ }
}

$real = Get-W2FrameProblems $repoRoot
Assert "the tranche-2 scaffold holds: $($srcUnits.Count + $cliUnits.Count) units in dpr + dproj, $($verbs.Count) verbs, $($flags.Count) flags, 2 lint-all calls, $($questions.Count) chart questions ($($real -join ', '))" ($real.Count -eq 0)

if (-not $NoSelfTest) {
  # 6. positive control on a broken copy
  $work = Join-Path ([IO.Path]::GetTempPath()) ("dl-v156-w2frame-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
  try {
    function Fresh-Copy {
      if (Test-Path $work) { [IO.Directory]::Delete($work, $true) }
      $rels = @('src\cli\drag-lint.dpr','src\cli\drag-lint.dproj','src\cli\DRagLint.CLI.pas','src\cli\DRagLint.CLI.Common.pas',
        'src\charts\DRagLint.Charts.Question.pas') + ($cliUnits | ForEach-Object { "src\cli\DRagLint.CLI.$_.pas" }) + ($srcUnits | ForEach-Object { "src\$_" })
      foreach ($r in $rels) {
        $s = Join-Path $repoRoot $r
        if (-not (Test-Path $s)) { continue }
        $d = Join-Path $work $r
        [void](New-Item -ItemType Directory -Force -Path (Split-Path $d))
        [IO.File]::Copy($s, $d, $true)
      }
    }
    function Edit-Copy($rel, [scriptblock]$fn) {
      $f = Join-Path $work $rel
      $t = [IO.File]::ReadAllText($f)
      $n = & $fn $t
      if ($n -ceq $t) { throw "positive control: the edit of $rel changed nothing" }
      [IO.File]::WriteAllText($f, $n, [Text.Encoding]::ASCII)
    }
    function Drop-Lines($rel, [string]$pattern) {
      Edit-Copy $rel { param($t) ($t -split "`r?`n" | Where-Object { $_ -notmatch $pattern }) -join "`r`n" }.GetNewClosure()
    }
    $cliRel = 'src\cli\DRagLint.CLI.pas'
    $qRel = 'src\charts\DRagLint.Charts.Question.pas'
    Fresh-Copy
    Assert 'control: the unbroken copy passes' ((Get-W2FrameProblems $work).Count -eq 0)
    # break name -> @(the break, the problem it must produce)
    $breaks = [ordered]@{
      'one dproj entry removed'            = @({ Drop-Lines 'src\cli\drag-lint.dproj' 'DRagLint\.Query\.Vcs\.pas' }, 'dproj:DRagLint.Query.Vcs')
      'one dpr entry removed'              = @({ Drop-Lines 'src\cli\drag-lint.dpr' 'DRagLint\.CLI\.Sbom\b' }, 'dpr:DRagLint.CLI.Sbom')
      'one stub file deleted'              = @({ [IO.File]::Delete((Join-Path $work 'src\sql\DRagLint.FieldRepo.Lineage.pas')) }, 'file:DRagLint.FieldRepo.Lineage')
      'one stub renamed inside'            = @({ Edit-Copy 'src\charts\DRagLint.Charts.Q.Sequence.pas' { param($t) $t -replace '(?m)^unit\s+DRagLint\.Charts\.Q\.Sequence', 'unit DRagLint.Charts.Q.SequenceX' } }, 'unit-name:DRagLint.Charts.Q.Sequence')
      'one verb dispatch line removed'     = @({ Drop-Lines $cliRel "Args\.Command = 'metrics'" }, 'cli-dispatch:metrics x0')
      'one verb out of the self-parsing list' = @({ Edit-Copy $cliRel { param($t) $t.Replace("'metrics', 'sbom', 'happens-before'", "'metrics', 'happens-before'") } }, 'cli-selfparsing:sbom')
      'one verb unit out of the uses clause' = @({ Drop-Lines $cliRel '^\s*,\s*DRagLint\.CLI\.HappensBefore\b' }, 'cli-uses:HappensBefore')
      'one verb function renamed'          = @({ Edit-Copy 'src\cli\DRagLint.CLI.Metrics.pas' { param($t) $t.Replace('function RunMetricsVerb: Integer;', 'function RunMetricsVerbX: Integer;') } }, 'verb-function:RunMetricsVerb')
      'the --changed-since arm removed'    = @({ Edit-Copy $cliRel { param($t) $t.Replace("(A = '--changed-since')", "(A = '--changed-sinceX')") } }, 'cli-flag-arm:--changed-since')
      'the --place arm fills nothing'      = @({ Edit-Copy $cliRel { param($t) $t.Replace('Result.Place:= ParamStr(i);', '') } }, 'cli-flag-arm:--place')
      'one TArgs field removed'            = @({ Drop-Lines 'src\cli\DRagLint.CLI.Common.pas' '^\s+ChangedSince\s*:\s*string' }, 'targs-field:ChangedSince')
      'the lint-all pre-check call removed' = @({ Edit-Copy $cliRel { param($t) $t.Replace('if not CheckChangedSince(SinceRequest, SinceRefusal) then', 'if False then') } }, 'lintall-call:CheckChangedSince')
      'the lint-all filter call removed'   = @({ Edit-Copy $cliRel { param($t) $t.Replace('if not KeepFindingsChangedSince(SinceRequest, Findings, SinceMessage) then', 'if False then') } }, 'lintall-call:KeepFindingsChangedSince')
      'one chart question row removed'     = @({ Drop-Lines $qRel "^\s+\('control-flow'," }, 'question-row:control-flow')
      'QuestionIds no longer reads the rows' = @({ Edit-Copy $qRel { param($t) $t.Replace('if LiveV156Row(V156_QUESTIONS[K, V156_ID]) <> NO_ROW then', 'if False then') } }, 'question-reader:QuestionIds')
    }
    foreach ($k in $breaks.Keys) {
      Fresh-Copy
      & $breaks[$k][0]
      $pr = Get-W2FrameProblems $work
      Assert "control: '$k' makes the guard FAIL with $($breaks[$k][1]) ($($pr -join ', '))" ($pr -contains $breaks[$k][1])
    }
  } finally { if (Test-Path $work) { [IO.Directory]::Delete($work, $true) } }
}

if ($fail -gt 0) { Write-Host "run_v156_w2frame_guard: $fail FAILED" -ForegroundColor Red; exit 1 }
Write-Host "run_v156_w2frame_guard: all passed"
exit 0
