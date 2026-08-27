unit DRagLint.MCP.Server;

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.JSON
  , System  .Generics   .Collections
  , DRagLint.Core       .Model
  , DRagLint.Core       .Interfaces
  , DRagLint.Storage    .SQLite
  , DRagLint.Lint       .Linter
  , DRagLint.Context    .Bundler
  , DRagLint.Resolver   .TypeAt
  , DRagLint.Refactor   .Rename
  , DRagLint.Diagnostics.CompileCheck
  , DRagLint.Diagnostics.AstChecks
  , DRagLint.Wiring
  ;

type
  // Newline-delimited JSON-RPC 2.0 server speaking MCP-2024-11-05 over stdio.
  // Holds one open ISymbolStore for the lifetime of the session.
  TMCPServer = class
    strict private
      FStore  : ISymbolStore  ;
      FLinter : TLinter       ;
      FDbPaths: TArray<string>;
      /// <param name="AText"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.MCP.Server.TMCPServer.SendError (DRagLint.MCP.Server.pas), DRagLint.MCP.Server.TMCPServer.SendResult (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: Flush, StringOf</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Destroy"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatDocAsJson"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatFindings"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatImpactAsJson"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SendRaw(const AText: string);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="AResult"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.MCP.Server.TMCPServer.HandleInitialize (DRagLint.MCP.Server.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsList (DRagLint.MCP.Server.pas), DRagLint.MCP.Server.TMCPServer.Run (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: DRagLint.MCP.Server.TMCPServer.SendRaw</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.SendRaw"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Destroy"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatDocAsJson"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatFindings"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SendResult(const AId: TJSONValue; const AResult: TJSONValue);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="ACode"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="AMessage"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas), DRagLint.MCP.Server.TMCPServer.Run (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: DRagLint.MCP.Server.TMCPServer.SendRaw</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.SendRaw"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Destroy"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatDocAsJson"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatFindings"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SendError(const AId: TJSONValue; ACode: Integer; const AMessage: string);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.MCP.Server.TMCPServer.Run (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: DRagLint.MCP.Server.TMCPServer.SendResult</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.SendResult"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Destroy"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatDocAsJson"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatFindings"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleInitialize(const AId: TJSONValue; const AParams: TJSONObject);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.MCP.Server.TMCPServer.Run (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: DRagLint.MCP.Server.TMCPServer.SendResult, DRagLint.MCP.Server.TMCPServer.ToolDescriptor</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.SendResult"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.ToolDescriptor"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Destroy"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatDocAsJson"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleToolsList(const AId: TJSONValue);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.MCP.Server.TMCPServer.Run (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: DRagLint.Context.Bundler.TContextBundler.Build, DRagLint.Context.Bundler.TContextBundler.RenderJson, DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName, DRagLint.Core.Interfaces.ISymbolStore.FindCallersByNameWithContext, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsFuzzy, DRagLint.Core.Model.JsonEscape, DRagLint.Diagnostics.AstChecks.TAstChecker.Check, DRagLint.Diagnostics.CompileCheck.TCompileChecker.InsertFindings (+26 more)</para>
      /// <para>Complexity: 93 (cyclomatic, outer body), 448 lines (full implementation)</para>
      /// <para>Reads: FStore, FLinter</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.Build"/>
      /// <seealso cref="DRagLint.Context.Bundler.TContextBundler.RenderJson"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindCallersByNameWithContext"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleToolsCall(const AId: TJSONValue; const AParams: TJSONObject);
      /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ADesc"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ASchemaJSON"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->TJSONObject -- Observed: TJSONObject.Create.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.MCP.Server.TMCPServer.HandleToolsList (DRagLint.MCP.Server.pas)</para>
      /// <para>Owns returned: new (caller owns)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Destroy"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatDocAsJson"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatFindings"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatImpactAsJson"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ToolDescriptor(const AName, ADesc: string; const ASchemaJSON: string): TJSONObject     ;
      /// <param name="AText"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->TJSONArray -- Observed: TJSONArray .Create.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)</para>
      /// <para>Owns returned: new (caller owns)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Destroy"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatDocAsJson"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatFindings"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatImpactAsJson"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function TextContent(const AText: string): TJSONArray                                           ;
      /// <param name="ASymbols"><!-- drag-lint:auto type -->const TArray&lt;TSymbol &gt;</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: Sb.ToString.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: Format</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Destroy"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatDocAsJson"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatFindings"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatImpactAsJson"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function FormatSymbols   (const ASymbols : TArray<TSymbol     >): string;
      /// <param name="ARefs"><!-- drag-lint:auto type -->const TArray&lt;TReference &gt;</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: Sb.ToString.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, Format</para>
      /// <para>Reads: FStore</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Destroy"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatDocAsJson"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatFindings"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function FormatReferences(const ARefs    : TArray<TReference  >): string;
      /// <param name="AFindings"><!-- drag-lint:auto type -->const TArray&lt;TLintFinding&gt;</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: Sb.ToString.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: Format</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Destroy"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatDocAsJson"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatImpactAsJson"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatReferences"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function FormatFindings  (const AFindings: TArray<TLintFinding>): string;
      /// <param name="AQName"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ADoc"><!-- drag-lint:auto type -->const TParsedDoc</param>
      /// <returns><!-- drag-lint:auto type -->string</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Model.DocFormatToStr, DRagLint.Core.Model.JsonEscape, DRagLint.Doc.Regions.TDocRegions.StripForDisplay</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.Model.DocFormatToStr"/>
      /// <seealso cref="DRagLint.Core.Model.JsonEscape"/>
      /// <seealso cref="DRagLint.Doc.Regions.TDocRegions.StripForDisplay"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function FormatDocAsJson(const AQName: string; const ADoc: TParsedDoc): string                  ;
      /// <param name="ASymbols"><!-- drag-lint:auto type -->const TArray&lt;TSymbol&gt;</param>
      /// <param name="AStore"><!-- drag-lint:auto type -->ISymbolStore</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: '[]'; '[' + string.Join(',',
      /// Parts) + ']'.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Model.JsonEscape, IntToStr</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
      /// <seealso cref="DRagLint.Core.Model.JsonEscape"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Destroy"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatDocAsJson"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function FormatSymbolsAsJsonArray(const ASymbols: TArray<TSymbol>; AStore: ISymbolStore): string;
      /// <param name="ARefs"><!-- drag-lint:auto type -->const TArray&lt;TReference&gt;</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: '{"callers":[]}';
      /// '{"callers":[' + string.Join(',', Parts) + ']}'.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Model.JsonEscape, IntToStr</para>
      /// <para>Reads: FStore</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
      /// <seealso cref="DRagLint.Core.Model.JsonEscape"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Destroy"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatDocAsJson"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function FormatReferencesWithContext(const ARefs: TArray<TReference>): string                   ;
      /// <param name="AQName"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ALevels"><!-- drag-lint:auto type -->const TArray&lt;TImpactLevel&gt;</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: '{"qname":"' +
      /// JsonEscape(AQName) + '","levels":[]}'; '{"qname":"' + JsonEscape(AQName) + '"' +
      /// ',"levels":[' + string.Join(',', Parts) + ']}'.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Model.JsonEscape, IntToStr</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.Model.JsonEscape"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Destroy"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatDocAsJson"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatFindings"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function FormatImpactAsJson (const AQName: string; const ALevels: TArray<TImpactLevel>): string;
      /// <param name="AQName"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ALines"><!-- drag-lint:auto type -->const TArray&lt;TSurfaceLine&gt;</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: '{"qname":"' +
      /// JsonEscape(AQName) + '","lines":[]}'; '{"qname":"' + JsonEscape(AQName) + '"' +
      /// ',"lines":[' + string.Join(',', Parts) + ']}'.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Model.JsonEscape, IntToStr</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.Model.JsonEscape"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Destroy"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatDocAsJson"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatFindings"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function FormatSurfaceAsJson(const AQName: string; const ALines : TArray<TSurfaceLine>): string;
      /// <param name="AQName"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AChunks"><!-- drag-lint:auto type -->const TArray&lt;TSliceChunk &gt;</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: '{"qname":"' +
      /// JsonEscape(AQName) + '","chunks":[]}'; '{"qname":"' + JsonEscape(AQName) + '"' +
      /// ',"chunks":[' + string.Join(',', Parts) + ']}'.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Model.JsonEscape, IntToStr</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.Model.JsonEscape"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Destroy"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatDocAsJson"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatFindings"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function FormatSliceAsJson  (const AQName: string; const AChunks: TArray<TSliceChunk >): string;
      /// <param name="AEdits"><!-- drag-lint:auto type -->const TArray&lt;TRenameEdit&gt;</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: '[]'; '[' + string.Join(',',
      /// Parts) + ']'.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Model.JsonEscape, IntToStr</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.Model.JsonEscape"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Destroy"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatDocAsJson"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatFindings"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function FormatRenameEditsAsJson(const AEdits: TArray<TRenameEdit>): string                     ;
      /// <param name="AArgs"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <returns><!-- drag-lint:auto -->ISymbolStore -- Observed:
      /// TSQLiteSymbolStore.Create(DbPath); FStore.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)</para>
      /// <para>Calls: DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create</para>
      /// <para>Reads: FStore</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Destroy"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatDocAsJson"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatFindings"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ResolveStore(const AArgs: TJSONObject): ISymbolStore                                   ;
    public
      /// <param name="ADbPaths"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.Run (DRagLint.CLI.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.Migrate, DRagLint.Lint.Linter.TLinter.Create, DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create</para>
      /// <para>constructor</para>
      /// <para>Reads: FDbPaths, FStore   Writes: FDbPaths, FStore, FLinter</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.Migrate"/>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.Create"/>
      /// <seealso cref="DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Destroy"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatDocAsJson"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(const ADbPaths: TArray<string>);
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Reads: FLinter   Writes: FStore</para>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.Create"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatDocAsJson"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatFindings"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatImpactAsJson"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.FormatReferences"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      destructor Destroy; override;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: DRagLint.MCP.Server.TMCPServer.HandleInitialize, DRagLint.MCP.Server.TMCPServer.HandleToolsCall, DRagLint.MCP.Server.TMCPServer.HandleToolsList, DRagLint.MCP.Server.TMCPServer.SendError, DRagLint.MCP.Server.TMCPServer.SendResult, Eof, ReadLn, TJSONObject, Trim</para>
      /// <para>Complexity: 19 (cyclomatic, outer body), 61 lines (full implementation)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.HandleInitialize"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.HandleToolsCall"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.HandleToolsList"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.SendError"/>
      /// <seealso cref="DRagLint.MCP.Server.TMCPServer.SendResult"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure Run;
  end;

