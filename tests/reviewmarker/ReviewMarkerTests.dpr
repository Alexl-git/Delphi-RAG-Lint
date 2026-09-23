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

  { 10: THE COLON FORM. `dl:ok <rule>: <prose>` is what people actually write.
    It used to make the WHOLE tail the rule list, so the marker named a rule
    that does not exist and suppressed nothing -- silently. DataCopy hit this
    on 11 sites. The comma inside the prose is the sharp edge: before the fix
    it split the tail into two bogus rule ids. }
  M:= TReviewMarkers.Parse('    Sleep(100); // dl:ok sleep-in-vcl: headless test, no UI');
  Check('10 colon form yields exactly one marker', Length(M) = 1);
  if Length(M) = 1 then
  begin
    Check('10 rule id stops at the colon', M[0].RuleId = 'sleep-in-vcl');
    Check('10 hash empty', M[0].Hash = '');
    Check('10 reason keeps its comma', M[0].Reason = 'headless test, no UI');
  end;

  { 10b: colon after a hash. }
  M:= TReviewMarkers.Parse('except // dl:ok bare-except@7f3a: rethrown by the caller');
  Check('10b colon after hash yields one marker', Length(M) = 1);
  if Length(M) = 1 then
  begin
    Check('10b rule id', M[0].RuleId = 'bare-except');
    Check('10b hash survives', M[0].Hash = '7f3a');
    Check('10b reason', M[0].Reason = 'rethrown by the caller');
  end;

  { 10c: two rules then a colon -- the comma BEFORE the separator still splits. }
  M:= TReviewMarkers.Parse('// dl:ok bare-except,deep-nesting: both accepted');
  Check('10c two rules parsed', Length(M) = 2);
  if Length(M) = 2 then
  begin
    Check('10c first rule', M[0].RuleId = 'bare-except');
    Check('10c second rule', M[1].RuleId = 'deep-nesting');
    Check('10c reason shared', M[1].Reason = 'both accepted');
  end;

  { 10d: WHICHEVER SEPARATOR COMES FIRST WINS. `--` first, so the colon is
    ordinary prose inside the reason. }
  M:= TReviewMarkers.Parse('// dl:ok bare-except -- see note: it is rethrown');
  Check('10d dash-first yields one marker', Length(M) = 1);
  if Length(M) = 1 then
  begin
    Check('10d rule id', M[0].RuleId = 'bare-except');
    Check('10d colon stays in the reason', M[0].Reason = 'see note: it is rethrown');
  end;

  { 10e: and the mirror -- colon first, so a later `--` is prose. }
  M:= TReviewMarkers.Parse('// dl:ok bare-except: rethrown -- by the caller');
  Check('10e colon-first yields one marker', Length(M) = 1);
  if Length(M) = 1 then
  begin
    Check('10e rule id', M[0].RuleId = 'bare-except');
    Check('10e dash stays in the reason', M[0].Reason = 'rethrown -- by the caller');
  end;
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

{ ---- review-marker-placeholder-hash ------------------------------------------

  A hash that was never computed is not a hash. `@0000` on a `//` marker can
  never equal the window hash except by a 1-in-65536 accident, so it suppresses
  nothing while reading as a review; in a brace block it is not even parsed. }

procedure TestPlaceholderHash;
var
  M: TArray<TReviewMarker>;
  B: TArray<Boolean>;
