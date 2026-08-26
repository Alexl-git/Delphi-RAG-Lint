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
  , DRagLint.Symbol     .Describe  { one shared type describer -- hover uses it too }
  ;

type
  // v0.20: LSP response builders for completion, signatureHelp, diagnostics.
  /// <summary><!-- drag-lint:auto -->v0.20: LSP response builders for completion,
  /// signatureHelp, diagnostics.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.LSP.Server.TLSPServer.HandleCompletion (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleSignatureHelp (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleDidOpenOrSave (DRagLint.LSP.Server.pas)</para>
  /// <para>Used in units: DRagLint.LSP.Server</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TLspCompletion = class
    public
      /// <param name="AKind"><!-- drag-lint:auto type -->TSymbolKind</param>
      /// <returns><!-- drag-lint:auto -->Integer -- Observed: 7; 22; 8; 13; 20; 2.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Completion.TLspCompletion.MakeCompletionItem (DRagLint.LSP.Completion.pas)</para>
      /// <para>Complexity: 13 (cyclomatic, outer body), 17 lines (full implementation)</para>
      /// <para>Pure</para>
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
      /// <returns><!-- drag-lint:auto -->Integer -- Observed: 1; 2; 3; 4.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto -->ASevText is the string severity stored in TLintFinding.Severity
      /// ('error', 'warning', 'info', 'hint').
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas)</para>
      /// <para>Calls: SameText</para>
      /// <para>Pure</para>
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
      /// <returns><!-- drag-lint:auto -->Integer -- Observed: 1; 2; 3; 4.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas)</para>
      /// <para>Calls: SameText</para>
      /// <para>Pure</para>
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
      /// <returns><!-- drag-lint:auto -->TJSONArray -- Observed:
      /// BuildCompletionItems(TArray&lt;ISymbolStore&gt;.Create(AStore), AFile, ALine,
      /// ACol).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems/4 (DRagLint.LSP.Completion.pas), DRagLint.LSP.Server.TLSPServer.HandleCompletion (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems/4</para>
      /// <para>Overload 1 of 2</para>
      /// <para>Recursive</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildSignatureHelp"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.EmptySigHelp"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.MakeCompletionItem"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function BuildCompletionItems(const AStore: ISymbolStore; const AFile: string; ALine, ACol: Integer): TJSONArray ; overload;

      /// <summary>Completion items at a position, resolved against EVERY open index.</summary>
      /// <param name="AStores">All open databases, the file's own project index
      /// first. Single-store completion silently returned nothing whenever the
      /// declaring type lived in another database -- a project-local variable of
      /// an RTL/VCL/third-party class, which is most variables in practice.</param>
      /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ALine"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="ACol"><!-- drag-lint:auto type -->Integer</param>
      /// <returns><!-- drag-lint:auto -->TJSONArray -- Observed: TJSONArray.Create.</returns>
      /// <remarks>
      /// Prefer this overload. The single-store one delegates here.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: CharInSet, Copy, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.LiveDocs.TLiveDocuments.Readable, DRagLint.Core.LiveDocs.TLiveDocuments.ReadLines, DRagLint.LSP.Completion.EnclosingTypeDescendsFrom, DRagLint.LSP.Completion.TLspCompletion.MakeCompletionItem, DRagLint.Resolver.TypeAt.TTypeAtResolver.CollectMembers, DRagLint.Resolver.TypeAt.TTypeAtResolver.ResolveMemberScope, LowerCase, Pos, SameText, StartsText</para>
      /// <para>Overload 2 of 2</para>
      /// <para>Complexity: 31 (cyclomatic, outer body), 156 lines (full implementation)</para>
      /// <para>Owns returned: new (caller owns)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
      /// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.Readable"/>
      /// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.ReadLines"/>
      /// <seealso cref="DRagLint.LSP.Completion.EnclosingTypeDescendsFrom"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.MakeCompletionItem"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function BuildCompletionItems(const AStores: TArray<ISymbolStore>; const AFile: string; ALine, ACol: Integer): TJSONArray ; overload;
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ALine"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="ACol"><!-- drag-lint:auto type -->Integer</param>
      /// <returns><!-- drag-lint:auto -->TJSONObject -- Observed: nil; EmptySigHelp;
      /// TJSONObject.Create.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.HandleSignatureHelp (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: CharInSet, Copy, DRagLint.Core.LiveDocs.TLiveDocuments.Readable, DRagLint.Core.LiveDocs.TLiveDocuments.ReadLines, DRagLint.Doc.Regions.TDocRegions.StripForDisplay, DRagLint.LSP.Completion.TLspCompletion.StripParamModifier, DRagLint.Resolver.TypeAt.TTypeAtResolver.Resolve/4, Pos, SplitString, Trim</para>
      /// <para>Complexity: 39 (cyclomatic, outer body), 197 lines (full implementation)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.Readable"/>
      /// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.ReadLines"/>
      /// <seealso cref="DRagLint.Doc.Regions.TDocRegions.StripForDisplay"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.StripParamModifier"/>
      /// <seealso cref="DRagLint.Resolver.TypeAt.TTypeAtResolver.Resolve"/>
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
      /// <returns><!-- drag-lint:auto -->TJSONArray -- Observed: TJSONArray.Create.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.HandleDidOpenOrSave (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindCompilerFindingsForFile, DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors, DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTypeAware, DRagLint.Diagnostics.CloneChecks.TCloneChecker.Check, DRagLint.Lint.Config.TLintConfig.ApplySeverity, DRagLint.Lint.Config.TLintConfig.Load, DRagLint.Lint.Config.TLintConfig.ShouldKeep, DRagLint.Lint.Linter.TLinter.LintFile, DRagLint.LSP.Completion.DiscoverLintConfig, DRagLint.LSP.Completion.TLspCompletion.MapCompilerSeverityToLspSeverity, DRagLint.LSP.Completion.TLspCompletion.MapLintSeverityToLspSeverity, ExtractFileExt, SameText</para>
      /// <para>Complexity: 16 (cyclomatic, outer body), 182 lines (full implementation)</para>
      /// <para>Owns returned: new (caller owns)</para>
      /// <para>Touches: file system</para>
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
      /// <returns><!-- drag-lint:auto -->TJSONObject -- Observed: TJSONObject.Create.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems/4 (DRagLint.LSP.Completion.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetSymbolDoc, DRagLint.Doc.Regions.TDocRegions.StripForDisplay, DRagLint.LSP.Completion.TLspCompletion.MapSymbolKindToLspKind, DRagLint.Symbol.Describe.DescribeTypeKind, LowerCase, Pos, Trim</para>
      /// <para>Complexity: 15 (cyclomatic, outer body), 101 lines (full implementation)</para>
      /// <para>Owns returned: new (caller owns)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolDoc"/>
      /// <seealso cref="DRagLint.Doc.Regions.TDocRegions.StripForDisplay"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.MapSymbolKindToLspKind"/>
      /// <seealso cref="DRagLint.Symbol.Describe.DescribeTypeKind"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function MakeCompletionItem(const ASym: TSymbol; const AStore: ISymbolStore): TJSONObject;
      /// <summary><!-- drag-lint:auto -->TLspCompletion</summary>
      /// <returns><!-- drag-lint:auto -->TJSONObject -- Observed: TJSONObject.Create.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Owns returned: new (caller owns)</para>
      /// <para>Pure</para>
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
      /// <para>Called from: DRagLint.LSP.Completion.TLspCompletion.BuildSignatureHelp (DRagLint.LSP.Completion.pas)</para>
      /// <para>Calls: Copy, StartsText, Trim</para>
      /// <para>Pure</para>
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
  , DRagLint.Core.LiveDocs  { v(live-buffer): unsaved editor text, consulted before disk }
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
  { `detail` is the TYPE slot. The IDE popup splits it into parameters and a
    return type and draws the return type green after a colon, so a symbol with
    no signature must contribute NOTHING here -- not its own qualified name,
    which used to be the fallback and rendered as `DoIt: uDetail.TThing.DoIt`.

    The plugin has been scrubbing that client-side with a
    `Pos('.' + label, detail) > 0` heuristic, which hid the symptom and would
    also blank a GENUINE signature containing '.' + the member's name (a
    parameter typed `TRec.Value` on a member called `Value`). Deciding it here,
    where the fact is known, removes both. }
  DetailStr:= ASym.Signature;

  { v(2026-08-19): a TYPE had nothing in this slot either -- a class, record,
    interface or enum reached the popup as a bare name. Same owner ask as the
    const work ("show the type of the result"), but NOT the same kind of change,
    and the difference is worth stating because it decided where the code went:

      a const's type/value existed NOWHERE in the store, so the parser had to
      emit it and DRAGLINT_EXTRACTOR_VERSION had to move -- hours of re-parse;

      a type's ancestors have been in `heritage` since v11, and an enum's
      members are already child symbols. Both are already inside the TSymbol
      this function is handed. Filling `signature` for them in the extractor
      would have duplicated indexed data and charged a SECOND full re-parse to
      say something the index already knew.

    So this is a rendering decision made where the facts arrive, exactly as the
    visibility and property-access markers below are. Nothing is INVENTED: a
    bare `TBase = class` declares no ancestor and stays blank rather than
    claiming TObject, because the popup draws this slot after a colon and an
    invented value would be indistinguishable from an indexed one. }
  { ONE describer, shared with the hover assembly -- see
    DRagLint.Symbol.Describe for why this must not be inlined here again. }
  if DetailStr = '' then DetailStr:= DescribeTypeKind(ASym, AStore);

  { Lead with the qualifiers that decide whether the symbol can be used HERE,
    and only those. Asked for after a protected field was offered, selected, and
    then rejected by the compiler with E2362: the popup described the symbol
    fully EXCEPT for the one property that determined whether it was usable.

    Two independent axes, both already in the store, so neither needs an
    extractor change or a DRAGLINT_EXTRACTOR_VERSION bump:
      visibility     -- Modifiers ('private' / 'protected'); public and
                        published carry nothing, since they constrain nothing.
      property access -- PropAccess ('ro' / 'wo'); 'rw' and '' say nothing
                        useful and are deliberately silent, per the request.
    A marker appears precisely when it is the thing worth knowing, so an
    ordinary public read/write property stays as clean as it was before. }
  var Quals: string:= '';

  if ASym.Modifiers <> '' then
  begin
    var VisWord: string:= LowerCase(Trim(ASym.Modifiers));
    if (Pos('private', VisWord) > 0) or (Pos('protected', VisWord) > 0) then Quals:= VisWord;
  end;

  if ASym.Kind = skProperty then
  begin
    var Acc: string:= LowerCase(Trim(ASym.PropAccess));
    var AccWord: string:= '';
    if      Acc = 'ro' then AccWord:= 'read-only'
    else if Acc = 'wo' then AccWord:= 'write-only';
    { 'rw' and '' fall through silently. '' is a bare redeclaration
      (`property Color;`) whose accessors are inherited -- reporting it as
      anything would be a guess. }
    if AccWord <> '' then
      if Quals = '' then Quals:= AccWord else Quals:= Quals + ', ' + AccWord;
  end;

  if Quals <> '' then DetailStr:= '[' + Quals + '] ' + DetailStr;
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

