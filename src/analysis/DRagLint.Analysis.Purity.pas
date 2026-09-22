unit DRagLint.Analysis.Purity;

{ Interprocedural purity v2 -- the PURE half of the model (spec
  docs\superpowers\specs\2026-09-15-interprocedural-purity.md, sections 3, 5.3
  and 7.3). No database, no file I/O: an effect-summary lattice, the closed
  axiom list and built-in table, a call-argument lexer, a routine-body scanner,
  an argument classifier and the callee -> caller translation. The resolve
  stage (plan C6.1 Task 3) drives these against symbol_facts; this unit never
  sees the store, which is what makes tests\PurityModelTests.dpr a plain dcc64
  console build. }

interface

uses
  System.SysUtils,
  System.Math,
  System.StrUtils,
  System.Generics.Collections,
  System.RegularExpressions;

type
  /// <summary>One coordinate of the effect lattice (spec 3.1): a routine
  /// writes global state, frees or resizes heap storage, writes fields of its
  /// own instance, or does something this build cannot classify.</summary>
  TEffectFlag  = (efGlobal, efHeap, efSelfFields, efUnknown);
  /// <summary>The flag half of an effect summary.</summary>
  TEffectFlags = set of TEffectFlag;

  /// <summary>A routine's effect summary (spec 3.1): the set of flags plus the
  /// 0-based ordinals of the parameters it writes through, and the FIRST
  /// blocker recorded as a human-readable witness.</summary>
  /// <remarks>Invariants: <c>Params</c> is ascending and distinct; <c>Witness</c>
  /// is set by the first <c>AddFlag</c>/<c>AddParam</c> that changes the summary
  /// and never overwritten. A zero-initialised record is the bottom element
  /// (effect-free). Arity is NOT checked here -- the stage enforces
  /// <c>k &lt; ParamCount</c> before calling <c>AddParam</c>.</remarks>
  TEffectSummary = record
    Flags  : TEffectFlags;
    Params : TArray<Integer>;
    Witness: string;
    /// <summary>True when no flag is set and no parameter is written.</summary>
    /// <returns><c>(Flags = []) and (Length(Params) = 0)</c>.</returns>
    function IsEffectFree: Boolean;
    /// <summary>Whether the routine writes through the given 0-based parameter.</summary>
    /// <param name="AOrdinal">0-based parameter ordinal.</param>
    /// <returns>True when <c>AOrdinal</c> is in <c>Params</c>.</returns>
    function WritesParam(AOrdinal: Integer): Boolean;
    /// <summary>Serialises the summary as the stored effect string: tokens
    /// <c>g</c>, <c>h</c>, <c>s</c>, then <c>p&lt;k&gt;</c> per parameter in
    /// ascending order, then <c>?</c>, joined with commas.</summary>
    /// <returns>E.g. <c>'g,p0,p3,?'</c>; <c>''</c> for an effect-free summary.</returns>
    function Encode: string;
    /// <summary>Parses an effect string written by <c>Encode</c>.</summary>
    /// <param name="AText">Comma-separated tokens; blanks around tokens are ignored.</param>
    /// <returns>The decoded summary. An unrecognised token sets <c>efUnknown</c>:
    /// a summary this build cannot read is not clean.</returns>
    class function Decode(const AText: string): TEffectSummary; static;
    /// <summary>Joins one flag into the summary.</summary>
    /// <param name="AFlag">The flag to include.</param>
    /// <param name="AWitness">Recorded as <c>Witness</c> only when this call is
    /// the first change to the summary.</param>
    /// <param name="AChanged">Set True when the flag was not already present;
    /// left untouched otherwise.</param>
    procedure AddFlag(AFlag: TEffectFlag; const AWitness: string; var AChanged: Boolean);
    /// <summary>Joins one written-parameter ordinal into the summary, keeping
    /// <c>Params</c> ascending and distinct.</summary>
    /// <param name="AOrdinal">0-based parameter ordinal; not range-checked here.</param>
    /// <param name="AWitness">Recorded as <c>Witness</c> only when this call is
    /// the first change to the summary.</param>
    /// <param name="AChanged">Set True when the ordinal was not already present;
    /// left untouched otherwise.</param>
    procedure AddParam(AOrdinal: Integer; const AWitness: string; var AChanged: Boolean);
  end;

  /// <summary>How a call argument (or a receiver) relates to the caller's own
  /// storage (spec 3.5): a literal, a non-escaping local, one of the caller's
  /// parameters, the caller's own instance or a field of it, or unclassified.</summary>
  TArgClass = (acLiteral, acLocal, acParam, acSelfOrField, acUnknown);

  /// <summary>One classified argument.</summary>
  /// <remarks><c>ParamOrdinal</c> is meaningful only when <c>Cls = acParam</c>
  /// and is -1 otherwise. <c>RootName</c> is the leading identifier exactly as
  /// written ('' for a literal or an address-of); <c>Text</c> is the whole
  /// argument, trimmed.</remarks>
  TArgInfo = record
    Cls         : TArgClass;
    ParamOrdinal: Integer;
    RootName    : string;
    Text        : string;
  end;

  /// <summary>Syntactic facts about a routine body that the resolve stage uses
  /// to decide whether the body can be trusted at all (spec 7.3).</summary>
  /// <remarks><c>HasVarBlock</c> is a <c>var</c> section before the first
  /// <c>begin</c>; <c>HasInlineVar</c> an inline <c>var X</c> (including
  /// <c>for var</c>) at or after it; <c>HasWith</c> a <c>with</c> statement at
  /// or after it; <c>HasBareInherited</c> a bare <c>inherited;</c> anywhere in
  /// the range. Comments, directives and string literals are never counted.</remarks>
  TBodyScan = record
    HasWith, HasBareInherited, HasVarBlock, HasInlineVar: Boolean;
  end;

  /// <summary>A set of identifier names; keys are LOWERCASED by the caller.</summary>
  TNameSet   = TDictionary<string, Boolean>;
  /// <summary>Lowercased parameter name -> 0-based ordinal.</summary>
  TParamMap  = TDictionary<string, Integer>;

