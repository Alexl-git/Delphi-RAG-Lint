program TextEditTests;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.IOUtils,
  DRagLint.Refactor.TextEdit in '..\..\src\refactor\DRagLint.Refactor.TextEdit.pas';
var GPass, GFail: Integer;
procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;
function Mk(const AFile: string; AKind: TTextEditKind; ALine, ACol, AEnd: Integer; const AText: string): TTextEdit;
begin
  Result:= Default(TTextEdit);   { explicit: ExpectLine must start unguarded }
  Result.FilePath:= AFile; Result.Kind:= AKind; Result.Line:= ALine;
  Result.Col:= ACol; Result.EndLine:= AEnd; Result.Text:= AText;
end;
{ v(PHASE A2) line-kind builder carrying the stale-ANCHOR guard: the edit may be
  written only while line AExpLine still holds AExpText and is not a comment. }
function MkAnchored(const AFile: string; AKind: TTextEditKind; ALine, AEnd: Integer;
  const AText: string; AExpLine: Integer; const AExpText: string): TTextEdit;
begin
  Result:= Default(TTextEdit);
  Result.FilePath:= AFile; Result.Kind:= AKind; Result.Line:= ALine;
  Result.EndLine:= AEnd; Result.Text:= AText;
  Result.ExpectLine:= AExpLine; Result.ExpectText:= AExpText;
end;
{ tekReplaceInLine builder: replace 1-based [ACol, AEndCol) on ALine with AText,
  guarded by AExpect ('' = unguarded / legacy behaviour). }
function MkRep(const AFile: string; ALine, ACol, AEndCol: Integer; const AText, AExpect: string): TTextEdit;
begin
  Result:= Default(TTextEdit);
  Result.FilePath:= AFile; Result.Kind:= tekReplaceInLine; Result.Line:= ALine;
  Result.Col:= ACol; Result.EndCol:= AEndCol; Result.Text:= AText; Result.ExpectText:= AExpect;
end;
var
  P: string; Edits: TArray<TTextEdit>; After: string; Skipped: Integer; Touched: Integer;