function EnclosingTypeDescendsFrom(const AStores: TArray<ISymbolStore>; const AFile: string;
  ALine: Integer; const ATypeName: string): Boolean;
{ True when the cursor sits inside a type that IS, or descends from, ATypeName.

  This is what makes `protected` legal at the completion site. Delphi's actual
  rule has three tiers: everything is reachable from code in the SAME UNIT as
  the declaring type; protected is additionally reachable from a DESCENDANT;
  otherwise only public/published. Offering protected everywhere put
  TEurekaExceptionInfo's protected FInfo/FLogBuilder into a completion list
  inside a plain procedure in an unrelated unit, where selecting it produces
  code that does not compile.

  Ancestry is matched BY NAME, not by symbol id, on purpose: ids are per
  database, and the interesting case is precisely the cross-database one -- the
  edited class lives in the project index while its ancestor lives in the
  platform library index, so an id comparison could never succeed. }
var
  I, J  : Integer            ;
  St    : ISymbolStore       ;
  FileId: Int64              ;
  Sym   : TSymbol            ;
  Owner : TSymbol            ;
  Anc   : TArray<TTypeAncestor>;
  Guard : Integer            ;
begin
  Result:= False;
  if ATypeName = '' then Exit;
  for I:= 0 to High(AStores) do
  begin
    St:= AStores[I];
    if St = nil then Continue;
    FileId:= St.FindFileIdByPath(AFile);
    if FileId <= 0 then Continue;          // not the store that owns this file

    Sym:= St.FindEnclosingRoutineByImpl(FileId, ALine);
    if Sym.Id <= 0 then Sym:= St.FindContainingSymbol(FileId, ALine);
    if Sym.Id <= 0 then Exit;

    { Walk up to the owning type. A free procedure never reaches one, which is
      the case that started this: the completion site was a standalone
      procedure, so nothing protected is legal there. }
    Owner:= Sym;
    Guard:= 0;
    while (Owner.Id > 0) and not (Owner.Kind in [skClass, skRecord, skInterface]) and (Guard < 16) do
    begin
      if Owner.ParentId <= 0 then Break;
      Owner:= St.GetSymbolById(Owner.ParentId);
      Inc(Guard);
    end;
    if (Owner.Id <= 0) or not (Owner.Kind in [skClass, skRecord, skInterface]) then Exit;

    if SameText(Owner.Name, ATypeName) then Exit(True);
    Anc:= St.GetTransitiveAncestors(Owner.Id);
    for J:= 0 to High(Anc) do
      if SameText(Anc[J].Name, ATypeName) then Exit(True);
    Exit;   // the owning store answered; no other store can improve on it
  end;
