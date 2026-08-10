unit DRagLint.LSP.Completion;

interface

uses
  System.SysUtils
  , System.Classes
  , System.JSON
  , System.IOUtils
  , System.Generics.Collections
  , System.StrUtils
  , System.Types
  , DRagLint.Core       .Model
  , DRagLint.Core       .Interfaces
  , DRagLint.Lint       .Linter
  , DRagLint.Resolver   .TypeAt
  , DRagLint.Diagnostics.AstChecks
  , DRagLint.Diagnostics.CloneChecks
  , DRagLint.Lint       .Config
  ;

type
  // v0.20: LSP response builders for completion, signatureHelp, diagnostics.
  /// <summary><!-- drag-lint:auto -->v0.20: LSP response builders for completion,
  /// signatureHelp, diagnostics.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.LSP.Server.TLSPServer.HandleCompletion (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleSignatureHelp (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleDidOpenOrSave (DRagLint.LSP.Server.pas)
  /// Used in units: DRagLint.LSP.Server
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TLspCompletion = class
    public
      /// <param name="AKind"><!-- drag-lint:auto type -->TSymbolKind</param>
      /// <returns><!-- drag-lint:auto -->Observed: 7; 22; 8; 13; 20; 2.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Completion.TLspCompletion.MakeCompletionItem (DRagLint.LSP.Completion.pas)
      /// Complexity: 13 (cyclomatic, outer body), 17 lines (full implementation)
      /// Pure
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildSignatureHelp"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.EmptySigHelp"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.MakeCompletionItem"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function MapSymbolKindToLspKind(AKind: TSymbolKind): Integer;
      // ASevText is the string severity stored in TLintFinding.Severity
      // ('error', 'warning', 'info', 'hint').
      /// <param name="ASevText"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Observed: 1; 2; 3; 4.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto -->ASevText is the string severity stored in TLintFinding.Severity
      /// ('error', 'warning', 'info', 'hint').
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas)
      /// Calls: SameText
      /// Pure
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildSignatureHelp"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.EmptySigHelp"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.MakeCompletionItem"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function MapLintSeverityToLspSeverity(const ASevText: string): Integer;
      // v0.26: map compiler finding severity ('Error'|'Warning'|'Hint'|
      // 'Information') to LSP DiagnosticSeverity (1=Error, 2=Warning,
      // 3=Information, 4=Hint).
      /// <summary><!-- drag-lint:auto -->v0.26: map compiler finding severity
      /// ('Error'|'Warning'|'Hint'| 'Information') to LSP DiagnosticSeverity (1=Error,
      /// 2=Warning, 3=Information, 4=Hint).</summary>
      /// <param name="ASev"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Observed: 1; 2; 3; 4.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas)
      /// Calls: SameText
      /// Pure
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildSignatureHelp"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.EmptySigHelp"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.MakeCompletionItem"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function MapCompilerSeverityToLspSeverity(const ASev: string)                                       : Integer    ;
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ALine"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="ACol"><!-- drag-lint:auto type -->Integer</param>
      /// <returns><!-- drag-lint:auto -->Observed: TJSONArray.Create.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Server.TLSPServer.HandleCompletion (DRagLint.LSP.Server.pas)
      /// Calls: CharInSet, Copy, DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByPrefix, DRagLint.LSP.Completion.TLspCompletion.MakeCompletionItem, DRagLint.Resolver.TypeAt.TTypeAtResolver.Resolve/4
      /// Complexity: 20 (cyclomatic, outer body), 65 lines (full implementation)
      /// Owns returned: new (caller owns)
      /// Touches: file system
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByPrefix"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.MakeCompletionItem"/>
      /// <seealso cref="DRagLint.Resolver.TypeAt.TTypeAtResolver.Resolve"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function BuildCompletionItems(const AStore: ISymbolStore; const AFile: string; ALine, ACol: Integer): TJSONArray ;
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ALine"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="ACol"><!-- drag-lint:auto type -->Integer</param>
      /// <returns><!-- drag-lint:auto -->Observed: nil; EmptySigHelp; TJSONObject.Create.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Server.TLSPServer.HandleSignatureHelp (DRagLint.LSP.Server.pas)
      /// Calls: CharInSet, Copy, DRagLint.Doc.Regions.TDocRegions.StripForDisplay, DRagLint.LSP.Completion.TLspCompletion.StripParamModifier, DRagLint.Resolver.TypeAt.TTypeAtResolver.Resolve/4, Pos, SplitString, Trim
      /// Complexity: 39 (cyclomatic, outer body), 197 lines (full implementation)
      /// Touches: file system
      /// <seealso cref="DRagLint.Doc.Regions.TDocRegions.StripForDisplay"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.StripParamModifier"/>
      /// <seealso cref="DRagLint.Resolver.TypeAt.TTypeAtResolver.Resolve"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function BuildSignatureHelp(const AStore: ISymbolStore; const AFile: string; ALine, ACol: Integer)  : TJSONObject;
      // v0.26: AStore is optional; when supplied, compiler_findings for this file
      // are merged into the result alongside lint findings.
      /// <summary><!-- drag-lint:auto -->v0.26: AStore is optional; when supplied,
      /// compiler_findings for this file are merged into the result alongside lint
      /// findings.</summary>
      /// <param name="ALinter"><!-- drag-lint:auto type -->const TLinter</param>
      /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore = nil</param>
      /// <returns><!-- drag-lint:auto -->Observed: TJSONArray.Create.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Server.TLSPServer.HandleDidOpenOrSave (DRagLint.LSP.Server.pas)
      /// Calls: default, DRagLint.Core.Interfaces.ISymbolStore.FindCompilerFindingsForFile, DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTypeAware, DRagLint.Diagnostics.CloneChecks.TCloneChecker.Check, DRagLint.Lint.Config.TLintConfig.ApplySeverity, DRagLint.Lint.Config.TLintConfig.Load, DRagLint.Lint.Config.TLintConfig.ShouldKeep, DRagLint.Lint.Linter.TLinter.LintFile (+7 more)
      /// Complexity: 16 (cyclomatic, outer body), 182 lines (full implementation)
      /// Owns returned: new (caller owns)
      /// Touches: file system
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindCompilerFindingsForFile"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors"/>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTypeAware"/>
      /// <seealso cref="DRagLint.Diagnostics.CloneChecks.TCloneChecker.Check"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function BuildDiagnostics(const ALinter: TLinter; const AFile: string; const AStore: ISymbolStore = nil): TJSONArray;
    private
      /// <param name="ASym"><!-- drag-lint:auto type -->const TSymbol</param>
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <returns><!-- drag-lint:auto -->Observed: TJSONObject.Create.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems (DRagLint.LSP.Completion.pas)
      /// Calls: DRagLint.Core.Interfaces.ISymbolStore.GetSymbolDoc, DRagLint.Doc.Regions.TDocRegions.StripForDisplay, DRagLint.LSP.Completion.TLspCompletion.MapSymbolKindToLspKind
      /// Owns returned: new (caller owns)
      /// Pure
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolDoc"/>
      /// <seealso cref="DRagLint.Doc.Regions.TDocRegions.StripForDisplay"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.MapSymbolKindToLspKind"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function MakeCompletionItem(const ASym: TSymbol; const AStore: ISymbolStore): TJSONObject;
      /// <summary><!-- drag-lint:auto -->TLspCompletion</summary>
      /// <returns><!-- drag-lint:auto -->Observed: TJSONObject.Create.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Owns returned: new (caller owns)
      /// Pure
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildSignatureHelp"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.MakeCompletionItem"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.MapCompilerSeverityToLspSeverity"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function EmptySigHelp                                                       : TJSONObject;
      /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto type -->string</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Completion.TLspCompletion.BuildSignatureHelp (DRagLint.LSP.Completion.pas)
      /// Calls: Copy, StartsText, Trim
      /// Pure
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildSignatureHelp"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.EmptySigHelp"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.MakeCompletionItem"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function StripParamModifier(const AName: string)                            : string     ;
  end;

