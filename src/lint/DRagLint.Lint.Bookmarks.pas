unit DRagLint.Lint.Bookmarks;

{ Comment-anchor bookmarks (E-BOOKMARKS, wave 146 lane g2; spec questions answered in
  docs\DECISION-2026-10-28-comment-anchors.md, rulings in INBOX-bookmarks-as-comment-anchors.md).

    // dl:bk3                          a USER bookmark: N is any integer
    // dl:bk:A7K3QX -- why it is here  a DL (engine/AI) bookmark: 6-8 alphanumerics
    // dl:bk3@7f3a                     either kind may carry the construct hash

  The anchor IS a comment, so it moves with its code; no (file,line) bookmark does.
  Bookmarks are ordinary committed comments (owner 2026-09-22: they stay unless the
  user erases them), so this unit only READS: list and find. strip / restore are not here.

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
    Kind  : string;
    Code  : string;
    Hash  : string;
    Reason: string;
  end;

  /// <summary>Reads `dl:bk` comment anchors. Pure; no I/O.</summary>
  TBookmarks = class
  public
    /// <summary>Every bookmark in AText, in source order.</summary>
    /// <param name="AText">Whole source text; any line ending.</param>
    /// <returns>[] when there is none. A tag that is malformed (a DL tag whose code is
    /// not 6-8 alphanumerics, a user tag whose number is not digits) is skipped.</returns>
    /// <remarks>Thread-safe: no state.</remarks>
    class function Scan(const AText: string): TArray<TBookmark>; static;

    /// <summary>The bookmarks of AText whose Code equals ACode (case-insensitive for the
    /// tagged kind, exact digits for the numbered kind).</summary>
    class function Find(const AText, ACode: string): TArray<TBookmark>; static;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections;

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
  N, I, Line, Stop: Integer;
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
        Inc(I, 2);
        while (I <= N) and CharInSet(AText[I], [' ', #9]) do Inc(I);
        Stop:= I;
        while (Stop <= N) and not CharInSet(AText[Stop], [#13, #10]) do Inc(Stop);
        if ParseTail(Copy(AText, I, Stop - I), Line, Bk) then Found.Add(Bk);
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

end.