implementation

uses
  DRagLint.Doc.Regions
  ;

constructor TMCPServer.Create(const ADbPaths: TArray<string>);
begin
  inherited Create;
  FDbPaths:= ADbPaths;
  // For simplicity v0.4 holds ONE primary store. Multi-DB at MCP call time
  // is v0.5; for now the AI passes a single --db on the serve invocation.
  if Length(FDbPaths) > 0 then
  begin
    FStore:= TSQLiteSymbolStore.Create(FDbPaths[0]);
    FStore.Migrate;
  end;
  FLinter:= TLinter.Create;
end;

destructor TMCPServer.Destroy;
begin
  FLinter.Free;
  FStore:= nil;
  inherited;
end;

procedure TMCPServer.SendRaw(const AText: string);
var
  Bytes: TBytes;
begin
  // Write directly to stdout as UTF-8, manually flushed. Avoids the
  // Delphi RTL TextFile layer's interpretation of newlines.
  Bytes:= TEncoding.UTF8.GetBytes(AText + #10);
  System.Write(StringOf(Bytes));
  Flush(Output);
end;

procedure TMCPServer.SendResult(const AId: TJSONValue; const AResult: TJSONValue);
var
  Reply: TJSONObject;
  Wire : string     ;
begin
  Reply:= TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue)
    else Reply.AddPair('id', TJSONNull.Create);
    Reply.AddPair('result', AResult);
    Wire:= Reply.ToJSON;
    SendRaw(Wire);
  finally
    Reply.Free;
  end;
end;

procedure TMCPServer.SendError(const AId: TJSONValue; ACode: Integer; const AMessage: string);
var
  Reply: TJSONObject;
  Err  : TJSONObject;
begin
  Reply:= TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue)
    else Reply.AddPair('id', TJSONNull.Create);
    Err:= TJSONObject.Create;
    Err.AddPair('code', TJSONNumber.Create(ACode));
    Err  .AddPair('message', AMessage);
    Reply.AddPair('error'  , Err     );
    SendRaw(Reply.ToJSON);
  finally
    Reply.Free;
  end;
end; // procedure

procedure TMCPServer.HandleInitialize(const AId: TJSONValue; const AParams: TJSONObject);
var
  Res : TJSONObject;
  Caps: TJSONObject;
  Info: TJSONObject;
begin
  Res:= TJSONObject.Create;
  Res.AddPair('protocolVersion', '2024-11-05');
  Caps:= TJSONObject.Create;
  Caps.AddPair('tools', TJSONObject.Create);
  Res.AddPair('capabilities', Caps);
  Info:= TJSONObject.Create;
  { NOT a literal, for the reason DRAGLINT_VERSION exists: an MCP client shows
    serverInfo in its logs, and the hardcoded copy here had drifted about forty
    releases behind the CLI banner. Core.Model's own doc-comment names the LSP
    and the CLI as the consumers -- this server was simply missed. }
  Info.AddPair('name'      , 'drag-lint'      );
  Info.AddPair('version'   , DRAGLINT_VERSION );
  Res .AddPair('serverInfo', Info             );
  SendResult(AId, Res);
end;

function TMCPServer.ToolDescriptor(const AName, ADesc, ASchemaJSON: string): TJSONObject;
var
  Schema: TJSONValue;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('name'       , AName);
  Result.AddPair('description', ADesc);
  Schema:= TJSONObject.ParseJSONValue(ASchemaJSON);
  if Schema = nil then Schema:= TJSONObject.Create;
  Result.AddPair('inputSchema', Schema);
end;

