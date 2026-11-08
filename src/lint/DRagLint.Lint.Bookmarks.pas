unit DRagLint.Lint.Bookmarks;

{ Comment-anchor bookmarks (E-BOOKMARKS, wave 146 lane g2; spec questions answered in
  docs\DECISION-2026-10-28-comment-anchors.md, rulings in INBOX-bookmarks-as-comment-anchors.md).

    // dl:bk3                          a USER bookmark: N is any integer
    // dl:bk:A7K3QX -- why it is here  a DL (engine/AI) bookmark: 6-8 alphanumerics
    // dl:bk3@7f3a                     either kind may carry the construct hash

  The anchor IS a comment, so it moves with its code; no (file,line) bookmark does.
  Bookmarks are ordinary committed comments (owner 2026-09-22: they stay unless the
  user erases them). Scan / Find only read; Strip / Restore are the USER-invoked pair behind
  bookmarks-strip / bookmarks-restore (wave 147 lane G2): Strip takes the anchors out and
  records every removed character, Restore puts them back byte-identical. All four are pure.

  The scanner tracks brace, star-paren and slash-slash comments plus string state over
  the WHOLE text, so a tag quoted inside a string literal or sitting in the middle of
  a line comment's prose is not a bookmark: the tag must be the FIRST token of its
  slash-slash comment (the same rule the dl:shared reader follows). The bookmark form
  inside braces or star-paren comments is not recognised: only the slash-slash form is
  specified. }

interface

type
  /// <summary>One bookmark found in a source text.</summary>
  /// <remarks>Kind is 'user' (numbered) or 'dl' (tagged). Code is the number or the
  /// 6-8 character tag, exactly as written. Hash and Reason are '' when absent.</remarks>
  TBookmark = record
    Line  : Integer;
    Offset: Integer; // 1-based index in the scanned text of the // that opens the anchor
    Kind  : string;
    Code  : string;
    Hash  : string;
    Reason: string;
  end;

  /// <summary>One anchor taken out by TBookmarks.Strip: everything Restore needs to put it back.</summary>
  /// <remarks>Mode 'trailing': Text (the blanks before the comment plus the comment) was cut
  /// from line StrippedLine at character Col, and Anchor is that line as the strip left it.
  /// Mode 'line': Text is the whole removed line WITH its line break, and it went back BEFORE
  /// line StrippedLine, whose text is Anchor -- or at the end of the text when AnchorEof.
  /// Line is the anchor's line in the ORIGINAL text; Bookmark is what Scan read there.</remarks>
  TBookmarkEdit = record
    Line        : Integer;
    StrippedLine: Integer;
    Col         : Integer;
    Mode        : string;
    Text        : string;
    Anchor      : string;
    AnchorEof   : Boolean;
    Bookmark    : TBookmark;
  end;

  /// <summary>Reads `dl:bk` comment anchors. Pure; no I/O.</summary>
  TBookmarks = class
  public
    /// <summary>AText without its bookmark anchors (all, or only those whose code is ACode).</summary>
    /// <param name="AText">Whole source text; any line ending, kept as it is.</param>
    /// <param name="ACode">'' strips every anchor; otherwise only the anchors Find(AText, ACode) returns.</param>
    /// <param name="AEdits">One edit per removed anchor, in source order; [] when none.</param>
    /// <returns>The stripped text; equal to AText when AEdits is [].</returns>
    /// <remarks>A trailing anchor loses the comment and the blanks before it; an anchor alone
    /// on its line loses the whole line including its line break. Lines end at #10 (a #13
    /// before it belongs to the break). Restore(Result, AEdits) returns AText exactly.</remarks>
    class function Strip(const AText, ACode: string; out AEdits: TArray<TBookmarkEdit>): string; static;

    /// <summary>Puts the anchors a Strip removed back into ACurrent.</summary>
    /// <param name="ACurrent">The text now on disk: the stripped text, or that text edited since.</param>
    /// <param name="AEdits">The edits Strip returned, in source order.</param>
    /// <param name="ALines">Per edit, the 1-based line of the anchor in the result; 0 = unplaced.</param>
    /// <returns>The restored text when every edit was placed; ACurrent unchanged otherwise.</returns>
    /// <remarks>An edit is placed on line StrippedLine when that line still reads Anchor, else on
    /// the ONE line that reads Anchor; no such line, several, or a second trailing anchor on the
    /// same line leave it unplaced. An end-of-text own-line anchor is unplaced when the text no
    /// longer ends with a line break. On the unedited stripped text every edit lands where it
    /// was, so the result is AText byte for byte.</remarks>
    class function Restore(const ACurrent: string; const AEdits: TArray<TBookmarkEdit>;
      out ALines: TArray<Integer>): string; static;

    /// <summary>Every bookmark in AText, in source order.</summary>
    /// <param name="AText">Whole source text; any line ending.</param>
    /// <returns>[] when there is none. A tag that is malformed (a DL tag whose code is
    /// not 6-8 alphanumerics, a user tag whose number is not digits) is skipped.</returns>
    /// <remarks>Thread-safe: no state.</remarks>
    class function Scan(const AText: string): TArray<TBookmark>; static;

    /// <summary>The bookmarks of AText whose Code equals ACode (case-insensitive for the
    /// tagged kind, exact digits for the numbered kind).</summary>
    /// <param name="AText">The source text.</param>
    /// <param name="ACode">The code to look for.</param>
    /// <returns>The matching bookmarks; [] when there is none.</returns>
    class function Find(const AText, ACode: string): TArray<TBookmark>; static;
  end;