implementation

uses
  DRagLint.Doc.Regions
  ;

{ TLspCompletion }

class function TLspCompletion.EmptySigHelp: TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('signatures', TJSONArray.Create);
  Result.AddPair('activeSignature', TJSONNumber.Create(0));
  Result.AddPair('activeParameter', TJSONNumber.Create(0));
end;

class function TLspCompletion.StripParamModifier(const AName: string): string;
const
  Modifiers: array[0..3] of string = ('const ', 'var ', 'out ', 'constref ');
var
  I: Integer;
begin
  Result:= AName;
  for I:= 0 to High(Modifiers) do
    if StartsText(Modifiers[I], Result) then
    begin
      Result:= Trim(Copy(Result, Length(Modifiers[I]) + 1, MaxInt));
      Break;
    end;
end;

class function TLspCompletion.MapSymbolKindToLspKind( AKind: TSymbolKind): Integer;
begin
  case AKind of
    skClass     : Result:= 7;  // Class
    skRecord    : Result:= 22; // Struct
    skInterface : Result:= 8;  // Interface
    skEnum      : Result:= 13; // Enum
    skEnumValue : Result:= 20; // EnumMember
    skMethod, skFunction, skProcedure: Result:= 2 ; // Method
    skConstructor, skDestructor      : Result:= 4 ; // Constructor
    skProperty : Result:= 10; // Property
    skField    : Result:= 5;  // Field
    skUnit, skProgram, skPackage     : Result:= 9 ; // Module
    skConstDecl : Result:= 21; // Constant
    skVarDecl   : Result:= 6;  // Variable
    else Result:= 1; // Text (default for skForm, skComponent, skTypeAlias, etc.)
  end; // case
