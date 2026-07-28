<#
  run_callsite_kind_universe.ps1 -- T3i / register item E1.

  THE INVARIANT. Every consumer that reports an UNRESOLVED call site takes the
  COMPLEMENT of the resolved call_edges, and ResolveCallTargets only ever walks
  kind='call' refs. So the complement is only meaningful inside that same
  universe, and all three sites read ONE declaration for it
  (DRagLint.Core.Model.REF_KIND_CALL / CallSiteRefKindSql):

    writer  TSQLiteSymbolStore.ResolveCallTargets
    reader  TSQLiteSymbolStore.GetAmbiguousCalls          -> `ambiguous-calls`
    reader  TSQLiteSymbolStore.FindUnresolvedNameCallers  -> `document` Called-from

  run_ambiguous_calls.ps1 and run_calledfrom_resolved.ps1 already pin the
  headline symptom (a call resolved CERTAIN to a DIFFERENT same-named method was
  reported as unverified as well). THIS runner pins the rest of the class, which
  neither of them reaches, plus the one shape the fix deliberately gives up:

    1  a PROPERTY read whose name collides with a routine name is not an
       unresolved call site -- for either consumer
    2  a TYPE mention (type_use) is not a caller: a class no longer collects a
       "Called from:" line built from type references, a fact "Used in units:"
       already carries properly
    3  ONE row per unresolved call SITE -- the co-located 'member-access' ref
       every dotted call also emits must not double-count it
    4  AGREEMENT: both consumers classify the SAME site set. Structural sharing
       proves the declarations agree; only behaviour proves the call sites do
    5  DISCLOSED GAP, pinned so it stays visible rather than silent: a
       paren-less dotted invocation in EXPRESSION position (`N:= FProbe.Make;`)
       emits NO 'call' ref, so it is outside the universe and both consumers
       miss it. It was already invisible to every other call-graph surface
       (Calls:, find-callers --resolved, call-path, call-tree) because the
       resolver never walked it either; it leaked into exactly one bucket by
       accident. Kind-blind name discovery still finds it -- asserted here, so
       the loss is bounded to the resolution-quality buckets. Closing it means
       EMITTING a call ref for the shape, i.e. changing what is indexed.

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\callsitekind.pas')).Path

