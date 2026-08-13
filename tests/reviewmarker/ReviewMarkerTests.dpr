program ReviewMarkerTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DRagLint.Lint.ReviewMarker in '..\..\src\lint\DRagLint.Lint.ReviewMarker.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;

function IsLowerHex(const AText: string): Boolean;
var
  C: Char;
begin
  Result:= AText <> '';
  for C in AText do
    if not (CharInSet(C, ['0'..'9', 'a'..'f'])) then Exit(False);
end;

function IsAscii7(const AText: string): Boolean;
var
  C: Char;
begin
  Result:= True;
  for C in AText do
    if Ord(C) > 127 then Exit(False);
end;

function OccurrenceCount(const AHaystack, ANeedle: string): Integer;
var
  P: Integer;
begin
  Result:= 0;
  if ANeedle = '' then Exit;
  P:= Pos(ANeedle, AHaystack);
  while P > 0 do
  begin
    Inc(Result);
    P:= Pos(ANeedle, AHaystack, P + Length(ANeedle));
  end;
end;

{ ---- the content hash ------------------------------------------------------ }

procedure TestHash;
var
  H: string;
begin
  H:= TReviewMarkers.HashLine('  except');
  Check('hash is 4 chars', Length(H) = 4);
  Check('hash is lowercase hex', IsLowerHex(H));

  { 1: whitespace dropped, identifiers lowercased -- YADF re-indents and
    case-normalises, and neither may invalidate a review. }
  Check('1 case+space insensitive',
    TReviewMarkers.HashLine('if a then') = TReviewMarkers.HashLine('IF   A  THEN'));

  { 2: a real edit must break the hash, or the marker suppresses code nobody
    reviewed -- the entire point of the @hash. }
  Check('2 real edit changes hash',
    TReviewMarkers.HashLine('x := 1;') <> TReviewMarkers.HashLine('x := 2;'));

  { 3: comments excluded. Without this the marker would change the hash it
    encodes the moment it is written -- chicken-and-egg. }
  Check('3 comments excluded',
    TReviewMarkers.HashLine('except') =
    TReviewMarkers.HashLine('except // dl:ok bare-except@7f3a -- rethrown'));
  Check('3b block comment excluded',
    TReviewMarkers.HashLine('except') = TReviewMarkers.HashLine('except { why }'));

  { 4: string literals keep their case. Delphi identifiers are case-insensitive
    but literal CONTENT is not; lowercasing it would let two genuinely different
    lines share a hash. }
  Check('4 literal case is significant',
    TReviewMarkers.HashLine('S := ''Abc'';') <> TReviewMarkers.HashLine('S := ''abc'';'));
  Check('4b literal doubled-quote survives',
    TReviewMarkers.HashLine('S := ''it''''s'';') = TReviewMarkers.HashLine('s:=''it''''s'';'));

  { A compiler directive is CODE, not a comment: an IFDEF of A and an IFDEF of B
    are different programs and must not share a hash. (Written without the brace
    form on purpose -- Delphi comments do not nest, so spelling the directive out
    here would close this comment early and leave a live conditional behind.) }
  Check('directive is code, not comment',
    TReviewMarkers.HashLine('{$IFDEF A}') <> TReviewMarkers.HashLine('{$IFDEF B}'));
end;

{ ---- parsing --------------------------------------------------------------- }

procedure TestParse;
var
  M: TArray<TReviewMarker>;
