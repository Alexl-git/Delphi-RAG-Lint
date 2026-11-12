unit DRagLint.Lint.RttiRules;

{ rtti-unavailable (wave 152b lane RTTI; INBOX rtti-availability-rule, owner request 2026-11-09).

  Generated persistence classes (ORM3 COMMON\OBJECTS) must keep complete classic AND extended RTTI so
  a TWriter / TReader stream and a future TRttiContext-based ORM can read every component. The rule
  flags the declarations that lose it. One rule id, four sub-kinds; the message starts with the
  sub-kind and a colon so a reader (and the guard) can split them:

    enum-no-typeinfo             an enum whose explicit ordinals are not contiguous from 0 (no PTypeInfo,
                                 TypeInfo() fails with E2134), and a published property of such a type
    published-record-property    a published property of a record type -- TWriter skips it silently;
                                 info when the class's DefineProperties names it, warning otherwise
    rtti-narrowing-directive     $RTTI EXPLICIT ... without vcPublic / vcPublished in a visibility set,
                                 $M- / $TYPEINFO OFF in effect over a class with a published section
                                 and no RTTI-bearing ancestor, $WEAKLINKRTTI ON in a unit declaring
                                 TComponent descendants
    published-without-persistent a class with a published section, no TPersistent ancestor and not
                                 declared under $M+

  Source-text rule over the indexed files (the directives and the explicit ordinals are not in the
  index); the index answers what a single file cannot: whether an ancestor chain reaches TPersistent /
  TComponent and whether a property type declared elsewhere is a record or a type-info-less enum.
  An ancestor the project and library indexes cannot place is UNKNOWN and never fires. An ordinal
  that is not an integer literal is not judged. Sub-check 5 of the note (anonymous property types)
  is not built: a Delphi property declaration requires a type identifier. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>The rule id, as `rules --json`, `--rule`, `--enable` and dl:ok markers spell it.</summary>
  RTTI_UNAVAILABLE_RULE = 'rtti-unavailable';

/// <summary>Finds the declarations of the project that lose classic or extended RTTI: enums
/// without type info, published record properties, RTTI-narrowing directives and published
/// sections on classes without TPersistent ancestry.</summary>
/// <param name="AStore">The project index; must not be nil. Supplies the file list, the file
/// paths and the type facts of declarations outside the scanned file.</param>
/// <param name="ALibraryStore">The platform library index, or nil. Without it an ancestor or a
/// property type that only the library declares is judged by a short built-in list of RTL / VCL
/// names, and anything else outside the project is unknown (silent).</param>
/// <param name="AOnlyFileId">0 scans every .pas / .dpr / .dpk file of the index; a file id scans
/// that file only (the `lint &lt;file&gt;` path).</param>
/// <returns>One finding per offending declaration or directive. RuleId is rtti-unavailable;
/// Message starts with the sub-kind and a colon; Severity is 'warning', or 'info' for a
/// published record property its class streams in DefineProperties.</returns>
/// <remarks>Reads every scanned file from disk; a file that is missing or unreadable is skipped.
/// Not thread-safe; writes nothing.</remarks>
function CollectRttiUnavailable(const AStore: ISymbolStore; const ALibraryStore: ISymbolStore = nil;
  const AOnlyFileId: Int64 = 0): TArray<TLintFinding>;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.IOUtils
  , System.Generics.Collections
  ;

const
  SEV_WARNING = 'warning';
  SEV_INFO    = 'info';
  KIND_ENUM      = 'enum-no-typeinfo';
  KIND_RECORD    = 'published-record-property';
  KIND_DIRECTIVE = 'rtti-narrowing-directive';
  KIND_NO_PERSIST = 'published-without-persistent';
  MAX_ANCESTRY_DEPTH = 64;
  SOURCE_EXTS: array[0..2] of string = ('.pas', '.dpr', '.dpk');
  { Library names judged without a library index. A name not listed and not indexed is UNKNOWN. }
  BUILTIN_PERSISTENT: array[0..21] of string = (
    'tpersistent', 'tinterfacedpersistent', 'tcomponent', 'tcontrol', 'twincontrol', 'tcustomcontrol',
    'tgraphiccontrol', 'tcustomform', 'tform', 'tcustomframe', 'tframe', 'tdatamodule', 'tcollection',
    'townedcollection', 'tcollectionitem', 'tstrings', 'tstringlist', 'tgraphic', 'tgraphicsobject',
    'tdataset', 'tfield', 'tcustomconnection');
  BUILTIN_COMPONENT: array[0..11] of string = (
    'tcomponent', 'tcontrol', 'twincontrol', 'tcustomcontrol', 'tgraphiccontrol', 'tcustomform', 'tform',
    'tcustomframe', 'tframe', 'tdatamodule', 'tdataset', 'tcustomconnection');
  { Roots known NOT to carry RTTI from an ancestor (TObject and its plain library children). }
  BUILTIN_NO_RTTI_ROOTS: array[0..9] of string = (
    'tobject', 'tinterfacedobject', 'taggregatedobject', 'tcontainedobject', 'tthread', 'exception',
    'tstream', 'tlist', 'tobjectlist', 'tsinglylinkedlist');
  BUILTIN_RECORDS: array[0..14] of string = (
    'tsqltimestamp', 'tsqltimestampoffset', 'tbcd', 'tguid', 'tpoint', 'trect', 'tsize', 'tpointf',
    'trectf', 'tsizef', 'tvalue', 'ttimestamp', 'tmethod', 'tvardata', 'tdatetimerec');
  VIS_PUBLISHED = 'published';
  VIS_WORDS: array[0..4] of string = ('private', 'protected', 'public', 'published', 'automated');
  { Keywords that end a type section at the top level of a unit. }
  SECTION_END_WORDS: array[0..14] of string = (
    'const', 'var', 'threadvar', 'resourcestring', 'label', 'exports', 'procedure', 'function',
    'constructor', 'destructor', 'begin', 'interface', 'initialization', 'finalization', 'uses');
  ROUTINE_WORDS: array[0..3] of string = ('procedure', 'function', 'constructor', 'destructor');
  RTTI_SET_NAMES: array[0..2] of string = ('METHODS', 'PROPERTIES', 'FIELDS');
  DEFINE_PROPERTIES = 'defineproperties';
  { procedure TFoo.DefineProperties: the class name, the dot and the method name follow the keyword. }
  HDR_NAME_OFFSET = 3;

type
  TTri = (triNo, triYes, triUnknown);

  TRttiTokKind = (rtIdent, rtNumber, rtString, rtSymbol, rtDirective);

  { One token of the source; Text is the identifier as written, a string's content, a symbol, or a
    directive's body without the braces and the dollar sign. }
  TRttiTok = record
    Kind: TRttiTokKind;
    Text: string;
    Line: Integer;
    Col : Integer;
  end;

  TRttiProp = record
    Name    : string;
    TypeName: string;
    Line    : Integer;
    Col     : Integer;
  end;

  TRttiClass = record
    Name        : string;
    Ancestor    : string;  { first heritage entry, unit qualifier and generic arguments stripped; '' = TObject }
    Line        : Integer;
    Col         : Integer;
    MPlus       : Boolean; { declared while $M+ / $TYPEINFO ON was in effect }
    MMinusLine  : Integer; { line of the explicit $M- / $TYPEINFO OFF in effect, 0 = none }
    HasPublished: Boolean;
    Props       : TArray<TRttiProp>; { published properties with a declared type }
  end;

  { The per-run state every file scan shares; owned by CollectRttiUnavailable. }
  TRttiShared = record
    Findings  : TList<TLintFinding>;
    Persistent: TDictionary<string, Boolean>; { lower names reaching TPersistent }
    Component : TDictionary<string, Boolean>; { lower names reaching TComponent }
    TypeCache : TDictionary<string, TTri>;    { 'rec|' / 'enum|' + lower type name }
  end;

  { One source file: tokens, the declarations found in them, and the findings they produce. }
  TRttiScan = class  // dl:ok god-class@23fe, high-response@23fe -- REVIEWED 2026-11-11: the class IS one file's scan (token array, per-file type maps, directive state); splitting it would only pass that state between objects
  strict private
    FStore, FLib  : ISymbolStore;
    FToks         : TArray<TRttiTok>;
    FPath         : string;
    FFileId       : Int64;
    FFindings     : TList<TLintFinding>;
    FPersistent   : TDictionary<string, Boolean>; { shared, not owned }
    FComponent    : TDictionary<string, Boolean>; { shared, not owned }
    FTypeCache    : TDictionary<string, TTri>;    { shared, not owned: 'rec|' / 'enum|' + lower name }
    FLocalAnc     : TDictionary<string, string>;  { lower class name -> ancestor (this file) }
    FLocalMPlus   : TDictionary<string, Boolean>; { classes of this file declared under $M+ }
    FLocalKind    : TDictionary<string, string>;  { lower type name -> 'record' | 'class' | 'enum' | 'other' }
    FLocalEnumBad : TDictionary<string, string>;  { lower enum name -> its value list, when it has no type info }
    FDefProps     : TDictionary<string, TDictionary<string, Boolean>>; { lower class -> names in DefineProperties }
    FClasses      : TList<TRttiClass>;
    FMPlus        : Boolean;
    FMMinusLine   : Integer;
    FWeakLinkLine : Integer;
    function Tok(AIndex: Integer): TRttiTok;
    function IsIdent(AIndex: Integer; const AWord: string): Boolean;
    function IsSym(AIndex: Integer; const ASym: string): Boolean;
    procedure Add(ALine, ACol: Integer; const ASeverity, ASymbol, AMessage: string);
    procedure HandleDirective(const ATok: TRttiTok);
    procedure CheckRttiExplicit(const ATok: TRttiTok; const ABody: string);
    function OpensNestedType(AIndex: Integer): Boolean;
    function SkipBody(AIndex: Integer): Integer;
    function SkipToSemicolon(AIndex: Integer): Integer;
    function SkipGroup(AIndex: Integer; const AOpen, AClose: string): Integer;
    function TypeDeclEquals(AIndex: Integer): Integer;
    function ParseTypeDecl(AIndex: Integer): Integer;
    function ParseEnum(AIndex: Integer; const ANameTok: TRttiTok): Integer;
    function ParseClass(AIndex: Integer; const ANameTok: TRttiTok): Integer;
    function ParseProperty(AIndex: Integer; var AClass: TRttiClass; const AVis: string): Integer;
    procedure CollectDefineProperties(AIndex: Integer; const AClassName: string);
    function Reaches(const AAncestor: string; ATargets: TDictionary<string, Boolean>; AUseMPlus: Boolean): TTri;
    function StoreHeritage(const AName: string; out AAncestor: string): Boolean;
    function IsRecordType(const ATypeName: string): Boolean;
    function EnumWithoutTypeInfo(const ATypeName: string; out AValues: string): Boolean;
    procedure Evaluate;
  public
    constructor Create(const AStore, ALib: ISymbolStore; AFileId: Int64; const APath, AText: string;
      const AShared: TRttiShared);
    destructor Destroy; override;
    procedure Run;
  end;

{ ---- helpers ---------------------------------------------------------------------------------- }

function InList(const AWord: string; const AList: array of string): Boolean;
begin
  for var S in AList do
    if SameText(S, AWord) then Exit(True);
  Result:= False;
end;

{ Last dotted segment, generic arguments dropped: 'Data.SqlTimSt.TSQLTimeStamp' -> 'TSQLTimeStamp'. }
function BareTypeName(const AName: string): string;
begin
  Result:= AName;
  var Lt: Integer:= Pos('<', Result);
  if Lt > 0 then Result:= Copy(Result, 1, Lt - 1);
  var Dot: Integer:= LastDelimiter('.', Result);
  if Dot > 0 then Result:= Copy(Result, Dot + 1, MaxInt);
  Result:= Trim(Result);
end;

{ First entry of a heritage list ('TBar, IBaz' -> 'TBar'), bare. }
function FirstHeritage(const AHeritage: string): string;
begin
  var S: string:= AHeritage;
  var Depth: Integer:= 0;
  for var I:= 1 to Length(S) do
  begin
    case S[I] of
      '<': Inc(Depth);
      '>': Dec(Depth);
      ',': if Depth = 0 then Exit(BareTypeName(Copy(S, 1, I - 1)));
    end;
  end;
  Result:= BareTypeName(S);
end;

function IsIdentStart(C: Char): Boolean;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '_']);
end;