const
  /// <summary>The lexer gives up on an argument list that spans more lines
  /// than this (spec 3.4 option 1).</summary>
  CMaxArgListLines = 64;

/// <summary>Whether <c>AName</c> is one of the CLOSED list of compiler
/// intrinsics and cast type names that never write anything (spec 5.3,
/// "survives"). Case-insensitive.</summary>
/// <param name="AName">Bare callee name as written.</param>
/// <returns>True for an axiom; a name not in the list is not an axiom,
/// whatever it is. There is no growth hook.</returns>
function IsPurityAxiom(const AName: string): Boolean;

/// <summary>Looks up the known effect summary of a compiler intrinsic that
/// WRITES (spec 5.3, second table): <c>Inc</c>, <c>SetLength</c>, <c>Val</c>,
/// <c>Dispose</c> and friends. Case-insensitive.</summary>
/// <param name="AName">Bare callee name as written.</param>
/// <param name="ASummary">The intrinsic's summary when found; undefined otherwise.</param>
/// <returns>True when <c>AName</c> is in the table.</returns>
function BuiltinSummary(const AName: string; out ASummary: TEffectSummary): Boolean;

/// <summary>Lexes the argument list that follows a callee name (spec 3.4
/// option 1): the FIRST parenthesised group after the name, split on
/// top-level commas.</summary>
/// <param name="ALines">The unit's lines.</param>
/// <param name="ALine">1-based line of the name in <c>ALines</c>.</param>
/// <param name="AColAfterName">1-based column just past the name
/// (<c>StartCol + Length(Name)</c>).</param>
/// <param name="AArgs">Each argument's text, trimmed; nil when the call has
/// no parenthesis.</param>
/// <returns>True when the list was lexed (a call with no parenthesis or with
/// <c>()</c> is lexed with zero arguments). False -- UNLEXABLE -- when a
/// <c>{$...}</c> directive sits inside the list, a string literal is left
/// open, or the closing parenthesis is not found within
/// <c>CMaxArgListLines</c> lines or before the end of <c>ALines</c>.</returns>
/// <remarks>Commas inside nested parentheses, brackets, string literals and
/// comments do not split; comment text is dropped from the argument text; a
/// line break inside an argument becomes one space. The ( is looked for on
/// the name's OWN line with only blanks between; when it follows a comment or
/// a line break the call is lexed as zero arguments, and the stage treats that
/// conservatively. Within that contract the argument COUNT agrees with
/// <c>CountCallArgs</c> in DRagLint.Index.CallResolver (which additionally
/// skips comments and newlines before the parenthesis).</remarks>
function LexCallArguments(const ALines: TArray<string>; ALine, AColAfterName: Integer;
  out AArgs: TArray<string>): Boolean;

/// <summary>Scans a routine's implementation lines for the body shapes of
/// spec 7.3 (see <see cref="TBodyScan"/>).</summary>
/// <param name="ALines">The unit's lines.</param>
/// <param name="AImplStart">1-based first line of the implementation, inclusive.</param>
/// <param name="AImplEnd">1-based last line, inclusive; both are clamped to the array.</param>
/// <returns>The flags found. Word tests are case-insensitive and run on lines
/// stripped by <see cref="StripCommentsAndStrings"/>.</returns>
function ScanRoutineBody(const ALines: TArray<string>; AImplStart, AImplEnd: Integer): TBodyScan;

