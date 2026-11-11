program CommentFactsParity;

{ Wave 151 lane W1 parity harness: the comment_facts producer
  (DRagLint.Index.CommentFacts.ExtractCommentFacts) against the three scanners
  that read comments today, on the same decoded text --
    DOC  `///` blocks : TDocCommentScanner.Scan regions of kind dckTripleSlash /
                        dckTripleSlashOne  vs  the table's `///` rows folded by
                        the scanner's own merge rule (same sub-kind, touching
                        lines, a trailing doc line opens a new run unless the run
                        began trailing);
    OK   dl:ok markers: TReviewMarkers.Parse on every line MarkerBearingLines
                        accepts  vs  Parse(row text) on every `//` row;
    BK   dl:bk anchors: TBookmarks.Scan(file)  vs  TBookmarks.Scan(row text) on
                        every `//` / `///` row (line = row line, offset = row
                        start + 1).
  Every set is compared as sorted tuples; a tuple on one side only is printed as
  MISMATCH and makes the exit code 1.

  Usage: CommentFactsParity [--drop-kind <kind>] <dir-or-file> ...
    --drop-kind  positive control: drop every row of that kind ('//', '///',
                 '{', '(*') before comparing -- the guard expects MISMATCHes.
  Last line: SUMMARY files=N rows=N doc=T/T ok=T/T bk=T/T mismatches=N extract_ms=N }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.Diagnostics
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.Parser.DocComments
  , DRagLint.Lint.ReviewMarker
  , DRagLint.Lint.Bookmarks
  , DRagLint.Index.CommentFacts
  ;

var
  DropKind  : string;
  Files     : TList<string>;
  Mismatches: Integer;
  RowCount  : Integer;
  Totals    : array[0..5] of Integer; { doc today/table, ok today/table, bk today/table }
  Watch     : TStopwatch;

function ReadSource(const APath: string): string;
var
  Bytes: TBytes;
  Skip : Integer;