procedure TMCPServer.HandleToolsList(const AId: TJSONValue);
var
  Res  : TJSONObject;
  Tools: TJSONArray ;
begin
  Res  := TJSONObject.Create;
  Tools:= TJSONArray .Create;

  Tools.AddElement(ToolDescriptor(
      'find_symbol', 'Find Delphi/Pascal symbols by exact name (with fuzzy fallback) or by ' + 'qualified name (e.g. UnitName.TClass.MethodName). Returns matching '
        + 'symbols with file:line:col.',
      '{"type":"object","properties":{' + '"name":{"type":"string","description":"Bare symbol name"},' + '"qname":{"type":"string","description":"Qualified name"}'
        + '},"additionalProperties":false}'));

  Tools.AddElement(ToolDescriptor(
      'find_callers', 'Find every reference site to a method/event-handler by name. Returns ' + 'file:line:col rows. Includes DFM event-handler bindings when the .dfm '
        + 'files are indexed. When context > 0 each result includes surrounding ' + 'source lines.',
      '{"type":"object","properties":{' + '"name":{"type":"string","description":"Callee/handler name"},'
        + '"context":{"type":"integer","description":"Number of surrounding source lines to include (optional, default 0)"}' + '},"required":["name"],"additionalProperties":false}'
    ));

  Tools.AddElement(ToolDescriptor(
      'lint', 'Run the linter on a file or folder. Returns each finding with rule id, ' + 'severity, file:line:col, and message. Built-in rules + any *.scm rule '
        + 'files in <exedir>/rules/.',
      '{"type":"object","properties":{' + '"path":{"type":"string","description":"File or folder to lint"}' + '},"required":["path"],"additionalProperties":false}'));

  Tools.AddElement(ToolDescriptor(
      'get_symbol_doc', 'Return the structured doc comment for a Delphi symbol by its qualified ' + 'name. Returns format, summary, params, returns, exceptions, since, '
        + 'deprecated flag, and raw_block.', '{"type":"object","properties":{' + '"qname":{"type":"string","description":"Qualified symbol name (e.g. Unit.TClass.Method)"},'
        + '"db":{"type":"string","description":"Path to .sqlite database (optional if --db passed at startup)"}' + '},"required":["qname"]}'));

  Tools.AddElement(ToolDescriptor(
      'find_by_doc_tag', 'Find symbols whose doc comment has a given tag. Supported tags: ' + '"deprecated" (symbols marked deprecated) and "since" (symbols with '
        + 'a @since / <since> annotation).', '{"type":"object","properties":{' + '"tag":{"type":"string","description":"Tag to search: deprecated | since"},'
        + '"db":{"type":"string","description":"Path to .sqlite database (optional)"}' + '},"required":["tag"]}'));

  Tools.AddElement(ToolDescriptor(
      'find_undocumented', 'Find symbols that have no doc comment. Optionally filter by symbol kind ' + '(method, function, procedure, class, ...) and restrict to public symbols.',
      '{"type":"object","properties":{' + '"kind":{"type":"string","description":"Symbol kind filter (optional)"},'
        + '"public_only":{"type":"boolean","description":"Only include public symbols (optional)"},'
        + '"db":{"type":"string","description":"Path to .sqlite database (optional)"}' + '}}'));

  Tools.AddElement(ToolDescriptor(
      'get_impact', 'Return the transitive blast-radius of a symbol: how many callers and ' + 'units are impacted at each depth level. Uses a recursive CTE over the '
        + 'refs table. Input: qualified name (last segment used for lookup) and ' + 'optional depth (default 3).',
      '{"type":"object","properties":{' + '"qname":{"type":"string","description":"Qualified symbol name (e.g. Unit.TClass.Method)"},'
        + '"depth":{"type":"integer","description":"Maximum recursion depth (optional, default 3)"},'
        + '"db":{"type":"string","description":"Path to .sqlite database (optional)"}' + '},"required":["qname"]}'));

  Tools.AddElement(ToolDescriptor(
      'get_wiring', 'Return framework-aware wiring edges for a name: Spring4D DI ' + 'implementations (interface -> impl class + lifetime) and resolve-sites, '
        + 'plus DFM event handlers (a form''s methods bound to component events). ' + 'Pass an interface name for DI, or a form/class name for event handlers. '
        + 'Answers "who implements IFoo / where is it resolved / what handles this ' + 'form''s events" in one call.',
      '{"type":"object","properties":{' + '"qname":{"type":"string","description":"Interface name (DI) or form/class name (DFM handlers)"},'
        + '"db":{"type":"string","description":"Path to .sqlite database (optional)"}' + '},"required":["qname"]}'));

  Tools.AddElement(ToolDescriptor(
      'get_surface', 'Return the public interface of a class or record: the lines of its ' + 'declaration in the interface section. By default private/strict-private '
        + 'sections are excluded. Use all_visibility to include them.',
      '{"type":"object","properties":{' + '"qname":{"type":"string","description":"Qualified class/record name (e.g. Unit.TClass)"},'
        + '"include_impl":{"type":"boolean","description":"Include implementation bodies (optional, default false)"},'
        + '"all_visibility":{"type":"boolean","description":"Include private sections (optional, default false)"},'
        + '"db":{"type":"string","description":"Path to .sqlite database (optional)"}' + '},"required":["qname"]}'));

  Tools.AddElement(ToolDescriptor(
      'get_slice', 'Return a minimal, self-contained slice of the source unit for a given ' + 'class: unit header, class declaration, and implementation bodies for '
        + 'each method. Useful for LLM context with only the relevant code.',
      '{"type":"object","properties":{' + '"qname":{"type":"string","description":"Qualified class name (e.g. Unit.TClass)"},'
        + '"db":{"type":"string","description":"Path to .sqlite database (optional)"}' + '},"required":["qname"]}'));

  Tools.AddElement(ToolDescriptor(
      'get_context_bundle',
      'Return a curated context bundle for a symbol: doc, class surface, impl slice, ' + 'callers, and token estimate. Useful for preparing minimal AI-ready context for '
        + 'refactoring, inspection, or deletion tasks.',
      '{"type":"object","properties":{' + '"task":{"type":"string","description":"Task description (verb qname, e.g. \"modify Foo.Bar\")"},'
        + '"qname":{"type":"string","description":"Qualified symbol name (e.g. Unit.TClass.Method)"},'
        + '"verb":{"type":"string","description":"Action verb: modify|inspect|refactor|delete|extend (default modify)"},'
        + '"caller_context":{"type":"integer","description":"Number of surrounding source lines for each caller (optional, default 3)"},'
        + '"max_callers":{"type":"integer","description":"Maximum number of callers to include (optional, default 5)"},'
        + '"full_surface":{"type":"boolean","description":"Keep the auto-generated DFM component fields in the class surface (optional, default false = lean; set true only when working on the form components/DFM)"},'
        + '"db":{"type":"string","description":"Path to .sqlite database (optional)"}' + '},"required":["qname"]}'));

  Tools.AddElement(ToolDescriptor(
      'get_type_at_position',
      'Resolve the identifier at a given file/line/col position to a symbol in ' + 'the index. Returns token, containing symbol, resolved symbol, signature, '
        + 'and a note when the position is unresolvable (e.g. local variable).',
      '{"type":"object","properties":{' + '"file":{"type":"string","description":"Absolute or relative path to the source file"},'
        + '"line":{"type":"integer","description":"1-based line number"},' + '"col":{"type":"integer","description":"1-based column number"},'
        + '"db":{"type":"string","description":"Path to .sqlite database (optional)"}' + '},"required":["file","line","col"]}'));

  Tools.AddElement(ToolDescriptor(
      'rename_symbol', 'Rename every occurrence of a Delphi symbol (declaration + all references) ' + 'by its qualified name. In dry_run mode returns the edit list without '
        + 'modifying files; otherwise applies edits in place and writes .bak backups.',
      '{"type":"object","properties":{' + '"qname":{"type":"string","description":"Qualified name of the symbol to rename (e.g. Unit.TClass.Method)"},'
        + '"to":{"type":"string","description":"New short name for the symbol"},'
        + '"dry_run":{"type":"boolean","description":"If true, return edits without applying them (optional, default false)"},'
        + '"db":{"type":"string","description":"Path to .sqlite database (optional if --db passed at startup)"}' + '},"required":["qname","to"]}'));

  // v0.31: run AST-based diagnostics (no compiler required).
  Tools.AddElement(ToolDescriptor(
      'run_ast_checks', 'Run compiler-less AST diagnostics on a Delphi source file. ' + 'Checks: unbalanced begin/end, undeclared identifiers (vs symbol index). '
        + 'Works in Zed / VS Code / any editor without dcc.exe installed.',
      '{"type":"object","properties":{' + '"target":{"type":"string","description":"Absolute path to a .pas file"},'
        + '"db":{"type":"string","description":"Path to .sqlite database (optional -- enables undeclared-identifier check)"}'
        + '},"required":["target"],"additionalProperties":false}'));

  // v0.26: run dcc64/msbuild and return compiler findings as JSON.
  Tools.AddElement(ToolDescriptor(
      'run_compile_check', 'Spawn dcc64 or msbuild against a .pas or .dproj file, parse the output ' + 'for H/W/E/F diagnostic lines, and return the findings as JSON. '
        + 'When db is supplied the findings are also stored in compiler_findings ' + 'for later LSP publishDiagnostics merging.',
      '{"type":"object","properties":{' + '"target":{"type":"string","description":"Absolute path to a .pas file or .dproj project"},'
        + '"msbuild_path":{"type":"string","description":"Absolute path to msbuild.exe (optional)"},'
        + '"db":{"type":"string","description":"Path to .sqlite database (optional -- stores findings)"}' + '},"required":["target"],"additionalProperties":false}'));

  Res.AddPair('tools', Tools);
  SendResult(AId, Res);