end; // function

class function TLspCompletion.MapLintSeverityToLspSeverity( const ASevText: string): Integer;
begin
  if SameText(ASevText, 'error') then Result:= 1
  else if SameText(ASevText, 'warning') then Result:= 2
  else if SameText(ASevText, 'info'   ) then Result:= 3
  else if SameText(ASevText, 'hint'   ) then Result:= 4
  else Result:= 3; // Information as default
end;

// v0.26: compiler finding severity uses title-case strings from
// TCompileChecker.NormalizeSeverity: 'Error', 'Warning', 'Hint', 'Information'.
class function TLspCompletion.MapCompilerSeverityToLspSeverity( const ASev: string): Integer;
begin
  if SameText(ASev, 'Error') then Result:= 1
  else if SameText(ASev, 'Warning'    ) then Result:= 2
  else if SameText(ASev, 'Information') then Result:= 3
  else if SameText(ASev, 'Hint'       ) then Result:= 4
  else Result:= 3; // default Information
end;

class function TLspCompletion.MakeCompletionItem(const ASym: TSymbol; const AStore: ISymbolStore): TJSONObject;
var
  Doc      : TParsedDoc;
  DetailStr: string    ;
  DocStr   : string    ;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('label', ASym.Name);
  Result.AddPair('kind', TJSONNumber.Create(MapSymbolKindToLspKind(ASym.Kind)));
  if ASym.Signature <> '' then DetailStr:= ASym.Signature
  else DetailStr:= ASym.QualifiedName;
  Result.AddPair('detail', DetailStr);
  Result.AddPair('insertText', ASym.Name);
  Result.AddPair('sortText', '0_' + ASym.Name);
  if Assigned(AStore) then
  begin
    Doc:= AStore.GetSymbolDoc(ASym.Id);
    // v(ADP3 T1) review fix (finding 1): strip the ownership marker before it
    // reaches the IDE completion popup -- see TDocRegions.StripForDisplay's
    // own comment; Doc.Summary/Doc.ReturnsText themselves must keep carrying
    // it for the read path (MergeComment/drift). Test the CLEANED summary for
    // emptiness (not the raw one), else a managed summary that is ONLY the
    // marker would still pass the old raw `<> ''` gate and add a
    // 'documentation' entry containing just the (now-stripped) marker.
    var CleanSummary: string:= TDocRegions.StripForDisplay(Doc.Summary);
    if Doc.HasContent and (CleanSummary <> '') then
    begin
      DocStr:= CleanSummary;
      var CleanReturns: string:= TDocRegions.StripForDisplay(Doc.ReturnsText);
      if CleanReturns <> '' then DocStr:= DocStr + #10 + 'Returns: ' + CleanReturns;
      Result.AddPair('documentation', DocStr);
    end;
  end;