begin
  { 5: the full form. }
  M:= TReviewMarkers.Parse('  except // dl:ok bare-except@7f3a -- rethrown by the caller');
  Check('5 one marker parsed', Length(M) = 1);
  if Length(M) = 1 then
  begin
    Check('5 rule id', M[0].RuleId = 'bare-except');
    Check('5 hash', M[0].Hash = '7f3a');
    Check('5 reason', M[0].Reason = 'rethrown by the caller');
  end;

  { 6: several findings on one line share one marker. }
  M:= TReviewMarkers.Parse('// dl:ok bare-except@7f3a, deep-nesting@aa01 -- both accepted');
  Check('6 two markers parsed', Length(M) = 2);
  if Length(M) = 2 then
  begin
    Check('6 second rule id', M[1].RuleId = 'deep-nesting');
    Check('6 second hash', M[1].Hash = 'aa01');
    Check('6 reason shared', M[0].Reason = 'both accepted');
  end;

  { 7: a hand-written marker with no @hash. Parsed, but unverifiable. }
  M:= TReviewMarkers.Parse('except // dl:ok bare-except');
  Check('7 hashless marker parsed', Length(M) = 1);
  if Length(M) = 1 then
  begin
    Check('7 rule id', M[0].RuleId = 'bare-except');
    Check('7 hash empty', M[0].Hash = '');
  end;

  { 8: ordinary lines. }
  Check('8 no marker', Length(TReviewMarkers.Parse('  x := 1; // just a comment')) = 0);
  Check('8b empty line', Length(TReviewMarkers.Parse('')) = 0);

  { 9: THE ONE THAT BITES. A marker inside a string literal is not a marker.
    The existing drag-lint:ignore filter uses a bare Pos() and gets this wrong. }
  Check('9 marker inside a literal is not a marker',
    Length(TReviewMarkers.Parse('  S := ''// dl:ok fake@0000'';')) = 0);

  { Case-insensitive on both the tag and the rule id. }
  Check('marker tag is case-insensitive',
    Length(TReviewMarkers.Parse('except // DL:OK Bare-Except@7F3A')) = 1);
end;

{ ---- insertion ------------------------------------------------------------- }

procedure TestInsert;
var
  L1, L2: string;
  M     : TArray<TReviewMarker>;