end; // procedure

function TMCPServer.TextContent(const AText: string): TJSONArray;
var
  Obj: TJSONObject;
begin
  Result:= TJSONArray .Create;
  Obj   := TJSONObject.Create;
  Obj.AddPair('type', 'text');
  Obj.AddPair('text', AText );
  Result.AddElement(Obj);
end;

function TMCPServer.FormatSymbols(const ASymbols: TArray<TSymbol>): string;
var
  S : TSymbol       ;
  Sb: TStringBuilder;
begin
  Sb:= TStringBuilder.Create;
  try
    for S in ASymbols do Sb.AppendLine(Format('%s %s (%s) - line %d:%d', [S.Kind.ToText, S.QualifiedName, S.Name, S.StartLine, S.StartCol]));
    if Length(ASymbols) = 0 then Sb.AppendLine('No matches.')
    else Sb.AppendLine(Format('%d match(es).', [Length(ASymbols)]));
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function TMCPServer.FormatReferences(const ARefs: TArray<TReference>): string;
var
  R   : TReference    ;
  Sb  : TStringBuilder;
  Path: string        ;
begin
  Sb:= TStringBuilder.Create;
  try
    for R in ARefs do
    begin
      Path:= FStore.GetFilePath(R.FileId);
      Sb.AppendLine(Format('%s:%d:%d  %s  [%s]', [Path, R.StartLine, R.StartCol, R.NameText, R.Kind]));
    end;
    if Length(ARefs) = 0 then Sb.AppendLine('No references.')
    else Sb.AppendLine(Format('%d reference(s).', [Length(ARefs)]));
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end; // function

function TMCPServer.FormatFindings( const AFindings: TArray<TLintFinding>): string;
var
  F : TLintFinding  ;
  Sb: TStringBuilder;
begin
  Sb:= TStringBuilder.Create;
  try
    for F in AFindings do Sb.AppendLine(Format('%s:%d:%d  [%s] %s: %s', [F.FilePath, F.StartLine, F.StartCol, F.Severity, F.RuleId, F.Message]));
    if Length(AFindings) = 0 then Sb.AppendLine('No findings.')
    else Sb.AppendLine(Format('%d finding(s).', [Length(AFindings)]));
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function TMCPServer.ResolveStore(const AArgs: TJSONObject): ISymbolStore;
var
  DbVal : TJSONValue;
  DbPath: string    ;
begin
  // If the caller supplies a "db" argument, open a per-call store.
  // Otherwise fall back to the session-level FStore.
  if AArgs <> nil then DbVal:= AArgs.GetValue('db')
  else DbVal:= nil;
  if DbVal <> nil then
  begin
    DbPath:= DbVal.Value;
    Result:= TSQLiteSymbolStore.Create(DbPath);
    Result.Migrate;
  end
  else Result:= FStore;
end; // function

function TMCPServer.FormatDocAsJson(const AQName: string; const ADoc: TParsedDoc): string;
var
  DepStr: string;
begin
  if ADoc.Deprecated then DepStr:= 'true' else DepStr:= 'false';
  // v(ADP3 T1) review fix (finding 1): strip the ownership marker before it
  // reaches this MCP-facing JSON -- see TDocRegions.StripForDisplay's own
  // comment; ADoc.Summary/ReturnsText/ParamsJsonRaw themselves must keep
  // carrying it for the read path (MergeComment/drift). ParamsJsonRaw is a
  // raw JSON-array-shaped blob (one {"name":...,"desc":...} per param), so
  // the marker can sit MID-STRING, not just at position 1 -- StripForDisplay
  // removes every embedded occurrence, not only a leading one, so this is
  // safe to call on the whole raw blob. "raw_block" is deliberately NOT
  // cleaned: it is the verbatim source comment, not a rendered field.
  Result:= '{"qname":"' + JsonEscape(AQName) + '"' + ',"format":"' + JsonEscape(DocFormatToStr(ADoc.Format)) + '"' + ',"summary":"' + JsonEscape(TDocRegions.StripForDisplay(ADoc.Summary)) + '"' +
  ',"returns":"' + JsonEscape(TDocRegions.StripForDisplay(ADoc.ReturnsText)) + '"' + ',"since":"' + JsonEscape(ADoc.SinceText) + '"' + ',"deprecated":' + DepStr +
  ',"params_json":"' + JsonEscape(TDocRegions.StripForDisplay(ADoc.ParamsJsonRaw)) + '"' + ',"exceptions_json":"' + JsonEscape(ADoc.ExceptionsJsonRaw) + '"' +
  ',"seealso_json":"' + JsonEscape(ADoc.SeeAlsoJsonRaw) + '"' + ',"raw_block":"' + JsonEscape(ADoc.RawBlock) + '"' + '}';