end; // function

class function TLspCompletion.BuildCompletionItems(const AStore: ISymbolStore; const AFile: string; ALine, ACol: Integer): TJSONArray;
var
  Lines     : TArray<string> ;
  LineText  : string         ;
  SubLine   : string         ;
  I         : Integer        ;
  IsDot     : Boolean        ;
  LhsEnd    : Integer        ;
  LhsStr    : string         ;
  PrefixStr : string         ;
  TypeResult: TTypeAtResult  ;
  Children  : TArray<TSymbol>;
  Matches   : TArray<TSymbol>;
  Sym       : TSymbol        ;
begin
  Result:= TJSONArray.Create;
  if not TFile.Exists(AFile) then Exit;
  Lines:= TFile.ReadAllLines(AFile, TEncoding.ANSI);
  if (ALine < 1) or (ALine > Length(Lines)) then Exit;
  LineText:= Lines[ALine - 1];

  // SubLine is the text from col 1 up to ACol.
  if ACol < 1 then Exit
  else if ACol > Length(LineText) then SubLine:= LineText
  else SubLine:= Copy(LineText, 1, ACol);

  // Walk left from end of SubLine skipping whitespace.
  I:= Length(SubLine);
  while (I >= 1) and CharInSet(SubLine[I], [' ', #9]) do Dec(I);

  IsDot:= (I >= 1) and (SubLine[I] = '.');

  if IsDot then
  begin
    // Member completion: walk further left to extract LHS identifier chain.
    LhsEnd:= I - 1;
    while (LhsEnd >= 1) and CharInSet(SubLine[LhsEnd], [' ', #9]) do Dec(LhsEnd);
    // LhsEnd is now at the last char of the LHS expression.
    // Walk left while identifier chars or dot (Foo.Bar etc.).
    I:= LhsEnd;
    while (I >= 1) and CharInSet(SubLine[I], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do Dec(I);
    LhsStr:= Copy(SubLine, I + 1, LhsEnd - I);

    if LhsStr = '' then Exit;

    // Resolve the LHS to find the declared type.
    TypeResult:= TTypeAtResolver.Resolve(AStore, AFile, ALine, LhsEnd);
    if TypeResult.HasResolved and (TypeResult.Resolved.Kind in [skClass, skRecord, skInterface]) then
    begin
      Children:= AStore.FindAllChildSymbols(TypeResult.Resolved.Id);
      for Sym in Children do Result.AddElement(MakeCompletionItem(Sym, AStore));
    end;
  end // if
  else
  begin
    // Identifier completion: walk left while identifier chars to get prefix.
    I:= Length(SubLine);
    while (I >= 1) and CharInSet(SubLine[I], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Dec(I);
    PrefixStr:= Copy(SubLine, I + 1, Length(SubLine) - I);

    if PrefixStr = '' then Exit;

    Matches:= AStore.FindSymbolsByPrefix(PrefixStr, 50);
    for Sym in Matches do Result.AddElement(MakeCompletionItem(Sym, AStore));
  end;
end; // function

class function TLspCompletion.BuildSignatureHelp(const AStore: ISymbolStore; const AFile: string; ALine, ACol: Integer): TJSONObject;
var
  Lines        : TArray<string> ;
  LineText     : string         ;
  I            : Integer        ;
  C            : Char           ;
  Depth        : Integer        ;
  OpenParenCol : Integer        ;
  CalleeEnd    : Integer        ;
  TypeResult   : TTypeAtResult  ;
  SigStr       : string         ;
  ActiveParam  : Integer        ;
  Params       : TStringList    ;
  SigInfoObj   : TJSONObject    ;
  SigsArr      : TJSONArray     ;
  ParamsArr    : TJSONArray     ;
  ParamObj     : TJSONObject    ;
  J            : Integer        ;
  DocStr       : string         ;
  InSigParenStr: string         ;
  SigParenStart: Integer        ;
  Groups       : TStringDynArray;
  GrpIdx       : Integer        ;
  Grp          : string         ;
  ColonPos     : Integer        ;
  NamesStr     : string         ;
  Names        : TStringDynArray;
  NIdx         : Integer        ;
  NName        : string         ;
begin
  Result:= nil;
  if not TFile.Exists(AFile) then
  begin
    Result:= EmptySigHelp;
    Exit;
  end;
  Lines:= TFile.ReadAllLines(AFile, TEncoding.ANSI);
  if (ALine < 1) or (ALine > Length(Lines)) then
  begin
    Result:= EmptySigHelp;
    Exit;
  end;
  LineText:= Lines[ALine - 1];

  // Walk left from ACol to find unmatched '(' (top-level open paren).
  OpenParenCol:= 0;
  Depth       := 0;
  I           := ACol;
  if I > Length(LineText) then I:= Length(LineText);
  while I >= 1 do
  begin
    C:= LineText[I];
    if C      = ')' then Inc(Depth)
    else if C = '(' then
    begin
      if Depth = 0 then
      begin
        OpenParenCol:= I;
        Break;
      end;
      Dec(Depth);
    end;
    Dec(I);
  end;

  if OpenParenCol = 0 then
  begin
    Result:= EmptySigHelp;
    Exit;
  end;

  // Extract callee identifier from just before the '('.
  CalleeEnd:= OpenParenCol - 1;
  while (CalleeEnd >= 1) and CharInSet(LineText[CalleeEnd], [' ', #9]) do Dec(CalleeEnd);
  I:= CalleeEnd;
  while (I >= 1) and CharInSet(LineText[I], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do Dec(I);

  if CalleeEnd < 1 then
  begin
    Result:= EmptySigHelp;
    Exit;
  end;

  // Resolve callee symbol.
  TypeResult:= TTypeAtResolver.Resolve(AStore, AFile, ALine, CalleeEnd);
  if not TypeResult.HasResolved then
  begin
    Result:= EmptySigHelp;
    Exit;
  end;

  SigStr:= TypeResult.Resolved.Signature;
  if SigStr = '' then
  begin
    Result:= EmptySigHelp;
    Exit;
  end;

  // Count active parameter: top-level commas between OpenParenCol and ACol.
  ActiveParam:= 0;
  Depth      := 0;
  for I:= OpenParenCol + 1 to ACol do
  begin
    if I > Length(LineText) then Break;
    C:= LineText[I];
    if C      = '(' then Inc(Depth)
    else if C = ')' then
    begin
      if Depth > 0 then Dec(Depth);
    end
    else if (C = ',') and (Depth = 0) then Inc(ActiveParam);
  end;

  // Parse parameters from the signature string.
  // SigStr format: "function Name(a: T; b, c: U): RetType" etc.
  Params:= TStringList.Create;
  try
    SigParenStart:= Pos('(', SigStr);
    if SigParenStart > 0 then
    begin
      // Extract content inside outermost parentheses.
      Depth        := 0;
      InSigParenStr:= '';
      for I:= SigParenStart to Length(SigStr) do
      begin
        C:= SigStr[I];
        if C = '(' then
        begin
          Inc(Depth);
          if Depth > 1 then InSigParenStr:= InSigParenStr + C;
        end
        else if C = ')' then
        begin
          Dec(Depth);
          if Depth = 0 then Break;
          InSigParenStr:= InSigParenStr + C;
        end
        else InSigParenStr:= InSigParenStr + C;
      end; // for

      // Split on ';' (Delphi param groups: a, b: Integer; c: string).
      Groups:= SplitString(InSigParenStr, ';');
      for GrpIdx:= 0 to High(Groups) do
      begin
        Grp:= Trim(Groups[GrpIdx]);
        if Grp = '' then Continue;
        // Get names before the colon.
        ColonPos:= Pos(':', Grp);
        if ColonPos > 0 then NamesStr:= Copy(Grp, 1, ColonPos - 1)
        else NamesStr:= Grp;
        // Split on ',' to get individual names.
        Names:= SplitString(NamesStr, ',');
        for NIdx:= 0 to High(Names) do
        begin
          NName:= Trim(Names[NIdx]);
          NName:= StripParamModifier(NName);
          if NName <> '' then Params.Add(NName);
        end;
      end; // for
    end; // if

    // Build the SignatureHelp JSON response.
    SigsArr   := TJSONArray .Create;
    SigInfoObj:= TJSONObject.Create;
    SigInfoObj.AddPair('label', SigStr);

    // v(ADP3 T1) review fix (finding 1): strip the ownership marker before it
    // reaches the IDE signature-help popup -- see the sibling MakeCompletionItem
    // fix above and TDocRegions.StripForDisplay's own comment; the read path
    // (TypeResult.Doc.* itself) must keep carrying it. Test the CLEANED
    // summary for emptiness, not the raw one.
    var CleanSigSummary: string:= TDocRegions.StripForDisplay(TypeResult.Doc.Summary);
    if TypeResult.HasDoc and (CleanSigSummary <> '') then
    begin
      DocStr:= CleanSigSummary;
      var CleanSigReturns: string:= TDocRegions.StripForDisplay(TypeResult.Doc.ReturnsText);
      if CleanSigReturns <> '' then DocStr:= DocStr + #10 + 'Returns: ' + CleanSigReturns;
      SigInfoObj.AddPair('documentation', DocStr);
    end;

    ParamsArr:= TJSONArray.Create;
    for J:= 0 to Params.Count - 1 do
    begin
      ParamObj:= TJSONObject.Create;
      ParamObj.AddPair('label', Params[J]);
      ParamsArr.AddElement(ParamObj);
    end;
    SigInfoObj.AddPair('parameters', ParamsArr);
    SigsArr.AddElement(SigInfoObj);

    Result:= TJSONObject.Create;
    Result.AddPair('signatures', SigsArr);
    Result.AddPair('activeSignature', TJSONNumber.Create(0          ));
    Result.AddPair('activeParameter', TJSONNumber.Create(ActiveParam));
  finally
    Params.Free;
  end; // try
end; // function

{ v0.77: discover a lint config by walking up from AFile's directory. The plugin
  writes 'drag-lint-lint.json' next to the project; a plain 'drag-lint.json' is
  also honored. Returns '' when none is found (Load then yields a no-op default
  that keeps everything). This lets the IDE (LSP) honor rule enable/disable +
  severity overrides the same way the CLI does -- previously the LSP ignored all
  config, so noisy rules could not be silenced in the editor. }
function DiscoverLintConfig(const AFile: string): string;
const
  CANDIDATES: array[0..1] of string = ('drag-lint-lint.json', 'drag-lint.json');
var
  Dir, Parent, Cand: string;
begin
  Result:= '';
  Dir:= ExtractFilePath(AFile);
  while Dir <> '' do
  begin
    for Cand in CANDIDATES do
      if TFile.Exists(Dir + Cand) then Exit(Dir + Cand);
    Parent:= ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if (Parent = '') or (Parent = Dir) then Break;
    Dir:= Parent;
  end;
end;

class function TLspCompletion.BuildDiagnostics(const ALinter: TLinter; const AFile: string; const AStore: ISymbolStore = nil): TJSONArray;
var
  Findings: TArray<TLintFinding>;
  F       : TLintFinding        ;
  Cfg     : TLintConfig         ;
  Sev     : string              ;
  DiagObj : TJSONObject         ;
  RangeObj: TJSONObject         ;
  StartObj: TJSONObject         ;
  EndObj  : TJSONObject         ;
  // v0.26 compiler findings
  FileId   : Int64                   ;
  CFindings: TArray<TCompilerFinding>;
  CF       : TCompilerFinding        ;
  CStart   : TJSONObject             ;
  CEnd     : TJSONObject             ;
  CRange   : TJSONObject             ;
begin
  Result:= TJSONArray.Create;
  if not TFile.Exists(AFile) then Exit;

  { v0.77: honor an up-tree lint config so the IDE can disable noisy rules /
    override severities, matching the CLI. Empty path -> no-op default (keep all). }
  Cfg:= TLintConfig.Load(DiscoverLintConfig(AFile), '');

  // --- Lint findings ---
  if Assigned(ALinter) then
  begin
    Findings:= ALinter.LintFile(AFile);
    { When a store is present, the precise type-aware built-in supersedes the
      type-BLIND .scm 'string-equality-comparison' rule for the SAME concern.
      The .scm regex fires on any non-literal '=' -- including `Key = VK_F10`
      (Word vs an integer const) and `X.BoxType = kFlex` (enum vs enum const) --
      because it cannot resolve a named-constant/enum/Word operand. Drop those
      .scm findings and replace them with ONLY the string-equality findings from
      CheckTypeAware, which flags a '=' solely when BOTH operands resolve to a
      string type. ResolveTypeCategory classifies intrinsics (Word -> integer,
      string -> tcString) DB-free, so no library DB is required for the common
      case. We take ONLY the string-equality-comparison finding from
      CheckTypeAware (not its full suite) so the LSP diagnostic set is otherwise
      unchanged -- this is a targeted FP fix, not a new-rule rollout. Without a
      store we keep the .scm finding (best effort). }
    if AStore <> nil then
    begin
      var Rebuilt: TArray<TLintFinding>;
      for var LF in Findings do
        if not SameText(LF.RuleId, 'string-equality-comparison') then Rebuilt:= Rebuilt + [LF];
      for var TF in DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTypeAware(AFile, AStore, AStore.FindFileIdByPath(AFile)) do
        if SameText(TF.RuleId, 'string-equality-comparison') then Rebuilt:= Rebuilt + [TF];
      Findings:= Rebuilt;
    end;
    for F in Findings do
    begin
      if not Cfg.ShouldKeep(F.RuleId, False) then Continue; { config-disabled rule }
      Sev:= Cfg.ApplySeverity(F.RuleId, F.Severity);

      DiagObj:= TJSONObject.Create;

      StartObj:= TJSONObject.Create;
      StartObj.AddPair('line'     , TJSONNumber.Create(F.StartLine - 1));
      StartObj.AddPair('character', TJSONNumber.Create(F.StartCol  - 1));

      EndObj:= TJSONObject.Create;
      EndObj.AddPair('line'     , TJSONNumber.Create(F.EndLine - 1));
      EndObj.AddPair('character', TJSONNumber.Create(F.EndCol  - 1));

      RangeObj:= TJSONObject.Create;
      RangeObj.AddPair('start', StartObj);
      RangeObj.AddPair('end'  , EndObj  );

      DiagObj.AddPair('range', RangeObj);
      DiagObj.AddPair('severity', TJSONNumber.Create(MapLintSeverityToLspSeverity(Sev)));
      DiagObj.AddPair('source', 'drag-lint');
      DiagObj.AddPair('code'   , F.RuleId );
      DiagObj.AddPair('message', F.Message);

      Result.AddElement(DiagObj);
    end; // for
  end; // if

  // --- v8: AST syntax errors, for PARITY with the CLI `lint` / live-runner path
  //     (added in dadf9b9). The LSP publishDiagnostics that runs on didOpen/
  //     didSave used to omit these, so it carried the lint warnings above but
  //     NEVER the typed syntax error -- and that save-time publish overwrites the
  //     live runner's richer set, leaving the diagnostics pane showing
  //     "warnings only". (Supersedes the v0.42 suppression note: the CLI path
  //     already ships these and the report is a MISSING error, not false ones; if
  //     a grammar false-positive recurs, fix tree-sitter-delphi13 rather than
  //     hide real errors.) Gated to source files. ---
  if SameText(ExtractFileExt(AFile), '.pas') or SameText(ExtractFileExt(AFile), '.inc') then
    for F in TAstChecker.CheckSyntaxErrors(AFile) do
    begin
      DiagObj := TJSONObject.Create;
      StartObj:= TJSONObject.Create;
      StartObj.AddPair('line'     , TJSONNumber.Create(F.StartLine - 1));
      StartObj.AddPair('character', TJSONNumber.Create(F.StartCol  - 1));
      EndObj:= TJSONObject.Create;
      EndObj.AddPair('line'     , TJSONNumber.Create(F.EndLine - 1));
      EndObj.AddPair('character', TJSONNumber.Create(F.EndCol  - 1));
      RangeObj:= TJSONObject.Create;
      RangeObj.AddPair('start', StartObj);
      RangeObj.AddPair('end'  , EndObj  );
      DiagObj .AddPair('range', RangeObj);
      DiagObj.AddPair('severity', TJSONNumber.Create(MapLintSeverityToLspSeverity(F.Severity)));
      DiagObj.AddPair('source', 'drag-lint');
      DiagObj.AddPair('code'   , F.RuleId );
      DiagObj.AddPair('message', F.Message);
      Result.AddElement(DiagObj);
    end; // for

  // --- v0.77: duplicate-code (clone) findings, for PARITY with the CLI `lint`
  //     path. BuildDiagnostics runs the TLinter set + syntax errors + compiler
  //     findings, but NOT the extra checks DoLint layers on top -- clone
  //     detection among them -- so the IDE (which reads these LSP diagnostics)
  //     never surfaced duplicated code. Run the within-file clone pass here so it
  //     appears inline. The CLI path already runs it via DoLint/DoLintAll, so this
  //     LSP-only addition does not double-report. Gated to source files. ---
  if SameText(ExtractFileExt(AFile), '.pas') or SameText(ExtractFileExt(AFile), '.inc') then
    for F in TCloneChecker.Check(AFile) do
    begin
      if not Cfg.ShouldKeep(F.RuleId, False) then Continue; { config-disabled }
      Sev:= Cfg.ApplySeverity(F.RuleId, F.Severity);
      DiagObj := TJSONObject.Create;
      StartObj:= TJSONObject.Create;
      StartObj.AddPair('line'     , TJSONNumber.Create(F.StartLine - 1));
      StartObj.AddPair('character', TJSONNumber.Create(F.StartCol  - 1));
      EndObj:= TJSONObject.Create;
      EndObj.AddPair('line'     , TJSONNumber.Create(F.EndLine - 1));
      EndObj.AddPair('character', TJSONNumber.Create(F.EndCol  - 1));
      RangeObj:= TJSONObject.Create;
      RangeObj.AddPair('start', StartObj);
      RangeObj.AddPair('end'  , EndObj  );
      DiagObj .AddPair('range', RangeObj);
      DiagObj.AddPair('severity', TJSONNumber.Create(MapLintSeverityToLspSeverity(Sev)));
      DiagObj.AddPair('source', 'drag-lint');
      DiagObj.AddPair('code'   , F.RuleId );
      DiagObj.AddPair('message', F.Message);
      Result.AddElement(DiagObj);
    end; // for

  // --- v0.26: Compiler findings from the DB ---
  if Assigned(AStore) then
  begin
    FileId:= AStore.FindFileIdByPath(AFile);
    if FileId > 0 then
    begin
      CFindings:= AStore.FindCompilerFindingsForFile(FileId);
      for CF in CFindings do
      begin
        DiagObj:= TJSONObject.Create;

        // LineNo/ColNo are 1-based; LSP range is 0-based. BUT compiler HINTS
        // (e.g. "Hint warning H2219") arrive with ColNo = 0 (no column), so a
        // naive ColNo-1 yields character = -1 -- an INVALID LSP position that
        // the IDE silently drops (the diagnostic is published but no gutter
        // glyph renders). Clamp: when ColNo <= 0, span the whole line start
        // (0..1) so the finding is always visible; otherwise use the 0-based
        // column with a non-empty end.
        CStart:= TJSONObject.Create;
        CStart.AddPair('line'     , TJSONNumber.Create(CF.LineNo - 1));
        if CF.ColNo <= 0 then CStart.AddPair('character', TJSONNumber.Create(0))
        else CStart.AddPair('character', TJSONNumber.Create(CF.ColNo - 1));

        CEnd:= TJSONObject.Create;
        CEnd.AddPair('line', TJSONNumber.Create(CF.LineNo - 1));
        if CF.ColNo <= 0 then CEnd.AddPair('character', TJSONNumber.Create(1))
        else CEnd.AddPair('character', TJSONNumber.Create(CF.ColNo));

        CRange:= TJSONObject.Create;
        CRange.AddPair('start', CStart);
        CRange.AddPair('end'  , CEnd  );

        DiagObj.AddPair('range', CRange);
        DiagObj.AddPair('severity', TJSONNumber.Create( MapCompilerSeverityToLspSeverity(CF.Severity)));
        DiagObj.AddPair('source', 'dcc');
        DiagObj.AddPair('code'   , CF.Code   );
        DiagObj.AddPair('message', CF.Message);

        Result.AddElement(DiagObj);
      end; // for
    end; // if
  end; // if
end; // function

end.
