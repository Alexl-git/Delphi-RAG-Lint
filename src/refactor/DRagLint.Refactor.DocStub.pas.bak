unit DRagLint.Refactor.DocStub;

interface

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections { ParseParamDecls' accumulator }
  , System.RegularExpressions
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoGenerateDocs (DRagLint.CLI.pas), declaration (DRagLint.Refactor.DocStub.pas), DRagLint.Refactor.DocStub.TDocStubGenerator.Generate (DRagLint.Refactor.DocStub.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDocStubFormat = (dsfXmlDoc, dsfPasDoc);

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoGenerateDocs (DRagLint.CLI.pas)</para>
  /// <para>Used in units: DRagLint.CLI</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDocStubGenerator = class
    public
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <param name="AQName"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AFormat"><!-- drag-lint:auto type -->TDocStubFormat</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: ''; Sb.ToString.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoGenerateDocs (DRagLint.CLI.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Refactor.DocStub.ExtractParamList, DRagLint.Refactor.DocStub.ParseParamNames, DRagLint.Refactor.DocStub.ReadSourceLine, DRagLint.Refactor.DocStub.SignatureDeclaresReturn, DRagLint.Refactor.DocStub.SignatureHasReturn, Trim</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
      /// <seealso cref="DRagLint.Refactor.DocStub.ExtractParamList"/>
      /// <seealso cref="DRagLint.Refactor.DocStub.ParseParamNames"/>
      /// <seealso cref="DRagLint.Refactor.DocStub.ReadSourceLine"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Generate(const AStore: ISymbolStore; const AQName: string; AFormat: TDocStubFormat): string;
  end;

// Signature parser helpers. Exported so DRagLint.Doc.Regions / .Document can
// reuse the same param-list extraction the generate-docs stub uses.
/// <summary><!-- drag-lint:auto -->Signature parser helpers. Exported so
/// DRagLint.Doc.Regions / .Document can reuse the same param-list extraction the
/// generate-docs stub uses.</summary>
/// <param name="ASig"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->string -- Observed: Trim(Copy(ASig, OpenPos + 1,
/// ClosePos - OpenPos - 1)).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas), DRagLint.Doc.Drift.TDocDrift.Analyze/4 (DRagLint.Doc.Drift.pas), DRagLint.Doc.Facts.MineParamNotes (DRagLint.Doc.Facts.pas), DRagLint.Doc.Facts.MineParamTypes (DRagLint.Doc.Facts.pas), DRagLint.Refactor.DocStub.TDocStubGenerator.Generate (DRagLint.Refactor.DocStub.pas)</para>
/// <para>Calls: Copy, LastDelimiter, Pos, Trim</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ExtractParamList(const ASig: string): string;
/// <summary><!-- drag-lint:auto -->ParseParamNames: parses a param-list string such as
/// "const A, B: string; C: Boolean; D: Integer" and returns an array of bare param names
/// (A, B, C, D). Handles const/var/out/in prefixes and grouped names (A, B: T).</summary>
/// <param name="AParamList"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto type -->TArray&lt;string&gt;</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas), DRagLint.Doc.Drift.GroupParamNames (DRagLint.Doc.Drift.pas), DRagLint.Doc.Drift.TDocDrift.Analyze/4 (DRagLint.Doc.Drift.pas), DRagLint.Refactor.DocStub.TDocStubGenerator.Generate (DRagLint.Refactor.DocStub.pas)</para>
/// <para>Calls: DRagLint.Refactor.DocStub.ParseParamDecls</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Refactor.DocStub.ParseParamDecls"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseParamNames(const AParamList: string): TArray<string>;
  /// <summary>One parsed parameter declaration: its qualifier (const/var/out/in,
  /// '' when none), its bare name, and its declared type text exactly as the
  /// indexed signature spells it ('' when the group carried no ': Type').</summary>
  /// <remarks>
  /// The type text is taken VERBATIM and never re-formatted. It is
  /// emitted into a managed &lt;param&gt; block that is regenerated and compared on
  /// every run, so any normalisation here would make a block that is not equal to
  /// itself on the next pass -- the exact failure ParseParamNames' own comment
  /// records for parameter NAMES.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Doc.Facts.MineParamTypes (DRagLint.Doc.Facts.pas), DRagLint.Refactor.DocStub.ParseParamNames (DRagLint.Refactor.DocStub.pas), DRagLint.Refactor.DocStub.ParseParamDecls (DRagLint.Refactor.DocStub.pas)</para>
  /// <para>Used in units: DRagLint.Doc.Facts, DRagLint.Refactor.DocStub</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
type
  TParamDecl = record
    Qualifier: string;
    Name     : string;
    TypeText : string;
  end;
/// <summary>Parses a param-list string into (qualifier, name, type) triples.
/// Same scan as ParseParamNames -- which delegates here and keeps only the
/// names -- so the name half and the type half can never disagree about where a
/// parameter or its type begins and ends.</summary>
/// <param name="AParamList">Param-list text as stored in symbols.signature,
/// comments included; ExtractPascalComments removes them per parameter.</param>
/// <returns>One entry per declared parameter, grouped names expanded (A, B: T
/// yields two entries sharing the type T).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Doc.Facts.MineParamTypes (DRagLint.Doc.Facts.pas), DRagLint.Refactor.DocStub.ParseParamNames (DRagLint.Refactor.DocStub.pas)</para>
/// <para>Calls: Copy, DRagLint.Refactor.DocStub.ExtractPascalComments, LowerCase, Pos, Trim</para>
/// <para>Returns: Acc.ToArray</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Refactor.DocStub.ExtractPascalComments"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseParamDecls(const AParamList: string): TArray<TParamDecl>;
/// <param name="ASig"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->Boolean -- Observed: Lower.StartsWith('function') or
/// Lower.StartsWith('constructor').</returns>
/// <remarks>
/// <!-- drag-lint:auto -->IsFunction: true when the signature starts with 'function' or
/// 'constructor'. Also returns true for 'method' kind when the text contains 'function ' keyword
/// before the identifier.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas), DRagLint.Doc.Drift.TDocDrift.Analyze/4 (DRagLint.Doc.Drift.pas), DRagLint.Refactor.DocStub.TDocStubGenerator.Generate (DRagLint.Refactor.DocStub.pas)</para>
/// <para>Calls: LowerCase, Trim</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SignatureHasReturn(const ASig: string): Boolean;
/// <summary>True when ASig carries a RETURN TYPE, judged from the signature's
/// SHAPE -- a ':' after the (balanced) parameter list -- rather than from a
/// leading keyword.</summary>
/// <param name="ASig">A signature in either spelling: the INDEXED form
/// ('(A: Integer): Integer') or a full declaration line.</param>
/// <returns>True when a return type follows the parameter list.</returns>
/// <remarks>
/// THIS IS THE TEST SignatureHasReturn CANNOT PERFORM, and the two are
/// deliberately separate rather than merged. SignatureHasReturn asks a question
/// about the DECLARATION TEXT ("does it begin with `function`"), which is
/// exactly right where a caller holds a source line and is always False for an
/// indexed signature, since the keyword is not stored. Merging them would make
/// one name answer two different questions depending on what it was handed.
/// Balanced scanning is load-bearing: a procedural-type parameter
/// ('(ACallback: procedure(X: Integer))') contains an inner ')' whose naive
/// match would expose that parameter's own colon and report a return type on a
/// procedure. An unbalanced signature returns False rather than guessing.
/// Pure.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Refactor.DocStub.TDocStubGenerator.Generate (DRagLint.Refactor.DocStub.pas)</para>
/// <para>Calls: Copy, Pos, Trim</para>
/// <para>Returns: Pos(':', Copy(S, i, MaxInt)) &gt; 0</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SignatureDeclaresReturn(const ASig: string): Boolean;
/// <summary>True when ASig declares a CONSTRUCTOR -- i.e. its first word is
/// `constructor`. The declaration TEXT is the only ground truth for this: the
/// parser indexes a constructor as kind `method`, so TSymbol.Kind cannot
/// answer it.</summary>
/// <param name="ASig">A signature, or (when the indexed signature is empty, as
/// it is for a parameterless constructor) the declaration line itself.</param>
/// <returns>True when the declaration is a constructor.</returns>
/// <remarks>
/// ONE implementation, TWO readers, and they must not diverge:
/// DRagLint.Doc.Facts.DetectMethodDirectives sets TDocFacts.IsConstructor from
/// it so the WRITER can emit the `constructor` facts-block marker, and
/// DRagLint.Doc.Drift.TDocDrift.Analyze calls it so the CHECKER can exempt a
/// constructor from the &lt;returns&gt; demand and require the marker instead. A
/// second spelling of this test would put those two back into the
/// checker-vs-writer disagreement the marker exists to end.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Doc.Drift.TDocDrift.Analyze/4 (DRagLint.Doc.Drift.pas), DRagLint.Doc.Facts.DetectMethodDirectives (DRagLint.Doc.Facts.pas)</para>
/// <para>Calls: LowerCase, Trim</para>
/// <para>Returns: LowerCase(Trim(ASig)).StartsWith('constructor')</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SignatureIsConstructor(const ASig: string): Boolean;
/// <summary>Splits AText into the comment text it contains and everything
/// else: returns the joined comment content, and sets ARest to AText with every
/// comment removed. Handles the three Pascal spellings ({ }, (* *), //).</summary>
/// <param name="AText"><!-- drag-lint:auto type -->const string</param>
/// <param name="ARest"><!-- drag-lint:auto type -->out string</param>
/// <returns><!-- drag-lint:auto -->string -- Observed: Trim(Note.ToString).</returns>
/// <remarks>
/// ONE implementation, TWO readers, and they must not diverge:
/// ParseParamNames strips comments out before reading a parameter's NAME (an
/// indexed signature keeps them verbatim, so `ALeft { the left edge }` would
/// otherwise become the name), while DRagLint.Doc.Facts.MineParamNotes keeps
/// the same comments as that parameter's harvested MEANING (ruling D-3). A
/// second copy of this scan is how the name half and the meaning half would end
/// up disagreeing about where a comment starts.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Doc.Facts.MineParamNotes (DRagLint.Doc.Facts.pas), DRagLint.Refactor.DocStub.ParseParamDecls (DRagLint.Refactor.DocStub.pas)</para>
/// <para>Calls: Copy, Trim</para>
/// <para>Complexity: 19 (cyclomatic, outer body), 49 lines (full implementation)</para>
/// <para>Mutates: ARest (out)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ExtractPascalComments(const AText: string; out ARest: string): string;

implementation

uses
  System.IOUtils
  ;

// ---------------------------------------------------------------------------
// Signature parser helpers
// ---------------------------------------------------------------------------

// ExtractParamList: returns the text between the outermost ( and ) in
// ASignature, or '' if there are no parentheses or the list is empty.
function ExtractParamList(const ASig: string): string;
var
  OpenPos : Integer;
  ClosePos: Integer;
begin
  OpenPos:= Pos('(', ASig);
  if OpenPos = 0 then Exit('');
  ClosePos:= LastDelimiter(')', ASig);
  if ClosePos <= OpenPos then Exit('');
  Result:= Trim(Copy(ASig, OpenPos + 1, ClosePos - OpenPos - 1));
end;

// IsFunction: true when the signature starts with 'function' or 'constructor'.
// Also returns true for 'method' kind when the text contains 'function ' keyword
// before the identifier.
function SignatureHasReturn(const ASig: string): Boolean;
var
  Lower: string;
begin
  Lower:= LowerCase(Trim(ASig));
  Result:= Lower.StartsWith('function') or Lower.StartsWith('constructor');
end;

{ True when ASig carries a RETURN TYPE, judged from the signature's own shape
  rather than from a leading keyword.

  This is the test SignatureHasReturn cannot perform. An INDEXED signature is
  '(AValue: Integer): Integer' -- the `function` keyword is not part of it -- so
  a keyword test is False for every indexed function, and the symbol kind does
  not rescue it because a class function is indexed as skMethod.

  HOW: skip the parameter list with a BALANCED paren scan, then ask whether a
  ':' remains. Balanced, not "find the last ')'", because a parameter may itself
  be a procedural type -- `(ACallback: procedure(X: Integer))` -- whose inner
  ')' would otherwise end the scan early and expose the parameter's own colon,
  reporting a return type on a procedure.

  The four shapes it must separate, all real:
    '(A: Integer): Integer'   -> True   (function with params)
    ': Integer'               -> True   (parameterless function)
    '(A: Integer)'            -> False  (procedure with params)
    ''                        -> False  (parameterless procedure)
  Trailing directives are harmless: '(A: Integer): Integer; static;' still has
  its colon, and '(A: Integer); overload;' still has none. }
function SignatureDeclaresReturn(const ASig: string): Boolean;
var
  S    : string ;
  i    : Integer;
  Depth: Integer;
begin
  S:= Trim(ASig);
  if S = '' then Exit(False);
  i:= 1;
  { Walk the parameter list, if there is one, tracking nesting. }
  if (Length(S) > 0) and (S[1] = '(') then
  begin
    Depth:= 0;
    while i <= Length(S) do
    begin
      if      S[i] = '(' then Inc(Depth)
      else if S[i] = ')' then
      begin
        Dec(Depth);
        if Depth = 0 then begin Inc(i); Break; end;
      end;
      Inc(i);
    end;
    { Unbalanced text (a truncated or malformed signature) is not evidence of a
      return type -- say no rather than guess from the remainder. }
    if Depth <> 0 then Exit(False);
  end;
  Result:= Pos(':', Copy(S, i, MaxInt)) > 0;
end;

function SignatureIsConstructor(const ASig: string): Boolean;
begin
  Result:= LowerCase(Trim(ASig)).StartsWith('constructor');
end;

function ExtractPascalComments(const AText: string; out ARest: string): string;
var
  i, N : Integer       ;
  Note : TStringBuilder;
  Rest : TStringBuilder;
  Inner: string        ;
begin
  Note:= TStringBuilder.Create;
  Rest:= TStringBuilder.Create;
  try
    i:= 1;
    N:= Length(AText);
    while i <= N do
    begin
      if (AText[i] = '{') then
      begin
        Inner:= '';
        Inc(i);
        while (i <= N) and (AText[i] <> '}') do begin Inner:= Inner + AText[i]; Inc(i); end;
        if i <= N then Inc(i); // the closing brace
        if Note.Length > 0 then Note.Append(' ');
        Note.Append(Trim(Inner));
      end
      else if (AText[i] = '(') and (i < N) and (AText[i + 1] = '*') then
      begin
        Inner:= '';
        Inc(i, 2);
        while (i < N) and not ((AText[i] = '*') and (AText[i + 1] = ')')) do begin Inner:= Inner + AText[i]; Inc(i); end;
        if i < N then Inc(i, 2);
        if Note.Length > 0 then Note.Append(' ');
        Note.Append(Trim(Inner));
      end
      else if (AText[i] = '/') and (i < N) and (AText[i + 1] = '/') then
      begin
        // A // comment inside a WRAPPED parameter list runs to the end of its
        // source line; the signature has already joined those lines, so the
        // only safe end is the end of this text.
        if Note.Length > 0 then Note.Append(' ');
        Note.Append(Trim(Copy(AText, i + 2, MaxInt)));
        i:= N + 1;
      end
      else begin Rest.Append(AText[i]); Inc(i); end;
    end;
    ARest := Trim(Rest.ToString);
    Result:= Trim(Note.ToString);
  finally
    Note.Free;
    Rest.Free;
  end;
end;

// ParseParamNames: parses a param-list string such as
//   "const A, B: string; C: Boolean; D: Integer"
// and returns an array of bare param names (A, B, C, D).
// Handles const/var/out/in prefixes and grouped names (A, B: T).
function ParseParamNames(const AParamList: string): TArray<string>;
var
  D: TParamDecl;
begin
  { Delegates: ONE scan decides where a parameter, its qualifier and its type
    begin and end. ParseParamDecls carries the type as well; this view drops it.
    A second scan here is exactly how the name half and the type half would come
    to disagree -- the same reasoning ExtractPascalComments' header records for
    the name half and the MEANING half. }
  Result:= nil;
  for D in ParseParamDecls(AParamList) do
    Result:= Result + [D.Name];
end; // function

function ParseParamDecls(const AParamList: string): TArray<TParamDecl>;
var
  Groups    : TArray<string>;
  Group     : string        ;
  NamesStr  : string        ;
  NamesClean: string        ;
  TypeText  : string        ;
  Qual      : string        ;
  Names     : TArray<string>;
  N         : string        ;
  NTrimmed  : string        ;
  Acc       : TList<TParamDecl>;
  ColonPos  : Integer       ;
  I         : Integer       ;
  D         : TParamDecl    ;
const
  Qualifiers: array[0..4] of string = ('const ', 'var ', 'out ', 'in ', 'array of ');
begin
  if Trim(AParamList) = '' then Exit(nil);
  Groups:= AParamList.Split([';']);
  Acc:= TList<TParamDecl>.Create;
  try
    for I:= 0 to High(Groups) do
    begin
      Group:= Trim(Groups[I]);
      if Group = '' then Continue;
      // Strip leading qualifiers (const/var/out/in/array of), REMEMBERING them:
      // 'const AName: string' documents as 'const string', which is a fact about
      // the contract (the callee will not modify it), not decoration.
      NamesStr:= Group;
      Qual:= '';
      var LowerGroup:= LowerCase(NamesStr);
      for N in Qualifiers do
        if LowerGroup.StartsWith(N) then
        begin
          Qual:= Trim(N);
          NamesStr:= Copy(NamesStr, Length(N) + 1, MaxInt);
          LowerGroup:= LowerCase(NamesStr);
        end;
      // Split at the colon: names on the left, declared type on the right. The
      // type is kept VERBATIM (default value included, e.g. 'Boolean = True') --
      // see TParamDecl's remark on why it must never be re-formatted.
      ColonPos:= Pos(':', NamesStr);
      if ColonPos > 0 then
      begin
        TypeText:= Trim(Copy(NamesStr, ColonPos + 1, MaxInt));
        NamesStr:= Copy(NamesStr, 1, ColonPos - 1);
        // A type can carry a trailing comment too ('AIndex: Integer { 1-based }');
        // strip it with the SAME scan the names use, or the emitted type text
        // would differ from itself once the comment is re-read.
        var TypeBare: string;
        ExtractPascalComments(TypeText, TypeBare);
        TypeText:= Trim(TypeBare);
      end
      else TypeText:= '';
      NamesClean:= Trim(NamesStr);
      // Split by comma for grouped params.
      Names:= NamesClean.Split([',']);
      for NTrimmed in Names do
      begin
        // v(PHASE A3): a NAME is never a comment. The INDEXED signature keeps
        // the parameter list verbatim -- comments included -- so
        // `ALeft { the left edge }, ARight: Integer` used to yield the "name"
        // `ALeft { the left edge }`, which then reached the emitter and became
        // `<param name="ALeft { the left edge }">`: malformed, and never equal
        // to itself on the next run, so the block was rewritten forever. The
        // comment is not discarded -- MineParamNotes reads the SAME scan for
        // that parameter's meaning (ruling D-3).
        var Bare: string;
        ExtractPascalComments(NTrimmed, Bare);
        Bare:= Trim(Bare);
        if Bare <> '' then
        begin
          D.Qualifier:= Qual;
          D.Name     := Bare;
          D.TypeText := TypeText; { grouped names (A, B: T) share one type }
          Acc.Add(D);
        end;
      end;
    end; // for
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end; // try
end; // function

// ReadSourceLine: reads the text of the given 1-based line from AFilePath.
// Returns '' on any error. Used when the DB signature field is empty.
function ReadSourceLine(const AFilePath: string; ALine: Integer): string;
var
  Lines: TArray<string>;
begin
  Result:= '';
  if (AFilePath = '') or (not TFile.Exists(AFilePath)) then Exit;
  try
    Lines:= TFile.ReadAllLines(AFilePath, TEncoding.ANSI);
    if (ALine >= 1) and (ALine <= Length(Lines)) then Result:= Trim(Lines[ALine - 1]);
  except
    Result:= '';
  end;
end;

// ---------------------------------------------------------------------------
// TDocStubGenerator
// ---------------------------------------------------------------------------

class function TDocStubGenerator.Generate(const AStore: ISymbolStore; const AQName: string; AFormat: TDocStubFormat): string;
var
  Syms      : TArray<TSymbol>;
  Sym       : TSymbol        ;
  Sig       : string         ;
  ParamList : string         ;
  FilePath  : string         ;
  ParamNames: TArray<string> ;
  N         : string         ;
  Sb        : TStringBuilder ;
  HasReturn : Boolean        ;
begin
  Result:= '';
  Syms:= AStore.FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then Exit;
  Sym:= Syms[0];
  Sig:= Trim(Sym.Signature);

  // If the stored signature is empty (parser did not capture it), fall back
  // to reading the source line at the symbol's declaration position.
  if Sig = '' then
  begin
    FilePath:= AStore.GetFilePath(Sym.FileId);
    Sig:= ReadSourceLine(FilePath, Sym.StartLine);
  end;

  ParamList := ExtractParamList(Sig      );
  ParamNames:= ParseParamNames (ParamList);

  { Does this routine RETURN something?

    BOTH of the tests that used to answer this are wrong for an INDEXED
    signature, and between them they emitted no <returns> for any class
    function. Found 2026-08-17 by T38_doc_stub, one of the legacy .bat tests
    that had been invisible to the battery:

      * SignatureHasReturn asks whether the text STARTS WITH 'function' /
        'constructor'. The stored signature is '(AValue: Integer): Integer' --
        the leading keyword is not part of it -- so it is False for every
        indexed function.
      * the kind fallback only ran when the signature was EMPTY, and would have
        failed here anyway: a class function is indexed as skMethod, not
        skFunction.

    DRagLint.Doc.Document already names this exact trap at its own call site and
    works around it by reading Facts.ReturnType first; DRagLint.Doc.Drift does
    the same. This generator is the one consumer that never got the treatment,
    so `generate-docs` silently dropped <returns> / @returns.

    The return type is read from the SIGNATURE ITSELF here rather than by
    building a full fact set: this is a stub generator, and TDocFactsBuilder.Build
    is orders of magnitude more work than the answer is worth. }
  HasReturn:= SignatureDeclaresReturn(Sig) or SignatureHasReturn(Sig)
              or (Sym.Kind in [skFunction, skConstructor]);

  Sb:= TStringBuilder.Create;
  try
    case AFormat of
      dsfXmlDoc:
      begin
        // v(ADP3 T3d2 D9): the trailing period matches the legacy sentinel
        // IsManagedDesc/TDocRegions still recognize ('TODO: describe.') for
        // self-healing a pre-v(ADP3) file -- see that function's own comment.
        // This generator's output goes to Writeln only today (never a .pas),
        // so the mismatch was never live, but a bare 'TODO: describe' here
        // would silently NOT be recognized as managed the day this stub is
        // wired into a write path.
        Sb.AppendLine('/// <summary>TODO: describe.</summary>');
        for N in ParamNames do Sb.AppendLine('/// <param name="' + N + '">TODO: describe.</param>');
        if HasReturn then Sb.Append('/// <returns>TODO: describe.</returns>');
      end;
      dsfPasDoc:
      begin
        // v(ADP3 T3d2 D9): period added for consistency with the XmlDoc arm
        // above -- one generator, one sentinel word, same punctuation. PasDoc
        // output has no IsManagedDesc-style recognizer of its own (a
        // different comment syntax entirely), so this half is cosmetic only.
        Sb.AppendLine('{**'               );
        Sb.AppendLine(' * TODO: describe.');
        for N in ParamNames do Sb.AppendLine(' * @param ' + N + ' TODO: describe.');
        if HasReturn then Sb.AppendLine(' * @returns TODO: describe.');
        Sb.Append(' *}');
      end;
    end; // case
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end; // try
end; // function

end.