end;

function TMCPServer.FormatSymbolsAsJsonArray(const ASymbols: TArray<TSymbol>; AStore: ISymbolStore): string;
var
  Parts   : TArray<string>;
  I       : Integer       ;
  FilePath: string        ;
begin
  if Length(ASymbols) = 0 then
  begin
    Result:= '[]';
    Exit;
  end;
  SetLength(Parts, Length(ASymbols));
  for I:= 0 to High(ASymbols) do
  begin
    if AStore <> nil then FilePath:= AStore.GetFilePath(ASymbols[I].FileId)
    else FilePath:= '';
    Parts[I]:= '{"qname":"' + JsonEscape(ASymbols[I].QualifiedName) + '"' + ',"kind":"' + JsonEscape(ASymbols[I].Kind.ToText) + '"' + ',"file":"' + JsonEscape(FilePath) + '"' +
    ',"line":' + IntToStr(ASymbols[I].StartLine) + '}';
  end;
  Result:= '[' + string.Join(',', Parts) + ']';
end; // function

function TMCPServer.FormatReferencesWithContext( const ARefs: TArray<TReference>): string;
// Formats callers as a JSON array; each element includes a "context" field
// when ContextText is non-empty (populated by FindCallersByNameWithContext).
var
  Parts   : TArray<string>;
  I       : Integer       ;
  FilePath: string        ;
  Store   : ISymbolStore  ;
begin
  Store:= FStore;
  if Length(ARefs) = 0 then
  begin
    Result:= '{"callers":[]}';
    Exit;
  end;
  SetLength(Parts, Length(ARefs));
  for I:= 0 to High(ARefs) do
  begin
    if Store <> nil then FilePath:= Store.GetFilePath(ARefs[I].FileId)
    else FilePath:= '';
    Parts[I]:= '{"file":"' + JsonEscape(FilePath) + '"' + ',"line":' + IntToStr(ARefs[I].StartLine) + ',"col":' + IntToStr(ARefs[I].StartCol) +
    ',"context":"' + JsonEscape(ARefs[I].ContextText) + '"' + '}';
  end;
  Result:= '{"callers":[' + string.Join(',', Parts) + ']}';
end; // function

function TMCPServer.FormatImpactAsJson(const AQName: string; const ALevels: TArray<TImpactLevel>): string;
// Returns: {"qname":"X","levels":[{"depth":1,"callers":12,"units":5,"delta":0},...]}
var
  Parts    : TArray<string>;
  I        : Integer       ;
  PrevCount: Integer       ;
  Delta    : Integer       ;
begin
  if Length(ALevels) = 0 then
  begin
    Result:= '{"qname":"' + JsonEscape(AQName) + '","levels":[]}';
    Exit;
  end;
  SetLength(Parts, Length(ALevels));
  PrevCount:= 0;
  for I:= 0 to High(ALevels) do
  begin
    Delta:= ALevels[I].CallerCount - PrevCount;
    Parts[I]:= '{"depth":' + IntToStr(ALevels[I].Depth) + ',"callers":' + IntToStr(ALevels[I].CallerCount) + ',"units":' + IntToStr(ALevels[I].UnitCount) +
    ',"delta":' + IntToStr(Delta) + '}';
    PrevCount:= ALevels[I].CallerCount;
  end;
  Result:= '{"qname":"' + JsonEscape(AQName) + '"' + ',"levels":[' + string.Join(',', Parts) + ']}';
end; // function

function TMCPServer.FormatSurfaceAsJson(const AQName: string; const ALines: TArray<TSurfaceLine>): string;
// Returns: {"qname":"X","lines":[{"kind":"source","text":"...","start_line":10,"end_line":10},...]}
var
  Parts: TArray<string>;
  I    : Integer       ;
begin
  if Length(ALines) = 0 then
  begin
    Result:= '{"qname":"' + JsonEscape(AQName) + '","lines":[]}';
    Exit;
  end;
  SetLength(Parts, Length(ALines));
  for I:= 0 to High(ALines) do Parts[I]:= '{"kind":"' + JsonEscape(ALines[I].Kind) + '"' + ',"text":"' + JsonEscape(ALines[I].Text) + '"' +
  ',"start_line":' + IntToStr(ALines[I].StartLine) + ',"end_line":' + IntToStr(ALines[I].EndLine) + '}';
  Result:= '{"qname":"' + JsonEscape(AQName) + '"' + ',"lines":[' + string.Join(',', Parts) + ']}';
end; // function

function TMCPServer.FormatSliceAsJson(const AQName: string; const AChunks: TArray<TSliceChunk>): string;
// Returns: {"qname":"X","chunks":[{"kind":"unit-header","text":"...","start_line":1,"end_line":3},...]}
var
  Parts: TArray<string>;
  I    : Integer       ;
begin
  if Length(AChunks) = 0 then
  begin
    Result:= '{"qname":"' + JsonEscape(AQName) + '","chunks":[]}';
    Exit;
  end;
  SetLength(Parts, Length(AChunks));
  for I:= 0 to High(AChunks) do Parts[I]:= '{"kind":"' + JsonEscape(AChunks[I].Kind) + '"' + ',"text":"' + JsonEscape(AChunks[I].Text) + '"' +
  ',"start_line":' + IntToStr(AChunks[I].StartLine) + ',"end_line":' + IntToStr(AChunks[I].EndLine) + '}';
  Result:= '{"qname":"' + JsonEscape(AQName) + '"' + ',"chunks":[' + string.Join(',', Parts) + ']}';
end; // function

function TMCPServer.FormatRenameEditsAsJson( const AEdits: TArray<TRenameEdit>): string;
// Returns a JSON array of edit objects:
// [{"file":"...","line":N,"col":N,"old":"OldName","new":"NewName"}, ...]
var
  Parts: TArray<string>;
  I    : Integer       ;
begin
  if Length(AEdits) = 0 then
  begin
    Result:= '[]';
    Exit;
  end;
  SetLength(Parts, Length(AEdits));
  for I:= 0 to High(AEdits) do Parts[I]:= '{"file":"' + JsonEscape(AEdits[I].FilePath) + '"' + ',"line":' + IntToStr(AEdits[I].Line) + ',"col":' + IntToStr(AEdits[I].Col) +
  ',"old":"' + JsonEscape(AEdits[I].OldName) + '"' + ',"new":"' + JsonEscape(AEdits[I].NewName) + '"' + '}';
  Result:= '[' + string.Join(',', Parts) + ']';
end; // function

procedure TMCPServer.HandleToolsCall(const AId: TJSONValue; const AParams: TJSONObject);
var
  ToolName  : string              ;
  Args      : TJSONObject         ;
  ResultText: string              ;
  Reply     : TJSONObject         ;
  Name      : string              ;
  QName     : string              ;
  Symbols   : TArray<TSymbol>     ;
  Refs      : TArray<TReference>  ;
  Findings  : TArray<TLintFinding>;
  LintPath  : string              ;