implementation

uses
  System.SysUtils, System.Math, System.Generics.Collections;

const
  BK_TAG     = 'dl:bk';
  CODE_MIN   = 6; // shortest DL tag
  CODE_MAX   = 8; // longest DL tag
  REASON_SEP = '--';

function IsDigit(AChar: Char): Boolean;
begin
  Result:= (AChar >= '0') and (AChar <= '9');
end;

function IsAlnum(AChar: Char): Boolean;
begin
  Result:= IsDigit(AChar) or ((AChar >= 'A') and (AChar <= 'Z')) or ((AChar >= 'a') and (AChar <= 'z'));
end;

{ Parses the text that FOLLOWS `//` and its blanks; ARest starts at the tag. }
function ParseTail(const ARest: string; ALine: Integer; out ABookmark: TBookmark): Boolean;
var
  P, Q: Integer;
  Tail: string;
begin
  Result:= False;
  ABookmark:= Default(TBookmark);
  if not SameText(Copy(ARest, 1, Length(BK_TAG)), BK_TAG) then Exit;
  P:= Length(BK_TAG) + 1;
  ABookmark.Line  := ALine;
  ABookmark.Hash  := '';
  ABookmark.Reason:= '';
  if (P <= Length(ARest)) and (ARest[P] = ':') then
  begin
    Inc(P);
    Q:= P;
    while (Q <= Length(ARest)) and IsAlnum(ARest[Q]) do Inc(Q);
    if (Q - P < CODE_MIN) or (Q - P > CODE_MAX) then Exit;
    ABookmark.Kind:= 'dl';
    ABookmark.Code:= Copy(ARest, P, Q - P);
  end
  else
  begin
    Q:= P;
    while (Q <= Length(ARest)) and IsDigit(ARest[Q]) do Inc(Q);
    if Q = P then Exit;
    ABookmark.Kind:= 'user';
    ABookmark.Code:= Copy(ARest, P, Q - P);
  end;
  { a code run into more identifier text (dl:bk3x, dl:bk:A7K3QXZZZ) is not a tag }
  if (Q <= Length(ARest)) and IsAlnum(ARest[Q]) then Exit;
  Tail:= Copy(ARest, Q, MaxInt);
  if (Tail <> '') and (Tail[1] = '@') then
  begin
    Q:= 2;
    while (Q <= Length(Tail)) and IsAlnum(Tail[Q]) do Inc(Q);
    ABookmark.Hash:= Copy(Tail, 2, Q - 2);
    Tail:= Copy(Tail, Q, MaxInt);
  end;
  Tail:= Trim(Tail);
  if Copy(Tail, 1, Length(REASON_SEP)) = REASON_SEP then ABookmark.Reason:= Trim(Copy(Tail, Length(REASON_SEP) + 1, MaxInt));
  Result:= True;
end;

class function TBookmarks.Scan(const AText: string): TArray<TBookmark>;
var
  Found: TList<TBookmark>;
  N, I, Line, Stop, Start: Integer;
  InBrace, InParen, InStr: Boolean;
  Bk: TBookmark;