function IsIdentChar(C: Char): Boolean;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '_', '0'..'9']);
end;

{ The lexer state: one pass over the text, comments dropped, directives kept as tokens, strings
  unquoted. }
type
  TRttiLexer = record
    Text  : string;
    N     : Integer;
    I     : Integer;
    Line  : Integer;
    LineAt: Integer; { index of the first char of the current line }
    Toks  : TList<TRttiTok>;
    procedure Emit(AKind: TRttiTokKind; const AValue: string; AStart, ALine, ALineAt: Integer);
    function SkipBlock(const ACloser: string; ABodyStart: Integer): string;
    procedure LexBlockComment(const ACloser: string; AOpenLen: Integer);
    procedure LexString;
    procedure LexIdent;
    procedure LexNumber;
    procedure LexSymbol;
    procedure Step;
  end;

procedure TRttiLexer.Emit(AKind: TRttiTokKind; const AValue: string; AStart, ALine, ALineAt: Integer);
var T: TRttiTok;
begin
  T.Kind:= AKind;
  T.Text:= AValue;
  T.Line:= ALine;
  T.Col := AStart - ALineAt + 1;
  Toks.Add(T);
end;

{ Advances I past ACloser (or the end of the text), counting lines; returns the body before it. }
function TRttiLexer.SkipBlock(const ACloser: string; ABodyStart: Integer): string;
begin
  var Stop: Integer:= Pos(ACloser, Text, ABodyStart);
  if Stop = 0 then Stop:= N + 1;
  Result:= Copy(Text, ABodyStart, Stop - ABodyStart);
  for var K:= I to Stop - 1 do
    if Text[K] = #10 then
    begin
      Inc(Line);
      LineAt:= K + 1;
    end;
  I:= Stop + Length(ACloser);
