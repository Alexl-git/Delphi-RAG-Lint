unit DRagLint.Core.UsesInsert;

{ Pure text helpers for adding a unit to a Delphi unit's interface or
  implementation uses clause, and the message contract of the lint rule
  unit-missing-from-uses.

  SHARED by the engine (the rule, its LSP code action and its `lint --fix`
  fixer) and by the IDE plugin (the Ctrl+Alt+U quick-fix), so every path that
  edits a uses clause for that rule computes the SAME insertion from the SAME
  text, and the plugin reads the section the engine decided out of the SAME
  message the engine wrote. Depends on the RTL only -- keep it that way: the
  design-time package compiles it. }

interface

type
  /// <summary>Which uses clause of a unit an insertion targets.</summary>
  TUsesSection = (usInterface, usImplementation);

  /// <summary>One text insertion that adds unit names to a uses clause.</summary>
  /// <remarks>Line and Col are 1-based; Text goes immediately BEFORE column Col
  /// of line Line (Col = Length(line) + 1 appends). Text uses CRLF line breaks
  /// and is 7-bit ASCII whenever the unit names are.</remarks>
  TUsesInsertion = record
    Line: Integer;
    Col : Integer;
    Text: string ;
  end;

  /// <summary>Uses-clause text analysis and editing over a unit's lines.</summary>
  /// <remarks>Stateless and pure: every routine reads only its arguments.
  /// Comments, strings and compiler directives are skipped by a small
  /// tokenizer, so a `uses` or `;` inside a comment never counts. Thread-safe.</remarks>
  TUsesText = class
  public
    /// <summary>The Delphi keyword of a section.</summary>
    /// <param name="ASection">The section.</param>
    /// <returns>'interface' or 'implementation'.</returns>
    class function SectionWord(ASection: TUsesSection): string; static;
    /// <summary>True when the text is a UNIT (its first token is `unit`), the
    /// only kind of file that has interface and implementation uses clauses.</summary>
    /// <param name="ALines">The file's lines, without line breaks.</param>
    /// <returns>False for a program, library, package or an empty text.</returns>
    class function IsUnitText(const ALines: TArray<string>): Boolean; static;
    /// <summary>The 1-based line of the `implementation` keyword.</summary>
    /// <param name="ALines">The file's lines.</param>
    /// <returns>0 when the text is not a unit or has no implementation keyword.</returns>
    class function ImplementationLine(const ALines: TArray<string>): Integer; static;
    /// <summary>Every unit name listed in any uses clause of the text, as written.</summary>
    /// <param name="ALines">The file's lines.</param>
    /// <returns>The names in source order; empty when there is no uses clause.</returns>
    class function UsesEntries(const ALines: TArray<string>): TArray<string>; static;
    /// <summary>True when a uses entry and a unit name denote the same unit,
    /// allowing for unit scope names (`Classes` is `System.Classes`).</summary>
    /// <param name="AEntry">A name as written in a uses clause.</param>
    /// <param name="AUnit">A unit name.</param>
    /// <returns>True on a case-insensitive match of the whole name or of a
    /// dotted suffix in either direction.</returns>
    class function SameUnit(const AEntry, AUnit: string): Boolean; static;
    /// <summary>True when AUnit is already named in any uses clause of the text.</summary>
    /// <param name="ALines">The file's lines.</param>
    /// <param name="AUnit">The unit name.</param>
    /// <returns>True when listed (SameUnit) in the interface or the implementation uses.</returns>
    class function UnitInUses(const ALines: TArray<string>; const AUnit: string): Boolean; static;
    /// <summary>Builds the insertion that adds AUnits to the ASection uses clause,
    /// keeping the clause's own layout.</summary>
    /// <param name="ALines">The file's lines.</param>
    /// <param name="AUnits">The unit names to add; names already listed anywhere
    /// in the text are dropped.</param>
    /// <param name="ASection">The target clause.</param>
    /// <param name="AIns">Out: the insertion.</param>
    /// <returns>False when the text is not a unit, has no keyword for ASection,
    /// has an unterminated uses clause, or every name is already listed.</returns>
    /// <remarks>An existing clause is extended just before its terminating `;`:
    /// `, X` when the clause is written on one line, `,`+CRLF+indent+`X` when
    /// its last entry starts its own line, CRLF+indent+`, X` for the comma-first
    /// style. A missing clause is created right after the section keyword as
    /// CRLF CRLF `uses` CRLF `  X;`.</remarks>
    class function BuildInsertion(const ALines: TArray<string>; const AUnits: array of string;
      ASection: TUsesSection; out AIns: TUsesInsertion): Boolean; static;
    /// <summary>Applies an insertion to the lines and returns the resulting
    /// line of ALines[AIns.Line - 1] (which may now hold CRLF breaks).</summary>
    /// <param name="ALines">The file's lines.</param>
    /// <param name="AIns">An insertion BuildInsertion made for these lines.</param>
    /// <returns>The edited line; ALines unchanged when AIns.Line is out of range.</returns>
    class function ApplyToLine(const ALines: TArray<string>; const AIns: TUsesInsertion): string; static;
    /// <summary>The rule message for a name declared in exactly one unit.</summary>
    /// <param name="AName">The unresolved identifier.</param>
    /// <param name="AUnit">The unit that declares it.</param>
    /// <param name="ASection">The clause the fix adds it to.</param>
    /// <param name="ASuffix">'' or a parenthesised note (a cycle), appended after a space.</param>
    /// <returns>'''AName'' is declared in unit AUnit -- add it to the &lt;section&gt; uses clause[ suffix]'.</returns>
    class function FormatMessage(const AName, AUnit: string; ASection: TUsesSection; const ASuffix: string): string; static;
    /// <summary>Reads the unit and the section back out of a FormatMessage text.</summary>
    /// <param name="AMsg">A diagnostic message.</param>
    /// <param name="AUnit">Out: the unit to add.</param>
    /// <param name="ASection">Out: the clause to add it to.</param>
    /// <returns>False for any other message, including the ambiguous form
    /// ("is declared in units A, B").</returns>
    class function ParseMessage(const AMsg: string; out AUnit: string; out ASection: TUsesSection): Boolean; static;
  end;