/// <summary>Returns <c>ALine</c> with every string literal replaced by
/// <c>''</c> and every comment (<c>{ }</c>, <c>(* *)</c>, <c>//</c>, and
/// <c>{$...}</c> directives alike) replaced by a single space.</summary>
/// <param name="ALine">One source line.</param>
/// <param name="AInBrace">Carries an open <c>{</c> comment across lines; pass
/// False for the first line and the same variable for each following line.</param>
/// <param name="AInParen">Carries an open <c>(*</c> comment likewise.</param>
/// <returns>The stripped line. Column positions are NOT preserved.</returns>
function StripCommentsAndStrings(const ALine: string; var AInBrace, AInParen: Boolean): string;

/// <summary>Returns <c>ALine</c> with every comment and the CONTENTS of every
/// string literal replaced by blanks, column for column, so a column measured
/// on the raw line lands on the same character of the result. The quotes of a
/// literal are kept; a <c>{</c> or <c>(*</c> comment left open by an earlier
/// line is not known here (each line is masked on its own, as
/// <see cref="ReadEscapesOnLine"/> does).</summary>
/// <param name="ALine">One raw source line.</param>
/// <returns>A string of the same length as <c>ALine</c>.</returns>
/// <remarks>The stage uses it to find the <c>(</c> that encloses a read at a
/// known column, where the compact form of <see cref="StripCommentsAndStrings"/>
/// would have shifted the columns.</remarks>
function MaskLinePreservingColumns(const ALine: string): string;

/// <summary>Classifies one call argument against the caller's own names
/// (spec 3.5, plan ruling 8).</summary>
/// <param name="AArgText">The argument as lexed.</param>
/// <param name="ALocals">Lowercased names of the caller's locals.</param>
/// <param name="AParams">Lowercased parameter name -> 0-based ordinal.</param>
/// <param name="AFields">Lowercased names of the owning class's fields.</param>
/// <param name="AEscaping">Lowercased locals whose value escapes the routine
/// (see <see cref="ReadEscapesOnLine"/>); such a local is never
/// <c>acLocal</c>.</param>
/// <returns>Literal for a number, string, char, hex, <c>nil</c>, <c>True</c>
/// or <c>False</c>; unknown for an address-of. Otherwise the leading
/// identifier decides: <c>Self</c> and a field (with or without a member
/// suffix) are <c>acSelfOrField</c>; a parameter (with or without a suffix)
/// is <c>acParam</c>; a local is <c>acLocal</c> only when it is bare and
/// non-escaping; anything else is <c>acUnknown</c>.</returns>
function ClassifyArgument(const AArgText: string; ALocals: TNameSet; AParams: TParamMap;
  AFields: TNameSet; AEscaping: TNameSet): TArgInfo;

/// <summary>Decides whether ONE read of a local at a given column lets its
/// value escape the routine (spec 3.5).</summary>
/// <param name="ALine">The raw source line; comments and string literals are
/// masked internally without moving columns.</param>
/// <param name="AStartCol">1-based column of the read.</param>
/// <param name="ANameLen">Length of the name at <c>AStartCol</c>.</param>
/// <param name="AInsideCallArgs">True when the read sits inside an open
/// parenthesis on this line, i.e. is an argument. Whether an argument of an
/// UNBOUND call escapes is decided by the stage, which knows the binding.</param>
/// <returns>True when the read is right of an <c>:=</c> or is taken by
/// <c>@</c>. A receiver position (the name is followed by <c>.</c>) never
/// escapes.</returns>
function ReadEscapesOnLine(const ALine: string; AStartCol, ANameLen: Integer;
  out AInsideCallArgs: Boolean): Boolean;

/// <summary>Folds a callee's summary into its caller's (spec 3.3): global,
/// heap and unknown propagate as they are; self-field writes translate through
/// the receiver's class; each written callee parameter translates through the
/// class of the argument in that position.</summary>
/// <param name="ACallee">The callee's summary.</param>
/// <param name="ACalleeName">Callee name for witness text.</param>
/// <param name="AArgs">Classified arguments in call order; ignored when
/// <c>AArgsKnown</c> is False.</param>
/// <param name="AArgsKnown">False when the argument list was UNLEXABLE; any
/// written callee parameter then makes the caller unknown.</param>
/// <param name="AReceiver">Classified receiver (<c>acUnknown</c> when the call
/// has none or it could not be classified).</param>
/// <param name="ACaller">The caller's summary, joined in place.</param>
/// <param name="AChanged">Set True when <c>ACaller</c> changed.</param>
/// <remarks>Every witness for an unbound or unclassified callee starts with
/// <c>calls </c>; the unbound form contains <c>(unbound</c>.</remarks>
procedure TranslateCallee(const ACallee: TEffectSummary; const ACalleeName: string;
  const AArgs: TArray<TArgInfo>; AArgsKnown: Boolean; const AReceiver: TArgInfo;
  var ACaller: TEffectSummary; var AChanged: Boolean);