begin
  Check('P1 all-zero is a placeholder', TReviewMarkers.IsPlaceholderHash('0000'));
  Check('P1b any run of zeros is a placeholder', TReviewMarkers.IsPlaceholderHash('00'));
  Check('P2 a computed-looking hash is not a placeholder', not TReviewMarkers.IsPlaceholderHash('7f3a'));
  Check('P3 empty is not a placeholder (that is the hashless case)', not TReviewMarkers.IsPlaceholderHash(''));

  Check('P4 4 lowercase hex is well formed', not TReviewMarkers.IsMalformedHash('7f3a'));
  Check('P4b 0000 is well formed (placeholder is a separate test)', not TReviewMarkers.IsMalformedHash('0000'));
  Check('P5 xxxx is malformed', TReviewMarkers.IsMalformedHash('xxxx'));
  Check('P5b three chars is malformed', TReviewMarkers.IsMalformedHash('7f3'));
  Check('P5c five chars is malformed', TReviewMarkers.IsMalformedHash('7f3a1'));
  Check('P5d <hash> is malformed', TReviewMarkers.IsMalformedHash('<hash>'));
  Check('P6 empty is not malformed (hashless is reported elsewhere)', not TReviewMarkers.IsMalformedHash(''));

  { EmbeddedMarkers reads a dl:ok WHEREVER it sits on the line -- the shape
    Parse deliberately refuses, used only to find markers that can never work. }
  M:= TReviewMarkers.EmbeddedMarkers('{ REVIEWED 2026-09-11, dl:ok deep-nesting@0000 -- six levels');
  Check('P7 a marker in a brace comment is found', Length(M) = 1);
  if Length(M) = 1 then
  begin
    Check('P7 rule id', M[0].RuleId = 'deep-nesting');
    Check('P7 hash', M[0].Hash = '0000');
  end;
  Check('P7b Parse still ignores it (not a live marker)',
    Length(TReviewMarkers.Parse('{ REVIEWED 2026-09-11, dl:ok deep-nesting@0000 -- six levels')) = 0);
  Check('P8 no tag, no markers', Length(TReviewMarkers.EmbeddedMarkers('{ just prose }')) = 0);

  { P9: A STRING LITERAL IS NOT A COMMENT. Found by dogfooding: this very file's
    P7 line quotes the LintTree marker inside a Pascal literal, and the rule
    reported it. Starting in code state, only a tag inside a comment counts. }
  Check('P9 a tag inside a string literal is not embedded',
    Length(TReviewMarkers.EmbeddedMarkers('  S:= ''{ dl:ok deep-nesting@0000 }'';')) = 0);
  Check('P9b a doubled quote does not end the literal early',
    Length(TReviewMarkers.EmbeddedMarkers('  S:= ''it''''s dl:ok deep-nesting@0000'';')) = 0);
  Check('P9c code, then a brace comment carrying the tag, is embedded',
    Length(TReviewMarkers.EmbeddedMarkers('  X:= 1; { dl:ok deep-nesting@0000 }')) = 1);
  { A line that begins INSIDE a multi-line block comment has no code state to
    track -- the caller says so, and the whole line counts. }
  Check('P10 continuation line of a block comment, apostrophe in prose',
    Length(TReviewMarkers.EmbeddedMarkers('  it''s why: dl:ok deep-nesting@0000', True)) = 1);
  { P11: BlockOpenAtLineStart is what the CLI passes as AStartsInComment. A
    quoted brace opens nothing; a real one carries over to the next line. }
  B:= TReviewMarkers.BlockOpenAtLineStart(['x:= 1; { open', 'inside', 'close } y:= 2;',
                                           'S:= ''{'';', 'z:= 3;']);
  Check('P11 block state at line start',
    (Length(B) = 5) and (not B[0]) and B[1] and B[2] and (not B[3]) and (not B[4]));
  Check('P10b the same line read from code state is not a comment',
    Length(TReviewMarkers.EmbeddedMarkers('  it''s why: dl:ok deep-nesting@0000')) = 0);
end;

{ ---- review-marker-reason-unreviewed -----------------------------------------

  OWNER RULING OWN-7 (2026-09-23): an optional `REVIEWED <yyyy-mm-dd>` stamp in
  the marker's reason. Uppercase keyword, case-SENSITIVE, so the ordinary prose
  "reviewed, the loop is bounded" is not mistaken for a stamp. }

procedure TestReviewStamp;
var
  Today, D: TDate;
begin
  Today:= EncodeDate(2026, 9, 23);
  Check('R1 no stamp -> missing',
    TReviewMarkers.ReviewStamp('rethrown by the caller', Today, 180, D) = rssMissing);
  Check('R1b lowercase prose is not a stamp',
    TReviewMarkers.ReviewStamp('reviewed 2026-09-01, the loop is bounded', Today, 180, D) = rssMissing);
  Check('R2 recent stamp -> current',
    TReviewMarkers.ReviewStamp('REVIEWED 2026-09-01 rethrown by the caller', Today, 180, D) = rssCurrent);
  Check('R2 stamp date returned', D = EncodeDate(2026, 9, 1));
  Check('R2b stamp anywhere in the reason',
    TReviewMarkers.ReviewStamp('rethrown by the caller (REVIEWED 2026-09-01)', Today, 180, D) = rssCurrent);
  Check('R3 exactly at the limit is current',
    TReviewMarkers.ReviewStamp('REVIEWED 2026-03-27', Today, 180, D) = rssCurrent);
  Check('R3b one day past the limit is expired',
    TReviewMarkers.ReviewStamp('REVIEWED 2026-03-26', Today, 180, D) = rssExpired);
  Check('R4 a future stamp is reported',
    TReviewMarkers.ReviewStamp('REVIEWED 2026-10-01', Today, 180, D) = rssFuture);
  Check('R5 an impossible date is malformed',
    TReviewMarkers.ReviewStamp('REVIEWED 2026-02-30', Today, 180, D) = rssMalformed);
  Check('R5b keyword with no date is malformed',
    TReviewMarkers.ReviewStamp('REVIEWED yesterday', Today, 180, D) = rssMalformed);
  Check('R6 max age 0 means presence only',
    TReviewMarkers.ReviewStamp('REVIEWED 2020-01-01', Today, 0, D) = rssCurrent);

  { THE HASH MUST NOT SEE THE STAMP. HashLine drops `//` comments, so editing
    the reason -- re-stamping it -- cannot make the marker stale. Verified, not
    assumed: a stamp edit that invalidated the hash would turn every re-review
    into a second review. }
  Check('R7 stamp edit leaves HashLine unchanged',
    TReviewMarkers.HashLine('  S := S + T; // dl:ok concat-in-loop@1a2b -- bounded') =
    TReviewMarkers.HashLine('  S := S + T; // dl:ok concat-in-loop@1a2b -- REVIEWED 2026-09-23 bounded'));
  Check('R7b stamp edit leaves HashWindow unchanged',
    TReviewMarkers.HashWindow(['  except // dl:ok bare-except@1a2b -- rethrown', '    raise;', '  end;'], 0) =
    TReviewMarkers.HashWindow(['  except // dl:ok bare-except@1a2b -- REVIEWED 2026-09-23 rethrown', '    raise;', '  end;'], 0));
end;

begin
  GPass:= 0; GFail:= 0;
  try
    TestHash;
    TestParse;
    TestInsert;
    TestRefresh;
    TestPlaceholderHash;
    TestReviewStamp;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('review-marker-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