implementation

uses
  System.SysUtils, System.StrUtils;

type
  TUTok = record
    Text  : string ; { identifiers keep their dots: System.SysUtils is one token }
    Line  : Integer;
    Col   : Integer;
    EndCol: Integer; { exclusive }
    First : Boolean; { first token on its line }
  end;

const
  CRLF         = #13#10;
  TOKEN_GROWTH = 64; { extra token slots per array growth }

function IsIdentStart(C: Char): Boolean;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '_', '&']);
end;

function IsIdentChar(C: Char): Boolean;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

{ Tokenizes the whole text: identifiers (dotted names joined) and single
  punctuation characters. Comments, directives, strings, char codes and
  numbers produce no token. }
function Tokenize(const ALines: TArray<string>): TArray<TUTok>;  // dl:ok cognitive-complexity@682a -- REVIEWED 2026-10-29: a flat lexer state machine (code / brace / paren-star, strings, numbers, idents); each branch is one token class
var
  State: Integer; { 0 code, 1 inside braces, 2 inside paren-star }
  Count: Integer;

  procedure Add(const AText: string; ALine, ACol, AEnd: Integer; AFirst: Boolean);
  begin
    if Count = Length(Result) then SetLength(Result, Count * 2 + TOKEN_GROWTH);
    Result[Count].Text  := AText;
    Result[Count].Line  := ALine;
    Result[Count].Col   := ACol;
    Result[Count].EndCol:= AEnd;
    Result[Count].First := AFirst;
    Inc(Count);
  end;