/// <summary>Parses the display string of <c>symbol_facts.mutates_params</c>
/// (written by <c>JoinCappedDisplay</c>, e.g. <c>'AList (var), AReason (out)'</c>)
/// back into bare parameter names.</summary>
/// <param name="AMutatesParams">The stored display string.</param>
/// <param name="ACapped">True when the string carries the <c>(+N more)</c>
/// suffix, i.e. names were dropped by the cap and the list is incomplete.</param>
/// <returns>The names shown, in order, with the <c>(var)</c>/<c>(out)</c>
/// modifier stripped; empty for <c>''</c>.</returns>
function ParseMutatedParamNames(const AMutatesParams: string; out ACapped: Boolean): TArray<string>;

implementation

const
  TOKEN_GLOBAL  = 'g';
  TOKEN_HEAP    = 'h';
  TOKEN_SELF    = 's';
  TOKEN_UNKNOWN = '?';
  TOKEN_PARAM   = 'p';

  { Spec 5.3 "survives": intrinsics that never write, plus the cast type names. }
  PURITY_AXIOMS: array[0..58] of string = (
    'exit', 'break', 'continue', 'length', 'high', 'low', 'ord', 'chr', 'succ',
    'pred', 'sizeof', 'assigned', 'abs', 'sqr', 'sqrt', 'odd', 'trunc', 'round',
    'int', 'frac', 'typeinfo', 'default', 'concat', 'slice', 'copy', 'pos',
    'swap', 'addr',
    'integer', 'cardinal', 'byte', 'word', 'shortint', 'smallint', 'longint',
    'longword', 'int64', 'uint64', 'nativeint', 'nativeuint', 'boolean', 'char',
    'ansichar', 'widechar', 'string', 'ansistring', 'widestring',
    'unicodestring', 'shortstring', 'pchar', 'pansichar', 'pwidechar',
    'pointer', 'single', 'double', 'extended', 'currency', 'real', 'comp');

type
  TBuiltinRow = record
    Name: string;
    Code: string;
  end;

const
  { Spec 5.3, second table: intrinsics that WRITE, and what they write. }
  PURITY_BUILTINS: array[0..14] of TBuiltinRow = (
    (Name: 'Inc';       Code: 'p0'),
    (Name: 'Dec';       Code: 'p0'),
    (Name: 'SetLength'; Code: 'p0'),
    (Name: 'Include';   Code: 'p0'),
    (Name: 'Exclude';   Code: 'p0'),
    (Name: 'Delete';    Code: 'p0'),
    (Name: 'FillChar';  Code: 'p0'),
    (Name: 'New';       Code: 'p0'),
    (Name: 'GetMem';    Code: 'p0'),
    (Name: 'Insert';    Code: 'p1'),
    (Name: 'Str';       Code: 'p1'),
    (Name: 'Move';      Code: 'p1'),
    (Name: 'Val';       Code: 'p1,p2'),
    (Name: 'Dispose';   Code: 'h'),
    (Name: 'FreeMem';   Code: 'h'));

  MODIFIER_VAR = ' (var)';
  MODIFIER_OUT = ' (out)';
  CAP_MARKER   = '(+';

var
  { Compiled once; TRegEx.IsMatch(Input, Pattern) would recompile per line. }
  RxBegin, RxVarBlock, RxInlineVar, RxWith, RxBareInherited, RxCappedTail: TRegEx;

{ ---------------------------------------------------------------- TEffectSummary }

function TEffectSummary.IsEffectFree: Boolean;
begin
  Result:= (Flags = []) and (Length(Params) = 0);
end;

function TEffectSummary.WritesParam(AOrdinal: Integer): Boolean;
begin
  for var K in Params do
    if K = AOrdinal then Exit(True);
  Result:= False;
end;

function TEffectSummary.Encode: string;
  procedure Add(var AText: string; const AToken: string);
  begin
    if AText <> '' then AText:= AText + ',';
    AText:= AText + AToken;
  end;
begin
  Result:= '';
  if efGlobal in Flags then Add(Result, TOKEN_GLOBAL);
  if efHeap in Flags then Add(Result, TOKEN_HEAP);
  if efSelfFields in Flags then Add(Result, TOKEN_SELF);
  for var K in Params do Add(Result, TOKEN_PARAM + IntToStr(K));
  if efUnknown in Flags then Add(Result, TOKEN_UNKNOWN);
end;

class function TEffectSummary.Decode(const AText: string): TEffectSummary;
var
  Tok    : string;
  Ordinal: Integer;
  Changed: Boolean;