begin
  GPass:= 0; GFail:= 0;
  try
    P:= TPath.Combine(TPath.GetTempPath, 'te_fixture.pas');

    { delete-lines: remove lines 2..3 of a 4-line file }
    TFile.WriteAllText(P, 'aaa'#13#10'bbb'#13#10'ccc'#13#10'ddd'#13#10, TEncoding.ANSI);
    Edits:= [Mk(P, tekDeleteLines, 2, 0, 3, '')];
    TTextEditApplier.Apply(Edits, False);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('delete-lines removed bbb+ccc', (Pos('bbb', After) = 0) and (Pos('ccc', After) = 0)
      and (Pos('aaa', After) > 0) and (Pos('ddd', After) > 0));

    { insert-lines: add a line after line 1 }
    TFile.WriteAllText(P, 'aaa'#13#10'ddd'#13#10, TEncoding.ANSI);
    Edits:= [Mk(P, tekInsertLines, 1, 0, 0, 'NEW')];
    TTextEditApplier.Apply(Edits, False);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('insert-lines added NEW after aaa',
      (Pos('aaa'#13#10'NEW'#13#10'ddd', After) > 0));

    { insert-in-line: insert ', X' at col 7 of "uses A;" -> "uses A, X;" }
    TFile.WriteAllText(P, 'uses A;'#13#10, TEncoding.ANSI);
    { 'uses A;' -> columns: u=1 s=2 e=3 s=4 (space)=5 A=6 ;=7. Insert before ';' (col 7). }
    Edits:= [Mk(P, tekInsertInLine, 1, 7, 0, ', X')];
    TTextEditApplier.Apply(Edits, False);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('insert-in-line made "uses A, X;"', (Pos('uses A, X;', After) > 0));

    { CRLF preserved + back-to-front multi-edit on one file }
    TFile.WriteAllText(P, 'l1'#13#10'l2'#13#10'l3'#13#10'l4'#13#10, TEncoding.ANSI);
    Edits:= [Mk(P, tekDeleteLines, 3, 0, 3, ''), Mk(P, tekDeleteLines, 1, 0, 1, '')];
    TTextEditApplier.Apply(Edits, False);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('multi-delete back-to-front kept l2+l4',
      (Pos('l2', After) > 0) and (Pos('l4', After) > 0) and (Pos('l1', After) = 0) and (Pos('l3', After) = 0));
    Check('CRLF preserved', Pos(#13#10, After) > 0);

    { --- tekReplaceInLine: the ExpectText stale-position guard --- }

    { unguarded (ExpectText='') replace still works exactly as before }
    TFile.WriteAllText(P, '  glyActive:= 1;'#13#10, TEncoding.ANSI);
    { '  glyActive:= 1;' -> g starts at col 3, span [3, 12) is 'glyActive' }
    Edits:= [MkRep(P, 1, 3, 12, 'GlyActive', '')];
    Skipped:= -1;
    TTextEditApplier.Apply(Edits, False, Skipped);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('replace-in-line unguarded still applies (legacy caller unaffected)',
      (Pos('  GlyActive:= 1;', After) > 0) and (Skipped = 0));

    { guard MATCHES (case-insensitively) -> applied }
    TFile.WriteAllText(P, '  glyActive:= 1;'#13#10, TEncoding.ANSI);
    Edits:= [MkRep(P, 1, 3, 12, 'GlyActive', 'GLYACTIVE')];
    Skipped:= -1;
    TTextEditApplier.Apply(Edits, False, Skipped);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('replace-in-line applies when ExpectText matches',
      (Pos('  GlyActive:= 1;', After) > 0) and (Skipped = 0));

    { guard MISMATCHES -> skipped, line byte-identical.
      This is the stale-index case: the store said line 1 col 3 held glyActive,
      but the file now has something else there. }
    TFile.WriteAllText(P, '  if not Err then'#13#10, TEncoding.ANSI);
    Edits:= [MkRep(P, 1, 3, 12, 'GlyActive', 'glyActive')];
    Skipped:= -1;
    TTextEditApplier.Apply(Edits, False, Skipped);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('replace-in-line SKIPPED when ExpectText does not match',
      (Pos('  if not Err then', After) > 0) and (Pos('GlyActive', After) = 0) and (Skipped = 1));

    { Col past end-of-line -> REJECTED, never a silent append.
      'else' is 4 chars, so col 20 is far past EOL; the old code clamped only
      EndCol and produced 'elseGlyActive'. }
    TFile.WriteAllText(P, 'else'#13#10, TEncoding.ANSI);
    Edits:= [MkRep(P, 1, 20, 29, 'GlyActive', '')];
    Skipped:= -1;
    TTextEditApplier.Apply(Edits, False, Skipped);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('replace-in-line REJECTED when Col is past end-of-line (no append)',
      (Pos('elseGlyActive', After) = 0) and (Pos('else', After) > 0) and (Skipped = 1));

    { mixed set: the bad edit is dropped, the good one on another line applies }
    TFile.WriteAllText(P, '  glyActive:= 1;'#13#10'else'#13#10, TEncoding.ANSI);
    Edits:= [MkRep(P, 1, 3, 12, 'GlyActive', 'glyActive'), MkRep(P, 2, 20, 29, 'Nope', '')];
    Skipped:= -1;
    TTextEditApplier.Apply(Edits, False, Skipped);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('one bad edit skipped does not block a good one',
      (Pos('  GlyActive:= 1;', After) > 0) and (Pos('elseNope', After) = 0) and (Skipped = 1));

    { --- a file whose EVERY edit was rejected must be left completely alone ---
      The applier used to write the .bak and re-serialize the file BEFORE any
      edit had been evaluated, so a fully-skipped file was still backed up,
      still rewritten, and still counted in "applied N fix(es) across M file(s)". }

    TFile.WriteAllText(P, '  if not Err then'#13#10, TEncoding.ANSI);
    if TFile.Exists(P + '.bak') then TFile.Delete(P + '.bak');
    Edits:= [MkRep(P, 1, 3, 12, 'GlyActive', 'glyActive')];
    Skipped:= -1;
    Touched:= TTextEditApplier.Apply(Edits, True { backups on }, Skipped);
    Check('all-skipped file is NOT counted as touched', (Touched = 0) and (Skipped = 1));
    Check('all-skipped file gets NO .bak', not TFile.Exists(P + '.bak'));

    { The write path re-serializes through a TStringList and forces CRLF, so an
      LF-only file is the sharpest probe for "rewritten with nothing applied". }
    TFile.WriteAllBytes(P, TEncoding.ANSI.GetBytes('aaa'#10'bbb'#10));
    Edits:= [MkRep(P, 1, 3, 12, 'GlyActive', 'glyActive')];
    Skipped:= -1;
    Touched:= TTextEditApplier.Apply(Edits, False, Skipped);
    Check('all-skipped file is byte-identical (LF endings survive)',
      (TFile.ReadAllText(P, TEncoding.ANSI) = 'aaa'#10'bbb'#10) and (Touched = 0));

    { ...while a file that really did change still gets its backup. }
    TFile.WriteAllText(P, '  glyActive:= 1;'#13#10, TEncoding.ANSI);
    if TFile.Exists(P + '.bak') then TFile.Delete(P + '.bak');
    Edits:= [MkRep(P, 1, 3, 12, 'GlyActive', 'glyActive')];
    Skipped:= -1;
    Touched:= TTextEditApplier.Apply(Edits, True, Skipped);
    Check('applied file still gets a .bak holding the original',
      (Touched = 1) and (Skipped = 0) and TFile.Exists(P + '.bak')
      and (Pos('glyActive:= 1;', TFile.ReadAllText(P + '.bak', TEncoding.ANSI)) > 0));

    { --- v(PHASE A2): the stale-ANCHOR guard on the LINE kinds --------------
      The line kinds had no guard at all, which is how `document --qname
      --apply` run twice on one class nested the second block inside the first.
      The anchor is the declaration line; the guard requires that line to still
      hold the name AND to not be a comment. }

    { anchor holds -> insert applies }
    TFile.WriteAllText(P, 'unit u;'#13#10'procedure Ping;'#13#10, TEncoding.ANSI);
    Edits:= [MkAnchored(P, tekInsertLines, 1, 0, '/// <summary>x</summary>', 2, 'Ping')];
    Skipped:= -1;
    TTextEditApplier.Apply(Edits, False, Skipped);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('anchored insert applies when the declaration is still at ExpectLine',
      (Pos('<summary>x</summary>'#13#10'procedure Ping;', After) > 0) and (Skipped = 0));

    { anchor moved (the name is on a DIFFERENT line now) -> dropped }
    TFile.WriteAllText(P, 'unit u;'#13#10'procedure Other;'#13#10'procedure Ping;'#13#10, TEncoding.ANSI);
    Edits:= [MkAnchored(P, tekInsertLines, 1, 0, '/// <summary>x</summary>', 2, 'Ping')];
    Skipped:= -1;
    TTextEditApplier.Apply(Edits, False, Skipped);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('anchored insert SKIPPED when the declaration has moved off ExpectLine',
      (Pos('<summary>', After) = 0) and (Skipped = 1));

    { THE FILED DEFECT: the stale line now points INSIDE a doc block the last
      apply wrote, on a line that DOES contain the name. A substring test alone
      passes here; the comment test is what rejects it. }
    TFile.WriteAllText(P, 'unit u;'#13#10'/// Calls: Ping'#13#10'procedure Ping;'#13#10, TEncoding.ANSI);
    Edits:= [MkAnchored(P, tekInsertLines, 1, 0, '/// <summary>x</summary>', 2, 'Ping')];
    Skipped:= -1;
    TTextEditApplier.Apply(Edits, False, Skipped);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('anchored insert SKIPPED when ExpectLine landed in a COMMENT that names the symbol',
      (Pos('<summary>', After) = 0) and (Skipped = 1));

    { whole-word, not substring: 'Ping' must not be satisfied by 'Pinger' }
    TFile.WriteAllText(P, 'unit u;'#13#10'procedure Pinger;'#13#10, TEncoding.ANSI);
    Edits:= [MkAnchored(P, tekInsertLines, 1, 0, '/// <summary>x</summary>', 2, 'Ping')];
    Skipped:= -1;
    TTextEditApplier.Apply(Edits, False, Skipped);
    Check('anchored guard matches WHOLE WORDS -- Pinger does not satisfy Ping', (Skipped = 1));

    { a DELETE+INSERT pair sharing one stale anchor must fail TOGETHER --
      otherwise the repair path deletes an existing comment and drops its
      replacement, which is worse than either half alone. }
    TFile.WriteAllText(P, 'unit u;'#13#10'/// old doc'#13#10'procedure Other;'#13#10'procedure Ping;'#13#10, TEncoding.ANSI);
    Edits:= [MkAnchored(P, tekDeleteLines, 2, 2, '', 3, 'Ping'),
             MkAnchored(P, tekInsertLines, 1, 0, '/// new doc', 3, 'Ping')];
    Skipped:= -1;
    Touched:= TTextEditApplier.Apply(Edits, False, Skipped);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('a stale delete+insert PAIR is dropped together -- no half-applied repair',
      (Pos('/// old doc', After) > 0) and (Pos('/// new doc', After) = 0)
      and (Skipped = 2) and (Touched = 0));

    { ... and the same pair applies in full when the anchor does hold. }
    TFile.WriteAllText(P, 'unit u;'#13#10'/// old doc'#13#10'procedure Ping;'#13#10, TEncoding.ANSI);
    Edits:= [MkAnchored(P, tekDeleteLines, 2, 2, '', 3, 'Ping'),
             MkAnchored(P, tekInsertLines, 1, 0, '/// new doc', 3, 'Ping')];
    Skipped:= -1;
    Touched:= TTextEditApplier.Apply(Edits, False, Skipped);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('the same pair applies in FULL when the anchor holds (de-vacuator)',
      (Pos('/// new doc', After) > 0) and (Pos('/// old doc', After) = 0)
      and (Skipped = 0) and (Touched = 1));

    if TFile.Exists(P) then TFile.Delete(P);
    if TFile.Exists(P + '.bak') then TFile.Delete(P + '.bak');
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('textedit-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