begin
  Result:= nil;
  Count := 0;
  State := 0;
  for var I: Integer:= 0 to High(ALines) do
  begin
    var S: string:= ALines[I];
    var N: Integer:= Length(S);
    var P: Integer:= 1;
    var FirstOnLine: Boolean:= True;
    while P <= N do
    begin
      if State = 1 then
      begin
        var Q: Integer:= PosEx('}', S, P);
        if Q = 0 then P:= N + 1
        else
        begin
          P    := Q + 1;
          State:= 0;
        end;
        Continue;
      end;
      if State = 2 then
      begin
        var Q: Integer:= PosEx('*)', S, P);
        if Q = 0 then P:= N + 1
        else
        begin
          P    := Q + 2;
          State:= 0;
        end;
        Continue;
      end;
      var C: Char:= S[P];
      if CharInSet(C, [' ', #9, #13, #10]) then Inc(P)
      else if (C = '/') and (P < N) and (S[P + 1] = '/') then P:= N + 1
      else if C = '{' then
      begin
        State:= 1;
        Inc(P);
      end
      else if (C = '(') and (P < N) and (S[P + 1] = '*') then
      begin
        State:= 2;
        Inc(P, 2);
      end
      else if C = '''' then
      begin
        Inc(P);
        while P <= N do
        begin
          if S[P] = '''' then
          begin
            if (P < N) and (S[P + 1] = '''') then Inc(P, 2)
            else Break;
          end
          else Inc(P);
        end;
        Inc(P);
      end
      else if C = '#' then
      begin
        Inc(P);
        while (P <= N) and CharInSet(S[P], ['0'..'9', '$', 'A'..'F', 'a'..'f']) do Inc(P);
      end
      else if CharInSet(C, ['0'..'9', '$']) then
      begin
        Inc(P);
        while (P <= N) and CharInSet(S[P], ['0'..'9', 'A'..'F', 'a'..'f', '.', 'x', 'X']) do Inc(P);
      end
      else if IsIdentStart(C) then
      begin
        var B: Integer:= P;
        Inc(P);
        while P <= N do
        begin
          if IsIdentChar(S[P]) then Inc(P)
          else if (S[P] = '.') and (P < N) and IsIdentStart(S[P + 1]) then Inc(P)
          else Break;
        end;
        Add(Copy(S, B, P - B), I + 1, B, P, FirstOnLine);
        FirstOnLine:= False;
      end
      else
      begin
        Add(C, I + 1, P, P + 1, FirstOnLine);
        FirstOnLine:= False;
        Inc(P);
      end;
    end; // while
  end; // for
  SetLength(Result, Count);
end;

{ Index of the section keyword token, or -1. Requires a unit text. }
function SectionTokenIndex(const AToks: TArray<TUTok>; ASection: TUsesSection): Integer;
var
  IntfAt: Integer;
begin
  Result:= -1;
  if (Length(AToks) = 0) or not SameText(AToks[0].Text, 'unit') then Exit;
  IntfAt:= -1;
  for var K: Integer:= 0 to High(AToks) do
    if SameText(AToks[K].Text, 'interface') then
    begin
      IntfAt:= K;
      Break;
    end;
  if IntfAt < 0 then Exit;
  if ASection = usInterface then Exit(IntfAt);
  for var K: Integer:= IntfAt + 1 to High(AToks) do
    if SameText(AToks[K].Text, 'implementation') then Exit(K);
end;

{ The unit names of the uses clause that starts at token AUsesAt (the `uses`
  keyword), and the index of its terminating `;` in ASemiAt (-1 when none). }
function ClauseEntries(const AToks: TArray<TUTok>; AUsesAt: Integer; out ASemiAt: Integer): TArray<Integer>;
var
  ExpectName: Boolean;
begin
  Result    := nil;
  ASemiAt   := -1;
  ExpectName:= True;
  for var K: Integer:= AUsesAt + 1 to High(AToks) do
  begin
    var T: string:= AToks[K].Text;
    if T = ';' then
    begin
      ASemiAt:= K;
      Exit;
    end;
    if T = ',' then ExpectName:= True
    else if ExpectName and IsIdentStart(T[1]) then
    begin
      Result    := Result + [K];
      ExpectName:= False;
    end;
  end;
end;

class function TUsesText.SectionWord(ASection: TUsesSection): string;
begin
  Result:= if ASection = usInterface then 'interface' else 'implementation';
end;

class function TUsesText.IsUnitText(const ALines: TArray<string>): Boolean;
var
  Toks: TArray<TUTok>;
begin
  Toks  := Tokenize(ALines);
  Result:= (Length(Toks) > 0) and SameText(Toks[0].Text, 'unit');
end;

class function TUsesText.ImplementationLine(const ALines: TArray<string>): Integer;
var
  Toks: TArray<TUTok>;
  K   : Integer;
begin
  Toks:= Tokenize(ALines);
  K   := SectionTokenIndex(Toks, usImplementation);
  Result:= if K < 0 then 0 else Toks[K].Line;
end;

class function TUsesText.UsesEntries(const ALines: TArray<string>): TArray<string>;
var
  Toks: TArray<TUTok>;
  Semi: Integer;
begin
  Result:= nil;
  Toks  := Tokenize(ALines);
  var K: Integer:= 0;
  while K <= High(Toks) do
  begin
    if SameText(Toks[K].Text, 'uses') or SameText(Toks[K].Text, 'contains') then
    begin
      for var E: Integer in ClauseEntries(Toks, K, Semi) do Result:= Result + [Toks[E].Text];
      if Semi < 0 then Break;
      K:= Semi;
    end;
    Inc(K);
  end;
end;

class function TUsesText.SameUnit(const AEntry, AUnit: string): Boolean;
begin
  Result:= (AEntry <> '') and (AUnit <> '') and
    (SameText(AEntry, AUnit) or EndsText('.' + AEntry, AUnit) or EndsText('.' + AUnit, AEntry));
end;

class function TUsesText.UnitInUses(const ALines: TArray<string>; const AUnit: string): Boolean;
begin
  for var E: string in UsesEntries(ALines) do
    if SameUnit(E, AUnit) then Exit(True);
  Result:= False;
end;

{ The leading whitespace of ALine up to column ACol, or two spaces when what
  precedes ACol is not pure whitespace. }
function IndentBefore(const ALine: string; ACol: Integer): string;
begin
  Result:= Copy(ALine, 1, ACol - 1);
  if Trim(Result) <> '' then Result:= '  ';
end;

class function TUsesText.BuildInsertion(const ALines: TArray<string>; const AUnits: array of string;
  ASection: TUsesSection; out AIns: TUsesInsertion): Boolean;
var
  Toks  : TArray<TUTok>;
  Kw    : Integer;
  Semi  : Integer;
  Names : TArray<string>;
  Listed: TArray<string>;
begin
  AIns  := Default(TUsesInsertion);
  Result:= False;
  Listed:= UsesEntries(ALines);
  Names := nil;
  for var U: string in AUnits do
  begin
    if Trim(U) = '' then Continue;
    var Dup: Boolean:= False;
    for var E: string in Listed + Names do
      if SameUnit(E, Trim(U)) then
      begin
        Dup:= True;
        Break;
      end;
    if not Dup then Names:= Names + [Trim(U)];
  end;
  if Length(Names) = 0 then Exit;
  Toks:= Tokenize(ALines);
  Kw  := SectionTokenIndex(Toks, ASection);
  if Kw < 0 then Exit;

  if (Kw < High(Toks)) and SameText(Toks[Kw + 1].Text, 'uses') then
  begin
    var Entries: TArray<Integer>:= ClauseEntries(Toks, Kw + 1, Semi);
    if (Semi < 0) or (Length(Entries) = 0) then Exit;
    var LastAt: Integer:= Entries[High(Entries)];
    var LastTok: TUTok:= Toks[LastAt];
    var Sep: string;
    var Lead: string;
    if (LastAt > 0) and (Toks[LastAt - 1].Text = ',') and Toks[LastAt - 1].First then
    begin
      { comma-first: "  , System.Math;" -> "  , System.Math" CRLF "  , X;" }
      Lead:= CRLF + IndentBefore(ALines[Toks[LastAt - 1].Line - 1], Toks[LastAt - 1].Col) + ', ';
      Sep := CRLF + IndentBefore(ALines[Toks[LastAt - 1].Line - 1], Toks[LastAt - 1].Col) + ', ';
    end
    else if LastTok.First and (LastTok.Line <> Toks[Kw + 1].Line) then
    begin
      { one entry per line: "  B;" -> "  B," CRLF "  X;" }
      Lead:= ',' + CRLF + IndentBefore(ALines[LastTok.Line - 1], LastTok.Col);
      Sep := Lead;
    end
    else
    begin
      Lead:= ', ';
      Sep := ', ';
    end;
    var Txt: string:= Lead + Names[0];
    for var J: Integer:= 1 to High(Names) do Txt:= Txt + Sep + Names[J];
    AIns.Line:= Toks[Semi].Line;
    AIns.Col := Toks[Semi].Col;
    AIns.Text:= Txt;
  end
  else
  begin
    var Txt: string:= CRLF + CRLF + 'uses' + CRLF + '  ' + Names[0];
    for var J: Integer:= 1 to High(Names) do Txt:= Txt + ', ' + Names[J];
    AIns.Line:= Toks[Kw].Line;
    AIns.Col := Toks[Kw].EndCol;
    AIns.Text:= Txt + ';';
  end;
  Result:= True;
end;

class function TUsesText.ApplyToLine(const ALines: TArray<string>; const AIns: TUsesInsertion): string;
begin
  Result:= '';
  if (AIns.Line < 1) or (AIns.Line > Length(ALines)) then Exit;
  var S: string:= ALines[AIns.Line - 1];
  Result:= Copy(S, 1, AIns.Col - 1) + AIns.Text + Copy(S, AIns.Col, MaxInt);
end;

class function TUsesText.FormatMessage(const AName, AUnit: string; ASection: TUsesSection; const ASuffix: string): string;
begin
  Result:= '''' + AName + ''' is declared in unit ' + AUnit + ' -- add it to the ' + SectionWord(ASection) + ' uses clause';
  if ASuffix <> '' then Result:= Result + ' ' + ASuffix;
end;

class function TUsesText.ParseMessage(const AMsg: string; out AUnit: string; out ASection: TUsesSection): Boolean;
const
  UNIT_MARK = ' is declared in unit ';
  SECT_MARK = ' -- add it to the ';
var
  P: Integer;
  Q: Integer;
begin
  Result  := False;
  AUnit   := '';
  ASection:= usImplementation;
  P:= Pos(UNIT_MARK, AMsg);
  if P = 0 then Exit;
  Inc(P, Length(UNIT_MARK));
  Q:= P;
  while (Q <= Length(AMsg)) and (IsIdentChar(AMsg[Q]) or (AMsg[Q] = '.')) do Inc(Q);
  AUnit:= Copy(AMsg, P, Q - P);
  if AUnit = '' then Exit;
  P:= PosEx(SECT_MARK, AMsg, Q);
  if P = 0 then Exit;
  var Tail: string:= Copy(AMsg, P + Length(SECT_MARK), MaxInt);
  if StartsText('interface ', Tail) then ASection:= usInterface
  else if StartsText('implementation ', Tail) then ASection:= usImplementation
  else Exit;
  Result:= True;
end;

end.
