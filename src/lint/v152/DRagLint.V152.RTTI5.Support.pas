unit DRagLint.V152.RTTI5.Support;

{ Wave v152 lane RTTI5 -- helpers of DRagLint.V152.RTTI5 (private to the lane).

  rtti-unavailable sub-kind anonymous-field-type (INBOX rtti-availability-rule, sub-check 5). Delphi
  does not allow an inline type in a PROPERTY declaration, so the anonymous types the note worries
  about live in FIELDS: `FData: array[0..3] of Integer;`, `FFlags: set of (fA, fB);`,
  `FRows: array of string;`, `FMode: (mA, mB);`. A published field of such a type has no type name
  for TRttiContext, an RTTI / ORM mapper or a DefineProperties stream to refer to; the named twin
  (`TData = array[0..3] of Integer; FData: TData;`) has.

  Text scan, no index: the unit lexes the source (comments, directives and strings are skipped),
  walks every `class` body and reports the fields of its published sections whose type starts with
  array / set of (...) / set of a literal or subrange / a parenthesised enum list. Not judged:
  private / protected / public sections, records, and the default visibility of a class declared
  under $M+ (a section-less member list is read as not published). }

interface

type
  /// <summary>One published field declaration whose type is spelled inline.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V152.RTTI5.Support.pas) ?, DRagLint.V152.RTTI5.Support.FindAnonymousFieldTypes (DRagLint.V152.RTTI5.Support.pas) ?, DRagLint.V152.RTTI5.Support.TAnonScanner.Create (DRagLint.V152.RTTI5.Support.pas) ?, DRagLint.V152.RTTI5.Support.TAnonScanner.ReadField (DRagLint.V152.RTTI5.Support.pas), DRagLint.V152.RTTI5.Support.TAnonScanner.Run (DRagLint.V152.RTTI5.Support.pas) ? (+2 more)</para>
  /// <para>Used in units: DRagLint.V152.RTTI5, DRagLint.V152.RTTI5.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TAnonField = record
    /// <summary>The class whose published section declares the field.</summary>
    ClassName: string;
    /// <summary>The field names of the declaration, comma separated (`FA, FB`).</summary>
    Names: string;
    /// <summary>The inline type as written, white space collapsed to single blanks.</summary>
    TypeText: string;
    /// <summary>1-based line of the first field name.</summary>
    Line: Integer;
    /// <summary>1-based column of the first field name.</summary>
    Col: Integer;
  end;

/// <summary>Finds the published fields of the classes in one source text whose type is an inline
/// array, an inline set of an anonymous enum or subrange, or an anonymous enum.</summary>
/// <param name="AText">The unit source; comments, directives and strings are ignored.</param>
/// <returns>One entry per field declaration (a `FA, FB: array[0..1] of Byte;` is one entry), in
/// source order; empty when there is none.</returns>
/// <remarks>
/// Pure and stateless; never raises on malformed source (an unbalanced body just ends the
/// scan of that class). A named type, a dynamic array of a named element type is NOT a named type:
/// `array of string` is reported, `TStrings`, `TArr4` and `TKinds` are not.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V152.RTTI5.TV152RTTI5Rules.CheckFile (DRagLint.V152.RTTI5.pas)</para>
/// <para>Calls: DRagLint.V152.RTTI5.Support.TAnonLexer.Create, DRagLint.V152.RTTI5.Support.TAnonLexer.Run, DRagLint.V152.RTTI5.Support.TAnonScanner.Create, DRagLint.V152.RTTI5.Support.TAnonScanner.Run</para>
/// <para>Returns: Scanner.Run</para>
/// <seealso cref="DRagLint.V152.RTTI5.Support.TAnonLexer.Create"/>
/// <seealso cref="DRagLint.V152.RTTI5.Support.TAnonLexer.Run"/>
/// <seealso cref="DRagLint.V152.RTTI5.Support.TAnonScanner.Create"/>
/// <seealso cref="DRagLint.V152.RTTI5.Support.TAnonScanner.Run"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindAnonymousFieldTypes(const AText: string): TArray<TAnonField>;

/// <summary>Builds the finding message of one anonymous published field.</summary>
/// <param name="AField">The field found by <see cref="FindAnonymousFieldTypes"/>.</param>
/// <returns>A message starting with the sub-kind `anonymous-field-type:`.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V152.RTTI5.TV152RTTI5Rules.CheckFile (DRagLint.V152.RTTI5.pas)</para>
/// <para>Calls: Format</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function AnonymousFieldMessage(const AField: TAnonField): string;

implementation

uses
  System.SysUtils
  , System.Generics.Collections
  ;

