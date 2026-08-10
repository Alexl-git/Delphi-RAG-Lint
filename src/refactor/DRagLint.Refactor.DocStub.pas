unit DRagLint.Refactor.DocStub;

interface

uses
  System.SysUtils
  , System.Classes
  , System.RegularExpressions
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoGenerateDocs (DRagLint.CLI.pas), declaration (DRagLint.Refactor.DocStub.pas), DRagLint.Refactor.DocStub.TDocStubGenerator.Generate (DRagLint.Refactor.DocStub.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDocStubFormat = (dsfXmlDoc, dsfPasDoc);

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoGenerateDocs (DRagLint.CLI.pas)
  /// Used in units: DRagLint.CLI
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDocStubGenerator = class
    public
      /// <param name="AStore"><!-- drag-lint:auto --></param>
      /// <param name="AQName"><!-- drag-lint:auto --></param>
      /// <param name="AFormat"><!-- drag-lint:auto --></param>
      /// <returns><!-- drag-lint:auto -->Observed: ''; Sb.ToString.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.DoGenerateDocs (DRagLint.CLI.pas)
      /// Calls: DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Refactor.DocStub.ExtractParamList, DRagLint.Refactor.DocStub.ParseParamNames, DRagLint.Refactor.DocStub.ReadSourceLine, DRagLint.Refactor.DocStub.SignatureHasReturn, Trim
      /// Pure
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
/// <param name="ASig"><!-- drag-lint:auto --></param>
/// <returns><!-- drag-lint:auto -->Observed: Trim(Copy(ASig, OpenPos + 1, ClosePos -
/// OpenPos - 1)).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas), DRagLint.Doc.Drift.TDocDrift.Analyze (DRagLint.Doc.Drift.pas), DRagLint.Doc.Facts.MineParamNotes (DRagLint.Doc.Facts.pas), DRagLint.Refactor.DocStub.TDocStubGenerator.Generate (DRagLint.Refactor.DocStub.pas)
/// Calls: Copy, LastDelimiter, Pos, Trim
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function ExtractParamList(const ASig: string): string;
/// <summary><!-- drag-lint:auto -->ParseParamNames: parses a param-list string such as
/// "const A, B: string; C: Boolean; D: Integer" and returns an array of bare param names
/// (A, B, C, D). Handles const/var/out/in prefixes and grouped names (A, B: T).</summary>
/// <param name="AParamList"><!-- drag-lint:auto --></param>
/// <returns><!-- drag-lint:auto -->Observed: Acc.ToStringArray.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas), DRagLint.Doc.Drift.GroupParamNames (DRagLint.Doc.Drift.pas), DRagLint.Doc.Drift.TDocDrift.Analyze (DRagLint.Doc.Drift.pas), DRagLint.Refactor.DocStub.TDocStubGenerator.Generate (DRagLint.Refactor.DocStub.pas)
/// Calls: Copy, DRagLint.Refactor.DocStub.ExtractPascalComments, LowerCase, Pos, Trim
/// Pure
/// <seealso cref="DRagLint.Refactor.DocStub.ExtractPascalComments"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseParamNames(const AParamList: string): TArray<string>;
/// <param name="ASig"><!-- drag-lint:auto --></param>
/// <returns><!-- drag-lint:auto -->Observed: Lower.StartsWith('function') or
/// Lower.StartsWith('constructor').</returns>
/// <remarks>
/// <!-- drag-lint:auto -->IsFunction: true when the signature starts with 'function' or
/// 'constructor'. Also returns true for 'method' kind when the text contains 'function ' keyword
/// before the identifier.
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas), DRagLint.Doc.Drift.TDocDrift.Analyze (DRagLint.Doc.Drift.pas), DRagLint.Refactor.DocStub.TDocStubGenerator.Generate (DRagLint.Refactor.DocStub.pas)
/// Calls: LowerCase, Trim
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function SignatureHasReturn(const ASig: string): Boolean;
/// <summary>Splits AText into the comment text it contains and everything
/// else: returns the joined comment content, and sets ARest to AText with every
/// comment removed. Handles the three Pascal spellings ({ }, (* *), //).</summary>
/// <param name="AText"><!-- drag-lint:auto --></param>
/// <param name="ARest"><!-- drag-lint:auto --></param>
/// <returns><!-- drag-lint:auto -->Observed: Trim(Note.ToString).</returns>
/// <remarks>
/// ONE implementation, TWO readers, and they must not diverge:
/// ParseParamNames strips comments out before reading a parameter's NAME (an
/// indexed signature keeps them verbatim, so `ALeft { the left edge }` would
/// otherwise become the name), while DRagLint.Doc.Facts.MineParamNotes keeps
/// the same comments as that parameter's harvested MEANING (ruling D-3). A
/// second copy of this scan is how the name half and the meaning half would end
/// up disagreeing about where a comment starts.
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Doc.Facts.MineParamNotes (DRagLint.Doc.Facts.pas), DRagLint.Refactor.DocStub.ParseParamNames (DRagLint.Refactor.DocStub.pas)
/// Calls: Copy, Trim
/// Complexity: 19 (cyclomatic, outer body), 49 lines (full implementation)
/// Mutates: ARest (out)
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
  Groups    : TArray<string>;
  Group     : string        ;
  NamesStr  : string        ;
  NamesClean: string        ;
  Names     : TArray<string>;
  N         : string        ;
  NTrimmed  : string        ;
  Acc       : TStringList   ;
  ColonPos  : Integer       ;
  I         : Integer       ;
const
  Qualifiers: array[0..4] of string = ('const ', 'var ', 'out ', 'in ', 'array of ');
begin
  if Trim(AParamList) = '' then Exit(nil);
  Groups:= AParamList.Split([';']);
  Acc:= TStringList.Create;
  try
    for I:= 0 to High(Groups) do
    begin
      Group:= Trim(Groups[I]);
      if Group = '' then Continue;
      // Strip leading qualifiers (const/var/out/in/array of).
      NamesStr:= Group;
      var LowerGroup:= LowerCase(NamesStr);
      for N in Qualifiers do
        if LowerGroup.StartsWith(N) then
        begin
          NamesStr:= Copy(NamesStr, Length(N) + 1, MaxInt);
          LowerGroup:= LowerCase(NamesStr);
        end;
      // Strip type after colon.
      ColonPos:= Pos(':', NamesStr);
      if ColonPos > 0 then NamesStr:= Copy(NamesStr, 1, ColonPos - 1);
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
        if Bare <> '' then Acc.Add(Bare);
      end;
    end; // for
    Result:= Acc.ToStringArray;
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

  // Determine whether a return value exists:
  //   - From signature text when available.
  //   - From symbol kind when no signature text could be found.
  if Sig <> '' then HasReturn:= SignatureHasReturn(Sig)
  else HasReturn:= Sym.Kind in [skFunction, skConstructor];

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