begin
  Found:= TList<TBookmark>.Create;
  try
    N      := Length(AText);
    I      := 1;
    Line   := 1;
    InBrace:= False;
    InParen:= False;
    InStr  := False;
    while I <= N do
    begin
      if AText[I] = #10 then
      begin
        Inc(Line);
        InStr:= False;
        Inc(I);
      end
      else if InBrace then
      begin
        InBrace:= AText[I] <> '}';
        Inc(I);
      end
      else if InParen then
      begin
        if (AText[I] = '*') and (I < N) and (AText[I + 1] = ')') then
        begin
          InParen:= False;
          Inc(I);
        end;
        Inc(I);
      end
      else if InStr then
      begin
        InStr:= AText[I] <> '''';
        Inc(I);
      end
      else if AText[I] = '''' then
      begin
        InStr:= True;
        Inc(I);
      end
      else if AText[I] = '{' then
      begin
        InBrace:= True;
        Inc(I);
      end
      else if (AText[I] = '(') and (I < N) and (AText[I + 1] = '*') then
      begin
        InParen:= True;
        Inc(I, 2);
      end
      else if (AText[I] = '/') and (I < N) and (AText[I + 1] = '/') then
      begin
        Start:= I;
        Inc(I, 2);
        while (I <= N) and CharInSet(AText[I], [' ', #9]) do Inc(I);
        Stop:= I;
        while (Stop <= N) and not CharInSet(AText[Stop], [#13, #10]) do Inc(Stop);
        if ParseTail(Copy(AText, I, Stop - I), Line, Bk) then
        begin
          Bk.Offset:= Start;
          Found.Add(Bk);
        end;
        I:= Stop;
      end
      else
        Inc(I);
    end;
    Result:= Found.ToArray;
  finally
    Found.Free;
  end;
end;

class function TBookmarks.Find(const AText, ACode: string): TArray<TBookmark>;
var
  All: TArray<TBookmark>;
  B: TBookmark;
  Hits: TList<TBookmark>;
begin
  All := Scan(AText);
  Hits:= TList<TBookmark>.Create;
  try
    for B in All do
      if SameText(B.Code, ACode) then Hits.Add(B);
    Result:= Hits.ToArray;
  finally
    Hits.Free;
  end;
end;

const
  MODE_TRAILING = 'trailing';
  MODE_LINE     = 'line';

type
  { One line of a text: Start is the 1-based index of its first character, Body its text
    without the line break, Brk the break itself (#13#10, #10, or '' on a last line). }
  TTextLine = record
    Start: Integer;
    Body : string;
    Brk  : string;
  end;

{ Lines end at #10, the rule Scan counts by; a #13 right before the #10 belongs to the break.
  A text that ends in a break has no empty last line. }
function SplitLines(const AText: string): TArray<TTextLine>;
var
  Lines: TList<TTextLine>;
  I, S: Integer;
  T: TTextLine;
begin
  Lines:= TList<TTextLine>.Create;
  try
    S:= 1;
    for I:= 1 to Length(AText) do
      if AText[I] = #10 then
      begin
        T.Start:= S;
        if (I > S) and (AText[I - 1] = #13) then
        begin
          T.Body:= Copy(AText, S, I - 1 - S);
          T.Brk := #13#10;
        end
        else
        begin
          T.Body:= Copy(AText, S, I - S);
          T.Brk := #10;
        end;
        Lines.Add(T);
        S:= I + 1;
      end;
    if S <= Length(AText) then
    begin
      T.Start:= S;
      T.Body := Copy(AText, S, MaxInt);
      T.Brk  := '';
      Lines.Add(T);
    end;
    Result:= Lines.ToArray;
  finally
    Lines.Free;
  end;
end;

function IsBlankRun(const AText: string): Boolean;
var
  C: Char;
begin
  for C in AText do
    if not CharInSet(C, [' ', #9]) then Exit(False);
  Result:= True;
end;

class function TBookmarks.Strip(const AText, ACode: string; out AEdits: TArray<TBookmarkEdit>): string;
var
  Hits: TArray<TBookmark>;
  Lines: TArray<TTextLine>;
  EditOfLine: TArray<Integer>;
  Pending: TList<Integer>;
  Buf: TStringBuilder;
  H: TBookmark;
  E: TBookmarkEdit;
  Body: string;
  K, Idx, Col, Cut, Stop, Kept, P: Integer;
begin
  Hits:= if ACode <> '' then Find(AText, ACode) else Scan(AText);
  AEdits:= [];
  if Length(Hits) = 0 then Exit(AText);
  Lines:= SplitLines(AText);
  SetLength(EditOfLine, Length(Lines));
  for Idx:= 0 to High(EditOfLine) do EditOfLine[Idx]:= -1;
  SetLength(AEdits, Length(Hits));
  for K:= 0 to High(Hits) do
  begin
    H  := Hits[K];
    Idx:= H.Line - 1;
    Body:= Lines[Idx].Body;
    Col := H.Offset - Lines[Idx].Start + 1;
    E := Default(TBookmarkEdit);
    E.Line    := H.Line;
    E.Bookmark:= H;
    if IsBlankRun(Copy(Body, 1, Col - 1)) then
    begin
      E.Mode:= MODE_LINE;
      E.Text:= Body + Lines[Idx].Brk;
    end
    else
    begin
      { the comment runs to the line end, or to a lone #13 as Scan reads it }
      Stop:= Col;
      while (Stop <= Length(Body)) and (Body[Stop] <> #13) do Inc(Stop);
      Cut:= Col;
      while (Cut > 1) and CharInSet(Body[Cut - 1], [' ', #9]) do Dec(Cut);
      E.Mode:= MODE_TRAILING;
      E.Col := Cut;
      E.Text:= Copy(Body, Cut, Stop - Cut);
      Lines[Idx].Body:= Copy(Body, 1, Cut - 1) + Copy(Body, Stop, MaxInt);
    end;
    AEdits[K]:= E;
    EditOfLine[Idx]:= K;
  end;
  Pending:= TList<Integer>.Create;
  Buf    := TStringBuilder.Create(Length(AText));
  try
    Kept:= 0;
    for Idx:= 0 to High(Lines) do
    begin
      K:= EditOfLine[Idx];
      if (K >= 0) and (AEdits[K].Mode = MODE_LINE) then
      begin
        Pending.Add(K);
        Continue;
      end;
      Inc(Kept);
      for P in Pending do
      begin
        AEdits[P].StrippedLine:= Kept;
        AEdits[P].Anchor      := Lines[Idx].Body;
      end;
      Pending.Clear;
      if K >= 0 then
      begin
        AEdits[K].StrippedLine:= Kept;
        AEdits[K].Anchor      := Lines[Idx].Body;
      end;
      Buf.Append(Lines[Idx].Body).Append(Lines[Idx].Brk);
    end;
    for P in Pending do
    begin
      AEdits[P].StrippedLine:= Kept + 1;
      AEdits[P].AnchorEof   := True;
    end;
    Result:= Buf.ToString;
  finally
    Buf.Free;
    Pending.Free;
  end;
end;

class function TBookmarks.Restore(const ACurrent: string; const AEdits: TArray<TBookmarkEdit>;
  out ALines: TArray<Integer>): string;
var
  Lines: TArray<TTextLine>;
  Target: TArray<Integer>;
  TrailUsed: TArray<Boolean>;
  Buf: TStringBuilder;
  E: TBookmarkEdit;
  N, K, I, T, Hits, OutLine: Integer;
  AllPlaced: Boolean;
  Body: string;
begin
  Lines:= SplitLines(ACurrent);
  N    := Length(Lines);
  SetLength(Target, Length(AEdits));
  SetLength(TrailUsed, N + 2);
  SetLength(ALines, Length(AEdits));
  AllPlaced:= True;
  for K:= 0 to High(AEdits) do
  begin
    E:= AEdits[K];
    T:= 0;
    if E.AnchorEof then
    begin
      if (N = 0) or (Lines[N - 1].Brk <> '') then T:= N + 1;
    end
    else if InRange(E.StrippedLine, 1, N) and (Lines[E.StrippedLine - 1].Body = E.Anchor) then
      T:= E.StrippedLine
    else
    begin
      Hits:= 0;
      for I:= 1 to N do
        if Lines[I - 1].Body = E.Anchor then
        begin
          Inc(Hits);
          T:= I;
        end;
      if Hits <> 1 then T:= 0;
    end;
    if (T > 0) and (E.Mode = MODE_TRAILING) then
    begin
      if (T > N) or TrailUsed[T] or (E.Col > Length(Lines[T - 1].Body) + 1) then T:= 0
      else TrailUsed[T]:= True;
    end;
    Target[K]:= T;
    ALines[K]:= 0;
    if T = 0 then AllPlaced:= False;
  end;
  Buf:= TStringBuilder.Create(Length(ACurrent));
  try
    OutLine:= 0;
    for I:= 1 to N + 1 do
    begin
      for K:= 0 to High(AEdits) do
        if (Target[K] = I) and (AEdits[K].Mode = MODE_LINE) then
        begin
          Buf.Append(AEdits[K].Text);
          Inc(OutLine);
          ALines[K]:= OutLine;
        end;
      if I > N then Break;
      Body:= Lines[I - 1].Body;
      Inc(OutLine);
      for K:= 0 to High(AEdits) do
        if (Target[K] = I) and (AEdits[K].Mode = MODE_TRAILING) then
        begin
          Body:= Copy(Body, 1, AEdits[K].Col - 1) + AEdits[K].Text + Copy(Body, AEdits[K].Col, MaxInt);
          ALines[K]:= OutLine;
        end;
      Buf.Append(Body).Append(Lines[I - 1].Brk);
    end;
    Result:= if AllPlaced then Buf.ToString else ACurrent;
  finally
    Buf.Free;
  end;
end;

end.
