unit DRagLint.V152.XCONST.Support;

{ Wave v152 lane XCONST -- the pure-text planner behind the MANUAL "extract
  constant" fix (ruling B4 part 2, PLAN D6), shared by the fixers of
  magic-literal / large-magic-number / case-magic-numbers / extract-constant
  (DRagLint.Fix.V152.XCONST) and by the on-demand rule extract-constant
  (DRagLint.V152.XCONST).

  WHAT A PLAN IS. One literal token (number or quoted string) picked by line and
  column; ONE new constant `<Name> = <literal>;` in a fresh `const` block right
  after the uses clause of the implementation section (every replaced
  occurrence is there) or of the interface section (any replaced occurrence is
  there); and every occurrence of the same token in the unit replaced by the
  name, EXCEPT the ones it lists as left: inside another const / resourcestring
  declaration, an attribute, a uses clause, a label, a composite string
  ('a'#13), or a context of a different declared TYPE. "Type context" is the
  declared type of the identifier the literal is assigned to / compared with /
  the case selector -- read from `Name: Type` declarations of the same unit. An
  occurrence whose context type is unknown is replaced; one whose known type
  differs from the target's known type is left (Ratio: Double vs Count:
  Integer).

  It is a TEXT planner: no parse tree, no index. Its blind spots are the
  conservative kind (an unknown type is never "different"), and the compile gate
  (lint --fix --apply --project X.dproj) is what proves the result builds. }

interface

uses
  System.Classes
  , DRagLint.Refactor.TextEdit
  ;