type
  TTokKind = (tkIdent, tkNumber, tkSymbol);

  TTok = record
    Kind : TTokKind;
    Text : string;
    Line : Integer;
    Col  : Integer;
    Start: Integer;  { 1-based offset of the first character }
    Stop : Integer;  { 1-based offset of the last character }
  end;

  { Lexer: identifiers, numbers and single-character symbols (`..` is one symbol); comments,
    directives, strings and white space produce no token. }
  TAnonLexer = class
  strict private
    FText: string;
    FPos : Integer;
    FLine: Integer;
    FLineStart: Integer;
    FToks: TList<TTok>;
    procedure Emit(AKind: TTokKind; AStart, AStop, ALine, ALineStart: Integer);
    procedure SkipTo(const ACloser: string);
    procedure SkipString;
    procedure Step;
  public
    constructor Create(const AText: string);
    destructor Destroy; override;
    function Run: TArray<TTok>;
  end;

  { Walks the tokens: finds class bodies and reads their member lists. }
  TAnonScanner = class
  strict private
    FToks: TArray<TTok>;
    FText: string;
    FFound: TList<TAnonField>;
    function IsWord(AIndex: Integer; const AWord: string): Boolean;
    function IsSym(AIndex: Integer; const ASym: string): Boolean;
    function OpensNestedBody(AIndex: Integer): Boolean;
    function SkipStatement(AIndex: Integer): Integer;
    function SkipClassHead(AIndex: Integer): Integer;
    function IsInlineType(AIndex: Integer): Boolean;
    function ReadField(AIndex: Integer; const AClassName: string; APublished: Boolean): Integer;
    function ScanBody(AIndex: Integer; const AClassName: string): Integer;
  public
    constructor Create(const AText: string; const AToks: TArray<TTok>);
    destructor Destroy; override;
    function Run: TArray<TAnonField>;
  end;

const
  VISIBILITY_WORDS: array[0..4] of string = ('private', 'protected', 'public', 'published', 'automated');
  ROUTINE_WORDS: array[0..7] of string = ('procedure', 'function', 'constructor', 'destructor',
    'property', 'operator', 'type', 'const');

function InWords(const AWord: string; const AList: array of string): Boolean;
begin
  for var W: string in AList do
    if SameText(W, AWord) then Exit(True);
  Result:= False;
end;

function IsIdentStart(AChar: Char): Boolean;
begin
  Result:= CharInSet(AChar, ['A'..'Z', 'a'..'z', '_', '&']);
end;

function IsIdentChar(AChar: Char): Boolean;
begin
  Result:= IsIdentStart(AChar) or CharInSet(AChar, ['0'..'9']);
end;

{ TAnonLexer }

constructor TAnonLexer.Create(const AText: string);
begin
  inherited Create;
  FText:= AText;
  FPos:= 1;
  FLine:= 1;
  FLineStart:= 1;
  FToks:= TList<TTok>.Create;
end;

destructor TAnonLexer.Destroy;
begin
  FToks.Free;
  inherited Destroy;
end;

procedure TAnonLexer.Emit(AKind: TTokKind; AStart, AStop, ALine, ALineStart: Integer);
begin
  var T: TTok:= Default(TTok);
  T.Kind:= AKind;
  T.Text:= Copy(FText, AStart, AStop - AStart + 1);
  T.Line:= ALine;
  T.Col:= AStart - ALineStart + 1;
  T.Start:= AStart;
  T.Stop:= AStop;
  FToks.Add(T);
end;

procedure TAnonLexer.SkipTo(const ACloser: string);
begin
  while FPos <= Length(FText) do
  begin
    if Copy(FText, FPos, Length(ACloser)) = ACloser then
    begin
      Inc(FPos, Length(ACloser));
      Exit;
    end;
    if FText[FPos] = #10 then
    begin
      Inc(FLine);
      FLineStart:= FPos + 1;
    end;
    Inc(FPos);
  end;
end;

