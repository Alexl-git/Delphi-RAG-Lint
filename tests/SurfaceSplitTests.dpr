program SurfaceSplitTests;
{$APPTYPE CONSOLE}
{ Does an edit land in the half of the unit that dependents can SEE?

  WHAT THIS PINS. The fan-out (PLAN-lint-tree P2/P3) must fire on an interface
  edit and stay silent on an implementation edit. LiveDiagnostics hashes the
  whole buffer, so the two are indistinguishable to it; DragLint.Plugin.
  SurfaceSplit is the unit that tells them apart, and TFanOutGate is the launch
  decision built on top.

  THE ASYMMETRY IS THE WHOLE TEST. Over-firing costs one BELOW_NORMAL engine
  run that the engine then short-circuits. Under-firing means an interface edit
  reaches no dependent and nobody is told -- the exact silence this feature
  exists to break. So the positive controls (an interface edit fires) and the
  negative controls (an implementation edit does not) are NOT symmetric in
  value, and the split point is deliberately chosen LATE. Case 8b asserts the
  over-firing case explicitly, so that a later tidy-up to "first match wins"
  fails here instead of going quiet in production.

  WHY A CONSOLE TEST. SurfaceSplit uses System.SysUtils and System.Hash and
  nothing else -- no OTA, no VCL -- so all of it links and runs outside the IDE,
  including the gate: TFanOutGate takes the tick count as a PARAMETER precisely
  so its idle clock can be tested without waiting in real time. Same recipe as
  JobQueueHoldTests.dpr. }
uses
  System.SysUtils,
  System.Classes,
  DragLint.Plugin.SurfaceSplit in '..\src\delphi-plugin\DragLint.Plugin.SurfaceSplit.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else
  begin
    Inc(GFail);
    Writeln('FAIL  ', AName);
    if ADetail <> '' then Writeln('      ', ADetail);
  end;
end;

{ Source text from lines, CRLF-joined -- the encoding real buffers arrive in. }
function U(const ALines: array of string): string;
var
  SB: TStringBuilder;
  i : Integer       ;