type
  /// <summary>Kind of one token of the extract-constant scanner.</summary>
  /// <remarks>
  /// xtCharCode is a `#13` / `#$0D` character code; xtSymbol is any
  /// operator or punctuation (`:=`, `<=`, `..` are one token).
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V152.XCONST.Support.pas), DRagLint.V152.XCONST.Support.XcTokenize.Add (DRagLint.V152.XCONST.Support.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TXcTokenKind = (xtIdent, xtNumber, xtString, xtCharCode, xtSymbol);

  /// <summary>One token of a Delphi unit, comments and directives removed.</summary>
  /// <remarks>
  /// Line and Col are 1-based; EndCol is exclusive (TTextEdit's
  /// convention). Glued is True for a string token written directly against
  /// another string or character code ('a'#13'b'), which cannot be replaced by a
  /// name on its own.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V152.XCONST.Support.pas) ?, DRagLint.V152.XCONST.Support.IsWord (DRagLint.V152.XCONST.Support.pas) ?, DRagLint.V152.XCONST.Support.XcLiteralAt (DRagLint.V152.XCONST.Support.pas) ?, DRagLint.V152.XCONST.Support.XcTokenize (DRagLint.V152.XCONST.Support.pas) ?, DRagLint.V152.XCONST.Support.XcTokenize.Add (DRagLint.V152.XCONST.Support.pas) (+11 more)</para>
  /// <para>Used in units: DRagLint.V152.XCONST, DRagLint.V152.XCONST.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TXcToken = record
    Kind  : TXcTokenKind;
    Text  : string;
    Line  : Integer;
    Col   : Integer;
    EndCol: Integer;
    Glued : Boolean;
  end;

  /// <summary>One occurrence of the planned literal.</summary>
  /// <remarks>
  /// Reason = '' for an occurrence the plan replaces, else the
  /// human-readable reason it is left. ContextType is the declared type of its
  /// context identifier, '' when unknown.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V152.XCONST.Support.pas) ?, DRagLint.V152.XCONST.Support.XcPlan (DRagLint.V152.XCONST.Support.pas) ?, DRagLint.V152.XCONST.Support.XcPlan.OccOf (DRagLint.V152.XCONST.Support.pas), DRagLint.V152.XCONST.Support.XcPlanEdits (DRagLint.V152.XCONST.Support.pas) ?, DRagLint.V152.XCONST.Support.XcPlanReport (DRagLint.V152.XCONST.Support.pas) ?</para>
  /// <para>Used in units: DRagLint.V152.XCONST.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TXcOccurrence = record
    Line       : Integer;
    Col        : Integer;
    EndCol     : Integer;
    ContextType: string;
    Reason     : string;
    InInterface: Boolean;
  end;

  /// <summary>The whole extract-constant plan for one literal of one unit.</summary>
  /// <remarks>
  /// Ok = False carries Refusal (why nothing may be written) and no
  /// edits. InsertAfterLine is 1-based: the const block goes after that line.
  /// Replaced always holds the target occurrence first.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V152.XCONST.Support.pas) ?, DRagLint.Fix.V152.XCONST.FixExtractConst (DRagLint.Fix.V152.XCONST.pas) ?, DRagLint.V152.XCONST.Support.XcPlan (DRagLint.V152.XCONST.Support.pas), DRagLint.V152.XCONST.Support.XcPlanEdits (DRagLint.V152.XCONST.Support.pas) ?, DRagLint.V152.XCONST.Support.XcPlanReport (DRagLint.V152.XCONST.Support.pas) ?</para>
  /// <para>Used in units: DRagLint.Fix.V152.XCONST, DRagLint.V152.XCONST.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TXcPlan = record
    Ok             : Boolean;
    Refusal        : string;
    Literal        : string;
    Name           : string;
    NameProposed   : Boolean;
    InInterface    : Boolean;
    InsertAfterLine: Integer;
    Replaced       : TArray<TXcOccurrence>;
    Skipped        : TArray<TXcOccurrence>;
  end;

/// <summary>Splits a Delphi unit into tokens; comments, `{$...}` directives and
/// blanks are dropped.</summary>
/// <param name="ALines">The unit, one string per line (no line breaks).</param>
/// <returns>The tokens in source order.</returns>
/// <remarks>
/// Pure; never raises. An unterminated string ends at the end of its
/// line. Multi-line (''') strings are not recognised.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V152.XCONST.Support.XcPlan (DRagLint.V152.XCONST.Support.pas), DRagLint.V152.XCONST.TV152XCONSTRules.CheckFile (DRagLint.V152.XCONST.pas)</para>
/// <para>Calls: CharInSet, Copy, Default, DRagLint.V152.XCONST.Support.IsDigitCh, DRagLint.V152.XCONST.Support.IsHexCh, DRagLint.V152.XCONST.Support.IsIdentChar, DRagLint.V152.XCONST.Support.IsIdentStart, DRagLint.V152.XCONST.Support.XcTokenize.Add, MatchStr, Min, PosEx</para>
/// <para>Returns: Toks.ToArray</para>
/// <para>Complexity: 71 (cyclomatic, outer body), 179 lines (full implementation)</para>
/// <seealso cref="DRagLint.V152.XCONST.Support.IsDigitCh"/>
/// <seealso cref="DRagLint.V152.XCONST.Support.IsHexCh"/>
/// <seealso cref="DRagLint.V152.XCONST.Support.IsIdentChar"/>
/// <seealso cref="DRagLint.V152.XCONST.Support.IsIdentStart"/>
/// <seealso cref="DRagLint.V152.XCONST.Support.XcTokenize.Add"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function XcTokenize(ALines: TStrings): TArray<TXcToken>;

/// <summary>The index of the number or string literal token at ALine:ACol.</summary>
/// <param name="ATokens">XcTokenize's result.</param>
/// <param name="ALine">1-based line.</param>
/// <param name="ACol">1-based column inside the literal (or right after it);
/// 0 = the first literal on the line.</param>
/// <returns>The token index; -1 when no literal is there.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V152.XCONST.Support.XcPlan (DRagLint.V152.XCONST.Support.pas), DRagLint.V152.XCONST.TV152XCONSTRules.CheckFile (DRagLint.V152.XCONST.pas)</para>
/// <para>Calls: InRange</para>
/// <para>Returns: -1</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function XcLiteralAt(const ATokens: TArray<TXcToken>; ALine, ACol: Integer): Integer;

/// <summary>Plans the extraction of the literal at ALine:ACol.</summary>
/// <param name="ALines">The unit as it is on disk.</param>
/// <param name="ALine">1-based line of the literal.</param>
/// <param name="ACol">1-based column inside the literal; 0 = first literal on the line.</param>
/// <param name="AName">The constant's name; '' = propose one (NameProposed).</param>
/// <returns>The plan; Ok = False with Refusal when there is no literal at the
/// position, the literal itself is in an excluded context, AName is not a valid
/// identifier, or AName already names an identifier of the unit.</returns>
/// <remarks>
/// Pure; reads nothing but ALines.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Fix.V152.XCONST.FixExtractConst (DRagLint.Fix.V152.XCONST.pas)</para>
/// <para>Calls: DeclTypeOfName, Default, DRagLint.V152.XCONST.Support.BuildTypeMap, DRagLint.V152.XCONST.Support.Classify, DRagLint.V152.XCONST.Support.ContextIdent, DRagLint.V152.XCONST.Support.InsertLineAfter, DRagLint.V152.XCONST.Support.IsValidIdent, DRagLint.V152.XCONST.Support.NameInUse, DRagLint.V152.XCONST.Support.ProposeName, DRagLint.V152.XCONST.Support.SameLiteral (+8 more)</para>
/// <para>Returns: Default(TXcPlan)</para>
/// <para>Complexity: 19 (cyclomatic, outer body), 90 lines (full implementation)</para>
/// <seealso cref="DRagLint.V152.XCONST.Support.BuildTypeMap"/>
/// <seealso cref="DRagLint.V152.XCONST.Support.Classify"/>
/// <seealso cref="DRagLint.V152.XCONST.Support.ContextIdent"/>
/// <seealso cref="DRagLint.V152.XCONST.Support.InsertLineAfter"/>
/// <seealso cref="DRagLint.V152.XCONST.Support.IsValidIdent"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function XcPlan(ALines: TStrings; ALine, ACol: Integer; const AName: string): TXcPlan;

/// <summary>The text edits that carry out an Ok plan.</summary>
/// <param name="APath">The unit's file path (TTextEdit.FilePath).</param>
/// <param name="APlan">An Ok plan from XcPlan.</param>
/// <returns>One tekInsertLines (the const block) plus one guarded
/// tekReplaceInLine per replaced occurrence; nil for a plan that is not Ok.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Fix.V152.XCONST.FixExtractConst (DRagLint.Fix.V152.XCONST.pas)</para>
/// <para>Calls: Default</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function XcPlanEdits(const APath: string; const APlan: TXcPlan): TArray<TTextEdit>;

/// <summary>The lines the fixer prints (stderr) for a plan: the name, the
/// counts, the placement, and one line per occurrence left.</summary>
/// <param name="APath">The unit's file path, used in every line.</param>
/// <param name="APlan">A plan from XcPlan.</param>
/// <returns>`extract-constant: name ...` + `extract-constant:   left ...` lines,
/// or the single `extract-constant: REFUSED ...` line for a refused plan.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Fix.V152.XCONST.FixExtractConst (DRagLint.Fix.V152.XCONST.pas)</para>
/// <para>Calls: Format, IfThen</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function XcPlanReport(const APath: string; const APlan: TXcPlan): TArray<string>;

/// <summary>The value after AFlag on this process's command line.</summary>
/// <param name="AFlag">The flag, e.g. '--name'; compared case-insensitively.</param>
/// <returns>'' when the flag is absent or last.</returns>
/// <remarks>
/// The fixer contract (TFindingFixer) carries no request options, and
/// the CLI's TArgs is not visible to a fixer unit, so the manual fix reads
/// --name / --col / --fix-rule / --fix-line here. Every one of them is a flag
/// `lint` already accepts.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Fix.V152.XCONST.FixExtractConst (DRagLint.Fix.V152.XCONST.pas), DRagLint.V152.XCONST.TV152XCONSTRules.CheckFile (DRagLint.V152.XCONST.pas)</para>
/// <para>Calls: ParamStr, SameText</para>
/// <para>Returns: ''</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function XcCmdLineValue(const AFlag: string): string;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.Math
  , System.Character
  , System.Generics.Collections
  ;

const
  { Keywords that close a const / label section (a token of one of them is never
    an identifier the type map or a name may use). }
  XC_SECTION_WORDS: array[0..25] of string = (
    'var', 'type', 'const', 'procedure', 'function', 'constructor', 'destructor', 'begin',
    'implementation', 'interface', 'resourcestring', 'threadvar', 'class', 'property', 'label',
    'exports', 'initialization', 'finalization', 'private', 'protected', 'public', 'published',
    'strict', 'end', 'operator', 'uses');
  { Reserved words a constant may not be called. }
  XC_RESERVED: array[0..64] of string = (
    'and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const', 'constructor', 'destructor',
    'dispinterface', 'div', 'do', 'downto', 'else', 'end', 'except', 'exports', 'file',
    'finalization', 'finally', 'for', 'function', 'goto', 'if', 'implementation', 'in',
    'inherited', 'initialization', 'inline', 'interface', 'is', 'label', 'library', 'mod', 'nil',
    'not', 'object', 'of', 'or', 'packed', 'procedure', 'program', 'property', 'raise', 'record',
    'repeat', 'resourcestring', 'set', 'shl', 'shr', 'string', 'then', 'threadvar', 'to', 'try',
    'type', 'unit', 'until', 'uses', 'var', 'while', 'with', 'xor', 'operator');
  { Words that may precede an attribute's '['. }
  XC_ATTR_ANCHORS: array[0..9] of string = (
    'type', 'var', 'const', 'private', 'protected', 'public', 'published', 'strict', 'interface',
    'implementation');
  XC_COMPARE: array[0..5] of string = ('=', '<>', '<', '>', '<=', '>=');
  { The longest number of string words a proposed name is built from. }
  XC_NAME_WORDS = 3;
  { Proposal suffixes tried before giving up on a free name. }
  XC_MAX_SUFFIX = 99;

type
  TXcTokInfo = record
    Excluded   : string;   // reason the token may not be replaced, '' = free
    InCaseLabel: Boolean;
    CaseSelType: string;
    InInterface: Boolean;
  end;

  TXcCaseFrame = record
    Level   : Integer;
    WaitOf  : Boolean;
    AtLabel : Boolean;
    SelType : string;
  end;

function XcCmdLineValue(const AFlag: string): string;
begin
  Result:= '';
  for var I: Integer:= 1 to ParamCount - 1 do
    if SameText(ParamStr(I), AFlag) then Exit(ParamStr(I + 1));
end;

function IsIdentStart(const C: Char): Boolean;
begin
  Result:= C.IsLetter or (C = '_');
end;

function IsIdentChar(const C: Char): Boolean;
begin
  Result:= C.IsLetterOrDigit or (C = '_');
end;

function IsDigitCh(const C: Char): Boolean;
begin
  Result:= CharInSet(C, ['0'..'9']);
end;

function IsHexCh(const C: Char): Boolean;
begin
  Result:= CharInSet(C, ['0'..'9', 'a'..'f', 'A'..'F', '_']);
end;

function XcTokenize(ALines: TStrings): TArray<TXcToken>;  // dl:ok cyclomatic-complexity@bf3c -- REVIEWED 2026-11-17 XCONST: single-pass lexer, one branch per Delphi token form; splitting it scatters the comment/string state  // dl:ok cognitive-complexity@37cc -- same lexer state machine  // dl:ok deep-nesting@239c -- same lexer state machine  // dl:ok cognitive-complexity@dc2f -- same lexer state machine  // dl:ok deep-nesting@239c -- same lexer state machine  // dl:ok deep-nesting@239c -- same lexer state machine  // dl:ok cognitive-complexity@dc2f -- same lexer state machine  // dl:ok deep-nesting@239c -- same lexer state machine
var
  Toks    : TList<TXcToken>;
  InBrace : Boolean;
  InStar  : Boolean;
  S       : string;
  N       : Integer;
  I, J    : Integer;
  Ln      : Integer;

  procedure Add(AKind: TXcTokenKind; AFrom, ATo: Integer);  { ATo exclusive }
  var
    T: TXcToken;
  begin
    T:= Default(TXcToken);
    T.Kind  := AKind;
    T.Text  := Copy(S, AFrom, ATo - AFrom);
    T.Line  := Ln;
    T.Col   := AFrom;
    T.EndCol:= ATo;
    Toks.Add(T);
  end;

begin
  Toks:= TList<TXcToken>.Create;
  try
    InBrace:= False;
    InStar := False;
    for Ln:= 1 to ALines.Count do
    begin
      S:= ALines[Ln - 1];
      N:= Length(S);
      I:= 1;
      while I <= N do
      begin
        if InBrace then
        begin
          J:= PosEx('}', S, I);
          if J = 0 then Break;
          InBrace:= False;
          I:= J + 1;
          Continue;
        end;
        if InStar then
        begin
          J:= PosEx('*)', S, I);
          if J = 0 then Break;
          InStar:= False;
          I:= J + 2;
          Continue;
        end;
        var C: Char:= S[I];
        var Nx: Char:= if I < N then S[I + 1] else #0;
        if C.IsWhiteSpace then
        begin
          Inc(I);
          Continue;
        end;
        if (C = '/') and (Nx = '/') then Break;
        if C = '{' then
        begin
          InBrace:= True;
          Inc(I);
          Continue;
        end;
        if (C = '(') and (Nx = '*') then
        begin
          InStar:= True;
          Inc(I, 2);
          Continue;
        end;
        if C = '''' then
        begin
          J:= I + 1;
          while J <= N do
          begin
            if S[J] = '''' then
            begin
              if (J < N) and (S[J + 1] = '''') then Inc(J, 2)
              else Break;
            end
            else Inc(J);
          end;
          Add(xtString, I, Min(J, N) + 1);
          I:= J + 1;
          Continue;
        end;
        if C = '#' then
        begin
          J:= I + 1;
          if (J <= N) and (S[J] = '$') then
          begin
            Inc(J);
            while (J <= N) and IsHexCh(S[J]) do Inc(J);
          end
          else
            while (J <= N) and IsDigitCh(S[J]) do Inc(J);
          Add(xtCharCode, I, J);
          I:= J;
          Continue;
        end;
        if IsDigitCh(C) then
        begin
          J:= I;
          while (J <= N) and (IsDigitCh(S[J]) or (S[J] = '_')) do Inc(J);
          if (J < N) and (S[J] = '.') and IsDigitCh(S[J + 1]) then
          begin
            Inc(J);
            while (J <= N) and IsDigitCh(S[J]) do Inc(J);
          end;
          if (J <= N) and CharInSet(S[J], ['e', 'E']) then
          begin
            var K: Integer:= J + 1;
            if (K <= N) and CharInSet(S[K], ['+', '-']) then Inc(K);
            if (K <= N) and IsDigitCh(S[K]) then
            begin
              J:= K;
              while (J <= N) and IsDigitCh(S[J]) do Inc(J);
            end;
          end;
          Add(xtNumber, I, J);
          I:= J;
          Continue;
        end;
        if (C = '$') and IsHexCh(Nx) then
        begin
          J:= I + 1;
          while (J <= N) and IsHexCh(S[J]) do Inc(J);
          Add(xtNumber, I, J);
          I:= J;
          Continue;
        end;
        if (C = '%') and CharInSet(Nx, ['0', '1']) then
        begin
          J:= I + 1;
          while (J <= N) and CharInSet(S[J], ['0', '1', '_']) do Inc(J);
          Add(xtNumber, I, J);
          I:= J;
          Continue;
        end;
        if (C = '&') and CharInSet(Nx, ['0'..'7']) then
        begin
          J:= I + 1;
          while (J <= N) and CharInSet(S[J], ['0'..'7', '_']) do Inc(J);
          Add(xtNumber, I, J);
          I:= J;
          Continue;
        end;
        if IsIdentStart(C) or ((C = '&') and IsIdentStart(Nx)) then
        begin
          J:= I + 1;
          while (J <= N) and IsIdentChar(S[J]) do Inc(J);
          Add(xtIdent, I, J);
          I:= J;
          Continue;
        end;
        var Two: string:= Copy(S, I, 2);
        if MatchStr(Two, [':=', '<=', '>=', '<>', '..', '+=', '-=']) then
        begin
          Add(xtSymbol, I, I + 2);
          Inc(I, 2);
          Continue;
        end;
        Add(xtSymbol, I, I + 1);
        Inc(I);
      end;
    end;
    Result:= Toks.ToArray;
  finally
    Toks.Free;
  end;
  for I:= 0 to High(Result) do
    if Result[I].Kind = xtString then
    begin
      if (I > 0) and (Result[I - 1].Kind in [xtString, xtCharCode]) and (Result[I - 1].Line = Result[I].Line)
         and (Result[I - 1].EndCol = Result[I].Col) then Result[I].Glued:= True;
      if (I < High(Result)) and (Result[I + 1].Kind in [xtString, xtCharCode]) and (Result[I + 1].Line = Result[I].Line)
         and (Result[I + 1].Col = Result[I].EndCol) then Result[I].Glued:= True;
    end;
end;

function XcLiteralAt(const ATokens: TArray<TXcToken>; ALine, ACol: Integer): Integer;
begin
  Result:= -1;
  for var I: Integer:= 0 to High(ATokens) do
  begin
    if ATokens[I].Line > ALine then Break;
    if (ATokens[I].Line <> ALine) or (ATokens[I].Kind not in [xtNumber, xtString]) then Continue;
    if (ACol <= 0) or InRange(ACol, ATokens[I].Col, ATokens[I].EndCol) then Exit(I);
  end;
end;

function IsWord(const ATok: TXcToken; const AWord: string): Boolean;
begin
  Result:= (ATok.Kind = xtIdent) and SameText(ATok.Text, AWord);
end;

function IsSym(const ATok: TXcToken; const ASym: string): Boolean;
begin
  Result:= (ATok.Kind = xtSymbol) and (ATok.Text = ASym);
end;

function IsReservedWord(const S: string): Boolean;
begin
  Result:= MatchText(S, XC_RESERVED) or MatchText(S, XC_SECTION_WORDS);
end;

{ Name -> declared type, read from every `A, B: Type` in the unit. A name declared
  with two different types maps to '' (ambiguous). }
function BuildTypeMap(const T: TArray<TXcToken>): TDictionary<string, string>;
begin
  Result:= TDictionary<string, string>.Create;
  for var I: Integer:= 1 to High(T) - 1 do
  begin
    if not IsSym(T[I], ':') then Continue;
    if (T[I + 1].Kind <> xtIdent) or (IsReservedWord(T[I + 1].Text) and not SameText(T[I + 1].Text, 'string')) then Continue;
    var TypeName: string:= T[I + 1].Text;
    var K: Integer:= I - 1;
    while (K >= 0) and (T[K].Kind = xtIdent) and not IsReservedWord(T[K].Text) do
    begin
      var Key: string:= LowerCase(T[K].Text);
      var Old: string;
      if Result.TryGetValue(Key, Old) then
      begin
        if not SameText(Old, TypeName) then Result[Key]:= '';
      end
      else Result.Add(Key, TypeName);
      if (K > 0) and IsSym(T[K - 1], ',') then Dec(K, 2) else Break;
    end;
  end;
end;

function DeclTypeOfName(const AMap: TDictionary<string, string>; const AIdent: string): string;
begin
  if not AMap.TryGetValue(LowerCase(AIdent), Result) then Result:= '';
end;

{ Does token J start another entry of a const section (`Name =`, `Name: T =`, `[Attr]`)? }
function StartsConstEntry(const T: TArray<TXcToken>; J: Integer): Boolean;
begin
  if J > High(T) then Exit(False);
  if IsSym(T[J], '[') then Exit(True);
  Result:= (T[J].Kind = xtIdent) and not IsReservedWord(T[J].Text) and (J < High(T))
    and (IsSym(T[J + 1], '=') or IsSym(T[J + 1], ':'));
end;

{ One pass over the tokens: which ones sit where a name may not replace a literal,
  which are case labels (and of what selector type), which are in the interface. }
function Classify(const T: TArray<TXcToken>; const AMap: TDictionary<string, string>): TArray<TXcTokInfo>;  // dl:ok cyclomatic-complexity@9144 -- REVIEWED 2026-11-17 XCONST: one pass tracking paren/attr/case/section state together; each branch is one Delphi construct  // dl:ok cognitive-complexity@c544 -- same single-pass classifier  // dl:ok cognitive-complexity@ab17 -- same single-pass classifier  // dl:ok cognitive-complexity@ab17 -- same single-pass classifier
var
  Frames    : TList<TXcCaseFrame>;
  Paren     : Integer;
  Nest      : Integer;
  ConstMode : Boolean;
  UsesMode  : Boolean;
  LabelMode : Boolean;
  AttrDepth : Integer;
  LastAttrEnd: Integer;
  ImplSeen  : Boolean;
begin
  SetLength(Result, Length(T));
  Frames:= TList<TXcCaseFrame>.Create;
  try
    Paren:= 0;
    Nest:= 0;
    AttrDepth:= 0;
    LastAttrEnd:= -2;  // dl:ok magic-literal@cfa2 -- sentinel: no attribute ended at K - 1 for any K >= 0
    ConstMode:= False;
    UsesMode:= False;
    LabelMode:= False;
    ImplSeen:= False;
    for var K: Integer:= 0 to High(T) do
    begin
      var Tk: TXcToken:= T[K];
      var L: string:= if Tk.Kind = xtIdent then LowerCase(Tk.Text) else '';
      if (L <> '') and (Paren = 0) and MatchStr(L, XC_SECTION_WORDS) then
      begin
        ConstMode:= False;
        LabelMode:= False;
      end;
      if L = 'implementation' then ImplSeen:= True;
      Result[K]:= Default(TXcTokInfo);
      Result[K].InInterface:= not ImplSeen;
      { an attribute opens on '[' at a declaration position }
      if IsSym(Tk, '[') and (AttrDepth = 0) and (Paren = 0)  // dl:ok boolean-expression-complexity@100e -- REVIEWED 2026-11-17 XCONST: token-shape test, each operand one adjacent-token check
         and ((K = 0) or IsSym(T[K - 1], ';') or (LastAttrEnd = K - 1)
              or ((T[K - 1].Kind = xtIdent) and MatchText(T[K - 1].Text, XC_ATTR_ANCHORS))) then
        AttrDepth:= 1
      else if (AttrDepth > 0) and IsSym(Tk, '[') then Inc(AttrDepth);
      if AttrDepth > 0 then Result[K].Excluded:= 'inside an attribute'
      else if UsesMode then Result[K].Excluded:= 'in a uses clause'
      else if LabelMode then Result[K].Excluded:= 'in a label declaration'
      else if ConstMode then Result[K].Excluded:= 'inside a const declaration';
      if (Frames.Count > 0) and Frames.Last.AtLabel and (Nest = Frames.Last.Level) and (Paren = 0) then
      begin
        Result[K].InCaseLabel:= True;
        Result[K].CaseSelType:= Frames.Last.SelType;
      end;
      if (AttrDepth > 0) and IsSym(Tk, ']') then
      begin
        Dec(AttrDepth);
        if AttrDepth = 0 then LastAttrEnd:= K;
      end;
      if Tk.Kind = xtSymbol then
      begin
        if Tk.Text = '(' then Inc(Paren)
        else if Tk.Text = ')' then begin if Paren > 0 then Dec(Paren); end
        else if (Tk.Text = ';') and (Paren = 0) then
        begin
          UsesMode:= False;
          LabelMode:= False;
          if ConstMode and not StartsConstEntry(T, K + 1) then ConstMode:= False;
          if (Frames.Count > 0) and (Nest = Frames.Last.Level) then
          begin
            var Fr: TXcCaseFrame:= Frames.Last;
            Fr.AtLabel:= True;
            Frames[Frames.Count - 1]:= Fr;
          end;
        end
        else if (Tk.Text = ':') and (Paren = 0) and (Frames.Count > 0) and Frames.Last.AtLabel and (Nest = Frames.Last.Level) then
        begin
          var Fr: TXcCaseFrame:= Frames.Last;
          Fr.AtLabel:= False;
          Frames[Frames.Count - 1]:= Fr;
        end;
        Continue;
      end;
      if L = '' then Continue;
      if MatchStr(L, ['const', 'resourcestring']) and (Paren = 0) and not ((K > 0) and IsWord(T[K - 1], 'of')) then
        ConstMode:= True
      else if (L = 'uses') and (Paren = 0) then UsesMode:= True
      else if (L = 'label') and (Paren = 0) then LabelMode:= True
      else if MatchStr(L, ['begin', 'try', 'asm', 'record']) then Inc(Nest)
      else if L = 'case' then
      begin
        Inc(Nest);
        var Fr: TXcCaseFrame:= Default(TXcCaseFrame);
        Fr.Level := Nest;
        Fr.WaitOf:= True;
        { the selector: an identifier chain alone between case and of }
        var J: Integer:= K + 1;
        var LastId: string:= '';
        var Simple: Boolean:= True;
        while (J <= High(T)) and not IsWord(T[J], 'of') do
        begin
          if T[J].Kind = xtIdent then LastId:= T[J].Text
          else if not IsSym(T[J], '.') then Simple:= False;
          Inc(J);
        end;
        Fr.SelType:= if Simple and (LastId <> '') then DeclTypeOfName(AMap, LastId) else '';
        Frames.Add(Fr);
      end
      else if (L = 'of') and (Frames.Count > 0) and Frames.Last.WaitOf and (Nest = Frames.Last.Level) then
      begin
        var Fr: TXcCaseFrame:= Frames.Last;
        Fr.WaitOf := False;
        Fr.AtLabel:= True;
        Frames[Frames.Count - 1]:= Fr;
      end
      else if (L = 'else') and (Frames.Count > 0) and Frames.Last.AtLabel and (Nest = Frames.Last.Level) then
      begin
        var Fr: TXcCaseFrame:= Frames.Last;
        Fr.AtLabel:= False;
        Frames[Frames.Count - 1]:= Fr;
        Result[K].InCaseLabel:= False;
      end
      else if L = 'end' then
      begin
        if (Frames.Count > 0) and (Nest = Frames.Last.Level) then Frames.Delete(Frames.Count - 1);
        Dec(Nest);
      end;
    end;
  finally
    Frames.Free;
  end;
end;

{ The identifier the literal at K is assigned to / compared with, '' when none. }
function ContextIdent(const T: TArray<TXcToken>; K: Integer): string;
var
  P: Integer;
begin
  Result:= '';
  P:= K - 1;
  if (P >= 1) and (IsSym(T[P], '-') or IsSym(T[P], '+')) and (T[P - 1].Kind = xtSymbol)  // dl:ok boolean-expression-complexity@6f2c -- REVIEWED 2026-11-17 XCONST: token-shape test, each operand one adjacent-token check
     and not IsSym(T[P - 1], ')') and not IsSym(T[P - 1], ']') then Dec(P);
  if (P >= 1) and ((T[P].Kind = xtSymbol) and (MatchStr(T[P].Text, XC_COMPARE) or (T[P].Text = ':=')))  // dl:ok boolean-expression-complexity@53d3 -- REVIEWED 2026-11-17 XCONST: token-shape test, each operand one adjacent-token check
     and (T[P - 1].Kind = xtIdent) and not IsReservedWord(T[P - 1].Text) then
    Exit(T[P - 1].Text);
  if (K + 2 <= High(T)) and (T[K + 1].Kind = xtSymbol) and MatchStr(T[K + 1].Text, XC_COMPARE)  // dl:ok boolean-expression-complexity@9f69 -- REVIEWED 2026-11-17 XCONST: token-shape test, each operand one adjacent-token check
     and (T[K + 2].Kind = xtIdent) and not IsReservedWord(T[K + 2].Text)
     and not ((K + 3 <= High(T)) and (IsSym(T[K + 3], '(') or IsSym(T[K + 3], '.'))) then  // dl:ok magic-literal@8aef -- token offset after literal, op, ident
    Exit(T[K + 2].Text);
end;

function SameLiteral(const A, B: TXcToken): Boolean;
begin
  if A.Kind <> B.Kind then Exit(False);
  Result:= if A.Kind = xtString then A.Text = B.Text else SameText(A.Text, B.Text);
end;

function UpperFirst(const S: string): string;
begin
  Result:= S;
  if Result <> '' then Result[1]:= UpCase(Result[1]);
end;

{ A field / parameter prefix (FCount, ACount, pCount) is not part of the meaning. }
function StripPrefix(const S: string): string;
begin
  Result:= if (Length(S) > 1) and CharInSet(S[1], ['F', 'A', 'p']) and CharInSet(S[2], ['A'..'Z'])
    then Copy(S, 2, MaxInt) else S;
end;

function ProposeName(const ALit: TXcToken; const ACtx: string): string;
begin
  if ALit.Kind = xtString then
  begin
    var Body: string:= Copy(ALit.Text, 2, Length(ALit.Text) - 2).Replace('''''', '''');
    var Words: Integer:= 0;
    var Cur: string:= '';
    Result:= 's';
    for var C: Char in Body + ' ' do
      if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9']) then Cur:= Cur + C  // dl:ok concat-in-loop@90c6 -- one short literal's word; bounded by the literal length
      else if Cur <> '' then
      begin
        if Words < XC_NAME_WORDS then Result:= Result + UpperFirst(LowerCase(Cur));  // dl:ok concat-in-loop@63aa -- at most XC_NAME_WORDS appends
        Inc(Words);
        Cur:= '';
      end;
    if Words = 0 then Result:= 'sText';
  end
  else
  begin
    var Digits: string:= ALit.Text.Replace('$', 'Hex').Replace('%', 'Bin').Replace('&', 'Oct')
      .Replace('.', '_').Replace('+', '').Replace('-', '_');
    Result:= 'c' + (if ACtx <> '' then UpperFirst(StripPrefix(ACtx)) else 'Value') + Digits;
  end;
end;

function IsValidIdent(const S: string): Boolean;
begin
  Result:= (S <> '') and IsIdentStart(S[1]) and not IsReservedWord(S);
  for var C: Char in S do
    if not IsIdentChar(C) then Exit(False);
end;

function NameInUse(const T: TArray<TXcToken>; const AName: string; out ALine: Integer): Boolean;
begin
  ALine:= 0;
  for var Tk: TXcToken in T do
    if IsWord(Tk, AName) then
    begin
      ALine:= Tk.Line;
      Exit(True);
    end;
  Result:= False;
end;

{ The line after which a const block goes: the end of the uses clause right after
  the section keyword, else the keyword's own line; for a program / library with
  no sections, after its header or its uses clause. 0 = not found. }
function InsertLineAfter(const T: TArray<TXcToken>; AInInterface: Boolean): Integer;
begin
  Result:= 0;
  var KeyIdx: Integer:= -1;
  for var I: Integer:= 0 to High(T) do
    if (T[I].Kind = xtIdent) and ((AInInterface and SameText(T[I].Text, 'interface'))
       or (not AInInterface and SameText(T[I].Text, 'implementation'))) then
    begin
      KeyIdx:= I;
      Break;
    end;
  if KeyIdx < 0 then
  begin
    { program / library: after the header's ';' }
    for var I: Integer:= 0 to High(T) do
      if IsSym(T[I], ';') then
      begin
        KeyIdx:= I;
        Break;
      end;
    if KeyIdx < 0 then Exit;
  end;
  Result:= T[KeyIdx].Line;
  if (KeyIdx < High(T)) and IsWord(T[KeyIdx + 1], 'uses') then
    for var I: Integer:= KeyIdx + 2 to High(T) do
      if IsSym(T[I], ';') then Exit(T[I].Line);
end;

function XcPlan(ALines: TStrings; ALine, ACol: Integer; const AName: string): TXcPlan;
var
  T     : TArray<TXcToken>;
  Map   : TDictionary<string, string>;
  Info  : TArray<TXcTokInfo>;
  Target: Integer;
  ClashLine: Integer;

  function OccOf(K: Integer): TXcOccurrence;
  begin
    Result:= Default(TXcOccurrence);
    Result.Line       := T[K].Line;
    Result.Col        := T[K].Col;
    Result.EndCol     := T[K].EndCol;
    Result.InInterface:= Info[K].InInterface;
    Result.ContextType:= if Info[K].InCaseLabel then Info[K].CaseSelType else DeclTypeOfName(Map, ContextIdent(T, K));
    if Info[K].Excluded <> '' then Result.Reason:= Info[K].Excluded
    else if T[K].Glued then Result.Reason:= 'part of a composite string literal'
    else if (K > 0) and IsWord(T[K - 1], 'goto') then Result.Reason:= 'a goto target'
    else if (not Info[K].InCaseLabel) and (K < High(T)) and IsSym(T[K + 1], ':') and (K > 0)  // dl:ok boolean-expression-complexity@b4d6 -- REVIEWED 2026-11-17 XCONST: token-shape test, each operand one adjacent-token check
            and (IsSym(T[K - 1], ';') or IsWord(T[K - 1], 'begin')) then Result.Reason:= 'a statement label';
  end;

begin
  Result:= Default(TXcPlan);
  T:= XcTokenize(ALines);
  Target:= XcLiteralAt(T, ALine, ACol);
  if Target < 0 then
  begin
    Result.Refusal:= Format('no number or string literal at line %d', [ALine]) + (if ACol > 0 then Format(' column %d', [ACol]) else '');
    Exit;
  end;
  Result.Literal:= T[Target].Text;
  Map:= BuildTypeMap(T);
  try
    Info:= Classify(T, Map);
    var Ref: TXcOccurrence:= OccOf(Target);
    if Ref.Reason <> '' then
    begin
      Result.Refusal:= Format('the literal %s at %d:%d is %s', [Result.Literal, Ref.Line, Ref.Col, Ref.Reason]);
      Exit;
    end;
    if AName <> '' then
    begin
      if not IsValidIdent(AName) then
      begin
        Result.Refusal:= Format('''%s'' is not a valid constant name', [AName]);
        Exit;
      end;
      if NameInUse(T, AName, ClashLine) then
      begin
        Result.Refusal:= Format('the name ''%s'' clashes with an identifier already in the unit (line %d)', [AName, ClashLine]);
        Exit;
      end;
      Result.Name:= AName;
    end
    else
    begin
      var Base: string:= ProposeName(T[Target], ContextIdent(T, Target));
      Result.Name:= Base;
      var Suffix: Integer:= 1;
      while NameInUse(T, Result.Name, ClashLine) and (Suffix < XC_MAX_SUFFIX) do
      begin
        Inc(Suffix);
        Result.Name:= Base + IntToStr(Suffix);
      end;
      Result.NameProposed:= True;
    end;
    Result.Replaced:= [Ref];
    for var K: Integer:= 0 to High(T) do
    begin
      if (K = Target) or not SameLiteral(T[K], T[Target]) then Continue;
      var Occ: TXcOccurrence:= OccOf(K);
      if (Occ.Reason = '') and (Ref.ContextType <> '') and (Occ.ContextType <> '') and not SameText(Ref.ContextType, Occ.ContextType) then
        Occ.Reason:= Format('a different type context: %s (the extracted literal is %s)', [Occ.ContextType, Ref.ContextType]);
      if Occ.Reason = '' then Result.Replaced:= Result.Replaced + [Occ]
      else Result.Skipped:= Result.Skipped + [Occ];
    end;
    for var O: TXcOccurrence in Result.Replaced do
      if O.InInterface then Result.InInterface:= True;
    Result.InsertAfterLine:= InsertLineAfter(T, Result.InInterface);
    if Result.InsertAfterLine <= 0 then
    begin
      Result.Refusal:= 'no interface / implementation section or program header to declare the constant in';
      Exit;
    end;
    Result.Ok:= True;
  finally
    Map.Free;
  end;
end;

function XcPlanEdits(const APath: string; const APlan: TXcPlan): TArray<TTextEdit>;
var
  E: TTextEdit;
begin
  Result:= nil;
  if not APlan.Ok then Exit;
  E:= Default(TTextEdit);
  E.FilePath:= APath;
  E.Kind    := tekInsertLines;
  E.Line    := APlan.InsertAfterLine;
  E.Text    := sLineBreak + 'const' + sLineBreak + '  ' + APlan.Name + ' = ' + APlan.Literal + ';';
  Result:= [E];
  for var O: TXcOccurrence in APlan.Replaced do
  begin
    E:= Default(TTextEdit);
    E.FilePath  := APath;
    E.Kind      := tekReplaceInLine;
    E.Line      := O.Line;
    E.Col       := O.Col;
    E.EndCol    := O.EndCol;
    E.Text      := APlan.Name;
    E.ExpectText:= APlan.Literal;
    Result:= Result + [E];
  end;
end;

function XcPlanReport(const APath: string; const APlan: TXcPlan): TArray<string>;
begin
  if not APlan.Ok then
  begin
    Result:= [Format('extract-constant: REFUSED %s: %s', [APath, APlan.Refusal])];
    Exit;
  end;
  Result:= [Format('extract-constant: name %s = %s (%s), placed in the %s section; %d occurrence(s) replaced, %d left (positions as before the edit)',
    [APlan.Name, APlan.Literal, IfThen(APlan.NameProposed, 'proposed -- pass --name <ident> to choose', 'given'),
     IfThen(APlan.InInterface, 'interface', 'implementation'), Length(APlan.Replaced), Length(APlan.Skipped)])];
  for var O: TXcOccurrence in APlan.Skipped do
    Result:= Result + [Format('extract-constant:   left %s:%d:%d -- %s', [APath, O.Line, O.Col, O.Reason])];
end;

end.