end;

{ A brace or paren-star block: a directive when its body starts with a dollar sign, else dropped. }
procedure TRttiLexer.LexBlockComment(const ACloser: string; AOpenLen: Integer);
begin
  var Start: Integer:= I;
  var StartLine: Integer:= Line;
  var StartLineAt: Integer:= LineAt;
  var Body: string:= SkipBlock(ACloser, I + AOpenLen);
  if Body.StartsWith('$') then Emit(rtDirective, Copy(Body, 2, MaxInt), Start, StartLine, StartLineAt);
end;

{ A quoted string; a doubled quote is one quote; an unterminated string stops at the line end. }
procedure TRttiLexer.LexString;
begin
  var Start: Integer:= I;
  Inc(I);
  while (I <= N) and (Text[I] <> #10) do
  begin
    if (Text[I] = '''') and (I < N) and (Text[I + 1] = '''') then Inc(I, 2)
    else if Text[I] = '''' then Break
    else Inc(I);
  end;
  var Body: string:= Copy(Text, Start + 1, I - Start - 1).Replace('''''', '''');
  if (I <= N) and (Text[I] = '''') then Inc(I);
  Emit(rtString, Body, Start, Line, LineAt);
end;

procedure TRttiLexer.LexIdent;
begin
  var Start: Integer:= I;
  if Text[I] = '&' then Inc(I);
  var S0: Integer:= I;
  while (I <= N) and IsIdentChar(Text[I]) do Inc(I);
  Emit(rtIdent, Copy(Text, S0, I - S0), Start, Line, LineAt);
end;

procedure TRttiLexer.LexNumber;
begin
  var Start: Integer:= I;
  Inc(I);
  while (I <= N) and CharInSet(Text[I], ['0'..'9', 'A'..'F', 'a'..'f']) do Inc(I);
  Emit(rtNumber, Copy(Text, Start, I - Start), Start, Line, LineAt);
end;

procedure TRttiLexer.LexSymbol;
begin
  var Two: string:= Copy(Text, I, 2);
  if MatchStr(Two, [':=', '..', '<=', '>=', '<>']) then
  begin
    Emit(rtSymbol, Two, I, Line, LineAt);
    Inc(I, 2);
  end
  else
  begin
    Emit(rtSymbol, Text[I], I, Line, LineAt);
    Inc(I);
  end;
end;

procedure TRttiLexer.Step;
begin
  var C: Char:= Text[I];
  var Nx: Char:= #0;
  if I < N then Nx:= Text[I + 1];
  if C = #10 then
  begin
    Inc(Line);
    Inc(I);
    LineAt:= I;
  end
  else if CharInSet(C, [#9, #13, ' ']) then Inc(I)
  else if (C = '/') and (Nx = '/') then
  begin
    while (I <= N) and (Text[I] <> #10) do Inc(I);
  end
  else if C = '{' then LexBlockComment('}', 1)
  else if (C = '(') and (Nx = '*') then LexBlockComment('*)', 2)
  else if C = '''' then LexString
  else if IsIdentStart(C) or ((C = '&') and IsIdentStart(Nx)) then LexIdent
  else if CharInSet(C, ['0'..'9']) or ((C = '$') and CharInSet(Nx, ['0'..'9', 'A'..'F', 'a'..'f'])) then LexNumber
  else LexSymbol;
end;

{ The lexer: comments dropped, directives kept as tokens, strings unquoted. }
function Tokenize(const AText: string): TArray<TRttiTok>;
var
  Lx: TRttiLexer;
begin
  Lx:= Default(TRttiLexer);
  Lx.Text:= AText;
  Lx.N:= Length(AText);
  Lx.I:= 1;
  Lx.Line:= 1;
  Lx.LineAt:= 1;
  Lx.Toks:= TList<TRttiTok>.Create;
  try
    while Lx.I <= Lx.N do Lx.Step;
    Result:= Lx.Toks.ToArray;
  finally
    Lx.Toks.Free;
  end;
end;

{ The explicit ordinal after '=' of an enum item, AIndex on its first token: True and AValue when it
  is an integer literal (optionally signed); AText receives the expression as written; AIndex ends
  on the ',' or ')' that closes the item. }
function ReadOrdinal(const AToks: TArray<TRttiTok>; var AIndex: Integer; out AValue: Int64; out AText: string): Boolean;
begin
  var Pieces: TArray<string>:= nil;
  var Depth: Integer:= 0;
  while AIndex < Length(AToks) do
  begin
    var E: TRttiTok:= AToks[AIndex];
    if (E.Kind = rtSymbol) and (Depth = 0) and MatchStr(E.Text, [',', ')']) then Break;
    if (E.Kind = rtSymbol) and (E.Text = '(') then Inc(Depth);
    if (E.Kind = rtSymbol) and (E.Text = ')') then Dec(Depth);
    Pieces:= Pieces + [E.Text];
    Inc(AIndex);
  end;
  AText:= string.Join('', Pieces);
  var Signed: Boolean:= (Length(Pieces) = 2) and MatchStr(Pieces[0], ['-', '+']);
  Result:= ((Length(Pieces) = 1) or Signed) and TryStrToInt64(AText, AValue);
end;

{ Parses the items of an enum value list starting at the '(' at AIndex. AValues receives the list as
  written ('gA = 1, gB = 3'); returns True only when an explicit ordinal exists, every explicit ordinal
  is an integer literal, and the ordinals are not 0, 1, 2, ... in declaration order. AEnd receives the
  index after the closing ')'. }
function EnumLacksTypeInfo(const AToks: TArray<TRttiTok>; AIndex: Integer; out AValues: string;
  out AEnd: Integer): Boolean;
var
  I         : Integer;
  Next      : Int64;
  Explicit  : Boolean;
  Unknown   : Boolean;
  Contiguous: Boolean;
  Items     : TArray<string>;
begin
  I:= AIndex + 1;
  Next:= 0;
  Items:= nil;
  Explicit:= False;
  Unknown:= False;
  Contiguous:= True;
  while (I < Length(AToks)) and not ((AToks[I].Kind = rtSymbol) and (AToks[I].Text = ')')) do
  begin
    var T: TRttiTok:= AToks[I];
    Inc(I);
    if T.Kind <> rtIdent then Continue;
    var Item: string:= T.Text;
    var Value: Int64:= Next;
    if (I < Length(AToks)) and (AToks[I].Kind = rtSymbol) and (AToks[I].Text = '=') then
    begin
      Explicit:= True;
      Inc(I);
      var Expr: string;
      if ReadOrdinal(AToks, I, Value, Expr) then Item:= Item + ' = ' + Expr else Unknown:= True;
    end;
    if Value <> Length(Items) then Contiguous:= False;
    Next:= Value + 1;
    Items:= Items + [Item];
  end;
  AValues:= string.Join(', ', Items);
  AEnd:= I + 1;
  Result:= Explicit and not Unknown and not Contiguous;
end;

{ ---- TRttiScan ---------------------------------------------------------------------------------- }

constructor TRttiScan.Create(const AStore, ALib: ISymbolStore; AFileId: Int64; const APath, AText: string;
  const AShared: TRttiShared);
begin
  inherited Create;
  FStore:= AStore;
  FLib:= ALib;
  FFileId:= AFileId;
  FPath:= APath;
  FToks:= Tokenize(AText);
  FFindings:= AShared.Findings;
  FPersistent:= AShared.Persistent;
  FComponent:= AShared.Component;
  FTypeCache:= AShared.TypeCache;
  FLocalAnc:= TDictionary<string, string>.Create;
  FLocalMPlus:= TDictionary<string, Boolean>.Create;
  FLocalKind:= TDictionary<string, string>.Create;
  FLocalEnumBad:= TDictionary<string, string>.Create;
  FDefProps:= TObjectDictionary<string, TDictionary<string, Boolean>>.Create([doOwnsValues]);
  FClasses:= TList<TRttiClass>.Create;
end;

destructor TRttiScan.Destroy;
begin
  FClasses.Free;
  FDefProps.Free;
  FLocalEnumBad.Free;
  FLocalKind.Free;
  FLocalMPlus.Free;
  FLocalAnc.Free;
  inherited Destroy;
end;

function TRttiScan.Tok(AIndex: Integer): TRttiTok;
begin
  if (AIndex >= 0) and (AIndex < Length(FToks)) then Exit(FToks[AIndex]);
  Result:= Default(TRttiTok);
  Result.Kind:= rtSymbol;
end;

function TRttiScan.IsIdent(AIndex: Integer; const AWord: string): Boolean;
begin
  var T: TRttiTok:= Tok(AIndex);
  Result:= (T.Kind = rtIdent) and SameText(T.Text, AWord);
end;

function TRttiScan.IsSym(AIndex: Integer; const ASym: string): Boolean;
begin
  var T: TRttiTok:= Tok(AIndex);
  Result:= (T.Kind = rtSymbol) and (T.Text = ASym);
end;

procedure TRttiScan.Add(ALine, ACol: Integer; const ASeverity, ASymbol, AMessage: string);
begin
  var F: TLintFinding:= Default(TLintFinding);
  F.RuleId    := RTTI_UNAVAILABLE_RULE;
  F.FileId    := FFileId;
  F.FilePath  := FPath;
  F.StartLine := ALine;
  F.StartCol  := ACol;
  F.EndLine   := ALine;
  F.EndCol    := ACol;
  F.Severity  := ASeverity;
  F.SymbolName:= ASymbol;
  F.Message   := AMessage;
  FFindings.Add(F);
end;

procedure TRttiScan.CheckRttiExplicit(const ATok: TRttiTok; const ABody: string);
begin
  var Up: string:= UpperCase(ABody);
  if not Up.Contains('EXPLICIT') then Exit;
  var Narrowed: TArray<string>:= nil;
  for var SetName in RTTI_SET_NAMES do
  begin
    var At: Integer:= Pos(SetName + '(', StringReplace(Up, ' ', '', [rfReplaceAll]));
    if At = 0 then Continue;
    var Compact: string:= StringReplace(Up, ' ', '', [rfReplaceAll]);
    var Open: Integer:= At + Length(SetName);
    var Close: Integer:= Pos(')', Compact, Open);
    if Close = 0 then Continue;
    var Inner: string:= Copy(Compact, Open + 1, Close - Open - 1);
    var HasPublic: Boolean:= False;
    var HasPublished: Boolean:= False;
    var Unknown: Boolean:= False;
    for var W in Inner.Split(['[', ']', ',', '+'], TStringSplitOptions.ExcludeEmpty) do
    begin
      if W.StartsWith('DEFAULT') then
      begin
        HasPublic:= True;
        HasPublished:= True;
      end
      else if W = 'VCPUBLIC' then HasPublic:= True
      else if W = 'VCPUBLISHED' then HasPublished:= True
      else if (W <> 'VCPRIVATE') and (W <> 'VCPROTECTED') then Unknown:= True;
    end;
    if Unknown or (HasPublic and HasPublished) then Continue;
    var Missing: TArray<string>:= nil;
    if not HasPublic then Missing:= Missing + ['vcPublic'];
    if not HasPublished then Missing:= Missing + ['vcPublished'];
    Narrowed:= Narrowed + [SetName + ' lacks ' + string.Join(', ', Missing)];
  end;
  if Narrowed = nil then Exit;
  Add(ATok.Line, ATok.Col, SEV_WARNING, '', Format('%s: {$RTTI EXPLICIT ...} narrows extended RTTI (%s) -- '
    + 'TRttiContext cannot see those members of the classes declared after it, so an RTTI-based ORM or '
    + 'serializer misses them; keep vcPublic and vcPublished in every visibility set', [KIND_DIRECTIVE, string.Join('; ', Narrowed)]));
end;

procedure TRttiScan.HandleDirective(const ATok: TRttiTok);
begin
  var Body: string:= Trim(ATok.Text);
  var K: Integer:= 1;
  while (K <= Length(Body)) and IsIdentChar(Body[K]) do Inc(K);
  var Name: string:= UpperCase(Copy(Body, 1, K - 1));
  var Rest: string:= UpperCase(Trim(Copy(Body, K, MaxInt)));
  if Name = 'TYPEINFO' then
  begin
    if Rest.StartsWith('ON') then
    begin
      FMPlus:= True;
      FMMinusLine:= 0;
    end
    else if Rest.StartsWith('OFF') then
    begin
      FMPlus:= False;
      FMMinusLine:= ATok.Line;
    end;
  end
  else if Name = 'RTTI' then CheckRttiExplicit(ATok, Rest)
  else if Name = 'WEAKLINKRTTI' then
  begin
    if Rest.StartsWith('ON') and (FWeakLinkLine = 0) then FWeakLinkLine:= ATok.Line;
  end
  else if Length(Name) = 1 then
  begin
    { switch form, possibly combined: $M+ / $A+,M- }
    for var Part in UpperCase(Body).Split([','], TStringSplitOptions.ExcludeEmpty) do
    begin
      var P: string:= Trim(Part);
      if (Length(P) = 2) and (P[1] = 'M') and (P[2] = '+') then
      begin
        FMPlus:= True;
        FMMinusLine:= 0;
      end
      else if (Length(P) = 2) and (P[1] = 'M') and (P[2] = '-') then
      begin
        FMPlus:= False;
        FMMinusLine:= ATok.Line;
      end;
    end;
  end;
end;

function TRttiScan.SkipGroup(AIndex: Integer; const AOpen, AClose: string): Integer;
begin
  var Depth: Integer:= 0;
  Result:= AIndex;
  while Result < Length(FToks) do
  begin
    if IsSym(Result, AOpen) then Inc(Depth)
    else if IsSym(Result, AClose) then
    begin
      Dec(Depth);
      if Depth <= 0 then Exit(Result + 1);
    end
    else if FToks[Result].Kind = rtDirective then HandleDirective(FToks[Result]);
    Inc(Result);
  end;
end;

{ AIndex sits on an opening record / object / class / interface keyword; returns the index after its
  matching 'end'. Nested bodies open on record, on object not after 'of', and on class / interface
  right after '=' unless a forward or a metaclass follows. }
{ A class / interface / dispinterface keyword right after '=' that is neither a forward nor a metaclass. }
function TRttiScan.OpensNestedType(AIndex: Integer): Boolean;
begin
  var IsTypeWord: Boolean:= MatchText(Tok(AIndex).Text, ['class', 'interface', 'dispinterface']) and (Tok(AIndex).Kind = rtIdent);
  var Declared: Boolean:= IsSym(AIndex - 1, '=');
  var HasBody: Boolean:= not IsIdent(AIndex + 1, 'of') and not IsSym(AIndex + 1, ';');
  Result:= IsTypeWord and Declared and HasBody;
end;

function TRttiScan.SkipBody(AIndex: Integer): Integer;
begin
  var Depth: Integer:= 1;
  Result:= AIndex + 1;
  while Result < Length(FToks) do
  begin
    var T: TRttiTok:= FToks[Result];
    if T.Kind = rtDirective then HandleDirective(T)
    else if T.Kind = rtIdent then
    begin
      if SameText(T.Text, 'end') then
      begin
        Dec(Depth);
        if Depth = 0 then Exit(Result + 1);
      end
      else if SameText(T.Text, 'record') then Inc(Depth)
      else if SameText(T.Text, 'object') and not IsIdent(Result - 1, 'of') then Inc(Depth)
      else if OpensNestedType(Result) then Inc(Depth);
    end;
    Inc(Result);
  end;
end;

function TRttiScan.SkipToSemicolon(AIndex: Integer): Integer;
begin
  Result:= AIndex;
  while Result < Length(FToks) do
  begin
    var T: TRttiTok:= FToks[Result];
    if T.Kind = rtDirective then
    begin
      HandleDirective(T);
      Inc(Result);
    end
    else if IsSym(Result, ';') then Exit(Result + 1)
    else if IsSym(Result, '(') then Result:= SkipGroup(Result, '(', ')')
    else if IsSym(Result, '[') then Result:= SkipGroup(Result, '[', ']')
    else if IsIdent(Result, 'record') then Result:= SkipBody(Result)
    else if IsIdent(Result, 'object') and not IsIdent(Result - 1, 'of') then Result:= SkipBody(Result)
    else Inc(Result);
  end;
end;

{ Returns the index after '=' when AIndex starts `Name [<...>] =`, else -1. }
function TRttiScan.TypeDeclEquals(AIndex: Integer): Integer;
begin
  Result:= -1;
  if Tok(AIndex).Kind <> rtIdent then Exit;
  var J: Integer:= AIndex + 1;
  if IsSym(J, '<') then J:= SkipGroup(J, '<', '>');
  if IsSym(J, '=') then Result:= J + 1;
end;

function TRttiScan.ParseEnum(AIndex: Integer; const ANameTok: TRttiTok): Integer;
var
  Values: string;
begin
  var Bad: Boolean:= EnumLacksTypeInfo(FToks, AIndex, Values, Result);
  FLocalKind.AddOrSetValue(LowerCase(ANameTok.Text), 'enum');
  if not Bad then Exit;
  FLocalEnumBad.AddOrSetValue(LowerCase(ANameTok.Text), Values);
  Add(ANameTok.Line, ANameTok.Col, SEV_WARNING, ANameTok.Text, Format('%s: %s = (%s) has explicit ordinals that '
    + 'are not contiguous from 0 -- the compiler emits no type info, TypeInfo(%s) fails (E2134) and every '
    + 'property of this type loses RTTI / ORM mapping; add RTTI-safe filler values or use a contiguous enum '
    + 'plus a code map, never renumber a persisted enum', [KIND_ENUM, ANameTok.Text, Values, ANameTok.Text]));
end;

function TRttiScan.ParseProperty(AIndex: Integer; var AClass: TRttiClass; const AVis: string): Integer;
begin
  { AIndex sits on 'property' }
  var NameTok: TRttiTok:= Tok(AIndex + 1);
  var J: Integer:= AIndex + 2;
  if IsSym(J, '[') then J:= SkipGroup(J, '[', ']');
  if (NameTok.Kind = rtIdent) and IsSym(J, ':') and SameText(AVis, VIS_PUBLISHED) then
  begin
    var Segs: TArray<string>:= nil;
    Inc(J);
    while Tok(J).Kind = rtIdent do
    begin
      Segs:= Segs + [Tok(J).Text];
      if not IsSym(J + 1, '.') then Break;
      Inc(J, 2);
    end;
    var TypeName: string:= string.Join('.', Segs);
    if TypeName <> '' then
    begin
      var P: TRttiProp;
      P.Name:= NameTok.Text;
      P.TypeName:= BareTypeName(TypeName);
      P.Line:= NameTok.Line;
      P.Col:= NameTok.Col;
      AClass.Props:= AClass.Props + [P];
    end;
  end;
  Result:= SkipToSemicolon(AIndex + 1);
end;

function TRttiScan.ParseClass(AIndex: Integer; const ANameTok: TRttiTok): Integer;
var
  C: TRttiClass;
begin
  C:= Default(TRttiClass);
  C.Name:= ANameTok.Text;
  C.Line:= ANameTok.Line;
  C.Col:= ANameTok.Col;
  C.MPlus:= FMPlus;
  C.MMinusLine:= FMMinusLine;
  var J: Integer:= AIndex + 1;
  while IsIdent(J, 'abstract') or IsIdent(J, 'sealed') do Inc(J);
  if IsSym(J, '(') then
  begin
    var Close: Integer:= SkipGroup(J, '(', ')');
    var Parts: TArray<string>:= nil;
    for var K:= J + 1 to Close - 2 do Parts:= Parts + [FToks[K].Text];
    C.Ancestor:= FirstHeritage(string.Join('', Parts));
    J:= Close;
  end;
  FLocalKind.AddOrSetValue(LowerCase(C.Name), 'class');
  FLocalAnc.AddOrSetValue(LowerCase(C.Name), C.Ancestor);
  if C.MPlus then FLocalMPlus.AddOrSetValue(LowerCase(C.Name), True);
  if IsSym(J, ';') then
  begin
    FClasses.Add(C);
    Exit(J + 1); { TFoo = class(TBar); -- no body }
  end;
  var Vis: string:= '';
  while J < Length(FToks) do
  begin
    var T: TRttiTok:= FToks[J];
    if T.Kind = rtDirective then
    begin
      HandleDirective(T);
      Inc(J);
      Continue;
    end;
    if T.Kind = rtSymbol then
    begin
      if T.Text = '(' then J:= SkipGroup(J, '(', ')')
      else if T.Text = '[' then J:= SkipGroup(J, '[', ']')
      else Inc(J);
      Continue;
    end;
    if T.Kind <> rtIdent then
    begin
      Inc(J);
      Continue;
    end;
    var W: string:= LowerCase(T.Text);
    if W = 'end' then
    begin
      Inc(J);
      Break;
    end;
    if InList(W, VIS_WORDS) then
    begin
      Vis:= W;
      if W = VIS_PUBLISHED then C.HasPublished:= True;
      Inc(J);
    end
    else if W = 'property' then J:= ParseProperty(J, C, Vis)
    else if W = 'record' then J:= SkipBody(J)
    else if (W = 'object') and not IsIdent(J - 1, 'of') then J:= SkipBody(J)
    else if OpensNestedType(J) then J:= SkipBody(J)
    else Inc(J);
  end;
  FClasses.Add(C);
  Result:= SkipToSemicolon(J);
end;

function TRttiScan.ParseTypeDecl(AIndex: Integer): Integer;
begin
  var NameTok: TRttiTok:= FToks[AIndex];
  var J: Integer:= TypeDeclEquals(AIndex);
  if IsIdent(J, 'type') then Inc(J);
  if IsIdent(J, 'packed') then Inc(J);
  var Kind: string:= 'other';
  if IsSym(J, '(') then
  begin
    Kind:= 'enum';
    J:= ParseEnum(J, NameTok);
  end
  else if IsIdent(J, 'class') and not IsIdent(J + 1, 'of') and not IsSym(J + 1, ';') then
  begin
    if not IsIdent(J + 1, 'helper') then Exit(ParseClass(J, NameTok));
    J:= SkipBody(J);
  end
  else if IsIdent(J, 'record') or IsIdent(J, 'object') or OpensNestedType(J) then
  begin
    if IsIdent(J, 'record') and not IsIdent(J + 1, 'helper') then Kind:= 'record';
    J:= SkipBody(J);
  end;
  FLocalKind.AddOrSetValue(LowerCase(NameTok.Text), Kind);
  Result:= SkipToSemicolon(J);
end;
{ AIndex sits on the routine keyword of `procedure TFoo.DefineProperties(...)`: collects every
  identifier and string literal up to the next method implementation header or section end. }
procedure TRttiScan.CollectDefineProperties(AIndex: Integer; const AClassName: string);
var
  Names: TDictionary<string, Boolean>;
begin
  if not FDefProps.TryGetValue(LowerCase(AClassName), Names) then
  begin
    Names:= TDictionary<string, Boolean>.Create;
    FDefProps.Add(LowerCase(AClassName), Names);
  end;
  var J: Integer:= AIndex + HDR_NAME_OFFSET + 1;
  while J < Length(FToks) do
  begin
    var T: TRttiTok:= FToks[J];
    if (T.Kind = rtIdent) and InList(T.Text, ROUTINE_WORDS) and (Tok(J + 1).Kind = rtIdent) and IsSym(J + 2, '.') then Break;
    if IsIdent(J, 'initialization') or IsIdent(J, 'finalization') then Break;
    if T.Kind in [rtIdent, rtString] then Names.AddOrSetValue(LowerCase(T.Text), True);
    Inc(J);
  end;
end;

function TRttiScan.StoreHeritage(const AName: string; out AAncestor: string): Boolean;
begin
  AAncestor:= '';
  for var Store in [FStore, FLib] do
  begin
    if Store = nil then Continue;
    for var S in Store.FindSymbolsByExactName(AName) do
      if (S.Kind = skClass) and not S.IsHelper then
      begin
        AAncestor:= FirstHeritage(S.Heritage);
        Exit(True);
      end;
  end;
  Result:= False;
end;

{ Walks the ancestor chain from AAncestor: triYes when it reaches a name in ATargets (or, with
  AUseMPlus, a class of this file declared under $M+), triNo when it ends at TObject or a known
  RTTI-less root, triUnknown when a link is in neither index. }
function TRttiScan.Reaches(const AAncestor: string; ATargets: TDictionary<string, Boolean>; AUseMPlus: Boolean): TTri;
begin
  var Cur: string:= AAncestor;
  for var Step:= 1 to MAX_ANCESTRY_DEPTH do
  begin
    if Cur = '' then Exit(triNo);
    var Lc: string:= LowerCase(Cur);
    if ATargets.ContainsKey(Lc) then Exit(triYes);
    if AUseMPlus and FLocalMPlus.ContainsKey(Lc) then Exit(triYes);
    if InList(Lc, BUILTIN_NO_RTTI_ROOTS) then Exit(triNo);
    var Next: string;
    if FLocalAnc.TryGetValue(Lc, Next) then
    begin
      Cur:= Next;
      Continue;
    end;
    if not StoreHeritage(Cur, Next) then Exit(triUnknown);
    Cur:= Next;
  end;
  Result:= triUnknown;
end;

function TRttiScan.IsRecordType(const ATypeName: string): Boolean;
var
  Kind  : string;
  Cached: TTri;
begin
  var Lc: string:= LowerCase(ATypeName);
  if FLocalKind.TryGetValue(Lc, Kind) then Exit(Kind = 'record');
  if FTypeCache.TryGetValue('rec|' + Lc, Cached) then Exit(Cached = triYes);
  Cached:= triUnknown;
  for var Store in [FStore, FLib] do
  begin
    if (Store = nil) or (Cached <> triUnknown) then Continue;
    for var S in Store.FindSymbolsByExactName(ATypeName) do
    begin
      if (S.Kind = skRecord) and not S.IsHelper then Cached:= triYes
      else if (S.Kind in [skClass, skInterface, skEnum, skTypeAlias]) and (Cached = triUnknown) then Cached:= triNo;
    end;
  end;
  if Cached = triUnknown then Cached:= TTri(Ord(InList(Lc, BUILTIN_RECORDS)));
  FTypeCache.AddOrSetValue('rec|' + Lc, Cached);
  Result:= Cached = triYes;
end;

function TRttiScan.EnumWithoutTypeInfo(const ATypeName: string; out AValues: string): Boolean;
var
  Kind  : string;
  Cached: TTri;
begin
  AValues:= '';
  var Lc: string:= LowerCase(ATypeName);
  if FLocalEnumBad.TryGetValue(Lc, AValues) then Exit(True);
  if FLocalKind.TryGetValue(Lc, Kind) then Exit(False);
  if FTypeCache.TryGetValue('enum|' + Lc, Cached) then Exit(Cached = triYes); { a cache hit reports no value list }
  Cached:= triNo;
  for var S in FStore.FindSymbolsByExactName(ATypeName) do
  begin
    if S.Kind <> skEnum then Continue;
    var Path: string:= FStore.GetFilePath(S.FileId);
    if not TFile.Exists(Path) then Continue;
    var Lines: TArray<string>;
    try
      Lines:= TFile.ReadAllLines(Path);
    except  // dl:ok try-except-swallowed@665b -- REVIEWED 2026-11-11: an unreadable enum source judges nothing; the enum counts as having type info (silent, never a false finding)
      on EInOutError do Continue;
      on EEncodingError do Continue;
    end;
    var Frag: string:= '';
    for var K:= S.StartLine - 1 to S.EndLine - 1 do
      if (K >= 0) and (K < Length(Lines)) then Frag:= Frag + Lines[K] + #10;
    var Toks: TArray<TRttiTok>:= Tokenize(Frag);
    for var K:= 0 to High(Toks) do
      if (Toks[K].Kind = rtSymbol) and (Toks[K].Text = '(') then
      begin
        var EndAt: Integer;
        if EnumLacksTypeInfo(Toks, K, AValues, EndAt) then Cached:= triYes;
        Break;
      end;
    Break;
  end;
  FTypeCache.AddOrSetValue('enum|' + Lc, Cached);
  Result:= Cached = triYes;
end;

procedure TRttiScan.Evaluate;
var
  Values : string;
  DefSet : TDictionary<string, Boolean>;
begin
  var MMinusDone: TDictionary<Integer, Boolean>:= TDictionary<Integer, Boolean>.Create;
  try
    var HasComponent: Boolean:= False;
    for var C in FClasses do
    begin
      if (FWeakLinkLine > 0) and not HasComponent then HasComponent:= Reaches(C.Ancestor, FComponent, False) = triYes;
      if not C.HasPublished then Continue;
      if not C.MPlus and (Reaches(C.Ancestor, FPersistent, True) = triNo) then
      begin
        Add(C.Line, C.Col, SEV_WARNING, C.Name, Format('%s: %s has a published section but no TPersistent ancestor '
          + 'and is not declared under {$M+} -- TWriter / TReader cannot stream it, so its published members are '
          + 'lost to classic streaming; derive it from TPersistent (or TInterfacedPersistent) or declare it under {$M+}',
          [KIND_NO_PERSIST, C.Name]));
        if (C.MMinusLine > 0) and not MMinusDone.ContainsKey(C.MMinusLine) then
        begin
          MMinusDone.Add(C.MMinusLine, True);
          Add(C.MMinusLine, 1, SEV_WARNING, C.Name, Format('%s: {$M-} / {$TYPEINFO OFF} is in effect over %s, a class '
            + 'with a published section and no RTTI-bearing ancestor -- its published members get no type info; '
            + 'remove the switch or restore {$M+} before the class', [KIND_DIRECTIVE, C.Name]));
        end;
      end;
      FDefProps.TryGetValue(LowerCase(C.Name), DefSet);
      for var P in C.Props do
      begin
        if EnumWithoutTypeInfo(P.TypeName, Values) then
          Add(P.Line, P.Col, SEV_WARNING, C.Name + '.' + P.Name, Format('%s: published property %s.%s is of type %s, '
            + 'which has no type info (explicit ordinals not contiguous from 0%s) -- the property is invisible to '
            + 'TWriter and to RTTI / ORM mapping; make the enum RTTI-safe with filler values',
            [KIND_ENUM, C.Name, P.Name, P.TypeName, (if Values <> '' then ': ' + Values else '')]))
        else if IsRecordType(P.TypeName) then
        begin
          if (DefSet <> nil) and DefSet.ContainsKey(LowerCase(P.Name)) then
            Add(P.Line, P.Col, SEV_INFO, C.Name + '.' + P.Name, Format('%s: published property %s.%s is of record type '
              + '%s -- TWriter.WriteComponent skips record properties; %s.DefineProperties names it, so classic '
              + 'streaming is covered by hand; extended RTTI still sees the property',
              [KIND_RECORD, C.Name, P.Name, P.TypeName, C.Name]))
          else
            Add(P.Line, P.Col, SEV_WARNING, C.Name + '.' + P.Name, Format('%s: published property %s.%s is of record '
              + 'type %s -- TWriter.WriteComponent skips it silently and the value is lost from the stream; stream it '
              + 'in an overridden DefineProperties (Filer.DefineProperty / DefineBinaryProperty)',
              [KIND_RECORD, C.Name, P.Name, P.TypeName]));
        end;
      end;
    end;
    if (FWeakLinkLine > 0) and HasComponent then
      Add(FWeakLinkLine, 1, SEV_WARNING, '', Format('%s: {$WEAKLINKRTTI ON} in a unit that declares components -- the '
        + 'linker may drop the RTTI of members nothing references by name, so TRttiContext and RTTI-based '
        + 'persistence see an incomplete class; remove it from units that declare persistent classes', [KIND_DIRECTIVE]));
  finally
    MMinusDone.Free;
  end;
end;

procedure TRttiScan.Run;
begin
  var InType: Boolean:= False;
  var InImpl: Boolean:= False;
  var I: Integer:= 0;
  while I < Length(FToks) do
  begin
    var T: TRttiTok:= FToks[I];
    if T.Kind = rtDirective then
    begin
      HandleDirective(T);
      Inc(I);
      Continue;
    end;
    if T.Kind <> rtIdent then
    begin
      Inc(I);
      Continue;
    end;
    var W: string:= LowerCase(T.Text);
    if W = 'implementation' then
    begin
      InImpl:= True;
      InType:= False;
    end
    else if W = 'type' then InType:= True
    else if InList(W, SECTION_END_WORDS) or (W = 'end') then
    begin
      InType:= False;
      if InImpl and InList(W, ROUTINE_WORDS) and (Tok(I + 1).Kind = rtIdent) and IsSym(I + 2, '.')
        and IsIdent(I + HDR_NAME_OFFSET, DEFINE_PROPERTIES) then CollectDefineProperties(I, Tok(I + 1).Text);
    end
    else if InType and (TypeDeclEquals(I) > 0) then
    begin
      I:= ParseTypeDecl(I);
      Continue;
    end;
    Inc(I);
  end;
  Evaluate;
end;

{ ---- entry ---------------------------------------------------------------------------------- }

function CollectRttiUnavailable(const AStore, ALibraryStore: ISymbolStore; const AOnlyFileId: Int64): TArray<TLintFinding>;
var
  Sh: TRttiShared;

  procedure Seed(ADict: TDictionary<string, Boolean>; const ARoot: string; const ABuiltin: array of string);
  begin
    for var S in ABuiltin do ADict.AddOrSetValue(S, True);
    for var Store in [AStore, ALibraryStore] do
      if Store <> nil then
        for var N in Store.FindDescendantNames(ARoot) do ADict.AddOrSetValue(LowerCase(N), True);
  end;

begin
  Result:= nil;
  if AStore = nil then Exit;
  Sh.Findings:= TList<TLintFinding>.Create;
  Sh.Persistent:= TDictionary<string, Boolean>.Create;
  Sh.Component:= TDictionary<string, Boolean>.Create;
  Sh.TypeCache:= TDictionary<string, TTri>.Create;
  try
    Seed(Sh.Persistent, 'TPersistent', BUILTIN_PERSISTENT);
    Seed(Sh.Component, 'TComponent', BUILTIN_COMPONENT);
    var Ids: TArray<Int64>:= [AOnlyFileId];
    if AOnlyFileId <= 0 then Ids:= AStore.GetAllFileIds;
    for var Fid in Ids do
    begin
      var Path: string:= AStore.GetFilePath(Fid);
      if not InList(LowerCase(ExtractFileExt(Path)), SOURCE_EXTS) or not TFile.Exists(Path) then Continue;
      var Text: string;
      try
        Text:= TFile.ReadAllText(Path);
      except  // dl:ok try-except-swallowed@665b -- REVIEWED 2026-11-11: an unreadable source file is skipped, as the DocInsight remarks of CollectRttiUnavailable state
        on EInOutError do Continue;
        on EEncodingError do Continue;
      end;
      var Scan: TRttiScan:= TRttiScan.Create(AStore, ALibraryStore, Fid, Path, Text, Sh);
      try
        Scan.Run;
      finally
        Scan.Free;
      end;
    end;
    Result:= Sh.Findings.ToArray;
  finally
    Sh.TypeCache.Free;
    Sh.Component.Free;
    Sh.Persistent.Free;
    Sh.Findings.Free;
  end;
end;

end.