begin
  if (AParams = nil) or (AParams.GetValue('name') = nil) then
  begin
    SendError(AId, -32602, 'tools/call requires name + arguments');
    Exit;
  end;
  ToolName:= AParams.GetValue('name').Value;
  var ArgsVal:= AParams.GetValue('arguments');
  if ArgsVal is TJSONObject then Args:= TJSONObject(ArgsVal)
  else Args:= TJSONObject.Create;
  try
    if ToolName = 'find_symbol' then
    begin
      if FStore = nil then
      begin
        SendError(AId, -32000, 'no database loaded; pass --db on serve');
        Exit;
      end;
      Name := '';
      QName:= '';
      if Args.GetValue('name' ) <> nil then Name := Args.GetValue('name' ).Value;
      if Args.GetValue('qname') <> nil then QName:= Args.GetValue('qname').Value;
      if QName <> '' then Symbols:= FStore.FindSymbolsByQualifiedName(QName)
      else if Name <> '' then
      begin
        Symbols:= FStore.FindSymbolsByExactName(Name);
        if Length(Symbols) = 0 then Symbols:= FStore.FindSymbolsFuzzy(Name, 10);
      end
      else
      begin
        SendError(AId, -32602, 'find_symbol requires name or qname');
        Exit;
      end;
      ResultText:= FormatSymbols(Symbols);
    end // if
    else if ToolName = 'find_callers' then
    begin
      if FStore = nil then
      begin
        SendError(AId, -32000, 'no database loaded; pass --db on serve');
        Exit;
      end;
      if Args.GetValue('name') = nil then
      begin
        SendError(AId, -32602, 'find_callers requires name');
        Exit;
      end;
      Name:= Args.GetValue('name').Value;
      var CtxLines:= 0;
      if Args.GetValue('context') <> nil then CtxLines:= StrToIntDef(Args.GetValue('context').Value, 0);
      if CtxLines > 0 then
      begin
        Refs:= FStore.FindCallersByNameWithContext(Name, CtxLines);
        ResultText:= FormatReferencesWithContext(Refs);
      end
      else
      begin
        Refs:= FStore.FindCallersByName(Name);
        ResultText:= FormatReferences(Refs);
      end;
    end // if
    else if ToolName = 'lint' then
    begin
      if Args.GetValue('path') = nil then
      begin
        SendError(AId, -32602, 'lint requires path');
        Exit;
      end;
      LintPath:= Args.GetValue('path').Value;
      if TFile.Exists(LintPath) then Findings:= FLinter.LintFile(LintPath)
      else if TDirectory.Exists(LintPath) then Findings:= FLinter.LintFolder(LintPath, True)
      else
      begin
        SendError(AId, -32602, 'lint path does not exist');
        Exit;
      end;
      ResultText:= FormatFindings(Findings);
    end // if
    else if ToolName = 'get_symbol_doc' then
    begin
      var CallStore:= ResolveStore(Args);
      if CallStore = nil then
      begin
        SendError(AId, -32000, 'no database loaded; pass --db on serve or in arguments');
        Exit;
      end;
      var QNameVal:= '';
      if Args.GetValue('qname') <> nil then QNameVal:= Args.GetValue('qname').Value;
      if QNameVal = '' then
      begin
        SendError(AId, -32602, 'get_symbol_doc requires qname');
        Exit;
      end;
      var SymsForDoc:= CallStore.FindSymbolsByQualifiedName(QNameVal);
      if Length(SymsForDoc) = 0 then ResultText:= '{"error":"symbol not found","qname":"' + JsonEscape(QNameVal) + '"}'
      else
      begin
        var DocResult:= CallStore.GetSymbolDoc(SymsForDoc[0].Id);
        if not DocResult.HasContent then ResultText:= '{"error":"no doc comment","qname":"' + JsonEscape(QNameVal) + '"}'
        else ResultText:= FormatDocAsJson(SymsForDoc[0].QualifiedName, DocResult);
      end;
    end // if
    else if ToolName = 'find_by_doc_tag' then
    begin
      var CallStore2:= ResolveStore(Args);
      if CallStore2 = nil then
      begin
        SendError(AId, -32000, 'no database loaded; pass --db on serve or in arguments');
        Exit;
      end;
      var TagVal:= '';
      if Args.GetValue('tag') <> nil then TagVal:= Args.GetValue('tag').Value;
      if TagVal = '' then
      begin
        SendError(AId, -32602, 'find_by_doc_tag requires tag');
        Exit;
      end;
      var TagSyms:= CallStore2.FindByDocTag(TagVal);
      ResultText:= FormatSymbolsAsJsonArray(TagSyms, CallStore2);
    end // if
    else if ToolName = 'find_undocumented' then
    begin
      var CallStore3:= ResolveStore(Args);
      if CallStore3 = nil then
      begin
        SendError(AId, -32000, 'no database loaded; pass --db on serve or in arguments');
        Exit;
      end;
      var KindVal:= '';
      var PubOnly:= False;
      if Args.GetValue('kind') <> nil then KindVal:= Args.GetValue('kind').Value;
      if Args.GetValue('public_only') <> nil then PubOnly:= Args.GetValue('public_only').Value = 'true';
      var UndocSyms:= CallStore3.FindUndocumented(KindVal, PubOnly);
      ResultText:= FormatSymbolsAsJsonArray(UndocSyms, CallStore3);
    end // if
    else if ToolName = 'get_impact' then
    begin
      var ImpStore:= ResolveStore(Args);
      if ImpStore = nil then
      begin
        SendError(AId, -32000, 'no database loaded; pass --db on serve or in arguments');
        Exit;
      end;
      var ImpQName:= '';
      if Args.GetValue('qname') <> nil then ImpQName:= Args.GetValue('qname').Value;
      if ImpQName = '' then
      begin
        SendError(AId, -32602, 'get_impact requires qname');
        Exit;
      end;
      var ImpDepth:= 3;
      if Args.GetValue('depth') <> nil then ImpDepth:= StrToIntDef(Args.GetValue('depth').Value, 3);
      // Use last segment of qname for the symbol name lookup
      var ImpSegments:= ImpQName.Split(['.']);
      var ImpName:= ImpSegments[High(ImpSegments)];
      var ImpLevels:= ImpStore.FindTransitiveCallers(ImpName, ImpDepth);
      ResultText:= FormatImpactAsJson(ImpQName, ImpLevels);
    end // if
    else if ToolName = 'get_wiring' then
    begin
      var WStore:= ResolveStore(Args);
      if WStore = nil then
      begin
        SendError(AId, -32000, 'no database loaded; pass --db on serve or in arguments');
        Exit;
      end;
      var WQName:= '';
      if Args.GetValue('qname') <> nil then WQName:= Args.GetValue('qname').Value;
      if WQName = '' then
      begin
        SendError(AId, -32602, 'get_wiring requires qname');
        Exit;
      end;
      var WJson:= BuildWiringJson(WQName, WStore);
      try
        ResultText:= WJson.Format(2);
      finally
        WJson.Free;
      end;
    end // if
    else if ToolName = 'get_surface' then
    begin
      var SurfStore:= ResolveStore(Args);
      if SurfStore = nil then
      begin
        SendError(AId, -32000, 'no database loaded; pass --db on serve or in arguments');
        Exit;
      end;
      var SurfQName:= '';
      if Args.GetValue('qname') <> nil then SurfQName:= Args.GetValue('qname').Value;
      if SurfQName = '' then
      begin
        SendError(AId, -32602, 'get_surface requires qname');
        Exit;
      end;
      var SurfIncImpl:= False;
      var SurfAllVis := False;
      if Args.GetValue('include_impl'  ) <> nil then SurfIncImpl:= Args.GetValue('include_impl'  ).Value = 'true';
      if Args.GetValue('all_visibility') <> nil then SurfAllVis := Args.GetValue('all_visibility').Value = 'true';
      var SurfLines:= SurfStore.GetClassSurface(SurfQName, SurfIncImpl, SurfAllVis);
      ResultText:= FormatSurfaceAsJson(SurfQName, SurfLines);
    end // if
    else if ToolName = 'get_slice' then
    begin
      var SliceStore:= ResolveStore(Args);
      if SliceStore = nil then
      begin
        SendError(AId, -32000, 'no database loaded; pass --db on serve or in arguments');
        Exit;
      end;
      var SliceQName:= '';
      if Args.GetValue('qname') <> nil then SliceQName:= Args.GetValue('qname').Value;
      if SliceQName = '' then
      begin
        SendError(AId, -32602, 'get_slice requires qname');
        Exit;
      end;
      var SliceChunks:= SliceStore.GetSymbolSlice(SliceQName);
      ResultText:= FormatSliceAsJson(SliceQName, SliceChunks);
    end // if
    else if ToolName = 'get_context_bundle' then
    begin
      var BundleStore:= ResolveStore(Args);
      if BundleStore = nil then
      begin
        SendError(AId, -32000, 'no database loaded; pass --db on serve or in arguments');
        Exit;
      end;

      // Parse qname (required)
      var BundleQName:= '';
      if Args.GetValue('qname') <> nil then BundleQName:= Args.GetValue('qname').Value;
      if BundleQName = '' then
      begin
        SendError(AId, -32602, 'get_context_bundle requires qname');
        Exit;
      end;

      // Parse verb and task
      var BundleVerb:= 'modify';
      var BundleTask:= '';
      if Args.GetValue('task') <> nil then
      begin
        BundleTask:= Args.GetValue('task').Value;
        // Parse "verb qname" or just "qname"
        var Parts:= BundleTask.Split([' ']);
        if Length(Parts) >= 2 then
        begin
          BundleVerb:= Parts[0];
          // qname is already from Args, or take from parts[1] if different
        end;
      end;
      if Args.GetValue('verb') <> nil then BundleVerb:= Args.GetValue('verb').Value;

      // Parse optional args
      var BundleCallerContext:= 3;
      if Args.GetValue('caller_context') <> nil then BundleCallerContext:= StrToIntDef(Args.GetValue('caller_context').Value, 3);

      var BundleMaxCallers:= 5;
      if Args.GetValue('max_callers') <> nil then BundleMaxCallers:= StrToIntDef(Args.GetValue('max_callers').Value, 5);

      // Lean by default: strip auto-generated DFM component fields from the
      // class surface unless full_surface=true.
      var BundleFullSurface:= False;
      if Args.GetValue('full_surface') <> nil then BundleFullSurface:= SameText(Args.GetValue('full_surface').Value, 'true');

      // Build the bundle
      { BundleTask, not BundleQName: the wiki lookup matches a HUMAN phrase, and
        the qname has already been reduced to an identifier by the split above. }
      var Bundle:= TContextBundler.Build(BundleStore, BundleVerb, BundleQName, BundleCallerContext, BundleMaxCallers, True, True, True, {AExcludeDfmFields=} not BundleFullSurface, {ATaskText=} BundleTask);

      // Render as JSON
      ResultText:= TContextBundler.RenderJson(Bundle);
    end // if
    else if ToolName = 'get_type_at_position' then
    begin
      var TAPosStore:= ResolveStore(Args);
      if TAPosStore = nil then
      begin
        SendError(AId, -32000, 'no database loaded; pass --db on serve or in arguments');
        Exit;
      end;
      var TAPosFile:= '';
      var TAPosLine:= 0;
      var TAPosCol := 0;
      if Args.GetValue('file') <> nil then TAPosFile:= Args.GetValue('file').Value;
      if Args.GetValue('line') <> nil then TAPosLine:= StrToIntDef(Args.GetValue('line').Value, 0);
      if Args.GetValue('col' ) <> nil then TAPosCol := StrToIntDef(Args.GetValue('col' ).Value, 0);
      if TAPosFile = '' then
      begin
        SendError(AId, -32602, 'get_type_at_position requires file');
        Exit;
      end;
      if (TAPosLine <= 0) or (TAPosCol <= 0) then
      begin
        SendError(AId, -32602, 'get_type_at_position: line and col must be positive integers');
        Exit;
      end;
      var TAPosResult:= TTypeAtResolver.Resolve( TAPosStore, TAPosFile, TAPosLine, TAPosCol);
      ResultText:= TTypeAtResolver.RenderJson(TAPosResult);
    end // if
    else if ToolName = 'rename_symbol' then
    begin
      var RenStore:= ResolveStore(Args);
      if RenStore = nil then
      begin
        SendError(AId, -32000, 'no database loaded; pass --db on serve or in arguments');
        Exit;
      end;
      var RenQName := '';
      var RenTo    := '';
      var RenDryRun:= False;
      if Args.GetValue('qname') <> nil then RenQName:= Args.GetValue('qname').Value;
      if Args.GetValue('to'   ) <> nil then RenTo   := Args.GetValue('to'   ).Value;
      if Args.GetValue('dry_run') <> nil then RenDryRun:= Args.GetValue('dry_run').Value = 'true';
      if RenQName                                                                        = '' then
      begin
        SendError(AId, -32602, 'rename_symbol requires qname');
        Exit;
      end;
      if RenTo = '' then
      begin
        SendError(AId, -32602, 'rename_symbol requires to');
        Exit;
      end;
      var RenEdits:= TRenameRefactoring.Build(RenStore, RenQName, RenTo);
      if Length(RenEdits) = 0 then
      begin
        ResultText:= '{"edits":[],"files_touched":0,"applied":false,' + '"error":"symbol not found: ' + JsonEscape(RenQName) + '"}';
      end
      else
      begin
        var RenEditsJson:= FormatRenameEditsAsJson(RenEdits);
        var RenFilesTouched: Integer;
        var RenApplied     : Boolean;
        if RenDryRun then
        begin
          // Count distinct files from the edits array
          var RenFileSet:= TDictionary<string, Boolean>.Create;
          try
            var RenEd: TRenameEdit;
            for RenEd in RenEdits do RenFileSet.AddOrSetValue(RenEd.FilePath, True);
            RenFilesTouched:= RenFileSet.Count;
          finally
            RenFileSet.Free;
          end;
          RenApplied:= False;
        end
        else
        begin
          RenFilesTouched:= TRenameRefactoring.Apply(RenEdits, True);
          RenApplied:= True;
        end;
        var RenAppliedStr: string;
        if RenApplied then RenAppliedStr:= 'true' else RenAppliedStr:= 'false';
        ResultText:= '{"edits":' + RenEditsJson + ',"files_touched":' + IntToStr(RenFilesTouched) + ',"applied":' + RenAppliedStr + '}';
      end; // else
    end // if
    else if ToolName = 'run_ast_checks' then
    begin
      var AstTarget:= '';
      if Args.GetValue('target') <> nil then AstTarget:= Args.GetValue('target').Value;
      if AstTarget = '' then
      begin
        SendError(AId, -32602, 'run_ast_checks requires target');
        Exit;
      end;
      var AstStore:= ResolveStore(Args);
      var AstFindings:= TAstChecker.Check(AstStore, AstTarget);
      var AstParts: TArray<string>;
      SetLength(AstParts, Length(AstFindings));
      var AstIdx: Integer;
      for AstIdx:= 0 to High(AstFindings) do
      begin
        var AF:= AstFindings[AstIdx];
        AstParts[AstIdx]:= '{"file":"' + JsonEscape(AF.FilePath) + '"' + ',"line":' + IntToStr(AF.StartLine) + ',"col":' + IntToStr(AF.StartCol) +
        ',"severity":"' + JsonEscape(AF.Severity) + '"' + ',"rule":"' + JsonEscape(AF.RuleId) + '"' + ',"message":"' + JsonEscape(AF.Message) + '"' + '}';
      end;
      ResultText:= '{"findings":[' + string.Join(',', AstParts) + ']' + ',"count":' + IntToStr(Length(AstFindings)) + '}';
    end // if
    else if ToolName = 'run_compile_check' then
    begin
      var CCTarget := '';
      var CCMsbuild:= '';
      if Args.GetValue('target') <> nil then CCTarget:= Args.GetValue('target').Value;
      if CCTarget = '' then
      begin
        SendError(AId, -32602, 'run_compile_check requires target');
        Exit;
      end;
      if Args.GetValue('msbuild_path') <> nil then CCMsbuild:= Args.GetValue('msbuild_path').Value;

      // Run the compiler / msbuild.
      var CCResult:= TCompileChecker.Run(CCTarget, {AFullBuild=}False, CCMsbuild);

      // If a db was specified, also persist the findings.
      var CCStore:= ResolveStore(Args);
      if CCStore <> nil then TCompileChecker.InsertFindings(CCStore, CCResult.Findings);

      // Count by severity.
      var CCErrors  := 0;
      var CCWarnings:= 0;
      var CCHints   := 0;
      var CF: TCompilerFinding;
      for CF in CCResult.Findings do
      begin
        if SameText(CF.Severity, 'Error') then Inc(CCErrors)
        else if SameText(CF.Severity, 'Warning') then Inc(CCWarnings)
        else Inc(CCHints);
      end;

      // Build findings JSON array.
      var CCParts: TArray<string>;
      SetLength(CCParts, Length(CCResult.Findings));
      var CCIdx: Integer;
      for CCIdx:= 0 to High(CCResult.Findings) do
      begin
        CF:= CCResult.Findings[CCIdx];
        CCParts[CCIdx]:= '{"file":"' + JsonEscape(CF.RawPath) + '"' + ',"line":' + IntToStr(CF.LineNo) + ',"col":' + IntToStr(CF.ColNo) +
        ',"severity":"' + JsonEscape(CF.Severity) + '"' + ',"code":"' + JsonEscape(CF.Code) + '"' + ',"message":"' + JsonEscape(CF.Message) + '"' + '}';
      end;

      ResultText:= '{"findings":[' + string.Join(',', CCParts) + ']' + ',"by_severity":{' + '"errors":' + IntToStr(CCErrors) + ',"warnings":' + IntToStr(CCWarnings) +
      ',"hints":' + IntToStr(CCHints) + '}' + ',"exit_code":' + IntToStr(CCResult.ExitCode) + '}';
    end // if
    else
    begin
      SendError(AId, -32601, 'unknown tool: ' + ToolName);
      Exit;
    end;
  finally
    if (AParams.GetValue('arguments') = nil) then Args.Free;
  end; // try

  Reply:= TJSONObject.Create;
  Reply.AddPair('content', TextContent(ResultText));
  Reply.AddPair('isError', TJSONBool.Create(False));
  SendResult(AId, Reply);