begin
  { The marker inserted on a line must be the marker that line's hash expects. }
  L1:= TReviewMarkers.InsertInto('    except', 'bare-except', 'rethrown by the caller');
  M := TReviewMarkers.Parse(L1);
  Check('insert produces one marker', Length(M) = 1);
  if Length(M) = 1 then
  begin
    Check('inserted hash matches the line', M[0].Hash = TReviewMarkers.HashLine(L1));
    Check('inserted rule id', M[0].RuleId = 'bare-except');
    Check('inserted reason', M[0].Reason = 'rethrown by the caller');
  end;
  Check('insert preserves the code', Pos('except', L1) > 0);
  Check('insert leaves indentation', Copy(L1, 1, 4) = '    ');

  { 10: a second rule merges into the existing comment, it does not add a
    second dl:ok comment. }
  L2:= TReviewMarkers.InsertInto(L1, 'deep-nesting', '');
  M := TReviewMarkers.Parse(L2);
  Check('10 merge gives two markers', Length(M) = 2);
  Check('10 still exactly one dl:ok comment', OccurrenceCount(LowerCase(L2), 'dl:ok') = 1);
  if Length(M) = 2 then
    Check('10 original reason preserved', M[0].Reason = 'rethrown by the caller');

  { Re-marking the same rule must not duplicate it. }
  Check('re-marking same rule is idempotent',
    Length(TReviewMarkers.Parse(TReviewMarkers.InsertInto(L1, 'bare-except', ''))) = 1);

  { 11: file conventions -- 7-bit ASCII, no trailing whitespace. }
  Check('11 no trailing whitespace', (L2 = '') or (L2[Length(L2)] <> ' '));
  Check('11 pure 7-bit ASCII', IsAscii7(L2));

  { Insertion must not disturb the hash it just recorded: the marker is a
    comment, and comments are excluded from the hash. }
  Check('hash stable across insertion',
    TReviewMarkers.HashLine(L2) = TReviewMarkers.HashLine('    except'));
end;

{ ---- re-accepting a review whose code changed ------------------------------

  A stale marker re-reports its finding, which is the whole point of the hash.
  The way back is to allow it again: the SAME action, not a separate one. That
  makes InsertInto's old guard wrong -- it matched on rule id alone and bailed,
  so re-allowing a stale marker was a silent no-op with nothing to show for the
  click. }

procedure TestRefresh;
var
  Marked, Stale, Fresh : string;
  Two, StaleTwo, Mixed : string;
  OldHash              : string;
  M                    : TArray<TReviewMarker>;
begin
  Marked:= TReviewMarkers.InsertInto('  x := 1;', 'magic-number', 'small and clear');

  { An edit to the code the review covered. The marker rides along unchanged,
    which is exactly the state the hash exists to detect. }
  Stale:= StringReplace(Marked, 'x := 1;', 'x := 2;', []);
  M    := TReviewMarkers.Parse(Stale);
  Check('12 precondition: marker is stale',
    (Length(M) = 1) and (M[0].Hash <> TReviewMarkers.HashLine(Stale)));

  Fresh:= TReviewMarkers.InsertInto(Stale, 'magic-number', '');
  M    := TReviewMarkers.Parse(Fresh);
  Check('12 re-allow refreshes the hash',
    (Length(M) = 1) and (M[0].Hash = TReviewMarkers.HashLine(Fresh)));
  Check('12 re-allow does not duplicate the rule', Length(M) = 1);
  Check('12 re-allow still one dl:ok comment', OccurrenceCount(LowerCase(Fresh), 'dl:ok') = 1);
  if Length(M) = 1 then
    Check('12 re-allow preserves the reason', M[0].Reason = 'small and clear');
  Check('12 re-allow keeps the code', Pos('x := 2;', Fresh) > 0);
  Check('12 re-allow keeps indentation', Copy(Fresh, 1, 2) = '  ');
  Check('12 re-allow stays 7-bit ASCII', IsAscii7(Fresh));
  Check('12 re-allow leaves no trailing space', (Fresh = '') or (Fresh[Length(Fresh)] <> ' '));

  { 13: a marker that still matches its line is untouched -- byte-identical, not
    merely equivalent, so an Allow on an already-clean finding cannot dirty the
    editor buffer. }
  Check('13 matching re-allow is a byte no-op',
    TReviewMarkers.InsertInto(Marked, 'magic-number', '') = Marked);

  { 14: THE trap. Two reviews on one line, both stale; re-allowing one must not
    silently re-validate the other. Its code was not re-examined, and a review
    that outlives the code it reviewed is worse than no review. }
  Two     := TReviewMarkers.InsertInto('  x := 1;', 'magic-number', 'why');
  Two     := TReviewMarkers.InsertInto(Two, 'deep-nesting', '');
  StaleTwo:= StringReplace(Two, 'x := 1;', 'x := 2;', []);
  M       := TReviewMarkers.Parse(StaleTwo);
  Check('14 precondition: two stale markers', Length(M) = 2);
  if Length(M) = 2 then
  begin
    OldHash:= M[1].Hash;
    Mixed  := TReviewMarkers.InsertInto(StaleTwo, 'magic-number', '');
    M      := TReviewMarkers.Parse(Mixed);
    Check('14 both markers survive the refresh', Length(M) = 2);
    if Length(M) = 2 then
    begin
      Check('14 clicked rule is refreshed', M[0].Hash = TReviewMarkers.HashLine(Mixed));
      Check('14 neighbour keeps its stale hash', M[1].Hash = OldHash);
      Check('14 neighbour is still reported stale', M[1].Hash <> TReviewMarkers.HashLine(Mixed));
    end;
  end;

  { 15: a hand-written marker carries no hash, so the CLI honours it but says it
    cannot be verified. Allowing it again is how that gets fixed. }
  Fresh:= TReviewMarkers.InsertInto('  y := 3;  // dl:ok bare-except', 'bare-except', '');
  M    := TReviewMarkers.Parse(Fresh);
  Check('15 hashless marker gains a hash',
    (Length(M) = 1) and (M[0].Hash = TReviewMarkers.HashLine(Fresh)));
end;

begin
  GPass:= 0; GFail:= 0;
  try
    TestHash;
    TestParse;
    TestInsert;
    TestRefresh;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('review-marker-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