end;

class function TLspCompletion.BuildCompletionItems(const AStore: ISymbolStore; const AFile: string; ALine, ACol: Integer): TJSONArray;
begin
  { Legacy single-store entry point. Kept so existing callers compile, but it is
    the SHAPE that caused the cross-database miss -- new callers should pass
    every open store. }
  Result:= BuildCompletionItems(TArray<ISymbolStore>.Create(AStore), AFile, ALine, ACol);
end; // function

class function TLspCompletion.BuildCompletionItems(const AStores: TArray<ISymbolStore>; const AFile: string; ALine, ACol: Integer): TJSONArray;
var
  Lines     : TArray<string> ;
  LineText  : string         ;
  SubLine   : string         ;
  I         : Integer        ;
  IsDot     : Boolean        ;
  LhsEnd    : Integer        ;
  LhsStr    : string         ;
  PrefixStr : string         ;
  Children  : TArray<TSymbol>;
  Matches   : TArray<TSymbol>;
  Sym       : TSymbol        ;
  ScopeSym  : TSymbol        ;
  ScopeStore: ISymbolStore   ;
  SIdx      : Integer        ;
  Emitted   : Integer        ;
  SameUnit  : Boolean        ;
  AllowProt : Boolean        ;
  Vis       : string         ;
begin
  Result:= TJSONArray.Create;
  if Length(AStores) = 0 then Exit;
  { v(live-buffer): the caret describes the client's BUFFER. Reading disk here
    made completion blind to anything typed since the last save -- including the
    dot that triggered the request. }
  if not TLiveDocuments.Readable(AFile) then Exit;
  Lines:= TLiveDocuments.ReadLines(AFile);
  if (ALine < 1) or (ALine > Length(Lines)) then Exit;
  LineText:= Lines[ALine - 1];

  { SubLine is the text STRICTLY BEFORE the caret.

    ACol is 1-based and derived from the LSP 0-based `character`, which is the
    offset the caret sits AT -- so the character at ACol is the one to the RIGHT
    of the caret and must not be included. Copying through ACol included it, and
    every test written for this passed anyway because each fixture put the dot
    at END OF LINE, where there is no character to the right and the off-by-one
    cannot show. Real code has something after the caret: for
    `var S:= AExceptionInfo.;` the extra character is the ';', the dot test saw
    a semicolon, and completion returned an empty list in 22 ms -- fast, silent,
    and wrong. }
  if ACol < 2 then Exit
  else if ACol - 1 >= Length(LineText) then SubLine:= LineText
  else SubLine:= Copy(LineText, 1, ACol - 1);

  { Take the identifier being typed FIRST, then look at what precedes it.

    THE BUG THIS SHAPE FIXES. The old code checked only whether the character
    immediately left of the caret was a dot. That is true for `Foo.` and false
    the moment a single letter is typed, so `Foo.FI` fell through to the
    identifier branch -- a GLOBAL prefix search across every store, with no type
    scoping and no visibility filter at all. The member list therefore appeared
    correct on '.' and was silently replaced by unrelated same-prefix symbols on
    the next keystroke: that is how a protected FInfo, and a FBackupIgnored
    belonging to a different class entirely, were still offered and selected
    after the visibility work.

    Measuring the prefix first makes both cases the same case: PrefixStr is ''
    for `Foo.` and 'FI' for `Foo.FI`, and in both the character before it is the
    dot that makes this member completion. }
  I:= Length(SubLine);
  while (I >= 1) and CharInSet(SubLine[I], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Dec(I);
  PrefixStr:= Copy(SubLine, I + 1, Length(SubLine) - I);

  // Skip whitespace to the left of the typed prefix.
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

    { Resolve the LHS to the TYPE whose members belong here.

      This used to call Resolve and then test Resolved.Kind for a class kind.
      Resolved is the symbol AT THE CURSOR, so for `SomeVar.` it is the VARIABLE
      (skLocalVar/skParam/skField) and that test was false every time -- member
      completion returned an empty list for anything but a literal type name.
      ResolveMemberScope performs the follow-the-declared-type cascade instead,
      and searches every open store, because the class is very often indexed in
      a different database than the variable that has one. }
    ScopeSym:= TTypeAtResolver.ResolveMemberScope(AStores, AFile, ALine, LhsEnd, ScopeStore);
    if (ScopeSym.Id > 0) and (ScopeStore <> nil) then
    begin
      { CollectMembers, not FindAllChildSymbols: inherited members are members
        too, and offering only the leaf class's own declarations is a subtler
        version of the same emptiness. }
      Children:= TTypeAtResolver.CollectMembers(ScopeStore, ScopeSym.Id);

      { Offer only what the caller could legally touch, following Delphi's three
        tiers rather than approximating them:
          same unit as the declaring type -> everything, including private
          inside a descendant type        -> public/published + protected
          anywhere else                   -> public/published only
        The store records visibility in Modifiers (NOT the virtual/abstract
        directive -- that is TSymbol.IsVirtual), so this needs no extractor
        change and no DRAGLINT_EXTRACTOR_VERSION bump.
        An earlier cut filtered private but kept protected unconditionally, on
        the theory that protected is reachable from a descendant. It is -- but
        only IN one. In a standalone procedure in an unrelated unit that put
        protected backing fields in the list, and picking one produced code that
        does not compile. }
      SameUnit:= SameText(ScopeStore.GetFilePath(ScopeSym.FileId), AFile);
      AllowProt:= SameUnit or EnclosingTypeDescendsFrom(AStores, AFile, ALine, ScopeSym.Name);
      for Sym in Children do
      begin
        { Narrow by what has been typed since the dot. Filtering here rather
          than leaving it to the client keeps the contract honest: what the
          server offers is what is actually legal AND actually matches. }
        if (PrefixStr <> '') and not StartsText(PrefixStr, Sym.Name) then Continue;
        Vis:= LowerCase(Sym.Modifiers);
        if not SameUnit then
        begin
          if Pos('private', Vis) > 0 then Continue;
          if (Pos('protected', Vis) > 0) and not AllowProt then Continue;
        end;
        Result.AddElement(MakeCompletionItem(Sym, ScopeStore));
      end;
    end;
  end // if
  else
  begin
    { Bare identifier completion -- no dot anywhere to the left, so this really
      is an unqualified name and a global search is the right answer.
      PrefixStr was already measured above; recomputing it here is what let the
      two branches drift apart in the first place. }
    if PrefixStr = '' then Exit;

    { Every store, not just the first: the same cross-database blindness applies
      to plain identifier completion. The 50-item cap is per store so one large
      library index cannot crowd out the project's own symbols, which are the
      ones the user is most likely to want. }
    Emitted:= 0;
    for SIdx:= 0 to High(AStores) do
    begin
      if AStores[SIdx] = nil then Continue;
      Matches:= AStores[SIdx].FindSymbolsByPrefix(PrefixStr, 50);
      for Sym in Matches do
      begin
        Result.AddElement(MakeCompletionItem(Sym, AStores[SIdx]));
        Inc(Emitted);
        if Emitted >= 200 then Exit;   // hard ceiling: this is on the typing path
      end;
    end;
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
  if not TLiveDocuments.Readable(AFile) then
  begin
    Result:= EmptySigHelp;
    Exit;
  end;
  Lines:= TLiveDocuments.ReadLines(AFile);
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