# Fresh scratch dir; keep the unit name so unit-name-matches-file stays quiet.
$scratch = Join-Path C:\TEMP 'draglint_callsite_kind'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target  = Join-Path $scratch 'callsitekind.pas'
$db      = Join-Path $scratch 'ck.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  $idxOut = & $exePath index $scratch --db $db 2>&1 | Out-String
  Check 'index exits 0' ($LASTEXITCODE -eq 0)
  Check 'index reported no parse errors' ($idxOut -match '0 errors')

  # ---------------------------------------------------------------- consumer 1
  # `ambiguous-calls` -- the resolver-coverage diagnostic.
  # POSITIVE CONTROL FIRST (T3i review round 2, folded 6): every EXCLUDES-check
  # below is a negative, and a negative is vacuously green if the command failed,
  # the DB was empty, or the file filter matched nothing. So capture stderr, check
  # the exit code, and require the ONE row we DO expect before trusting absence.
  $acRaw  = & $exePath ambiguous-calls --file $target --json --db $db 2>&1 | Out-String
  $acExit = $LASTEXITCODE
  Check 'ambiguous-calls exits 0' ($acExit -eq 0) $acRaw
  $rows = @($acRaw | ConvertFrom-Json)
  $encl = @($rows | ForEach-Object { $_.enclosing_qname })
  Check 'CONTROL: ambiguous-calls produced the expected positive row (absence below is meaningful)' `
    ($encl -contains 'callsitekind.TDriver.CallsUnknown') $acRaw

  # 3: exactly ONE row, for the ONE genuinely unresolved site. Pre-fix this
  # fixture returned FIVE: the property read, both halves of the untypable call,
  # and the member-access halves of the resolved call and the paren-less call.
  Check 'ambiguous-calls: exactly 1 row for the file (one row per unresolved SITE)' (@($rows).Count -eq 1)
  Check 'ambiguous-calls: the row is CallsUnknown (untypable receiver)' `
    ($encl -contains 'callsitekind.TDriver.CallsUnknown')
  Check 'ambiguous-calls: CallsUnknown counted ONCE, not once per ref kind' `
    (@($encl | Where-Object { $_ -eq 'callsitekind.TDriver.CallsUnknown' }).Count -eq 1)

  # 1: a property read is not a call site, even when its name collides with a
  # routine's (TProbe.Count the property vs callsitekind.Count the function).
  Check 'ambiguous-calls: EXCLUDES ReadsProperty (property read, name collides with a routine)' `
    (-not ($encl -contains 'callsitekind.TDriver.ReadsProperty'))
  Check 'ambiguous-calls: EXCLUDES CallsFire (resolved certain -- no phantom second row)' `
    (-not ($encl -contains 'callsitekind.TDriver.CallsFire'))

  # 5: the disclosed gap, at this consumer.
  Check 'ambiguous-calls: EXCLUDES ParenlessExpr (DISCLOSED: no call ref is emitted for the shape)' `
    (-not ($encl -contains 'callsitekind.TDriver.ParenlessExpr'))

  # ---------------------------------------------------------------- consumer 2
  # `document`'s Called-from. Dry-run: the emitted block is printed, so nothing
  # on disk changes and each qname is inspected independently.
  #
  # POSITIVE CONTROL, T3i review round 2 (folded 6): `document --qname` on a name
  # that does not resolve prints 'symbol not found: X' and exits 1 -- which would
  # make every "no Called from: line" assertion below pass for the WRONG reason.
  # So Doc-Out captures stderr too, asserts exit 0, and asserts the run actually
  # reached the fixture ('File: ...callsitekind.pas'). Only then is absence
  # evidence. The check name carries the qname so a failure names the culprit.
  function Doc-Out([string]$QName) {
    $out  = & $exePath document --qname $QName --db $db 2>&1 | Out-String
    $exit = $LASTEXITCODE
    Check ("CONTROL: document --qname $QName resolved and exited 0") `
      (($exit -eq 0) -and ($out -match 'File:.*callsitekind\.pas')) $out
    return $out
  }
  function CalledFromLine([string]$QName) {
    $out = Doc-Out $QName
    $ln  = ($out -split "`r?`n" | Where-Object { $_ -match 'Called from:' } | Select-Object -First 1)
    if ($null -eq $ln) { return '' } else { return $ln }
  }

  # 4: AGREEMENT -- the site ambiguous-calls reported is exactly the ' ?' entry
  # here, and the site it excluded as resolved is exactly the plain entry.
  $fireLine = CalledFromLine 'callsitekind.TProbe.Fire'
  Check 'Called-from(TProbe.Fire): line present' ($fireLine -ne '')
  Check 'Called-from(TProbe.Fire): CallsFire present and PLAIN (resolved certain)' `
    ($fireLine -match 'callsitekind\.TDriver\.CallsFire \(callsitekind\.pas\)(?! \?)')
  Check 'Called-from(TProbe.Fire): CallsUnknown present WITH trailing ? (untypable receiver)' `
    ($fireLine -match 'callsitekind\.TDriver\.CallsUnknown \(callsitekind\.pas\) \?')
  Check 'AGREEMENT: CallsFire appears ONCE -- not also as an unverified twin' `
    (@([regex]::Matches($fireLine, 'CallsFire')).Count -eq 1)
  Check 'AGREEMENT: CallsUnknown appears ONCE -- not once per ref kind' `
    (@([regex]::Matches($fireLine, 'CallsUnknown')).Count -eq 1)

  # 1: the property read must not become a phantom caller of the like-named
  # unit-level function.
  $countLine = CalledFromLine 'callsitekind.Count'
  Check 'Called-from(Count): no Called-from line at all (its only name-match is a PROPERTY read)' `
    ($countLine -eq '')

  # 2: THE SCOPE BOUNDARY, pinned deliberately, for EVERY non-routine kind.
  # A class, record, enum or alias can never be a call target, so for those this
  # bucket has never held call sites -- it holds plain type_use REFERENCES, which
  # the renderer labels "Called from:". The label is the defect; relabelling it
  # (the planned "Used by:" for types) is owned by the render workstream and
  # tests/autotest/run_doc_no_self_caller.ps1 pins the present content. So the
  # call-sites-only restriction is NOT applied to them.
  #
  # T3i REVIEW ROUND 2 -- WHY THE ENUM AND ALIAS ARE PINNED SEPARATELY. Round 1
  # gated on a literal [skClass, skInterface, skRecord], which is the set the
  # OTHER runner happens to pin, so skEnum and skTypeAlias silently LOST their
  # only reference fact -- and, unlike a class, nothing else carries it for them
  # ("Used in units:" is deliberately class/interface/record only). The boundary
  # had been drawn by test coverage rather than by the semantics. These four
  # checks are what make that impossible to reintroduce unnoticed.
  foreach ($kindCase in @(
      @{ QName = 'callsitekind.TProbe'     ; What = 'CLASS' },
      @{ QName = 'callsitekind.TProbeKind' ; What = 'ENUM'  },
      @{ QName = 'callsitekind.TProbeAlias'; What = 'ALIAS' })) {
    $kOut = Doc-Out $kindCase.QName
    Check ("BOUNDARY: a {0} still lists references under Called from: (never a call target -- owned by the Used by: relabel)" -f $kindCase.What) `
      ($kOut -match 'Called from:') $kOut
  }
  # The class ALSO keeps its own units fact; the enum deliberately does NOT get
  # one (that gate is class/interface/record and must not widen -- see Doc.Facts).
  $probeOut = Doc-Out 'callsitekind.TProbe'
  Check 'BOUNDARY: the class also still gets its proper Used in units: fact' `
    ($probeOut -match 'Used in units:') $probeOut
  $kindOut = Doc-Out 'callsitekind.TProbeKind'
  Check 'BOUNDARY: the enum gets NO Used in units: fact (that gate must not widen as a side effect)' `
    (-not ($kindOut -match 'Used in units:')) $kindOut

  # 5: the disclosed gap, at this consumer -- and the bound on it.
  $makeLine = CalledFromLine 'callsitekind.TProbe.Make'
  Check 'Called-from(TProbe.Make): EXCLUDES ParenlessExpr (DISCLOSED: no call ref for the shape)' `
    ($makeLine -eq '')
  # Line number computed from the fixture rather than hardcoded, so the assertion
  # keeps its teeth when the fixture grows (it did, in round 2) instead of going
  # vacuously false-negative on a stale literal.
  # Comment lines are skipped: the fixture's own header block documents the shape
  # and literally contains 'FProbe.Make', so a naive first-match scan finds the
  # COMMENT and pins the wrong line -- which is exactly what this control caught
  # on its first run.
  $srcLines = [IO.File]::ReadAllLines($target)
  $makeLineNo = 0
  for ($i = 0; $i -lt $srcLines.Count; $i++) {
    if ($srcLines[$i].TrimStart().StartsWith('//')) { continue }
    if ($srcLines[$i] -match 'FProbe\.Make') { $makeLineNo = $i + 1; break }
  }
  Check 'CONTROL: the paren-less call site was located in fixture CODE (not its header comment)' `
    (($makeLineNo -gt 0) -and (-not $srcLines[$makeLineNo - 1].TrimStart().StartsWith('//'))) "line=$makeLineNo"
  $callers  = & $exePath query find-callers --name Make --db $db 2>&1 | Out-String
  $callExit = $LASTEXITCODE
  Check 'query find-callers exits 0' ($callExit -eq 0) $callers
  Check 'BOUND on the disclosed gap: kind-blind `query find-callers --name Make` STILL finds ParenlessExpr' `
    ($callers -match ("callsitekind\.pas:" + $makeLineNo + "\b")) $callers
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