begin
  Bytes:= TFile.ReadAllBytes(APath);
  Skip := 0;
  if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then Skip:= 3;
  try
    Result:= TEncoding.UTF8.GetString(Bytes, Skip, Length(Bytes) - Skip);
  except
    on EEncodingError do Result:= #$FFFD; { not UTF-8: read it as ANSI below }
  end;
  if Pos(#$FFFD, Result) > 0 then Result:= TEncoding.ANSI.GetString(Bytes, Skip, Length(Bytes) - Skip);
end;

function SplitLines(const AText: string): TArray<string>;
var
  I: Integer;
begin
  Result:= AText.Split([#10]);
  for I:= 0 to High(Result) do
    if Result[I].EndsWith(#13) then Result[I]:= Copy(Result[I], 1, Length(Result[I]) - 1);
end;

{ Prints the tuples present on one side only; returns how many. }
function Compare(const ASet, AFile: string; AToday, ATable: TList<string>): Integer;
var
  S: string;
  A, B: TDictionary<string, Integer>;
  N: Integer;
begin
  Result:= 0;
  A:= TDictionary<string, Integer>.Create;
  B:= TDictionary<string, Integer>.Create;
  try
    for S in AToday do if A.TryGetValue(S, N) then A[S]:= N + 1 else A.Add(S, 1);
    for S in ATable do if B.TryGetValue(S, N) then B[S]:= N + 1 else B.Add(S, 1);
    for S in A.Keys do
      if (not B.TryGetValue(S, N)) or (N <> A[S]) then
      begin
        Writeln(Format('MISMATCH %s only-today %s %s', [ASet, AFile, S]));
        Inc(Result);
      end;
    for S in B.Keys do
      if (not A.TryGetValue(S, N)) or (N <> B[S]) then
      begin
        Writeln(Format('MISMATCH %s only-table %s %s', [ASet, AFile, S]));
        Inc(Result);
      end;
  finally
    A.Free;
    B.Free;
  end;
end;

function Esc(const S: string): string;
begin
  Result:= S.Replace(#13, '\r').Replace(#10, '\n');
end;

procedure CheckFile(const APath: string);
var
  Text   : string;
  Rows   : TArray<TCommentFactRow>;
  Kept   : TList<TCommentFactRow>;
  Row    : TCommentFactRow;
  Today  : TList<string>;
  Table  : TList<string>;
  Regions: TList<TDocCommentRegion>;
  Reg    : TDocCommentRegion;
  Lines  : TArray<string>;
  Bearing: TArray<Boolean>;
  M      : TReviewMarker;
  Bk     : TBookmark;
  I      : Integer;
  LineStartOf: TArray<Integer>;

  function CharCol(const ARow: TCommentFactRow): Integer;
  begin
    Result:= ARow.StartOffset + 1 - LineStartOf[ARow.Line - 1] + 1;
  end;

  procedure FoldDocRows;
  var
    J        : Integer;
    Cur      : TCommentFactRow;
    CurOne   : Boolean;
    CurTrl   : Boolean;
    CurEnd   : Integer;
    CurText  : string;
    Started  : Boolean;
    NxtOne   : Boolean;
    NxtTrl   : Boolean;
    Joins    : Boolean;

    function Body(const ARow: TCommentFactRow; AOne: Boolean): string;
    begin
      Result:= Copy(ARow.Text, if AOne then 5 else 4, MaxInt);
    end;

    procedure Flush;
    begin
      if Started then
        Table.Add(Format('L%d-%d C%d %s %s', [Cur.Line, CurEnd, CharCol(Cur), if CurOne then '///1' else '///', Esc(CurText)]));
    end;

  begin
    Started:= False;
    CurOne := False;
    CurTrl := False;
    CurEnd := 0;
    for J:= 0 to Kept.Count - 1 do
    begin
      if Kept[J].Kind <> '///' then Continue;
      NxtOne:= Kept[J].Text.StartsWith('///1');
      NxtTrl:= Kept[J].AnchorKind = 'end-of-line';
      Joins := Started and (NxtOne = CurOne) and (Kept[J].Line = CurEnd + 1) and not (NxtTrl and not CurTrl);
      if Joins then
      begin
        CurText:= CurText + sLineBreak + Body(Kept[J], NxtOne);
        CurEnd := Kept[J].EndLine;
      end
      else
      begin
        Flush;
        Cur    := Kept[J];
        CurOne := NxtOne;
        CurTrl := NxtTrl;
        CurEnd := Kept[J].EndLine;
        CurText:= Body(Kept[J], NxtOne);
        Started:= True;
      end;
    end;
    Flush;
  end;

  procedure ComputeLineStarts;
  var
    L: TList<Integer>;
    J: Integer;
  begin
    L:= TList<Integer>.Create;
    try
      L.Add(1);
      J:= 1;
      while J <= Length(Text) do
      begin
        if (Text[J] = #13) and (J < Length(Text)) and (Text[J + 1] = #10) then Inc(J);
        if CharInSet(Text[J], [#13, #10]) then L.Add(J + 1);
        Inc(J);
      end;
      LineStartOf:= L.ToArray;
    finally
      L.Free;
    end;
  end;

begin
  Text:= ReadSource(APath);
  Watch.Start;
  Rows:= ExtractCommentFacts(APath, Text, nil);
  Watch.Stop;
  Inc(RowCount, Length(Rows));
  ComputeLineStarts;
  Kept := TList<TCommentFactRow>.Create;
  Today:= TList<string>.Create;
  Table:= TList<string>.Create;
  try
    for Row in Rows do
      if (DropKind = '') or (Row.Kind <> DropKind) then Kept.Add(Row);

    { DOC }
    Regions:= TDocCommentScanner.Scan(Text);
    try
      for Reg in Regions do
        if Reg.Kind in [dckTripleSlash, dckTripleSlashOne] then
          Today.Add(Format('L%d-%d C%d %s %s', [Reg.StartLine, Reg.EndLine, Reg.StartCol,
            if Reg.Kind = dckTripleSlashOne then '///1' else '///', Esc(Reg.RawText)]));
    finally
      Regions.Free;
    end;
    FoldDocRows;
    Inc(Totals[0], Today.Count);
    Inc(Totals[1], Table.Count);
    Inc(Mismatches, Compare('DOC', APath, Today, Table));
    Today.Clear;
    Table.Clear;

    { OK }
    Lines  := SplitLines(Text);
    Bearing:= TReviewMarkers.MarkerBearingLines(Lines);
    for I:= 0 to High(Lines) do
      if (I <= High(Bearing)) and Bearing[I] then
        for M in TReviewMarkers.Parse(Lines[I]) do
          Today.Add(Format('L%d %s@%s %s', [I + 1, M.RuleId, M.Hash, M.Reason]));
    for Row in Kept do
      if Row.Kind = '//' then
        for M in TReviewMarkers.Parse(Row.Text) do
          Table.Add(Format('L%d %s@%s %s', [Row.Line, M.RuleId, M.Hash, M.Reason]));
    Inc(Totals[2], Today.Count);
    Inc(Totals[3], Table.Count);
    Inc(Mismatches, Compare('OK', APath, Today, Table));
    Today.Clear;
    Table.Clear;

    { BK }
    for Bk in TBookmarks.Scan(Text) do
      Today.Add(Format('L%d O%d %s %s @%s %s', [Bk.Line, Bk.Offset, Bk.Kind, Bk.Code, Bk.Hash, Bk.Reason]));
    for Row in Kept do
      if (Row.Kind = '//') or (Row.Kind = '///') then
        for Bk in TBookmarks.Scan(Row.Text) do
          Table.Add(Format('L%d O%d %s %s @%s %s', [Row.Line, Row.StartOffset + Bk.Offset, Bk.Kind, Bk.Code, Bk.Hash, Bk.Reason]));
    Inc(Totals[4], Today.Count);
    Inc(Totals[5], Table.Count);
    Inc(Mismatches, Compare('BK', APath, Today, Table));
  finally
    Kept.Free;
    Today.Free;
    Table.Free;
  end;
end;

procedure Collect(const APath: string);
var
  F: string;
begin
  if TFile.Exists(APath) then
  begin
    if IsCommentFactsFile(APath) then Files.Add(APath);
    Exit;
  end;
  for F in TDirectory.GetFiles(APath, '*', TSearchOption.soAllDirectories) do
    if IsCommentFactsFile(F) then Files.Add(F);
end;

var
  A: Integer;
  F: string;
begin
  try
    Files:= TList<string>.Create;
    try
      A:= 1;
      while A <= ParamCount do
      begin
        if ParamStr(A) = '--drop-kind' then
        begin
          Inc(A);
          DropKind:= ParamStr(A);
        end
        else Collect(ParamStr(A));
        Inc(A);
      end;
      if Files.Count = 0 then
      begin
        Writeln('usage: CommentFactsParity [--drop-kind <kind>] <dir-or-file> ...');
        ExitCode:= 2;
        Exit;
      end;
      Files.Sort;
      Watch:= TStopwatch.Create;
      for F in Files do CheckFile(F);
      Writeln(Format('SUMMARY files=%d rows=%d doc=%d/%d ok=%d/%d bk=%d/%d mismatches=%d extract_ms=%d',
        [Files.Count, RowCount, Totals[0], Totals[1], Totals[2], Totals[3], Totals[4], Totals[5], Mismatches,
         Watch.ElapsedMilliseconds]));
      if Mismatches > 0 then ExitCode:= 1;
    finally
      Files.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln('FATAL ', E.ClassName, ': ', E.Message);
      ExitCode:= 3;
    end;
  end;
end.