begin
  Result:= Default(TEffectSummary);
  Changed:= False;
  for var Raw in AText.Split([',']) do
  begin
    Tok:= LowerCase(Trim(Raw));
    if Tok = '' then Continue;
    if Tok = TOKEN_GLOBAL then Result.AddFlag(efGlobal, '', Changed)
    else if Tok = TOKEN_HEAP then Result.AddFlag(efHeap, '', Changed)
    else if Tok = TOKEN_SELF then Result.AddFlag(efSelfFields, '', Changed)
    else if Tok = TOKEN_UNKNOWN then Result.AddFlag(efUnknown, '', Changed)
    else if (Tok[1] = TOKEN_PARAM) and TryStrToInt(Copy(Tok, 2, MaxInt), Ordinal) and (Ordinal >= 0) then
      Result.AddParam(Ordinal, '', Changed)
    else
      Result.AddFlag(efUnknown, 'unrecognised effect token ' + Raw, Changed);
  end;
end;

procedure TEffectSummary.AddFlag(AFlag: TEffectFlag; const AWitness: string; var AChanged: Boolean);
begin
  if AFlag in Flags then Exit;
  Include(Flags, AFlag);
  if Witness = '' then Witness:= AWitness;
  AChanged:= True;
end;

procedure TEffectSummary.AddParam(AOrdinal: Integer; const AWitness: string; var AChanged: Boolean);
var
  I: Integer;
begin
  I:= 0;
  while (I < Length(Params)) and (Params[I] < AOrdinal) do Inc(I);
  if (I < Length(Params)) and (Params[I] = AOrdinal) then Exit;
  Insert(AOrdinal, Params, I);
  if Witness = '' then Witness:= AWitness;
  AChanged:= True;
end;

{ ---------------------------------------------------------- axioms / built-ins }

function IsPurityAxiom(const AName: string): Boolean;
begin
  for var Axiom in PURITY_AXIOMS do
    if SameText(AName, Axiom) then Exit(True);
  Result:= False;
end;

function BuiltinSummary(const AName: string; out ASummary: TEffectSummary): Boolean;
begin
  for var Row in PURITY_BUILTINS do
    if SameText(AName, Row.Name) then
    begin
      ASummary:= TEffectSummary.Decode(Row.Code);
      Exit(True);
    end;
  ASummary:= Default(TEffectSummary);
  Result:= False;
end;

{ ------------------------------------------------------------------- masking }

{ Finds the closing quote of the string literal opening at ALine[AOpen]; a
  doubled quote is an escape. Returns the closing quote's index, or 0 when the
  literal runs off the end of the line. }
function CloseOfStringLiteral(const ALine: string; AOpen: Integer): Integer;
var
  J, N: Integer;
begin
  N:= Length(ALine);
  J:= AOpen + 1;
  while J <= N do
  begin
    if ALine[J] = '''' then
    begin
      if (J < N) and (ALine[J + 1] = '''') then Inc(J, 2)
      else Exit(J);
    end
    else Inc(J);
  end;
  Result:= 0;
end;

// While a brace or paren-star comment is open at ALine[AIdx]: consumes one
// step of it (clearing the flag on the closer) and returns the characters
// consumed. Returns 0 when no comment is open.
function SkipOpenComment(const ALine: string; AIdx: Integer; var AInBrace, AInParen: Boolean): Integer;
begin
  Result:= 0;
  if AInBrace then
  begin
    if ALine[AIdx] = '}' then AInBrace:= False;
    Result:= 1;
  end
  else if AInParen then
  begin
    if (ALine[AIdx] = '*') and (AIdx < Length(ALine)) and (ALine[AIdx + 1] = ')') then
    begin
      AInParen:= False;
      Result:= 2;
    end
    else Result:= 1;
  end;
end;

// When a brace or paren-star comment opens at ALine[AIdx]: sets the flag and
// returns the opener's length (1 or 2). Returns 0 otherwise.
function OpensComment(const ALine: string; AIdx: Integer; var AInBrace, AInParen: Boolean): Integer;
begin
  Result:= 0;
  if ALine[AIdx] = '{' then
  begin
    AInBrace:= True;
    Result:= 1;
  end
  else if (ALine[AIdx] = '(') and (AIdx < Length(ALine)) and (ALine[AIdx + 1] = '*') then
  begin
    AInParen:= True;
    Result:= 2;
  end;
end;

// True when ALine[AIdx] starts a double-slash comment.
function StartsLineComment(const ALine: string; AIdx: Integer): Boolean;
begin
  Result:= (ALine[AIdx] = '/') and (AIdx < Length(ALine)) and (ALine[AIdx + 1] = '/');
end;

{ The one masker behind StripCommentsAndStrings (compact form, spec-facing) and
  ReadEscapesOnLine (length-preserving form: comment and literal text become
  spaces so a column measured on the raw line still lands on the same
  character). A length-preserving mask is what keeps `Foo('a,b', L)` reporting
  L as an argument; the compact form would shift L left of its own `(`. }
function MaskLine(const ALine: string; var AInBrace, AInParen: Boolean;
  APreserveLength: Boolean): string;