procedure TAnonLexer.SkipString;
begin
  Inc(FPos);
  while FPos <= Length(FText) do
  begin
    if FText[FPos] = '''' then
    begin
      if (FPos < Length(FText)) and (FText[FPos + 1] = '''') then
        Inc(FPos, 2)
      else
      begin
        Inc(FPos);
        Exit;
      end;
    end
    else if CharInSet(FText[FPos], [#10, #13]) then Exit  { unterminated string ends at the line }
    else Inc(FPos);
  end;
end;

procedure TAnonLexer.Step;
begin
  var C: Char:= FText[FPos];
  var Nxt: Char:= if FPos < Length(FText) then FText[FPos + 1] else #0;
  if C = #10 then
  begin
    Inc(FLine);
    Inc(FPos);
    FLineStart:= FPos;
  end
  else if C <= ' ' then Inc(FPos)
  else if (C = '/') and (Nxt = '/') then
  begin
    while (FPos <= Length(FText)) and (FText[FPos] <> #10) do Inc(FPos);
  end
  else if C = '{' then SkipTo('}')
  else if (C = '(') and (Nxt = '*') then SkipTo('*)')
  else if C = '''' then SkipString
  else if IsIdentStart(C) then
  begin
    var S: Integer:= FPos;
    while (FPos <= Length(FText)) and IsIdentChar(FText[FPos]) do Inc(FPos);
    Emit(tkIdent, S, FPos - 1, FLine, FLineStart);
  end
  else if CharInSet(C, ['0'..'9']) then
  begin
    var S: Integer:= FPos;
    while (FPos <= Length(FText)) and IsIdentChar(FText[FPos]) do Inc(FPos);
    Emit(tkNumber, S, FPos - 1, FLine, FLineStart);
  end
  else if (C = '.') and (Nxt = '.') then
  begin
    Emit(tkSymbol, FPos, FPos + 1, FLine, FLineStart);
    Inc(FPos, 2);
  end
  else
  begin
    Emit(tkSymbol, FPos, FPos, FLine, FLineStart);
    Inc(FPos);
  end;
end;

function TAnonLexer.Run: TArray<TTok>;
begin
  while FPos <= Length(FText) do Step;
  Result:= FToks.ToArray;
end;

{ TAnonScanner }

constructor TAnonScanner.Create(const AText: string; const AToks: TArray<TTok>);
begin
  inherited Create;
  FText:= AText;
  FToks:= AToks;
  FFound:= TList<TAnonField>.Create;
end;

destructor TAnonScanner.Destroy;
begin
  FFound.Free;
  inherited Destroy;
end;

function TAnonScanner.IsWord(AIndex: Integer; const AWord: string): Boolean;
begin
  Result:= (AIndex >= 0) and (AIndex < Length(FToks)) and (FToks[AIndex].Kind = tkIdent)
    and SameText(FToks[AIndex].Text, AWord);
end;

function TAnonScanner.IsSym(AIndex: Integer; const ASym: string): Boolean;
begin
  Result:= (AIndex >= 0) and (AIndex < Length(FToks)) and (FToks[AIndex].Kind = tkSymbol)
    and (FToks[AIndex].Text = ASym);
end;

{ True at the record / object / interface / class keyword of `= record ...`: a body with its own end. }
function TAnonScanner.OpensNestedBody(AIndex: Integer): Boolean;
begin
  Result:= False;
  if not (IsSym(AIndex - 1, '=') or IsWord(AIndex - 1, 'packed')) then Exit;
  Result:= IsWord(AIndex, 'record') or IsWord(AIndex, 'object') or IsWord(AIndex, 'interface')
    or (IsWord(AIndex, 'class') and not IsWord(AIndex + 1, 'of'));
end;

{ Index of the token after the next `;` at bracket depth 0, stepping over nested record / class /
  object / interface bodies (`= record ... end`). Stops at an `end` of the enclosing body without
  consuming it. }
function TAnonScanner.SkipStatement(AIndex: Integer): Integer;
begin
  var Depth: Integer:= 0;
  var Nest: Integer:= 0;
  Result:= AIndex;
  while Result < Length(FToks) do
  begin
    if IsSym(Result, '(') or IsSym(Result, '[') then Inc(Depth)
    else if IsSym(Result, ')') or IsSym(Result, ']') then Dec(Depth)
    else if IsWord(Result, 'end') then
    begin
      if Nest = 0 then Exit;
      Dec(Nest);
    end
    else if OpensNestedBody(Result) then Inc(Nest)
    else if IsSym(Result, ';') and (Depth <= 0) and (Nest = 0) then
    begin
      Inc(Result);
      Exit;
    end;
    Inc(Result);
  end;
end;

{ AIndex is the token after `class`; steps over `abstract` / `sealed` and an ancestor list. }
function TAnonScanner.SkipClassHead(AIndex: Integer): Integer;
begin
  Result:= AIndex;
  while IsWord(Result, 'abstract') or IsWord(Result, 'sealed') do Inc(Result);
  if IsSym(Result, '(') then
  begin
    var Depth: Integer:= 0;
    repeat
      if IsSym(Result, '(') then Inc(Depth)
      else if IsSym(Result, ')') then Dec(Depth);
      Inc(Result);
    until (Depth = 0) or (Result >= Length(FToks));
  end;
end;

{ AIndex is the first token of a field type. }
function TAnonScanner.IsInlineType(AIndex: Integer): Boolean;
begin
  if IsWord(AIndex, 'packed') then Inc(AIndex);
  if IsWord(AIndex, 'array') or IsSym(AIndex, '(') then Exit(True);
  Result:= False;
  if IsWord(AIndex, 'set') and IsWord(AIndex + 1, 'of') then
  begin
    var T: Integer:= AIndex + 2;
    Result:= IsSym(T, '(') or ((T < Length(FToks)) and (FToks[T].Kind = tkNumber))
      or (IsSym(T + 1, '..'));
  end;
end;

{ AIndex is at the first field name; returns the index after the declaration, or AIndex when it is
  not a `Names: Type;` declaration. }
function TAnonScanner.ReadField(AIndex: Integer; const AClassName: string; APublished: Boolean): Integer;
begin
  var I: Integer:= AIndex;
  var Names: string:= '';
  while (I < Length(FToks)) and (FToks[I].Kind = tkIdent) do
  begin
    Names:= if Names = '' then FToks[I].Text else Names + ', ' + FToks[I].Text;
    Inc(I);
    if IsSym(I, ',') then Inc(I) else Break;
  end;
  if (Names = '') or not IsSym(I, ':') then Exit(AIndex);
  Inc(I);
  var TypeStart: Integer:= I;
  Result:= SkipStatement(I);
  var TypeEnd: Integer:= Result - 1;
  if IsSym(TypeEnd, ';') then Dec(TypeEnd);
  if not (APublished and IsInlineType(TypeStart) and (TypeEnd >= TypeStart)) then Exit;
  var F: TAnonField:= Default(TAnonField);
  F.ClassName:= AClassName;
  F.Names:= Names;
  F.Line:= FToks[AIndex].Line;
  F.Col:= FToks[AIndex].Col;
  var Raw: string:= Copy(FText, FToks[TypeStart].Start, FToks[TypeEnd].Stop - FToks[TypeStart].Start + 1);
  F.TypeText:= string.Join(' ', Raw.Split([' ', #9, #10, #13], TStringSplitOptions.ExcludeEmpty));
  FFound.Add(F);
end;

{ AIndex is the first member token; returns the index after the body's `end`. }
function TAnonScanner.ScanBody(AIndex: Integer; const AClassName: string): Integer;
begin
  Result:= AIndex;
  var Published: Boolean:= False;
  while (Result < Length(FToks)) and not IsWord(Result, 'end') do
  begin
    if (FToks[Result].Kind = tkIdent) and InWords(FToks[Result].Text, VISIBILITY_WORDS) then
    begin
      Published:= SameText(FToks[Result].Text, 'published');
      Inc(Result);
    end
    else if IsWord(Result, 'strict') or IsWord(Result, 'var') then Inc(Result)
    else if IsWord(Result, 'class') and (IsWord(Result + 1, 'var') or IsWord(Result + 1, 'property')
      or IsWord(Result + 1, 'procedure') or IsWord(Result + 1, 'function')) then Inc(Result)
    else if (FToks[Result].Kind = tkIdent) and InWords(FToks[Result].Text, ROUTINE_WORDS) then
      Result:= SkipStatement(Result)
    else
    begin
      var Next: Integer:= ReadField(Result, AClassName, Published);
      Result:= if Next > Result then Next else SkipStatement(Result);
    end;
  end;
  if IsWord(Result, 'end') then Inc(Result);
end;

function TAnonScanner.Run: TArray<TAnonField>;
begin
  var I: Integer:= 0;
  while I < Length(FToks) do
  begin
    if IsWord(I, 'class') and IsSym(I - 1, '=') and (I >= 2) and (FToks[I - 2].Kind = tkIdent)
      and not IsWord(I + 1, 'of') then
    begin
      var Body: Integer:= SkipClassHead(I + 1);
      { a semicolon right after the head is a forward declaration: nothing to scan }
      I:= if IsSym(Body, ';') then Body + 1 else ScanBody(Body, FToks[I - 2].Text);
    end
    else Inc(I);
  end;
  Result:= FFound.ToArray;
end;

function FindAnonymousFieldTypes(const AText: string): TArray<TAnonField>;
begin
  var Lexer: TAnonLexer:= TAnonLexer.Create(AText);
  try
    var Scanner: TAnonScanner:= TAnonScanner.Create(AText, Lexer.Run);
    try
      Result:= Scanner.Run;
    finally
      Scanner.Free;
    end;
  finally
    Lexer.Free;
  end;
end;

function AnonymousFieldMessage(const AField: TAnonField): string;
begin
  Result:= Format('anonymous-field-type: published field %s of %s has the anonymous type ''%s'' -- an inline '
    + 'array / set / enum type has no name, so TRttiContext, an RTTI-based ORM and a DefineProperties stream '
    + 'cannot refer to it by type; declare a named type (TName = %s;) and use it for the field',
    [AField.Names, AField.ClassName, AField.TypeText, AField.TypeText]);
end;

end.