begin
  SB:= TStringBuilder.Create;
  try
    for i:= Low(ALines) to High(ALines) do SB.Append(ALines[i]).Append(#13#10);
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function Q: string;
begin
  Result:= '''';
end;

{ ---- 1..8: where the split lands ------------------------------------------ }

procedure TestPlainUnit;
var
  Src, Half: string;
begin
  Src:= U(['unit uA;', '', 'interface', '', 'procedure P;', '',
           'implementation', '', 'procedure P; begin end;', '', 'end.']);
  Half:= InterfaceHalf(Src);
  Check('1a the interface half starts at the interface keyword',
        Copy(Half, 1, 9) = 'interface', 'got: [' + Copy(Half, 1, 30) + ']');
  Check('1b it contains the declaration', Pos('procedure P;', Half) > 0, Half);
  Check('1c it stops before the body', Pos('begin end', Half) = 0, Half);
end;

{ 2..5 EACH TEST THE DECOY IN BOTH POSITIONS, and the two positions catch
  different bugs. This is not thoroughness for its own sake -- the `a` variants
  ALONE were measured NOT to discriminate.

    BEFORE the real keyword ("a") -- catches first-match-wins. Last-match-wins
      already survives it, so with the shipped rule these pass even if the
      scanner reads comments as code. Mutation M1 proved exactly that: deleting
      the line-comment state left all four green.
    AFTER the real keyword ("b") -- catches a scanner that reads comments and
      strings as code. Last-match-wins then splits at the DECOY, dragging the
      whole implementation into the interface half, and the fan-out fires on
      every body keystroke. This is the common shape in real code: a comment
      inside an implementation section that mentions the word. }

procedure TestKeywordInLineComment;
var
  Src: string;
begin
  Src:= U(['unit uA;', 'interface', '// implementation detail: not a split point',
           'procedure P;', 'implementation', 'procedure P; begin end;', 'end.']);
  Check('2a a // comment BEFORE the keyword does not split early',
        Pos('procedure P;', InterfaceHalf(Src)) > 0,
        'split fired on the comment, so the declaration was lost to the impl half');

  Src:= U(['unit uA;', 'interface', 'procedure P;', 'implementation',
           'procedure P; begin end;',
           '// a note about the implementation, after the real keyword', 'end.']);
  Check('2b a // comment AFTER the keyword does not split late',
        Pos('begin end', InterfaceHalf(Src)) = 0,
        'the comment became the split point -- every body edit now fans out');
end;

procedure TestKeywordInBraceComment;
var
  Src: string;
begin
  Src:= U(['unit uA;', 'interface', '{ see the implementation below }',
           'procedure P;', 'implementation', 'procedure P; begin end;', 'end.']);
  Check('3a a brace comment BEFORE the keyword does not split early',
        Pos('procedure P;', InterfaceHalf(Src)) > 0, InterfaceHalf(Src));

  Src:= U(['unit uA;', 'interface', 'procedure P;', 'implementation',
           'procedure P; begin end;', '{ that was the implementation }', 'end.']);
  Check('3b a brace comment AFTER the keyword does not split late',
        Pos('begin end', InterfaceHalf(Src)) = 0, InterfaceHalf(Src));
end;

procedure TestKeywordInParenComment;
var
  Src: string;
begin
  Src:= U(['unit uA;', 'interface', '(* implementation notes *)',
           'procedure P;', 'implementation', 'procedure P; begin end;', 'end.']);
  Check('4a a (* *) comment BEFORE the keyword does not split early',
        Pos('procedure P;', InterfaceHalf(Src)) > 0, InterfaceHalf(Src));

  Src:= U(['unit uA;', 'interface', 'procedure P;', 'implementation',
           'procedure P; begin end;', '(* implementation notes *)', 'end.']);
  Check('4b a (* *) comment AFTER the keyword does not split late',
        Pos('begin end', InterfaceHalf(Src)) = 0, InterfaceHalf(Src));
end;

procedure TestKeywordInStringLiteral;
var
  Src: string;
begin
  Src:= U(['unit uA;', 'interface', 'const',
           '  Msg = ' + Q + 'implementation' + Q + ';',
           'procedure P;', 'implementation', 'procedure P; begin end;', 'end.']);
  Check('5a a string literal BEFORE the keyword does not split early',
        Pos('procedure P;', InterfaceHalf(Src)) > 0, InterfaceHalf(Src));

  Src:= U(['unit uA;', 'interface', 'procedure P;', 'implementation',
           'procedure P; begin end;',
           'const Msg = ' + Q + 'implementation' + Q + ';', 'end.']);
  Check('5b a string literal AFTER the keyword does not split late',
        Pos('begin end', InterfaceHalf(Src)) = 0, InterfaceHalf(Src));
end;

procedure TestKeywordAsIdentifierPrefix;
var
  Src: string;
begin
  Src:= U(['unit uA;', 'interface', 'type', '  TImplementationKind = (ikA, ikB);',
           'procedure P;', 'implementation', 'procedure P; begin end;', 'end.']);
  Check('6 an identifier merely CONTAINING the keyword does not split',
        Pos('procedure P;', InterfaceHalf(Src)) > 0, InterfaceHalf(Src));
end;

procedure TestNoImplementation;
var
  Src: string;
begin
  Src:= U(['unit uA;', 'interface', 'procedure P;']);
  Check('7 a buffer with no implementation is ALL interface (conservative)',
        Pos('procedure P;', InterfaceHalf(Src)) > 0,
        'a buffer this scanner cannot read must still fan out on edits');
end;

procedure TestConditionalCandidates;
var
  Src, Half            : string ;
  IfaceAt, ImplAt, Cand: Integer;
begin
  { 8a THE SAFE DIRECTION: a candidate inside a disabled branch BEFORE the real
    one. First-match-wins would split here and lose ALL the real interface. }
  Src:= U(['unit uA;', 'interface', '{$IFDEF NEVER}', 'implementation', '{$ENDIF}',
           'procedure P;', 'implementation', 'procedure P; begin end;', 'end.']);
  FindSplit(Src, IfaceAt, ImplAt, Cand);
  Half:= InterfaceHalf(Src);
  Check('8a two candidates are counted', Cand = 2, Format('candidates=%d', [Cand]));
  Check('8b the LAST candidate wins, so the declaration stays in the interface half',
        Pos('procedure P;', Half) > 0,
        'first-match-wins would silently drop every interface edit after the dead branch');

  { 8c THE COST OF THAT CHOICE, asserted so it is a decision and not a
    surprise: a candidate in a dead branch AFTER the real one splits late, and
    implementation text ends up in the interface half. The gate then over-fires
    on bodies in this one unit. That is the price of never missing. }
  Src:= U(['unit uA;', 'interface', 'procedure P;', 'implementation',
           'procedure P; begin end;', '{$IFDEF NEVER}', 'implementation', '{$ENDIF}',
           'end.']);
  Half:= InterfaceHalf(Src);
  Check('8c a dead branch AFTER the real one splits late -- over-fires, never misses',
        Pos('begin end', Half) > 0,
        'if this ever goes green the other way, check that 8b still holds');
end;

procedure TestUnterminatedLiteral;
var
  Src: string;
begin
  { A buffer mid-edit. One stray quote must not swallow the rest of the unit. }
  Src:= U(['unit uA;', 'interface', 'const', '  Msg = ' + Q + 'oops',
           'procedure P;', 'implementation', 'procedure P; begin end;', 'end.']);
  Check('9 an unterminated literal ends at the line break, not at EOF',
        Pos('begin end', InterfaceHalf(Src)) = 0,
        'the stray quote hid the real implementation keyword');
end;

{ ---- 10..12: what moves the hash ------------------------------------------ }

procedure TestHashSensitivity;
var
  Base, Body, Iface, Header: string;
begin
  Base:= U(['unit uA;', '', 'interface', '', 'procedure P;', '',
            'implementation', '', 'procedure P; begin Sleep(1); end;', '', 'end.']);
  Body:= U(['unit uA;', '', 'interface', '', 'procedure P;', '',
            'implementation', '', 'procedure P; begin Sleep(999); end;', '', 'end.']);
  Iface:= U(['unit uA;', '', 'interface', '', 'procedure P(X: Integer);', '',
             'implementation', '', 'procedure P; begin Sleep(1); end;', '', 'end.']);
  Header:= U(['unit uA;', '{ a note nobody outside this file can see }', 'interface', '',
              'procedure P;', '', 'implementation', '', 'procedure P; begin Sleep(1); end;',
              '', 'end.']);

  Check('10 NEGATIVE CONTROL: an implementation body edit does not move the hash',
        InterfaceHalfHash(Base) = InterfaceHalfHash(Body),
        'the fan-out would fire on every keystroke inside a method');
  Check('11 POSITIVE CONTROL: an interface edit does move the hash',
        InterfaceHalfHash(Base) <> InterfaceHalfHash(Iface),
        'without this, case 10 is equally true of a hash that never moves');
  Check('12 a comment above the interface keyword does not move the hash',
        InterfaceHalfHash(Base) = InterfaceHalfHash(Header),
        'editing the unit header would fan out');
end;

{ ---- 13..19: the gate ------------------------------------------------------ }

const
  IDLE = 2000;

procedure TestGate;
var
  G      : TFanOutGate;
  Gen    : Integer    ;
  Base, Body, Iface, Iface2: string;
begin
  Base := U(['unit uA;', 'interface', 'procedure P;', 'implementation',
             'procedure P; begin Sleep(1); end;', 'end.']);
  Iface:= U(['unit uA;', 'interface', 'procedure P(X: Integer);', 'implementation',
             'procedure P; begin Sleep(1); end;', 'end.']);
  { Body MUST differ from Iface only below the split. Built from Iface, not
    from Base: a body variant of the WRONG interface is an interface change,
    and case 16 would then be measuring the opposite of what it claims. }
  Body := U(['unit uA;', 'interface', 'procedure P(X: Integer);', 'implementation',
             'procedure P; begin Sleep(2); end;', 'end.']);
  Iface2:=U(['unit uA;', 'interface', 'procedure P(X, Y: Integer);', 'implementation',
             'procedure P; begin Sleep(1); end;', 'end.']);

  G.Reset;
  Gen:= -1;
  Check('13 first sight of a file baselines and does NOT launch',
        not G.Consider('uA.pas', Base, 1000, IDLE, Gen),
        'arriving on a tab is not editing it');

  { 14 -- still settling. The edit is seen at t=2000; a launch before t=4000
    would mean the debounce is not there. }
  Check('14a an interface edit does not launch immediately',
        not G.Consider('uA.pas', Iface, 2000, IDLE, Gen), 'no debounce');
  Check('14b nor part-way through the idle period',
        not G.Consider('uA.pas', Iface, 3500, IDLE, Gen), 'debounce too short');
  Check('14c it launches once the interface half has held still',
        G.Consider('uA.pas', Iface, 4100, IDLE, Gen), 'the edit never fanned out');
  Check('14d and reports a generation', Gen = 1, Format('generation=%d', [Gen]));

  Check('15 it does not launch again with nothing changed',
        not G.Consider('uA.pas', Iface, 9000, IDLE, Gen),
        'one edit would fan out on every poll for as long as you looked at it');

  { 16 -- THE ONE THAT DECIDES WHETHER THE FEATURE STAYS SWITCHED ON. }
  Check('16a an implementation edit does not launch, however long it idles',
        not G.Consider('uA.pas', Body, 12000, IDLE, Gen), 'body edits fan out');
  Check('16b nor on a later poll',
        not G.Consider('uA.pas', Body, 20000, IDLE, Gen), 'body edits fan out');

  { 17 -- a different file re-baselines rather than launching. }
  Check('17a switching file does not launch',
        not G.Consider('uB.pas', Iface, 21000, IDLE, Gen), 'tab switch fanned out');
  Check('17b and the new file still fans out on ITS first real edit',
        not G.Consider('uB.pas', Iface2, 21500, IDLE, Gen) and
            G.Consider('uB.pas', Iface2, 24000, IDLE, Gen),
        'the reset left the new file permanently gated off');
end;

{ 18 -- the last-fingerprint short-circuit, and it takes an A-B-A-B sequence to
  exercise at all. The mark names ONE shape: the one that was on screen when the
  engine repeated its previous answer. Coming straight back to it is already
  blocked by "nothing new since the last launch", so the mark only earns its
  keep after an intervening launch for a different shape -- edit, undo, edit,
  undo, which is what a developer actually does.

  Getting that sequence wrong is how this test first failed: driven to B instead
  of back to A, it asserted a short-circuit on a shape that was never marked,
  and the code was right. }
procedure TestSilentShape;
var
  G      : TFanOutGate;
  Gen    : Integer    ;
  A, B, C: string     ;

  { Edit to ASrc and let it settle; returns whether it launched. }
  function EditAndSettle(const ASrc: string; ABase: Cardinal): Boolean;
  begin
    G.Consider('uA.pas', ASrc, ABase, IDLE, Gen);
    Result:= G.Consider('uA.pas', ASrc, ABase + IDLE + 500, IDLE, Gen);
  end;

begin
  A:= U(['unit uA;', 'interface', 'procedure P;', 'implementation', 'end.']);
  B:= U(['unit uA;', 'interface', 'procedure P(X: Integer);', 'implementation', 'end.']);
  C:= U(['unit uA;', 'interface', 'procedure P(X, Y: Integer);', 'implementation', 'end.']);

  G.Reset;
  G.Consider('uA.pas', A, 1000, IDLE, Gen);            { baseline }

  Check('18a the first change launches', EditAndSettle(B, 2000));
  G.NoteFingerprint('f1');

  Check('18b back to the original shape launches -- no answer has repeated yet',
        EditAndSettle(A, 10000));
  G.NoteFingerprint('f1');   { the SAME answer twice -> shape A yields nothing new }

  Check('18c an intervening shape still launches', EditAndSettle(B, 20000));
  G.NoteFingerprint('f2');

  Check('18d undoing back to the marked shape does NOT re-run it',
        not EditAndSettle(A, 30000),
        'the undo paid the engine again for an answer already known');

  Check('18e POSITIVE CONTROL: a shape that was never marked still launches',
        EditAndSettle(C, 40000),
        'the short-circuit gated the file off entirely -- worse than not having it');
end;


{ A LAUNCH THE CALLER COULD NOT START MUST NOT BE LOST.

  Consider COMMITS when it answers True -- it advances the launched-shape marker
  so one edit cannot fire twice. If the caller then declines (the fan-out worker
  is still unwinding from a previous run) that commit makes the edit VANISH:
  every later poll reports "interface unchanged since the last launch" and the
  change is never fanned out at all.

  MEASURED IN PRODUCTION 2026-09-11, which is why this test exists: a 6m22s
  tier-3 compile held the worker while two consecutive interface edits were
  authorised and then declined. Both were lost, and the owner saw "nothing
  changes for ten minutes". }
procedure TestUndoLaunch;
var
  G       : TFanOutGate;
  Gen     : Integer    ;
  FirstGen: Integer    ;
  Tick    : UInt64     ;
  A, B    : string     ;
begin
  Writeln;
  Writeln('-- a declined launch is taken back, not lost --');
  A:= 'unit U; interface procedure One; implementation procedure One; begin end; end.';
  B:= 'unit U; interface procedure Two; implementation procedure Two; begin end; end.';

  G.Reset;
  Tick:= 100000;
  G.Consider('U.pas', A, Tick, 2000, Gen);
  Inc(Tick, 10);
  G.Consider('U.pas', B, Tick, 2000, Gen);
  Inc(Tick, 3000);
  Check('19a the settled interface change launches',
        G.Consider('U.pas', B, Tick, 2000, Gen) and (Gen > 0));

  G.UndoLaunch;   { the caller could not start it }

  Inc(Tick, 3000);
  Check('19b after UndoLaunch the SAME shape launches again',
        G.Consider('U.pas', B, Tick, 2000, Gen),
        'without this the edit is lost forever: ' + G.LastWhy);

  Inc(Tick, 3000);
  Check('19c NEGATIVE CONTROL: a launch that STANDS goes quiet again',
        not G.Consider('U.pas', B, Tick, 2000, Gen),
        G.LastWhy);

  G.Reset;
  Tick:= 500000;
  G.Consider('V.pas', A, Tick, 2000, Gen);
  Inc(Tick, 10);
  G.Consider('V.pas', B, Tick, 2000, Gen);
  Inc(Tick, 3000);
  G.Consider('V.pas', B, Tick, 2000, Gen);
  FirstGen:= Gen;
  G.UndoLaunch;
  Inc(Tick, 3000);
  G.Consider('V.pas', B, Tick, 2000, Gen);
  Check('19d the generation is NOT reused after an undo',
        Gen > FirstGen,
        Format('first=%d second=%d', [FirstGen, Gen]));
end;


begin
  GPass:= 0;
  GFail:= 0;
  Writeln('SurfaceSplitTests');

  try
    TestPlainUnit;
    TestKeywordInLineComment;
    TestKeywordInBraceComment;
    TestKeywordInParenComment;
    TestKeywordInStringLiteral;
    TestKeywordAsIdentifierPrefix;
    TestNoImplementation;
    TestConditionalCandidates;
    TestUnterminatedLiteral;
    TestHashSensitivity;
    TestGate;
    TestSilentShape;
    TestUndoLaunch;
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL  unhandled ', E.ClassName, ': ', E.Message);
    end;
  end;

  Writeln;
  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  if GFail > 0 then Halt(1);
end.