var
  SB      : TStringBuilder;
  I, N    : Integer;
  Close   : Integer;
  Consumed: Integer;
  procedure Blank(ACount: Integer);
  begin
    if APreserveLength then SB.Append(' ', ACount);
  end;
begin
  SB:= TStringBuilder.Create(Length(ALine));
  try
    N:= Length(ALine);
    I:= 1;
    while I <= N do
    begin
      Consumed:= SkipOpenComment(ALine, I, AInBrace, AInParen);
      if Consumed = 0 then
      begin
        Consumed:= OpensComment(ALine, I, AInBrace, AInParen);
        if (Consumed > 0) and not APreserveLength then SB.Append(' ');
      end;
      if Consumed > 0 then
      begin
        Blank(Consumed);
        Inc(I, Consumed);
        Continue;
      end;
      if StartsLineComment(ALine, I) then
      begin
        Blank(N - I + 1);
        Break;
      end;
      if ALine[I] = '''' then
      begin
        Close:= CloseOfStringLiteral(ALine, I);
        if Close = 0 then Close:= N;
        SB.Append('''');
        Blank(Close - I - 1);
        if Close > I then SB.Append('''');
        I:= Close + 1;
        Continue;
      end;
      SB.Append(ALine[I]);
      Inc(I);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function StripCommentsAndStrings(const ALine: string; var AInBrace, AInParen: Boolean): string;
begin
  Result:= MaskLine(ALine, AInBrace, AInParen, False);
end;

function MaskLinePreservingColumns(const ALine: string): string;
var
  InBrace, InParen: Boolean;
begin
  InBrace:= False;
  InParen:= False;
  Result:= MaskLine(ALine, InBrace, InParen, True);
end;

{ --------------------------------------------------------------------- lexer }

function LexCallArguments(const ALines: TArray<string>; ALine, AColAfterName: Integer;
  out AArgs: TArray<string>): Boolean;
var
  Args              : TList<string>;
  Cur               : TStringBuilder;
  Line              : string;
  LineIdx, Col, N   : Integer;
  Depth, Brackets   : Integer;
  LinesSeen, Close  : Integer;
  Consumed          : Integer;
  InBrace, InParen  : Boolean;
  Done              : Boolean;
  procedure Flush(AFinal: Boolean);
  var
    T: string;
  begin
    T:= Trim(Cur.ToString);
    if (not AFinal) or (T <> '') or (Args.Count > 0) then Args.Add(T);
    Cur.Clear;
  end;
  { Moves to the next line; False when the array or the line budget is exhausted. }
  function AdvanceLine: Boolean;
  begin
    Inc(LineIdx);
    Inc(LinesSeen);
    Result:= (LineIdx <= High(ALines)) and (LinesSeen <= CMaxArgListLines);
    if not Result then Exit;
    Line:= ALines[LineIdx];
    N:= Length(Line);
    Col:= 1;
    if not (InBrace or InParen) then Cur.Append(' ');
  end;
  procedure CloseParen;
  begin
    Dec(Depth);
    if Depth = 0 then
    begin
      Flush(True);
      Done:= True;
    end
    else Cur.Append(')');
  end;
begin
  AArgs:= nil;
  Result:= False;
  if (ALine < 1) or (ALine > Length(ALines)) then Exit;
  Line:= ALines[ALine - 1];
  N:= Length(Line);
  Col:= AColAfterName;
  while (Col <= N) and CharInSet(Line[Col], [' ', #9]) do Inc(Col);
  if (Col > N) or (Line[Col] <> '(') then Exit(True);

  Args:= TList<string>.Create;
  Cur:= TStringBuilder.Create;
  try
    LineIdx:= ALine - 1;
    LinesSeen:= 1;
    Depth:= 0;
    Brackets:= 0;
    InBrace:= False;
    InParen:= False;
    Done:= False;
    while not Done do
    begin
      if Col > N then
      begin
        if not AdvanceLine then Break;
        Continue;
      end;
      if (Line[Col] = '{') and (Col < N) and (Line[Col + 1] = '$') then Break;   // a directive: UNLEXABLE
      Consumed:= SkipOpenComment(Line, Col, InBrace, InParen);
      if Consumed = 0 then Consumed:= OpensComment(Line, Col, InBrace, InParen);
      if Consumed > 0 then
      begin
        Inc(Col, Consumed);
        Continue;
      end;
      if StartsLineComment(Line, Col) then
      begin
        Col:= N + 1;
        Continue;
      end;
      case Line[Col] of
        '(':
          begin
            Inc(Depth);
            if Depth > 1 then Cur.Append('(');
            Inc(Col);
          end;
        ')':
          begin
            CloseParen;
            Inc(Col);
          end;
        '[', ']':
          begin
            if Line[Col] = '[' then Inc(Brackets) else Dec(Brackets);
            Cur.Append(Line[Col]);
            Inc(Col);
          end;
        '''':
          begin
            Close:= CloseOfStringLiteral(Line, Col);
            if Close = 0 then Break;                               // open literal: UNLEXABLE
            Cur.Append(Line, Col - 1, Close - Col + 1);
            Col:= Close + 1;
          end;
        ',':
          begin
            if (Depth = 1) and (Brackets = 0) then Flush(False)
            else Cur.Append(',');
            Inc(Col);
          end;
      else
        Cur.Append(Line[Col]);
        Inc(Col);
      end;
    end;
    if Done then
    begin
      AArgs:= Args.ToArray;
      Result:= True;
    end;
  finally
    Cur.Free;
    Args.Free;
  end;
end;

{ ------------------------------------------------------------------- scanner }

function ScanRoutineBody(const ALines: TArray<string>; AImplStart, AImplEnd: Integer): TBodyScan;
var
  First, Last      : Integer;
  InBrace, InParen : Boolean;
  SeenBegin        : Boolean;
  Stripped, Trimmed: string;
begin
  Result:= Default(TBodyScan);
  First:= Max(AImplStart, 1);
  Last:= Min(AImplEnd, Length(ALines));
  InBrace:= False;
  InParen:= False;
  SeenBegin:= False;
  for var I:= First to Last do
  begin
    Stripped:= StripCommentsAndStrings(ALines[I - 1], InBrace, InParen);
    Trimmed:= Trim(Stripped);
    if not SeenBegin then
    begin
      if RxBegin.IsMatch(Trimmed) then SeenBegin:= True
      else if RxVarBlock.IsMatch(Trimmed) then Result.HasVarBlock:= True;
    end;
    if SeenBegin then
    begin
      if RxInlineVar.IsMatch(Stripped) then Result.HasInlineVar:= True;
      if RxWith.IsMatch(Stripped) then Result.HasWith:= True;
    end;
    if RxBareInherited.IsMatch(Stripped) then Result.HasBareInherited:= True;
  end;
end;

{ ---------------------------------------------------------------- classifier }

function ClassifyArgument(const AArgText: string; ALocals: TNameSet; AParams: TParamMap;
  AFields: TNameSet; AEscaping: TNameSet): TArgInfo;
var
  Text, Root, Suffix, Key: string;
  I, Ordinal             : Integer;
begin
  Result:= Default(TArgInfo);
  Result.Cls:= acUnknown;
  Result.ParamOrdinal:= -1;
  Text:= Trim(AArgText);
  Result.Text:= Text;
  if Text = '' then Exit;
  if CharInSet(Text[1], ['0'..'9', '''', '#', '$'])
    or SameText(Text, 'nil') or SameText(Text, 'True') or SameText(Text, 'False') then
  begin
    Result.Cls:= acLiteral;
    Exit;
  end;
  if Text[1] = '@' then Exit;
  I:= 1;
  if CharInSet(Text[1], ['A'..'Z', 'a'..'z', '_']) then
  begin
    I:= 2;
    while (I <= Length(Text)) and CharInSet(Text[I], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(I);
  end;
  Root:= Copy(Text, 1, I - 1);
  Suffix:= Copy(Text, I, MaxInt);
  Result.RootName:= Root;
  if Root = '' then Exit;
  Key:= LowerCase(Root);
  if Key = 'self' then Result.Cls:= acSelfOrField
  else if (ALocals <> nil) and ALocals.ContainsKey(Key) then
  begin
    if (Suffix = '') and not ((AEscaping <> nil) and AEscaping.ContainsKey(Key)) then
      Result.Cls:= acLocal;
  end
  else if (AParams <> nil) and AParams.TryGetValue(Key, Ordinal) then
  begin
    Result.Cls:= acParam;
    Result.ParamOrdinal:= Ordinal;
  end
  else if (AFields <> nil) and AFields.ContainsKey(Key) then
    Result.Cls:= acSelfOrField;
end;

function ReadEscapesOnLine(const ALine: string; AStartCol, ANameLen: Integer;
  out AInsideCallArgs: Boolean): Boolean;
var
  Masked, Before, After: string;
  InBrace, InParen     : Boolean;
  Opens, Closes, I     : Integer;
begin
  InBrace:= False;
  InParen:= False;
  Masked:= MaskLine(ALine, InBrace, InParen, True);
  Before:= Copy(Masked, 1, AStartCol - 1);
  After:= TrimLeft(Copy(Masked, AStartCol + ANameLen, MaxInt));
  Opens:= 0;
  Closes:= 0;
  for var C in Before do
    if C = '(' then Inc(Opens)
    else if C = ')' then Inc(Closes);
  AInsideCallArgs:= Opens > Closes;
  if (After <> '') and (After[1] = '.') then Exit(False);
  if Pos(':=', Before) > 0 then Exit(True);
  I:= Length(Before);
  while (I > 0) and (Before[I] = ' ') do Dec(I);
  Result:= (I > 0) and (Before[I] = '@');
end;

{ --------------------------------------------------------------- translation }

procedure TranslateCallee(const ACallee: TEffectSummary; const ACalleeName: string;
  const AArgs: TArray<TArgInfo>; AArgsKnown: Boolean; const AReceiver: TArgInfo;
  var ACaller: TEffectSummary; var AChanged: Boolean);
  function Calls(const AWhy: string): string;
  begin
    Result:= 'calls ' + ACalleeName + ' (' + AWhy + ')';
  end;
  function Through(AOrdinal: Integer; const AWhat, AWhy: string): string;
  begin
    Result:= 'writes through ' + ACalleeName + '(#' + IntToStr(AOrdinal) + ' = ' + AWhat + ', ' + AWhy + ')';
  end;
begin
  if efGlobal in ACallee.Flags then
    ACaller.AddFlag(efGlobal, Calls('writes global state'), AChanged);
  if efHeap in ACallee.Flags then
    ACaller.AddFlag(efHeap, Calls('frees storage'), AChanged);
  if efUnknown in ACallee.Flags then
    ACaller.AddFlag(efUnknown, Calls('unbound callee inside'), AChanged);
  if efSelfFields in ACallee.Flags then
    case AReceiver.Cls of
      acSelfOrField:
        ACaller.AddFlag(efSelfFields, Calls('writes its own fields; receiver ' + AReceiver.RootName), AChanged);
      acParam:
        ACaller.AddParam(AReceiver.ParamOrdinal,
          Calls('writes its own fields; receiver ' + AReceiver.RootName + ' is a parameter'), AChanged);
      acLocal: ; { a non-escaping local receiver: the write stays inside the caller }
    else
      ACaller.AddFlag(efUnknown, Calls('writes its own fields; receiver ' + AReceiver.RootName + ' not classified'), AChanged);
    end;
  for var K in ACallee.Params do
  begin
    if not AArgsKnown then
    begin
      ACaller.AddFlag(efUnknown, Calls('argument list not lexed'), AChanged);
      Break;
    end;
    if K > High(AArgs) then
    begin
      ACaller.AddFlag(efUnknown, Calls('argument #' + IntToStr(K) + ' missing'), AChanged);
      Continue;
    end;
    case AArgs[K].Cls of
      acLiteral, acLocal: ; { nothing of the caller's is reachable through these }
      acParam:
        ACaller.AddParam(AArgs[K].ParamOrdinal,
          Through(K, AArgs[K].RootName, 'parameter #' + IntToStr(AArgs[K].ParamOrdinal)), AChanged);
      acSelfOrField:
        ACaller.AddFlag(efSelfFields, Through(K, AArgs[K].RootName, 'a field'), AChanged);
    else
      ACaller.AddFlag(efUnknown, Through(K, AArgs[K].Text, 'not classified'), AChanged);
    end;
  end;
end;

{ ----------------------------------------------------------- mutates_params }

function ParseMutatedParamNames(const AMutatesParams: string; out ACapped: Boolean): TArray<string>;
var
  Names: TList<string>;
  Text, Item: string;
begin
  ACapped:= False;
  { JoinCappedDisplay glues ' (+N more)' to the LAST item, so it is detected on
    the whole string before splitting; an item that is nothing but the marker
    is tolerated too. }
  Text:= RxCappedTail.Replace(AMutatesParams, '');
  if Text <> AMutatesParams then ACapped:= True;
  Names:= TList<string>.Create;
  try
    for var Raw in Text.Split([',']) do
    begin
      Item:= Trim(Raw);
      if Item = '' then Continue;
      if StartsStr(CAP_MARKER, Item) then
      begin
        ACapped:= True;
        Continue;
      end;
      if EndsText(MODIFIER_VAR, Item) then Item:= Trim(Copy(Item, 1, Length(Item) - Length(MODIFIER_VAR)))
      else if EndsText(MODIFIER_OUT, Item) then Item:= Trim(Copy(Item, 1, Length(Item) - Length(MODIFIER_OUT)));
      Names.Add(Item);
    end;
    Result:= Names.ToArray;
  finally
    Names.Free;
  end;
end;

initialization
  RxBegin:= TRegEx.Create('^begin\b', [roIgnoreCase]);
  RxVarBlock:= TRegEx.Create('^var(\s|$)', [roIgnoreCase]);
  RxInlineVar:= TRegEx.Create('\bvar\s+[A-Za-z_]', [roIgnoreCase]);
  RxWith:= TRegEx.Create('\bwith\b', [roIgnoreCase]);
  RxBareInherited:= TRegEx.Create('\binherited\s*;', [roIgnoreCase]);
  RxCappedTail:= TRegEx.Create('\s*\(\+\d+ more\)\s*$');

end.
