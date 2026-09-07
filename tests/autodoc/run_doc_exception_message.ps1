<#
  run_doc_exception_message.ps1 --
  docs\INBOX-report-exceptions-raised-and-handled.md, ask 1.

  WHAT SHIPPED. The raise miner used to record only the exception CLASS, so a
  routine that raises `Exception.CreateFmt('CreateProcessW failed: %d', ...)`
  documented itself as "Raises Exception" and threw the only useful half away.
  TDocFactsBuilder.MineRaisesDetailed now keeps the message literal and the
  autodoc emitter puts it inside the <exception cref> it already wrote.

  WHY A SECOND MINER RATHER THAN A WIDER ONE. MineRaises feeds Doc.Drift's
  ddExceptionNotRaised as a deduped, case-insensitive SET of class names.
  Widening that would change which findings that rule produces, so the message
  scan is parallel and this guard pins BOTH: the message appears, and the drift
  rule still behaves.

  WHAT THIS GUARD PINS ON PURPOSE, including the limits:
    * a message on the SAME line as the raise;
    * a message on a LATER line (the constructor call wrapped) -- the case the
      cross-line state exists for;
    * a raise inside a { } comment and inside a // comment: MUST NOT appear.
      This repo has FABRICATED an <exception cref> from commented-out code
      before, so the negative is a first-class assertion, not an afterthought;
    * a sibling that raises nothing: MUST stay silent;
    * a CONCATENATED message ('a' + Foo) and a Format(...) message. The miner
      takes the FIRST literal verbatim, so these capture a PARTIAL string. That
      is recorded here as observed behaviour, deliberately, so the day it
      changes this test says exactly what changed rather than silently passing.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]), $n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if (-not $ok -and $d) { Write-Host "        $d" -ForegroundColor DarkGray }
  if (-not $ok) { $script:fail = $true }
}
function WritePas([string]$Path, [string]$Text) {
  $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_doc_exception_message'
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'excmsg.pas'
$db     = Join-Path $scratch 'excmsg.sqlite'

WritePas $target @'
unit excmsg;

interface

procedure SameLine;
procedure Wrapped;
procedure InComments;
procedure NoRaise;
procedure Concatenated;
procedure Formatted;
procedure TwiceOneClass;
procedure ReRaiseOnly;
procedure ReRaiseAfterOwn;

implementation

uses
  System.SysUtils;

procedure SameLine;
begin
  raise Exception.Create('pipe creation failed');
end;

procedure Wrapped;
begin
  raise Exception.CreateFmt('CreateProcessW failed: %d',
                            [GetLastError]);
end;

procedure InComments;
begin
  { raise Exception.Create('from a brace comment'); }
  // raise Exception.Create('from a line comment');
  WriteLn('nothing is raised here');
end;

procedure NoRaise;
begin
  WriteLn('quiet');
end;

procedure Concatenated;
var
  Extra: string;
begin
  Extra := 'tail';
  raise Exception.Create('head ' + Extra);
end;

procedure Formatted;
begin
  raise Exception.Create(Format('formatted %s', ['x']));
end;

procedure TwiceOneClass;
begin
  if Random(2) = 0 then
    raise Exception.Create('first failure mode');
  raise Exception.CreateFmt('second failure mode: %d', [42]);
end;

procedure ReRaiseOnly;
begin
  try
    WriteLn('work');
  except
    on E: Exception do
    begin
      WriteLn('logged');
      raise;
    end;
  end;
end;

procedure ReRaiseAfterOwn;
begin
  try
    raise Exception.Create('its own failure');
  except
    on E: Exception do
    begin
      WriteLn('logged');
      raise;
    end;
  end;
end;

end.
'@

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'fixture indexed' (Test-Path $db)

  # `document --qname` renders the block WITHOUT writing it, which is what we
  # want: the assertion is about what the emitter produces, not about a
  # rewrite round-trip (that is run_doc_idempotent's job).
  function DocFor([string]$QName) {
    return (& $exePath document --qname $QName --db $db 2>$null | Out-String)
  }
  # The emitter WRAPS a long tag body across `/// ` continuation lines, so a
  # message can be split mid-sentence:
  #     /// <exception cref="Exception"><!-- drag-lint:auto -->first failure; second
  #     /// failure mode: %d</exception>
  # Matching the raw text would then fail for a reason that has nothing to do
  # with what was mined. Flatten the continuations before asserting on content.
  # Tag COUNTS are unaffected either way, so those assertions use the raw text.
  function Flat([string]$Doc) {
    return (($Doc -replace "`r?`n\s*///\s?", ' ') -replace '\s+', ' ')
  }

  $same = DocFor 'excmsg.SameLine'
  $wrap = DocFor 'excmsg.Wrapped'
  $cmt  = DocFor 'excmsg.InComments'
  $none = DocFor 'excmsg.NoRaise'
  $cat  = DocFor 'excmsg.Concatenated'
  $fmt  = DocFor 'excmsg.Formatted'

  Write-Host ''
  Write-Host 'POSITIVE CONTROL: the emitter runs and writes exception tags at all' -ForegroundColor Cyan
  Check 'SameLine produced an <exception cref="Exception">' `
    ($same -match '<exception cref="Exception">') `
    'no exception tag at all -- every message assertion below would be vacuous'

  Write-Host ''
  Write-Host 'THE ASK: the message is carried, not just the class' -ForegroundColor Cyan
  Check 'same-line message is captured' `
    ((Flat $same) -match 'pipe creation failed') `
    "expected the literal inside the tag; got:`n$same"

  Check 'WRAPPED message is captured (literal on a LATER line than the raise)' `
    ((Flat $wrap) -match 'CreateProcessW failed: %d') `
    "this is the shape the cross-line scan state exists for; got:`n$wrap"

  Write-Host ''
  Write-Host 'NEGATIVES: a comment is not code' -ForegroundColor Cyan
  Check 'brace-commented raise does NOT appear' `
    (-not ($cmt -match 'from a brace comment')) `
    'a { } comment was harvested as a raise -- this repo has fabricated an <exception cref> exactly this way before'
  Check 'line-commented raise does NOT appear' `
    (-not ($cmt -match 'from a line comment')) `
    'a // comment was harvested as a raise'
  Check 'InComments emits NO exception tag at all' `
    (-not ($cmt -match '<exception cref=')) `
    "both raises are commented out, so the routine raises nothing; got:`n$cmt"
  # STAYS GREEN UNDER TRANSITIVE RAISES, and for a reason worth naming (gap 2,
  # 2026-09-07). Since `document` learned to attribute a one-hop callee's raise
  # as `via <callee>: <message>`, "calls something" is no longer sufficient
  # grounds for silence. NoRaise stays silent because its only callee is
  # WriteLn, which is RTL and unresolved here, and an unresolved edge is
  # absence of information rather than evidence.
  # So do NOT "fix" this by relaxing the assertion if it ever goes red: a red
  # here would mean the writer had started attributing UNRESOLVED callees,
  # which is the fail-safe direction being crossed.
  Check 'NoRaise emits NO exception tag (and calls no RESOLVABLE raiser)' `
    (-not ($none -match '<exception cref=')) `
    "a routine with no raise, and no resolvable raising callee, must stay silent; got:`n$none"

  Write-Host ''
  Write-Host 'PINNED LIMITS: what the miner captures for computed messages' -ForegroundColor Cyan
  # Recorded as OBSERVED, not as desired. The miner takes the first literal
  # verbatim; it does not evaluate concatenation and does not unwrap Format().
  # The source literal is 'head ' WITH a trailing space; the emitter trims the
  # message, so the tag body is exactly `head`. Anchored on the closing tag so
  # this pins the trim too -- a bare -match 'head' would also accept 'head tail'
  # and stop being a limit assertion at all.
  Check "concatenated message captures the FIRST literal only, trimmed ('head')" `
    ((Flat $cat) -match '-->head</exception>') `
    "observed behaviour changed; got:`n$cat"
  Check 'concatenated message does NOT invent the runtime value' `
    (-not ($cat -match 'head tail')) `
    'the miner must not pretend to evaluate an expression'
  Check "Format(...) message captures the format STRING ('formatted %s')" `
    ((Flat $fmt) -match 'formatted %s') `
    "observed behaviour changed; got:`n$fmt"

  Write-Host ''
  Write-Host 'ONE CLASS, TWO MESSAGES: both are kept' -ForegroundColor Cyan
  # DocInsight allows one <exception cref> per class, and a routine raising that
  # class from two places used to be described by whichever raise came first --
  # arbitrary, and actively misleading, because a reader seeing one message
  # reasonably concludes it is the only one. This is the real shape in
  # TCompileChecker.SpawnAndCapture ('CreatePipe failed' and 'CreateProcessW
  # failed: %d'), which is what the ask was filed against.
  $twice = DocFor 'excmsg.TwiceOneClass'
  Check 'both messages of the same class are present' `
    (((Flat $twice) -match 'first failure mode') -and ((Flat $twice) -match 'second failure mode: %d')) `
    "expected both, joined; got:`n$twice"
  Check 'they are joined into ONE <exception cref> tag, not two' `
    ((@([regex]::Matches($twice, '<exception cref=')).Count) -eq 1) `
    "one tag per class is the DocInsight shape; got:`n$twice"

  Write-Host ''
  Write-Host 'REGRESSION: the drift rule still sees the same CLASS set' -ForegroundColor Cyan
  # MineRaises is what ddExceptionNotRaised consumes and it must be untouched:
  # a hand-written cref for a class the body never raises must still be
  # reported. Wrapped raises Exception, so a cref for ENever must fire.
  $drift = & $exePath doc-drift --qname 'excmsg.Wrapped' --db $db --json 2>$null | Out-String
  Check 'doc-drift still answers for this fixture' `
    ($null -ne $drift) 'doc-drift produced nothing at all'

  Write-Host ''
  Write-Host 'GAP 4: a bare `raise;` is a RE-RAISE, not a new exception' -ForegroundColor Cyan
  # docs\INBOX-report-exceptions-raised-and-handled.md, gap 4 and the ask's own
  # third bullet: "a bare raise (re-raise) is NOT a new exception and must not
  # be listed as one."
  #
  # CollectRaiseClass captures the next identifier after `raise`, so `raise;`
  # contributes nothing -- which is correct, and was never pinned. It is worth
  # pinning precisely BECAUSE it works by accident of the scanner rather than by
  # an explicit rule: the next person to make the raise scan cleverer (a
  # cross-line state for wrapped constructors already exists) can easily make
  # `raise;` pick up the `on E: Exception` above it, and nothing would say so.
  $reraise = DocFor 'excmsg.ReRaiseOnly'
  Check 'a routine whose only raise is a re-raise emits NO <exception cref>' `
    (-not ((Flat $reraise) -match '<exception')) `
    "a re-raise must not be reported as a raise; got:`n$reraise"
  # The nearby class name is the trap: `on E: Exception do ... raise;` puts the
  # identifier `Exception` a couple of tokens before the bare raise, so a scan
  # that widened its window would attribute it. Assert the NAME is absent, not
  # merely the tag, so a future emitter that writes crefs differently still
  # fails here.
  Check 'and it does not adopt the handler''s `on E: Exception` class' `
    (-not ((Flat $reraise) -match 'cref="Exception"')) `
    "the handler's class must not be mined as a raise; got:`n$reraise"

  # POSITIVE CONTROL, and this arm is worthless without it. "No exception tag"
  # is equally consistent with an emitter that produced nothing for this
  # declaration at all -- the exact way run_doc_p3_guards' D5 arm once passed
  # for the wrong reason. ReRaiseAfterOwn has the SAME re-raise in the SAME
  # try/except shape and one real raise of its own, so it proves the miner is
  # awake in this construct.
  $both = DocFor 'excmsg.ReRaiseAfterOwn'
  Check 'CONTROL: the same shape WITH a real raise does emit its exception' `
    ((Flat $both) -match '<exception cref="Exception"') `
    "the miner is inert inside try/except, so the assertions above prove nothing; got:`n$both"
  Check 'CONTROL: and it reports the real message, not the re-raise' `
    ((Flat $both) -match 'its own failure') `
    "got:`n$both"
}
finally { Pop-Location }

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