end; // procedure

procedure TMCPServer.Run;
var
  Line  : string     ;
  Msg   : TJSONObject;
  Method: string     ;
  Id    : TJSONValue ;
  Params: TJSONObject;
  Parsed: TJSONValue ;
  Uri   : string     ;
begin
  while not Eof(Input) do
  begin
    ReadLn(Input, Line);
    Line:= Trim(Line);
    if Line = '' then Continue;
    Parsed:= TJSONObject.ParseJSONValue(Line);
    if not (Parsed is TJSONObject) then
    begin
      Parsed.Free;
      Continue;
    end;
    Msg:= TJSONObject(Parsed);
    try
      Method:= '';
      if Msg.GetValue('method') <> nil then Method:= Msg.GetValue('method').Value;
      Id:= Msg.GetValue('id');
      var ParamsVal:= Msg.GetValue('params');
      if ParamsVal is TJSONObject then Params:= TJSONObject(ParamsVal)
      else Params:= nil;

      if Method = 'initialize' then HandleInitialize(Id, Params)
      else if (Method = 'initialized') or (Method = 'notifications/initialized') then
        // notification, no response
      else if Method = 'tools/list' then HandleToolsList(Id)
      else if Method = 'tools/call' then HandleToolsCall(Id, Params)
      else if Method = 'ping' then SendResult(Id, TJSONObject.Create)
      // We expose no prompts and no resources -- but each method must answer
      // with ITS OWN key. Sharing one branch made resources/list reply
      // {"prompts":[]}: a SUCCESS carrying no `resources` member, which is
      // harder on a client than a clean -32601, because it walks straight into
      // result.resources.length. Guarded by run_mcp_protocol_guard.ps1.
      else if Method = 'prompts/list' then
        SendResult(Id, TJSONObject.Create.AddPair('prompts'  , TJSONArray.Create))
      else if Method = 'resources/list' then
        SendResult(Id, TJSONObject.Create.AddPair('resources', TJSONArray.Create))
      else if Method = 'resources/templates/list' then
        SendResult(Id, TJSONObject.Create.AddPair('resourceTemplates', TJSONArray.Create))
      else if Method = 'resources/read' then
      begin
        // Every URI is unknown because we advertise none. -32002 is the MCP
        // convention for that; -32601 would claim the METHOD is missing, which
        // is a different and misleading thing to tell a client.
        Uri:= '';
        if (Params <> nil) and (Params.GetValue('uri') <> nil) then Uri:= Params.GetValue('uri').Value;
        SendError(Id, -32002, 'resource not found: ' + Uri);
      end
      else if Method <> '' then SendError(Id, -32601, 'method not found: ' + Method);
    finally
      Msg.Free;
    end; // try
  end; // while
end; // procedure

end.
