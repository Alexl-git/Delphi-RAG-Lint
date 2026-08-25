unit DRagLint.LSP.Server;

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.Generics.Collections  { v(P7): the per-file source cache in HandleHoverBundle }
  , System.JSON
  , System.NetEncoding
  , Winapi.Windows
  , TreeSitter
  , TreeSitterLib
  , DRagLint.Core    .Model
  , DRagLint.Core    .Interfaces
  , DRagLint.Core    .Encoding
  , DRagLint.Storage .SQLite
  , DRagLint.Parser  .Delphi13
  , DRagLint.Hover   .Renderer
  , DRagLint.Hover   .Returns
  , DRagLint.Resolver.TypeAt
  , DRagLint.Lint    .Linter
  , DRagLint.LSP     .Completion
  , DRagLint.Core    .LiveDocs  { v(live-buffer): unsaved editor text, consulted before disk }
  , DRagLint.Doc     .Facts     { v(ADP2 T9): TDocFactsBuilder.Build -- hover's Phase-2 facts }
  , DRagLint.Doc     .Regions   { v(ADP2 T9): TDocRegions.FormatPhase2FactLines -- the shared formatter }
  , DRagLint.Index   .Manifest  { v(ADP2 T9): LoadDocComplexityMin -- same threshold `document` uses }
  , DRagLint.Query   .Callers   { v(hover bundle): the shared caller queries the CLI also renders from }
  , DRagLint.Query   .HoverModel{ v(hover bundle): the shared model assembly `hover --format json` uses }
  ;

type
  /// <summary>Everything resolving a hover position produces, so that
  /// `textDocument/hover` and `draglint/hoverBundle` answer from ONE
  /// resolution instead of two that can disagree.</summary>
  /// <remarks>
  /// <para>MdValue is always set when the computation succeeded. The remaining
  /// fields are meaningful only WHILE HasSymbol is True: a compiler intrinsic
  /// renders real markdown but has no indexed symbol behind it, and a bundle
  /// built from Sel in that state would describe symbol id 0.</para>
  /// <para>Store is the store the symbol was found in -- not necessarily
  /// FStores[0], because the type-at resolver may cross into a library index
  /// for an inherited or generic member. Caller queries must run against THIS
  /// store, or they answer about a different symbol that shares the name.</para>
  /// </remarks>
  THoverComputation = record
    MdValue  : string      ;
    HasSymbol: Boolean     ;
    Sel      : TSymbol     ;
    Store    : ISymbolStore;
    /// <summary>Set when the cursor was on a compiler intrinsic. There is no
    /// indexed symbol behind one, so HasSymbol stays False -- but the name and
    /// signature ARE known, and a client that got only markdown had nothing to
    /// render but plain text.</summary>
    /// <remarks>Reported from the live IDE 2026-08-19: hovering Length showed
    /// uncoloured text while every other symbol showed a coloured signature,
    /// because the popup's structured renderer needs a MODEL and intrinsics
    /// were the one case that never produced one.</remarks>
    IsIntrinsic  : Boolean;
    IntrinsicName: string ;
    IntrinsicSig : string ;
  end;

  // Language Server Protocol over stdio with Content-Length framing.
  // Implements the subset that's actually useful when backed by a static
  // symbol index: initialize, shutdown, workspace/symbol,
  // textDocument/definition, textDocument/references.
  //
  // v0.6 did NOT implement textDocument/didChange - files are indexed via
  // `drag-lint index` ahead of time, and a re-index is sub-second per file.
  //
  // v(live-buffer) REVISITED, and the distinction the original note missed:
  // that argument is about the INDEX, but didChange is about the CURSOR. A
  // client's position describes its BUFFER, and the buffer diverges from disk
  // on the first keystroke. Without an overlay every position lookup read
  // disk, so a symbol the user could see on screen resolved to '' and hover
  // returned null -- reported 2026-08-18 for `AExceptionInfo.Assign`, typed
  // but unsaved. didChange is now accepted (full sync) and stored in
  // TLiveDocuments; SYMBOL RESOLUTION still comes from the index, so the
  // original reasoning is intact -- only the text under the caret is live.
  TLSPServer = class
    strict private
      FStore       : ISymbolStore        ; { v0.40.3: FStores[0]; kept for legacy single-store callers }
      FStores      : TArray<ISymbolStore>; { v0.40.3: every --db opened, queried + merged across all }
      /// <summary>The path each FStores entry was opened from, same order and
      /// length.</summary>
      /// <remarks>Kept only so caller queries can tell a platform LIBRARY index
      /// from a project one -- scanning the library by name is what made
      /// find-callers take ~20 s, and callers of project code are not in it.
      /// ISymbolStore does not expose its own path, and widening that interface
      /// for one caller-scoping rule would be the larger change.</remarks>
      FStorePaths  : TArray<string>      ;
      FStdIn       : THandleStream       ;
      FLinter      : TLinter             ;
      FInitialized : Boolean             ;
      FShuttingDown: Boolean             ;
      /// <returns><!-- drag-lint:auto -->Observed: nil; TJSONObject(Parsed).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: Char, Copy, StrToIntDef, TJSONObject, Trim
      /// Complexity: 14 (cyclomatic, outer body), 64 lines (full implementation)
      /// Reads: FStdIn
      /// Pure
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Destroy"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.EnsureLinter"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileToUri"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ReadMessage: TJSONObject  ;
      /// <param name="AObj"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Server.TLSPServer.HandleCompletion (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleDefinition (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleHover (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleInitialize (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleReferences (DRagLint.LSP.Server.pas) (+5 more)
      /// Calls: AnsiString, GetStdHandle, IntToStr, Move, WriteFile
      /// Pure
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Destroy"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.EnsureLinter"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileToUri"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SendMessage        (const AObj: TJSONObject);
      /// <summary><!-- drag-lint:auto -->SendRawNotification sends a notification (no id)
      /// with Content-Length framing. Identical to SendMessage but semantically distinct
      /// -- used for server-pushed notifications such as textDocument/publishDiagnostics.</summary>
      /// <param name="AObj"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Server.TLSPServer.HandleDidOpenOrSave (DRagLint.LSP.Server.pas)
      /// Calls: DRagLint.LSP.Server.TLSPServer.SendMessage
      /// Pure
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendMessage"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Destroy"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.EnsureLinter"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SendRawNotification(const AObj: TJSONObject);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="ACode"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="AMessage"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Server.TLSPServer.Run (DRagLint.LSP.Server.pas)
      /// Calls: DRagLint.LSP.Server.TLSPServer.SendMessage
      /// Pure
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendMessage"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Destroy"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.EnsureLinter"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SendError(const AId: TJSONValue; ACode: Integer; const AMessage: string);
      /// <param name="AUri"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto type -->string</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Server.TLSPServer.HandleCompletion (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleDefinition (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleDidOpenOrSave (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleHover (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleReferences (DRagLint.LSP.Server.pas) (+1 more)
      /// Calls: Copy, StringReplace
      /// Pure
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Destroy"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.EnsureLinter"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileToUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.HandleCompletion"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function FileFromUri(const AUri : string): string;
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto type -->string</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Server.TLSPServer.LocationFromRef/2 (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.LocationFromSymbol/1 (DRagLint.LSP.Server.pas)
      /// Calls: Copy, StringReplace
      /// Pure
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Destroy"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.EnsureLinter"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.HandleCompletion"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function FileToUri  (const APath: string): string;
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Server.TLSPServer.Run (DRagLint.LSP.Server.pas)
      /// Calls: DRagLint.LSP.Server.TLSPServer.SendMessage
      /// Writes: FInitialized
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendMessage"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Destroy"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.EnsureLinter"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleInitialize(const AId: TJSONValue; const AParams: TJSONObject);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Server.TLSPServer.Run (DRagLint.LSP.Server.pas)
      /// Calls: DRagLint.LSP.Server.TLSPServer.SendMessage
      /// Writes: FShuttingDown
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendMessage"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Destroy"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.EnsureLinter"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleShutdown(const AId: TJSONValue);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Server.TLSPServer.Run (DRagLint.LSP.Server.pas)
      /// Calls: DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsFuzzy, DRagLint.LSP.Server.TLSPServer.LocationFromSymbol/2, DRagLint.LSP.Server.TLSPServer.SendMessage
      /// Complexity: 22 (cyclomatic, outer body), 75 lines (full implementation)
      /// Reads: FStores
      /// Pure
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsFuzzy"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.LocationFromSymbol"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendMessage"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleWorkspaceSymbol(const AId: TJSONValue; const AParams: TJSONObject);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Server.TLSPServer.Run (DRagLint.LSP.Server.pas)
      /// Calls: DRagLint.LSP.Server.TLSPServer.FileFromUri, DRagLint.LSP.Server.TLSPServer.IdentifierAtPosition, DRagLint.LSP.Server.TLSPServer.LocationFromSymbol/2, DRagLint.LSP.Server.TLSPServer.SendMessage, StrToIntDef
      /// Reads: FStores
      /// Pure
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.IdentifierAtPosition"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.LocationFromSymbol"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendMessage"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleDefinition     (const AId: TJSONValue; const AParams: TJSONObject);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Server.TLSPServer.Run (DRagLint.LSP.Server.pas)
      /// Calls: DRagLint.LSP.Server.TLSPServer.FileFromUri, DRagLint.LSP.Server.TLSPServer.IdentifierAtPosition, DRagLint.LSP.Server.TLSPServer.LocationFromRef/2, DRagLint.LSP.Server.TLSPServer.LocationFromSymbol/2, DRagLint.LSP.Server.TLSPServer.SendMessage, StrToIntDef, TJSONBool
      /// Complexity: 11 (cyclomatic, outer body), 70 lines (full implementation)
      /// Reads: FStores
      /// Pure
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.IdentifierAtPosition"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.LocationFromRef"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.LocationFromSymbol"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendMessage"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleReferences     (const AId: TJSONValue; const AParams: TJSONObject);
      /// <summary><!-- drag-lint:auto -->v0.46: compiler intrinsics that are NOT real
      /// indexed symbols. Hovering one (e.g. `Assigned(X)`) otherwise matched a random
      /// library symbol of the same name (FMX.Graphics.TCanvasSaveState.Assigned, a
      /// property) because the project DB has no such symbol and the search fell through
      /// to the library DB.</summary>
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto -->The TABLE MOVED to DRagLint.Core.Model (IntrinsicSignature /
      /// IsCompilerIntrinsic) when the documentation facts builder needed the same list to keep
      /// intrinsics out of its "Calls:" lines. Two copies of one list is a drift channel; there is
      /// now one, and this unit reads it through its existing DRagLint.Core.Model dependency.
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Server.TLSPServer.Run (DRagLint.LSP.Server.pas)
      /// Calls: Copy, DRagLint.Core.Model.IntrinsicSignature, DRagLint.Core.Model.IsCompilerIntrinsic, DRagLint.Doc.Facts.TDocFactsBuilder.Build, DRagLint.Doc.Regions.TDocRegions.FormatPhase2FactLines, DRagLint.Hover.Returns.MineReturnExpressions, DRagLint.LSP.Server.DeclLineFor, DRagLint.LSP.Server.DedupAndPreferSource, DRagLint.LSP.Server.TLSPServer.FileFromUri, DRagLint.LSP.Server.TLSPServer.IdentifierAtPosition (+6 more)
      /// Complexity: 54 (cyclomatic, outer body), 315 lines (full implementation)
      /// Reads: FStores
      /// Touches: file system
      /// <seealso cref="DRagLint.Core.Model.IntrinsicSignature"/>
      /// <seealso cref="DRagLint.Core.Model.IsCompilerIntrinsic"/>
      /// <seealso cref="DRagLint.Doc.Facts.TDocFactsBuilder.Build"/>
      /// <seealso cref="DRagLint.Doc.Regions.TDocRegions.FormatPhase2FactLines"/>
      /// <seealso cref="DRagLint.Hover.Returns.MineReturnExpressions"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleHover          (const AId: TJSONValue; const AParams: TJSONObject);
      /// <summary>Resolves a hover position to markdown plus the indexed symbol
      /// behind it, without writing a reply.</summary>
      /// <param name="AParams">The request's params; a textDocument/position pair.</param>
      /// <param name="AOut">Receives the computation; only valid when True is
      /// returned. See THoverComputation for which fields HasSymbol gates.</param>
      /// <returns>True when the position produced hover content. False for every
      /// case that historically answered a null result -- no stores, malformed
      /// params, no identifier under the cursor, or no symbol matching it.</returns>
      /// <remarks>Extracted verbatim from HandleHover so the bundle cannot
      /// resolve a different symbol than the plain hover does for the same
      /// position. Every former `result: null` exit became `Exit(False)`; no
      /// resolution rule changed.</remarks>
      function  ComputeHover         (const AParams: TJSONObject; out AOut: THoverComputation): Boolean;
      /// <summary>Answers `draglint/hoverBundle`: hover markdown, the structured
      /// hover model, and both caller row sets, in ONE reply.</summary>
      /// <param name="AId">The request id; the reply is addressed to it.</param>
      /// <param name="AParams">A textDocument/position pair, as for hover.</param>
      /// <remarks>Exists because the IDE popup previously cost four engine round
      /// trips -- this request plus three drag-lint.exe spawns that re-opened,
      /// from cold, the very indexes this server already holds open. Opens no
      /// database of its own.</remarks>
      procedure HandleHoverBundle    (const AId: TJSONValue; const AParams: TJSONObject);
      /// <summary>Answers `draglint/callerCounts`: the caller count for EVERY
      /// routine in one file, in a single round trip.</summary>
      /// <param name="AParams">`{textDocument:{uri}}`.</param>
      /// <remarks>Replaces one engine SPAWN PER METHOD in the plugin's code-lens
      /// cache. Measured on DataCopy's uMainZeissCopy: 77 methods x 165 ms =
      /// 12.7 s of serial process starts to label one file. Every store consulted
      /// here is already open.</remarks>
      procedure HandleCallerCounts   (const AId: TJSONValue; const AParams: TJSONObject);
      /// <summary>Answers `draglint/usages`: the same payload
      /// `usages --format json` prints, built from the stores already open on
      /// this server.</summary>
      /// <param name="AId">JSON-RPC id; nil for a notification.</param>
      /// <param name="AParams">`name` (required), `width`, `depth`.</param>
      /// <remarks>Replaces a PROCESS SPAWN per user-initiated Find Usages --
      /// measured at 1,678 ms with the library index open versus 163 ms without,
      /// nearly all of it opening databases this server already holds. The reply
      /// shape is deliberately identical to the CLI verb's, and
      /// tests\autotest\run_lsp_usages_guard.ps1 compares the two so they cannot
      /// drift apart.</remarks>
      procedure HandleUsages         (const AId: TJSONValue; const AParams: TJSONObject);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Server.TLSPServer.Run (DRagLint.LSP.Server.pas)
      /// Calls: DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems, DRagLint.LSP.Server.TLSPServer.FileFromUri, DRagLint.LSP.Server.TLSPServer.SendMessage, StrToIntDef
      /// Reads: FStore
      /// Pure
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendMessage"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleCompletion     (const AId: TJSONValue; const AParams: TJSONObject);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Server.TLSPServer.Run (DRagLint.LSP.Server.pas)
      /// Calls: DRagLint.LSP.Completion.TLspCompletion.BuildSignatureHelp, DRagLint.LSP.Server.TLSPServer.FileFromUri, DRagLint.LSP.Server.TLSPServer.SendMessage, StrToIntDef
      /// Reads: FStore
      /// Pure
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildSignatureHelp"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendMessage"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleSignatureHelp  (const AId: TJSONValue; const AParams: TJSONObject);
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Server.TLSPServer.Run (DRagLint.LSP.Server.pas)
      /// Calls: DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics, DRagLint.LSP.Server.TLSPServer.FileFromUri, DRagLint.LSP.Server.TLSPServer.SendRawNotification
      /// Reads: FStore
      /// Pure
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendRawNotification"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleDidOpenOrSave(const AParams: TJSONObject);
      /// <summary>Stores the client's live buffer text (full sync) so position
      /// lookups see unsaved edits. See TLiveDocuments for why.</summary>
      procedure HandleDidChange(const AParams: TJSONObject);
      /// <summary>Drops the live buffer, making disk authoritative again.</summary>
      procedure HandleDidClose(const AParams: TJSONObject);
      /// <param name="ASym"><!-- drag-lint:auto type -->const TSymbol</param>
      /// <returns><!-- drag-lint:auto -->Observed: TJSONObject.Create.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: DRagLint.LSP.Server.TLSPServer.FileToUri
      /// Overload 1 of 2
      /// Owns returned: new (caller owns)
      /// Pure
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileToUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Destroy"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.EnsureLinter"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function LocationFromSymbol(const ASym: TSymbol   ): TJSONObject; overload;
      /// <param name="ARef"><!-- drag-lint:auto type -->const TReference</param>
      /// <returns><!-- drag-lint:auto -->Observed: LocationFromRef(ARef, FStore).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: DRagLint.LSP.Server.TLSPServer.LocationFromRef/2
      /// Overload 1 of 2
      /// Reads: FStore
      /// Pure
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.LocationFromRef"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Destroy"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.EnsureLinter"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function LocationFromRef   (const ARef: TReference): TJSONObject; overload;
      { v0.40.3: explicit-store overloads -- preferred for multi-DB queries
      so each Location URI resolves against the store that owns the row. }
      /// <summary><!-- drag-lint:auto -->v0.40.3: explicit-store overloads -- preferred
      /// for multi-DB queries so each Location URI resolves against the store that owns
      /// the row.</summary>
      /// <param name="ASym"><!-- drag-lint:auto type -->const TSymbol</param>
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <returns><!-- drag-lint:auto -->Observed: LocationFromSymbol(ASym, FStore).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Server.TLSPServer.HandleDefinition (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleReferences (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleWorkspaceSymbol (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.LocationFromSymbol/2 (DRagLint.LSP.Server.pas)
      /// Calls: DRagLint.LSP.Server.TLSPServer.LocationFromSymbol/2
      /// Overload 2 of 2
      /// Reads: FStore
      /// Recursive
      /// Pure
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Destroy"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.EnsureLinter"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileToUri"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function LocationFromSymbol(const ASym: TSymbol   ; const AStore: ISymbolStore): TJSONObject; overload;
      /// <param name="ARef"><!-- drag-lint:auto type -->const TReference</param>
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <returns><!-- drag-lint:auto -->Observed: TJSONObject.Create.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Server.TLSPServer.HandleReferences (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.LocationFromRef/1 (DRagLint.LSP.Server.pas)
      /// Calls: DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.LSP.Server.TLSPServer.FileToUri
      /// Overload 2 of 2
      /// Owns returned: new (caller owns)
      /// Pure
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileToUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Destroy"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.EnsureLinter"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function LocationFromRef   (const ARef: TReference; const AStore: ISymbolStore): TJSONObject; overload;
      // v0.7: reparse the file at APath and find the identifier text under
      // (ALine, ACol) - both 0-based (LSP convention). Returns empty string
      // if the file doesn't exist or the cursor isn't on an identifier.
      /// <summary><!-- drag-lint:auto -->v0.7: reparse the file at APath and find the
      /// identifier text under (ALine, ACol) - both 0-based (LSP convention). Returns
      /// empty string if the file doesn't exist or the cursor isn't on an identifier.</summary>
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ALine"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="ACol"><!-- drag-lint:auto type -->Integer</param>
      /// <returns><!-- drag-lint:auto type -->string</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.LSP.Server.TLSPServer.HandleDefinition (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleHover (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleReferences (DRagLint.LSP.Server.pas)
      /// Calls: DRagLint.Core.Encoding.EnsureUtf8Bytes, DRagLint.LSP.Server.ContainsPosition, DRagLint.LSP.Server.FindSmallestNamedAt, DRagLint.LSP.Server.NodeTextLocal, Integer, Move, TreeSitter.TTSParser.Create, TreeSitter.TTSParser.Parse, Trim
      /// Complexity: 17 (cyclomatic, outer body), 63 lines (full implementation)
      /// Touches: file system
      /// <seealso cref="DRagLint.Core.Encoding.EnsureUtf8Bytes"/>
      /// <seealso cref="DRagLint.LSP.Server.ContainsPosition"/>
      /// <seealso cref="DRagLint.LSP.Server.FindSmallestNamedAt"/>
      /// <seealso cref="DRagLint.LSP.Server.NodeTextLocal"/>
      /// <seealso cref="TreeSitter.TTSParser.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function IdentifierAtPosition(const APath: string; ALine, ACol: Integer): string;
      /// <returns><!-- drag-lint:auto -->Observed: FLinter.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: DRagLint.Lint.Linter.TLinter.Create
      /// Reads: FLinter   Writes: FLinter
      /// Owns returned: borrowed
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Destroy"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileToUri"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function EnsureLinter: TLinter                                                  ;
    public
      /// <param name="ADbPath"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.Run (DRagLint.CLI.pas), DRagLint.LSP.Server.TLSPServer.Create/1 (DRagLint.LSP.Server.pas)
      /// Calls: DRagLint.LSP.Server.TLSPServer.Create/1
      /// Overload 1 of 2
      /// constructor
      /// Recursive
      /// Pure
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Destroy"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.EnsureLinter"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileToUri"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(const ADbPath: string); overload;
      { v0.40.3: multi-DB constructor. Opens every path; missing paths are
      logged via stderr (LSP doesn't see them) and skipped. The first
      surviving store becomes FStore for legacy code paths. }
      /// <summary><!-- drag-lint:auto -->v0.40.3: multi-DB constructor. Opens every path;
      /// missing paths are logged via stderr (LSP doesn't see them) and skipped. The
      /// first surviving store becomes FStore for legacy code paths.</summary>
      /// <param name="ADbPaths"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: DRagLint.Core.Interfaces.ISymbolStore.Migrate, DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create, GetStdHandle, Writeln
      /// Overload 2 of 2
      /// constructor
      /// Reads: FStores   Writes: FStdIn, FLinter, FStore
      /// Touches: file system
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.Migrate"/>
      /// <seealso cref="DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Destroy"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.EnsureLinter"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(const ADbPaths: TArray<string>); overload;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Reads: FLinter, FStdIn   Writes: FStore
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.EnsureLinter"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileToUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.HandleCompletion"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      destructor Destroy; override;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: DRagLint.LSP.Server.TLSPServer.HandleCompletion, DRagLint.LSP.Server.TLSPServer.HandleDefinition, DRagLint.LSP.Server.TLSPServer.HandleDidOpenOrSave, DRagLint.LSP.Server.TLSPServer.HandleHover, DRagLint.LSP.Server.TLSPServer.HandleInitialize, DRagLint.LSP.Server.TLSPServer.HandleReferences, DRagLint.LSP.Server.TLSPServer.HandleShutdown, DRagLint.LSP.Server.TLSPServer.HandleSignatureHelp, DRagLint.LSP.Server.TLSPServer.HandleWorkspaceSymbol, DRagLint.LSP.Server.TLSPServer.SendError, TJSONObject
      /// Complexity: 19 (cyclomatic, outer body), 38 lines (full implementation)
      /// Reads: FShuttingDown
      /// Pure
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.HandleCompletion"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.HandleDefinition"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.HandleDidOpenOrSave"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.HandleHover"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.HandleInitialize"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure Run;
  end;

implementation

constructor TLSPServer.Create(const ADbPath: string);
begin
  Create(TArray<string>.Create(ADbPath));
end;

constructor TLSPServer.Create(const ADbPaths: TArray<string>);
var
  I   : Integer     ;
  Path: string      ;
  S   : ISymbolStore;
begin
  inherited Create;
  FStdIn:= THandleStream.Create(GetStdHandle(STD_INPUT_HANDLE));
  FLinter:= nil;
  SetLength(FStores    , 0);
  SetLength(FStorePaths, 0);
  for I:= 0 to High(ADbPaths) do
  begin
    Path:= ADbPaths[I];
    if Path = '' then Continue;
    if not TFile.Exists(Path) then
    begin
      { Server protocol doesn't have a startup-message channel; write to
        stderr so the spawning plugin / shell can surface it. The plugin's
        DebugLog will capture this if redirected. }
      Writeln(ErrOutput, 'drag-lint LSP: db not found, skipping: ', Path);
      Continue;
    end;
    try
      S:= TSQLiteSymbolStore.Create(Path);
      S.Migrate;
      SetLength(FStores, Length(FStores) + 1);
      FStores[High(FStores)]:= S;
      { Kept in lockstep with FStores -- appended only on the success path, so
        a db that failed to open never shifts the two out of alignment. }
      SetLength(FStorePaths, Length(FStores));
      FStorePaths[High(FStorePaths)]:= Path;
    except
      on E: Exception do Writeln(ErrOutput, 'drag-lint LSP: could not open ', Path, ': ', E.Message);
    end;
  end; // for
  if Length(FStores) > 0 then FStore:= FStores[0];
end; // constructor

destructor TLSPServer.Destroy;
begin
  FLinter.Free;
  FStdIn.Free;
  FStore:= nil;
  inherited;
end;

function TLSPServer.EnsureLinter: TLinter;
begin
  if FLinter = nil then FLinter:= TLinter.Create('');
  Result:= FLinter;
end;

function TLSPServer.ReadMessage: TJSONObject;
var
  Headers         : TStringList   ;
  Line            : TStringBuilder;
  Ch              : Byte          ;
  Header          : string        ;
  ContentLengthStr: string        ;
  ContentLength   : Integer       ;
  Body            : TBytes        ;
  ReadBytes       : Integer       ;
  Parsed          : TJSONValue    ;
  I               : Integer       ;
begin
  Result:= nil;
  Headers:= TStringList   .Create;
  Line   := TStringBuilder.Create;
  try
    // Read CRLF-terminated header lines until empty line.
    while True do
    begin
      if FStdIn.Read(Ch, 1) <> 1 then Exit;
      if Ch = 13 then // CR - expect LF next
      begin
        if FStdIn.Read(Ch, 1) <> 1 then Exit;
        if Ch = 10 then
        begin
          if Line.Length = 0 then Break; // empty line - end of headers
          Headers.Add(Line.ToString);
          Line.Clear;
        end;
      end
      else if Ch = 10 then
      begin
        if Line.Length = 0 then Break;
        Headers.Add(Line.ToString);
        Line.Clear;
      end
      else Line.Append(Char(Ch));
    end; // while
    ContentLength:= 0;
    for Header in Headers do
    begin
      if Header.StartsWith('Content-Length:', True) then
      begin
        ContentLengthStr:= Trim(Copy(Header, Length('Content-Length:') + 1, MaxInt));
        ContentLength:= StrToIntDef(ContentLengthStr, 0);
      end;
    end;
    if ContentLength <= 0 then Exit;
    SetLength(Body, ContentLength);
    ReadBytes:= 0;
    while ReadBytes < ContentLength do
    begin
      I:= FStdIn.Read(Body[ReadBytes], ContentLength - ReadBytes);
      if I <= 0 then Exit;
      Inc(ReadBytes, I);
    end;
    Parsed:= TJSONObject.ParseJSONValue(Body, 0);
    if Parsed is TJSONObject then Result:= TJSONObject(Parsed)
    else Parsed.Free;
  finally
    Line.Free;
    Headers.Free;
  end; // try
end; // function

procedure TLSPServer.SendMessage(const AObj: TJSONObject);
var
  Body        : string    ;
  BodyBytes   : TBytes    ;
  Header      : AnsiString;
  HeaderBytes : TBytes    ;
  StdOutHandle: THandle   ;
  Written     : DWORD     ;
begin
  Body:= AObj.ToJSON;
  BodyBytes:= TEncoding.UTF8.GetBytes(Body);
  Header:= AnsiString('Content-Length: ' + IntToStr(Length(BodyBytes)) + #13#10#13#10);
  SetLength(HeaderBytes, Length(Header));
  if Length(Header) > 0 then Move(Header[1], HeaderBytes[0], Length(Header));
  StdOutHandle:= GetStdHandle(STD_OUTPUT_HANDLE);
  if Length(HeaderBytes) > 0 then WriteFile(StdOutHandle, HeaderBytes[0], Length(HeaderBytes), Written, nil);
  if Length(BodyBytes  ) > 0 then WriteFile(StdOutHandle, BodyBytes  [0], Length(BodyBytes  ), Written, nil);
end;

// SendRawNotification sends a notification (no id) with Content-Length framing.
// Identical to SendMessage but semantically distinct -- used for server-pushed
// notifications such as textDocument/publishDiagnostics.
procedure TLSPServer.SendRawNotification(const AObj: TJSONObject);
begin
  SendMessage(AObj);
end;

procedure TLSPServer.SendError(const AId: TJSONValue; ACode: Integer; const AMessage: string);
var
  Obj: TJSONObject;
  Err: TJSONObject;
begin
  Obj:= TJSONObject.Create;
  try
    Obj.AddPair('jsonrpc', '2.0');
    if AId <> nil then Obj.AddPair('id', AId.Clone as TJSONValue)
    else Obj.AddPair('id', TJSONNull.Create);
    Err:= TJSONObject.Create;
    Err.AddPair('code', TJSONNumber.Create(ACode));
    Err.AddPair('message', AMessage);
    Obj.AddPair('error'  , Err     );
    SendMessage(Obj);
  finally
    Obj.Free;
  end;
end; // procedure

function TLSPServer.FileFromUri(const AUri: string): string;
var
  Decoded: string;
begin
  Result:= AUri;
  if Result.StartsWith('file:///') then Result:= Copy(Result, 9, MaxInt);
  Decoded:= TNetEncoding.URL.Decode(Result);
  Result:= StringReplace(Decoded, '/', '\', [rfReplaceAll]);
end;

function TLSPServer.FileToUri(const APath: string): string;
var
  Normalised: string;
  Encoded   : string;
begin
  Normalised:= StringReplace(APath, '\', '/', [rfReplaceAll]);
  Encoded:= TNetEncoding.URL.EncodePath(Normalised);
  // EncodePath preserves the leading slash if it exists, so we'd end up
  // with file://// for absolute Windows paths. Strip it before prepending.
  if Encoded.StartsWith('/') then Encoded:= Copy(Encoded, 2, MaxInt);
  Result:= 'file:///' + Encoded;
end;

function TLSPServer.LocationFromSymbol(const ASym: TSymbol): TJSONObject;
begin
  { Legacy single-store path: defer to the explicit-store overload using
    FStore (= FStores[0]). New multi-DB code paths should pass the
    originating store explicitly. }
  Result:= LocationFromSymbol(ASym, FStore);
end;

function TLSPServer.LocationFromRef(const ARef: TReference): TJSONObject;
begin
  Result:= LocationFromRef(ARef, FStore);
end;

function TLSPServer.LocationFromSymbol(const ASym: TSymbol; const AStore: ISymbolStore): TJSONObject;
var
  Range : TJSONObject;
  Start : TJSONObject;
  EndPos: TJSONObject;
  Path  : string     ;
begin
  Result:= TJSONObject.Create;
  if AStore <> nil then Path:= AStore.GetFilePath(ASym.FileId)
  else Path:= '';
  Result.AddPair('uri', FileToUri(Path));
  Range:= TJSONObject.Create;
  Start:= TJSONObject.Create;
  // LSP positions are 0-based; our DB stores 1-based.
  Start.AddPair('line'     , TJSONNumber.Create(ASym.StartLine - 1));
  Start.AddPair('character', TJSONNumber.Create(ASym.StartCol  - 1));
  EndPos:= TJSONObject.Create;
  EndPos.AddPair('line'     , TJSONNumber.Create(ASym.EndLine - 1));
  EndPos.AddPair('character', TJSONNumber.Create(ASym.EndCol  - 1));
  Range .AddPair('start', Start );
  Range .AddPair('end'  , EndPos);
  Result.AddPair('range', Range );
end; // function

function TLSPServer.LocationFromRef(const ARef: TReference; const AStore: ISymbolStore): TJSONObject;
var
  Range : TJSONObject;
  Start : TJSONObject;
  EndPos: TJSONObject;
  Path  : string     ;
begin
  Result:= TJSONObject.Create;
  if AStore <> nil then Path:= AStore.GetFilePath(ARef.FileId)
  else Path:= '';
  Result.AddPair('uri', FileToUri(Path));
  Range:= TJSONObject.Create;
  Start:= TJSONObject.Create;
  Start.AddPair('line'     , TJSONNumber.Create(ARef.StartLine - 1));
  Start.AddPair('character', TJSONNumber.Create(ARef.StartCol  - 1));
  EndPos:= TJSONObject.Create;
  EndPos.AddPair('line'     , TJSONNumber.Create(ARef.EndLine - 1));
  EndPos.AddPair('character', TJSONNumber.Create(ARef.EndCol  - 1));
  Range .AddPair('start', Start );
  Range .AddPair('end'  , EndPos);
  Result.AddPair('range', Range );
end; // function

procedure TLSPServer.HandleInitialize(const AId: TJSONValue; const AParams: TJSONObject);
var
  Reply                 : TJSONObject;
  ResObj                : TJSONObject;
  Caps                  : TJSONObject;
  Info                  : TJSONObject;
  CompProvider          : TJSONObject;
  SigProvider           : TJSONObject;
  TriggerCharsCompletion: TJSONArray ;
  TriggerCharsSig       : TJSONArray ;
begin
  Reply:= TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);
    ResObj:= TJSONObject.Create;
    Caps  := TJSONObject.Create;
    Caps.AddPair('definitionProvider'     , TJSONBool.Create(True));
    Caps.AddPair('referencesProvider'     , TJSONBool.Create(True));
    Caps.AddPair('workspaceSymbolProvider', TJSONBool.Create(True));
    Caps.AddPair('hoverProvider'          , TJSONBool.Create(True));
    { v(live-buffer): TextDocumentSyncKind.Full = 1. Advertising this is not
      cosmetic -- a conforming client sends NOTHING until the server asks, so
      without this pair the didChange handler below can never fire and every
      position lookup silently stays on disk. Full rather than Incremental (2)
      because a Delphi source unit is small enough that resending it costs less
      than the range arithmetic costs in correctness risk. }
    Caps.AddPair('textDocumentSync'       , TJSONNumber.Create(1) );
    // v0.20: completion provider
    CompProvider          := TJSONObject.Create;
    TriggerCharsCompletion:= TJSONArray .Create;
    TriggerCharsCompletion.AddElement(TJSONString.Create('.'));
    TriggerCharsCompletion.AddElement(TJSONString.Create('('));
    TriggerCharsCompletion.AddElement(TJSONString.Create(','));
    CompProvider.AddPair('triggerCharacters', TriggerCharsCompletion);
    CompProvider.AddPair('resolveProvider', TJSONBool.Create(False));
    Caps.AddPair('completionProvider', CompProvider);
    // v0.20: signatureHelp provider
    SigProvider    := TJSONObject.Create;
    TriggerCharsSig:= TJSONArray .Create;
    TriggerCharsSig.AddElement(TJSONString.Create('('));
    TriggerCharsSig.AddElement(TJSONString.Create(','));
    SigProvider.AddPair('triggerCharacters'    , TriggerCharsSig);
    Caps       .AddPair('signatureHelpProvider', SigProvider    );
    ResObj     .AddPair('capabilities'         , Caps           );
    Info:= TJSONObject.Create;
    Info  .AddPair('name'      , 'drag-lint LSP');
    { NOT a literal: editors show this in their LSP logs, and a hardcoded copy
      had already drifted eleven releases behind the CLI banner. }
    Info  .AddPair('version'   , DRAGLINT_VERSION);
    ResObj.AddPair('serverInfo', Info           );
    Reply .AddPair('result'    , ResObj         );
    SendMessage(Reply);
    FInitialized:= True;
  finally
    Reply.Free;
  end; // try
end; // procedure

function ContainsPosition(const ANode: TTSNode; ALine, ACol: Integer): Boolean;
var
  Sp: TTSPoint;
  Ep: TTSPoint;
begin
  Sp:= ANode.StartPoint;
  Ep:= ANode.EndPoint;
  // Tree-sitter rows/cols are 0-based, matching LSP.
  if (ALine < Integer(Sp.row)) or (ALine > Integer(Ep.row)) then Exit(False);
  if (ALine = Integer(Sp.row)) and (ACol < Integer(Sp.column)) then Exit(False);
  // EndPoint is exclusive - cursor right at the end is past the token.
  if (ALine = Integer(Ep.row)) and (ACol >= Integer(Ep.column)) then Exit(False);
  Result:= True;
end;

function FindSmallestNamedAt(const ANode: TTSNode; ALine, ACol: Integer): TTSNode;
var
  I    : Integer;
  Child: TTSNode;
  Hit  : TTSNode;
begin
  Result:= Default(TTSNode);
  if ANode.IsNull then Exit;
  if not ContainsPosition(ANode, ALine, ACol) then Exit;
  for I:= 0 to ANode.NamedChildCount - 1 do
  begin
    Child:= ANode.NamedChild(I);
    if ContainsPosition(Child, ALine, ACol) then
    begin
      Hit:= FindSmallestNamedAt(Child, ALine, ACol);
      if not Hit.IsNull then Exit(Hit);
    end;
  end;
  Result:= ANode;
end; // function

function NodeTextLocal(const ANode: TTSNode; const ASource: TBytes): string;
var
  StartIdx: Integer;
  EndIdx  : Integer;
  Len     : Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  StartIdx:= Integer(ANode.StartByte);
  EndIdx  := Integer(ANode.EndByte  );
  Len:= EndIdx - StartIdx;
  if (Len <= 0) or (StartIdx < 0) or (EndIdx > Length(ASource)) then Exit;
  Result:= TEncoding.UTF8.GetString(ASource, StartIdx, Len);
end;

function TLSPServer.IdentifierAtPosition(const APath: string; ALine, ACol: Integer): string;
var
  Parser: TTSParser;
  Tree  : TTSTree  ;
  Source: TBytes   ;
  Node  : TTSNode  ;
begin
  Result:= '';
  if not TLiveDocuments.Readable(APath) then Exit;
  // v0.86 (Task 3): transcode ANSI/UTF-16 sources to valid UTF-8 before the
  // parse/slice pipeline (both assume UTF-8); a valid CP1252 file (SOFTWID
  // class) errored here otherwise.
  // v(live-buffer): overlay bytes are produced as UTF-8 already, so they skip
  // the transcode -- running EnsureUtf8Bytes over them would re-sniff a BOM
  // that the editor's buffer does not carry.
  var FromOverlay: Boolean;
  Source:= TLiveDocuments.ReadBytes(APath, FromOverlay);
  if not FromOverlay then Source:= EnsureUtf8Bytes(Source);
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes var Remaining: Integer; begin Remaining:= Length(Source)
        - Integer(AByteIndex); if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end; SetLength(Result, Remaining); Move(Source[AByteIndex], Result[0],
          Remaining); ABytesRead:= Remaining; end, TTSInputEncoding.TSInputEncodingUTF8);

    Node:= FindSmallestNamedAt(Tree.RootNode, ALine, ACol);
    if Node.IsNull then Exit;
    // Prefer an identifier-shaped node. If the smallest enclosing is e.g.
    // a `genericDot` (qualified name like Foo.Bar), drill into its rhs.
    if Node.NodeType = 'genericDot' then
    begin
      var Rhs:= Node.ChildByField('rhs');
      if (not Rhs.IsNull) and ContainsPosition(Rhs, ALine, ACol) then Node:= Rhs;
    end
    else if Node.NodeType = 'exprDot' then
    begin
      var Rhs:= Node.ChildByField('rhs');
      if (not Rhs.IsNull) and ContainsPosition(Rhs, ALine, ACol) then Node:= Rhs;
    end;
    if (Node.NodeType <> 'identifier') and (Node.NodeType <> 'moduleName') then
    begin
      // Try to find an identifier descendant covering the cursor.
      var ChildIt:= Node;
      while (ChildIt.NamedChildCount > 0) and (ChildIt.NodeType <> 'identifier') do
      begin
        var Found:= False;
        for var I:= 0 to ChildIt.NamedChildCount - 1 do
        begin
          var C:= ChildIt.NamedChild(I);
          if ContainsPosition(C, ALine, ACol) then
          begin
            ChildIt:= C;
            Found  := True;
            Break;
          end;
        end;
        if not Found then Break;
      end;
      Node:= ChildIt;
    end; // if
    Result:= Trim(NodeTextLocal(Node, Source));
  finally
    Tree.Free;
    Parser.Free;
  end; // try
end; // function

procedure TLSPServer.HandleShutdown(const AId: TJSONValue);
var
  Reply: TJSONObject;
begin
  Reply:= TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);
    Reply.AddPair('result', TJSONNull.Create);
    SendMessage(Reply);
    FShuttingDown:= True;
  finally
    Reply.Free;
  end;
end;

procedure TLSPServer.HandleWorkspaceSymbol(const AId: TJSONValue; const AParams: TJSONObject);
var
  Reply   : TJSONObject    ;
  Arr     : TJSONArray     ;
  QueryStr: string         ;
  Symbols : TArray<TSymbol>;
  Sym     : TSymbol        ;
  SymObj  : TJSONObject    ;
  Loc     : TJSONObject    ;
  StIdx   : Integer        ;
  StCur   : ISymbolStore   ;
begin
  Reply:= TJSONObject.Create;
  Arr  := TJSONArray .Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);
    if Length(FStores) = 0 then
    begin
      Reply.AddPair('result', Arr);
      SendMessage(Reply);
      Exit;
    end;
    QueryStr:= '';
    if (AParams <> nil) and (AParams.GetValue('query') <> nil) then QueryStr:= AParams.GetValue('query').Value;
    if QueryStr = '' then
    begin
      Reply.AddPair('result', Arr);
      SendMessage(Reply);
      Exit;
    end;

    { v0.40.3: iterate every store, merge results. For each store, prefer
      exact-name matches; fall back to fuzzy when exact returns nothing.
      Per-store fallback is intentional -- if project DB has an exact hit
      we don't want library DB's fuzzy noise diluting the result. }
    for StIdx:= 0 to High(FStores) do
    begin
      StCur:= FStores[StIdx];
      Symbols:= StCur.FindSymbolsByExactName(QueryStr);
      if Length(Symbols) = 0 then Symbols:= StCur.FindSymbolsFuzzy(QueryStr, 50);
      for Sym in Symbols do
      begin
        SymObj:= TJSONObject.Create;
        SymObj.AddPair('name', Sym.Name);
        var Kind: Integer;
        case Sym.Kind of
          skClass     : Kind:= 5;
          skInterface : Kind:= 11;
          skRecord    : Kind:= 23;
          skEnum      : Kind:= 10;
          skEnumValue : Kind:= 22;
          skMethod, skConstructor, skDestructor: Kind:= 6 ;
          skProcedure, skFunction              : Kind:= 12;
          skProperty  : Kind:= 7;
          skField     : Kind:= 8;
          skVarDecl   : Kind:= 13;
          skConstDecl : Kind:= 14;
          skUnit, skPackage, skProgram         : Kind:= 2 ;
          skForm      : Kind:= 5;
          skComponent : Kind:= 8;
          else Kind:= 1;
        end; // case
        SymObj.AddPair('kind', TJSONNumber.Create(Kind));
        SymObj.AddPair('containerName', Sym.QualifiedName);
        Loc:= LocationFromSymbol(Sym, StCur);
        SymObj.AddPair('location', Loc);
        Arr.AddElement(SymObj);
      end; // for
    end; // for
    Reply.AddPair('result', Arr);
    SendMessage(Reply);
  finally
    Reply.Free;
  end; // try
end; // procedure

procedure TLSPServer.HandleDefinition(const AId: TJSONValue; const AParams: TJSONObject);
var
  Reply   : TJSONObject    ;
  Arr     : TJSONArray     ;
  TextDoc : TJSONObject    ;
  Position: TJSONObject    ;
  Uri     : string         ;
  Path    : string         ;
  Ident   : string         ;
  Line    : Integer        ;
  Col     : Integer        ;
  Symbols : TArray<TSymbol>;
  Sym     : TSymbol        ;
begin
  Reply:= TJSONObject.Create;
  Arr  := TJSONArray .Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);
    if (Length(FStores) = 0) or (AParams = nil) then
    begin
      Reply.AddPair('result', Arr);
      SendMessage(Reply);
      Exit;
    end;
    TextDoc := AParams.GetValue('textDocument') as TJSONObject;
    Position:= AParams.GetValue('position'    ) as TJSONObject;
    if (TextDoc = nil) or (Position = nil) then
    begin
      Reply.AddPair('result', Arr);
      SendMessage(Reply);
      Exit;
    end;
    Uri:= TextDoc.GetValue('uri').Value;
    Path:= FileFromUri(Uri);
    Line:= StrToIntDef(Position.GetValue('line'     ).Value, 0);
    Col := StrToIntDef(Position.GetValue('character').Value, 0);

    Ident:= IdentifierAtPosition(Path, Line, Col);
    if Ident <> '' then
    begin
      { v0.40.3: iterate every store, accumulate definitions. }
      for var StIdx:= 0 to High(FStores) do
      begin
        Symbols:= FStores[StIdx].FindSymbolsByExactName(Ident);
        for Sym in Symbols do Arr.AddElement(LocationFromSymbol(Sym, FStores[StIdx]));
      end;
    end;
    Reply.AddPair('result', Arr);
    SendMessage(Reply);
  finally
    Reply.Free;
  end; // try
end; // procedure

procedure TLSPServer.HandleReferences(const AId: TJSONValue; const AParams: TJSONObject);
var
  Reply      : TJSONObject       ;
  Arr        : TJSONArray        ;
  TextDoc    : TJSONObject       ;
  Position   : TJSONObject       ;
  Context    : TJSONObject       ;
  Uri        : string            ;
  Path       : string            ;
  Ident      : string            ;
  Line       : Integer           ;
  Col        : Integer           ;
  Refs       : TArray<TReference>;
  Symbols    : TArray<TSymbol>   ;
  IncludeDecl: Boolean           ;
  R          : TReference        ;
  Sym        : TSymbol           ;
begin
  Reply:= TJSONObject.Create;
  Arr  := TJSONArray .Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);
    if (Length(FStores) = 0) or (AParams = nil) then
    begin
      Reply.AddPair('result', Arr);
      SendMessage(Reply);
      Exit;
    end;
    TextDoc := AParams.GetValue('textDocument') as TJSONObject;
    Position:= AParams.GetValue('position'    ) as TJSONObject;
    if (TextDoc = nil) or (Position = nil) then
    begin
      Reply.AddPair('result', Arr);
      SendMessage(Reply);
      Exit;
    end;
    Uri:= TextDoc.GetValue('uri').Value;
    Path:= FileFromUri(Uri);
    Line:= StrToIntDef(Position.GetValue('line'     ).Value, 0);
    Col := StrToIntDef(Position.GetValue('character').Value, 0);

    IncludeDecl:= True;
    Context:= AParams.GetValue('context') as TJSONObject;
    if Context <> nil then
    begin
      var IncDeclVal:= Context.GetValue('includeDeclaration');
      if IncDeclVal is TJSONBool then IncludeDecl:= TJSONBool(IncDeclVal).AsBoolean;
    end;

    Ident:= IdentifierAtPosition(Path, Line, Col);
    if Ident <> '' then
    begin
      { v0.40.3: iterate every store for both callers and declarations. }
      for var StIdx:= 0 to High(FStores) do
      begin
        Refs:= FStores[StIdx].FindCallersByName(Ident);
        for R in Refs do Arr.AddElement(LocationFromRef(R, FStores[StIdx]));
        if IncludeDecl then
        begin
          Symbols:= FStores[StIdx].FindSymbolsByExactName(Ident);
          for Sym in Symbols do Arr.AddElement(LocationFromSymbol(Sym, FStores[StIdx]));
        end;
      end;
    end;
    Reply.AddPair('result', Arr);
    SendMessage(Reply);
  finally
    Reply.Free;
  end; // try
end; // procedure

// v0.42: render a symbol as a Code-Insight-style declaration line, e.g.
//   function TShape.Area: Double          (proc-likes: sig has params+return)
//   constructor Create(const AName: string)
//   property Name: string                 (prop/field/const/var: sig is type)
//   class TShape                          (containers: no signature)
// Signature already carries the leading '(' or ': ' for proc-likes, so we
// concatenate directly; for type-valued kinds we insert ': ' before the type.
function DeclLineFor(const ASym: TSymbol): string;
var
  Keyword: string;
  Sig    : string;
begin
  Sig:= ASym.Signature;
  case ASym.Kind of
    skFunction   : Keyword:= 'function';
    skProcedure  : Keyword:= 'procedure';
    skConstructor: Keyword:= 'constructor';
    skDestructor : Keyword:= 'destructor';
    skMethod     : { class/interface methods: tell function from procedure by whether the
        signature carries a return type. }
      if (Sig <> '') and ((Sig[1] = ':') or (Pos('): ', Sig) > 0)) then Keyword:= 'function'
    else Keyword:= 'procedure';
    skProperty : Keyword:= 'property';
    skField    : Keyword:= 'var';
    skVarDecl  : Keyword:= 'var';
    skConstDecl: Keyword:= 'const';
    else Keyword:= ASym.Kind.ToText;
  end; // case

  case ASym.Kind of
    skFunction, skProcedure, skConstructor, skDestructor, skMethod:
      // Sig is '(args): Ret' or ': Ret' or '(args)' or '' -- concat directly.
      Result:= Format('%s %s%s', [Keyword, ASym.Name, Sig]);
    skProperty, skField, skVarDecl, skConstDecl: if Sig <> '' then Result:= Format('%s %s: %s', [Keyword, ASym.Name, Sig])
    else Result:= Format('%s %s', [Keyword, ASym.Name]);
    else Result:= Format('%s %s', [Keyword, ASym.Name]);
  end;
end; // function

// v0.46 hover polish. Two passes over the candidate symbols:
//   1. De-duplicate by (QualifiedName, FileId, StartLine). A doubled index (the
//      pre-0.46 accumulate bug) otherwise renders a phantom "N overloads".
//   2. If any source declaration (not skForm/skComponent) is present, drop the
//      DFM component/form entries: a published field in the .pas and its
//      generated DFM object describe the same thing, and the source declaration
//      carries the real declared type (what the IDE shows on hover).
// The candidate list is small (capped at 50 upstream), so a linear dedup is fine.
function DedupAndPreferSource(const ASyms: TArray<TSymbol>): TArray<TSymbol>;
  function IsSourceKind(AKind: TSymbolKind): Boolean                        ;
  begin
    Result:= not (AKind in [skForm, skComponent]);
  end;
var
  I        : Integer        ;
  J        : Integer        ;
  Dup      : Boolean        ;
  HasSource: Boolean        ;
  Deduped  : TArray<TSymbol>;
begin
  SetLength(Deduped, 0);
  HasSource:= False;
  for I:= 0 to High(ASyms) do
  begin
    Dup:= False;
    for J:= 0 to High(Deduped) do
      if (Deduped[J].QualifiedName = ASyms[I].QualifiedName) and (Deduped[J].FileId = ASyms[I].FileId) and (Deduped[J].StartLine = ASyms[I].StartLine) then
      begin
        Dup:= True;
        Break;
      end;
    if Dup then Continue;
    SetLength(Deduped, Length(Deduped) + 1);
    Deduped[High(Deduped)]:= ASyms[I];
    if IsSourceKind(ASyms[I].Kind) then HasSource:= True;
  end; // for

  if not HasSource then Exit(Deduped);

  // A source declaration is present -> drop the generated DFM components.
  SetLength(Result, 0);
  for I:= 0 to High(Deduped) do
    if IsSourceKind(Deduped[I].Kind) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)]:= Deduped[I];
    end;
end; // begin

// v0.46: compiler intrinsics that are NOT real indexed symbols. Hovering one
// (e.g. `Assigned(X)`) otherwise matched a random library symbol of the same
// name (FMX.Graphics.TCanvasSaveState.Assigned, a property) because the project
// DB has no such symbol and the search fell through to the library DB.
//
// The TABLE MOVED to DRagLint.Core.Model (IntrinsicSignature /
// IsCompilerIntrinsic) when the documentation facts builder needed the same
// list to keep intrinsics out of its "Calls:" lines. Two copies of one list is
// a drift channel; there is now one, and this unit reads it through its
// existing DRagLint.Core.Model dependency.

function QualifiedKindText(const ASym: TSymbol): string;
{ The symbol's kind, prefixed by the qualifiers that decide whether it can be
  used at a given call site -- visibility, and for properties the accessor
  shape. 'field' -> 'protected field'; 'property' -> 'read-only property'.

  Deliberately silent for public/published and for read/write: those constrain
  nothing, so a marker there would be noise that devalues the marker elsewhere.
  Both facts are already stored (Modifiers, PropAccess), so this costs no
  extractor change and no DRAGLINT_EXTRACTOR_VERSION bump. }
var
  Vis: string;
  Acc: string;
begin
  Result:= ASym.Kind.ToText;

  if ASym.Kind = skProperty then
  begin
    Acc:= LowerCase(Trim(ASym.PropAccess));
    if      Acc = 'ro' then Result:= 'read-only '  + Result
    else if Acc = 'wo' then Result:= 'write-only ' + Result;
    { 'rw' and '' (a bare redeclaration inheriting its accessors) say nothing. }
  end;

  Vis:= LowerCase(Trim(ASym.Modifiers));
  if      Pos('private'  , Vis) > 0 then Result:= 'private '   + Result
  else if Pos('protected', Vis) > 0 then Result:= 'protected ' + Result;
end;

function TLSPServer.ComputeHover(const AParams: TJSONObject; out AOut: THoverComputation): Boolean;
var
  TextDoc : TJSONObject    ;
  Position: TJSONObject    ;
  Uri     : string         ;
  Path    : string         ;
  Ident   : string         ;
  MdValue : string         ;
  Line    : Integer        ;
  Col     : Integer        ;
  Symbols : TArray<TSymbol>;
  Sym     : TSymbol        ;
  Doc     : TParsedDoc     ;
  Sb      : TStringBuilder ;
  OwnerFloorType: TSymbol  ;   // when set, the resolver found the LHS type but not the member -> render an honest inherited-member note
  HaveOwnerFloor: Boolean  ;
begin
  Result:= False;
  AOut  := Default(THoverComputation);
  { Zeroed together: OwnerFloorType is only ever READ under HaveOwnerFloor, but
    nothing in the type system says so, and an uninitialised TSymbol read on a
    path someone adds later would carry a garbage Id straight into a store
    lookup. Cheap to make that impossible. }
  HaveOwnerFloor:= False;
  OwnerFloorType:= Default(TSymbol);
  if (Length(FStores) = 0) or (AParams = nil) then
  begin
    Exit;
  end;
  TextDoc := AParams.GetValue('textDocument') as TJSONObject;
  Position:= AParams.GetValue('position'    ) as TJSONObject;
  if (TextDoc = nil) or (Position = nil) then
  begin
    Exit;
  end;
  Uri:= TextDoc.GetValue('uri').Value;
  Path:= FileFromUri(Uri);
  Line:= StrToIntDef(Position.GetValue('line'     ).Value, 0);
  Col := StrToIntDef(Position.GetValue('character').Value, 0);
  Ident:= IdentifierAtPosition(Path, Line, Col);
  if Ident = '' then
  begin
    Exit;
  end;
  { v0.46: a compiler intrinsic has no real indexed symbol -- show it as a
    built-in with its System-unit signature (like the IDE) instead of falling
    through to a wrong library match. The "- `System.X` - line 1" row keeps the
    clickable shape the popup parses (opens System.pas if on the source path). }
  if IsCompilerIntrinsic(Ident) then
  begin
    MdValue:= Format(
      '**%s** `intrinsic`'#10#10 + '- `System.%s` - line 1'#10 + '    %s'#10#10 + '_Delphi compiler built-in (System unit)._', [Ident, Ident, IntrinsicSignature(Ident)]);
    { Real markdown, but NO indexed symbol behind it -- HasSymbol stays False
      so a bundle built from this never describes symbol id 0. The name and
      signature are carried separately so a client can still render a structured
      view; see THoverComputation.IsIntrinsic. }
    AOut.MdValue     := MdValue;
    AOut.IsIntrinsic := True   ;
    AOut.IntrinsicName:= Ident ;
    AOut.IntrinsicSig := IntrinsicSignature(Ident);
    Exit(True);
  end;
  { v0.40.3: hover returns the FIRST hit across stores in declared order
    (project DB before library DB, per CLI arg ordering). For multi-hit
    cases the user can use Find Usages to see all stores' results. }
  Symbols:= nil;
  var HitStore: ISymbolStore:= nil;
  for var StIdx:= 0 to High(FStores) do
  begin
    Symbols:= FStores[StIdx].FindSymbolsByExactName(Ident);
    if Length(Symbols) > 0 then
    begin
      HitStore:= FStores[StIdx];
      Break;
    end;
  end;
  if (Length(Symbols) = 0) or (HitStore = nil) then
  begin
    Exit;
  end;
  // Overload disambiguation: FindSymbolsByExactName returns ALL same-named
  // symbols; pick the one whose declaration line or implementation span (in
  // THIS file) contains the cursor, so hovering the 2nd overload shows the 2nd
  // -- not always [0].
  var Chosen: Integer:= 0;
  var FoundDeclImpl: Boolean:= False;
  if Length(Symbols) > 1 then
  begin
    var CurLine1: Integer:= Line + 1;
    for var si:= 0 to High(Symbols) do
      if SameText(HitStore.GetFilePath(Symbols[si].FileId), Path)
        and ((Symbols[si].StartLine = CurLine1)
             or ((Symbols[si].ImplStartLine > 0) and (CurLine1 >= Symbols[si].ImplStartLine) and (CurLine1 <= Symbols[si].ImplEndLine))) then
      begin
        Chosen:= si; FoundDeclImpl:= True; Break;
      end;
  end;
  var Sel: TSymbol:= Symbols[Chosen];

  { v(hover call-site fix): the loop above only matches when the cursor sits ON a
    candidate's own DECLARATION or IMPLEMENTATION. At a CALL SITE like
    `TGroup.Create(...)` nothing matches, so Sel stayed Symbols[0] = an ARBITRARY
    same-named symbol -- and because FindSymbolsByExactName stops at the FIRST
    store holding the name, that can be a library hit that merely sorts first
    alphabetically (e.g. Abccompf.*.Create). Resolve the symbol ACTUALLY
    referenced at the cursor: anchor to the store that OWNS the hovered file, and
    follow the qualifier (`TGroup.` -> the Create member of TGroup) via
    TTypeAtResolver. Only override when it lands on the SAME identifier we hovered
    (not the owner-type fallback it returns for inherited members), so
    `TGroup.Create` shows TGroup.Create instead of some unrelated Create. Refresh
    HitStore/Symbols to the home store so the no-doc branch below stays consistent. }
  { The multi-store resolver anchors to the store owning the hovered file
    internally and resolves cross-DB (a generic/inherited member can live in a
    library index). The guard is only `not FoundDeclImpl` -- even a SINGLE
    same-named symbol may be the wrong one (an unrelated project `Count` vs the
    real TList<T>.Count), so let the resolver override whenever the cursor is not
    on a decl/impl. Override only when it lands on the SAME identifier hovered;
    on the owner-type floor (member not found on the type or any base) render an
    honest note instead of the arbitrary Symbols[0]. }
  if not FoundDeclImpl then
  begin
    var TAR:= TTypeAtResolver.Resolve(FStores, Path, Line + 1, Col + 1);
    if TAR.HasResolved and (TAR.Resolved.Id > 0) and SameText(TAR.Resolved.Name, Ident) then
    begin
      Sel:= TAR.Resolved;
      if (TAR.ResolvedStoreIndex >= 0) and (TAR.ResolvedStoreIndex <= High(FStores)) then
      begin
        HitStore:= FStores[TAR.ResolvedStoreIndex];
        Symbols := HitStore.FindSymbolsByExactName(Ident);
      end;
    end
    else if TAR.HasResolved and TAR.OwnerTypeFallback and (TAR.Resolved.Id > 0) then
    begin
      OwnerFloorType:= TAR.Resolved;
      HaveOwnerFloor:= True;
    end;
  end;

  // Live-mine the CHOSEN overload's Result:=/Exit() return cases for the popup,
  // so the hover shows the actual returned values (unifies the popup with the
  // managed doc's 'Returns:' fact line). Empty for a procedure / no body.
  var HovRhs: TArray<string>;
  SetLength(HovRhs, 0);
  if (Sel.ImplStartLine > 0) and (Sel.ImplEndLine >= Sel.ImplStartLine) then
  begin
    var HovPath: string:= HitStore.GetFilePath(Sel.FileId);
    if (HovPath <> '') and TLiveDocuments.Readable(HovPath) then
    begin
      var HovAll: TArray<string>:= TLiveDocuments.ReadLines(HovPath);
      var HLo: Integer:= Sel.ImplStartLine - 1;
      var HHi: Integer:= Sel.ImplEndLine - 1;
      if HLo < 0 then HLo:= 0;
      if HHi > High(HovAll) then HHi:= High(HovAll);
      if HHi >= HLo then
      begin
        var HBody: TArray<string>;
        SetLength(HBody, HHi - HLo + 1);
        for var hk:= HLo to HHi do HBody[hk - HLo]:= HovAll[hk];
        HovRhs:= MineReturnExpressions(HBody, Sel.QualifiedName);
      end;
    end;
  end;

  // Honest owner-type floor: the resolver found the LHS type but the member is
  // not on it or any base (incl. cross-DB generic bases). Show "Type.Member --
  // inherited member; owner type QName" rather than the arbitrary Symbols[0].
  if HaveOwnerFloor then
    MdValue:= Format('**%s.%s**'#10#10 + '_inherited member; owner type_ `%s`', [OwnerFloorType.Name, Ident, OwnerFloorType.QualifiedName])
  else
  begin
  // v0.16: try to enrich the hover with doc-comment content.
  // GetSymbolDoc returns a zeroed TParsedDoc with HasContent=False when
  // no row exists; in that case fall back to the legacy signature listing.
  Doc:= HitStore.GetSymbolDoc(Sel.Id);
  if Doc.HasContent then
  begin
    // v(ADP2 T9): thread the SAME Phase-2 analysis facts `document` and
    // the CLI's `hover` render into the IDE's hover popup -- via
    // TDocFactsBuilder.Build (the identical facts assembly `document`
    // uses) and TDocRegions.FormatPhase2FactLines (the SHARED formatter
    // every surface calls), so this popup can never show different facts
    // than the managed doc block for the same symbol (the doc/hover
    // consistency lock). LoadDocComplexityMin loads the SAME
    // docs.complexity_min threshold `document` uses. AIncludeSeeAlso/
    // AIncludeSince stay False (no --seealso/--since opt-in here),
    // mirroring a default `document` run.
    var HovFacts: TDocFacts:= TDocFactsBuilder.Build(HitStore, Sel);
    var HovFactLines: TArray<string>:= TDocRegions.FormatPhase2FactLines(HovFacts, LoadDocComplexityMin);
    MdValue:= DRagLint.Hover.Renderer.RenderHoverMarkdown(Sel, Doc, HovRhs, HovFactLines);
  end
  else
  begin
    Sb:= TStringBuilder.Create;
    try
      { v0.40.8f: try to resolve the actual type at cursor first. If we
        can, narrow the candidate list to symbols on THAT type (else a
        common member like DataBinding lists every class that has one). }
      var TAResult:= TTypeAtResolver.Resolve( FStores, Path, Line + 1, Col + 1);

      var Filtered: TArray<TSymbol>;
      SetLength(Filtered, 0);
      var ResolvedQName: string:= '';
      if TAResult.HasResolved then ResolvedQName:= TAResult.Resolved.QualifiedName;

      if ResolvedQName <> '' then
      begin
        { Keep only candidates whose QualifiedName matches the resolved
          symbol exactly, or whose QualifiedName begins with the resolved
          qname plus '.' (member access on a record/interface). }
        for Sym in Symbols do
        begin
          if (Sym.QualifiedName = ResolvedQName) or (Pos(ResolvedQName + '.', Sym.QualifiedName) = 1) then
          begin
            SetLength(Filtered, Length(Filtered) + 1);
            Filtered[High(Filtered)]:= Sym;
          end;
        end;
      end;

      { v0.46: owner-type / unit fallback. When the exact-type filter found
        nothing because the member is INHERITED (resolved to the owner type,
        not the member itself), narrow by the resolved type's UNIT prefix.
        Turns ~50 same-named properties across unrelated types into the few
        in the right library unit (e.g. AButton: TdxBarButton -> only dxBar). }
      if (Length(Filtered) = 0) and (ResolvedQName <> '') then
      begin
        var DotP: Integer:= Pos('.', ResolvedQName);
        if DotP > 1 then
        begin
          var UnitPfx: string:= Copy(ResolvedQName, 1, DotP); { incl. '.' }
          for Sym in Symbols do
            if Pos(UnitPfx, Sym.QualifiedName) = 1 then
            begin
              SetLength(Filtered, Length(Filtered) + 1);
              Filtered[High(Filtered)]:= Sym;
            end;
        end;
      end;

      { Fallback: if filtering yielded nothing (no LHS info, or qname
        mismatch across stores), keep the original list capped at 50 so
        mega-common members like DataBinding don't blow up the popup. }
      if Length(Filtered) = 0 then
      begin
        if Length(Symbols) <= 50 then Filtered:= Symbols
        else
        begin
          SetLength(Filtered, 50);
          for var I:= 0 to 49 do Filtered[I]:= Symbols[I];
        end;
      end;

      { v0.46 hover polish: de-duplicate candidates and prefer the source
        declaration over a generated DFM component (see DedupAndPreferSource),
        so a published field shows once with its real declared type instead of
        a phantom "2 overloads" (field + DFM object, possibly doubled by a
        stale index). The mislabeled "_Resolved type: <qname>_" line is gone --
        the indented declaration line below already shows "name: Type" exactly
        as the IDE does. }
      Filtered:= DedupAndPreferSource(Filtered);

      { Qualify the kind with what constrains USE, so the one-line popup header
        the plugin builds from this ("<kind> <name> - <unit>.pas (<line>)")
        says 'protected field' rather than just 'field'. Requested after a
        protected field was accepted from the completion list and then
        rejected by the compiler with E2362: every other fact about the symbol
        was on screen except the one that mattered.
        Only constraining qualifiers appear -- public/published and read/write
        add nothing and stay silent, so ordinary members read exactly as
        before and the marker keeps its signal. }
      Sb.AppendLine(Format('**%s** `%s`', [Ident, QualifiedKindText(Filtered[0])]));
      Sb.AppendLine('');
      { v0.42: render each candidate (every overload) as a Code-Insight-style
        declaration. Signature now carries the full param list + return type,
        e.g. '(const A: Integer): Boolean'. The "- `qname` - line N" shape is
        preserved exactly so the popup's single-click navigation still parses
        the qname + line; the declaration line is shown indented underneath. }
      if Length(Filtered) > 1 then Sb.AppendLine(Format('_%d overloads:_', [Length(Filtered)]));
      for Sym in Filtered do
      begin
        Sb.AppendLine(Format('- `%s` - line %d', [Sym.QualifiedName, Sym.StartLine]));
        Sb.AppendLine('    ' + DeclLineFor(Sym));
        { v0.43: break the signature into an IDE-style Parameters block
          (name + type per line, + Returns). Only for a focused candidate
          set so a 50-hit common member doesn't explode the popup. }
        if Length(Filtered) <= 5 then
        begin
          var ParamBlock: string:= DRagLint.Hover.Renderer.RenderSignatureParamsMarkdown(Sym.Signature);
          if ParamBlock <> '' then
          begin
            Sb.AppendLine(''        );
            Sb.Append    (ParamBlock);
          end;
        end;
      end;
      { Partial-list note: only when the original hit set actually exceeded the
        50-candidate cap (the DataBinding case), NOT when dedup/prefer-source
        shrank the list -- otherwise a field+DFM pair would read "showing 1 of 2". }
      if (Length(Symbols) > 50) and (ResolvedQName = '') then
        Sb.AppendLine(Format(#10'_(showing %d of %d -- use Find Usages for full list)_', [Length(Filtered), Length(Symbols)]));

      MdValue:= Sb.ToString;
    finally
      Sb.Free;
    end; // try
  end; // else Doc.HasContent
  end; // else HaveOwnerFloor
  AOut.MdValue:= MdValue;
  { On the owner-type floor the markdown deliberately names the OWNER TYPE,
    because the member was not found on it or any base. Report that same type
    as the bundle's subject; reporting Sel there would hand back an arbitrary
    same-named symbol -- the shape that put an FMX type in a VCL project. }
  if HaveOwnerFloor then AOut.Sel:= OwnerFloorType
  else                   AOut.Sel:= Sel;
  AOut.Store    := HitStore;
  AOut.HasSymbol:= True    ;
  Result:= True;
end; // function

procedure TLSPServer.HandleHover(const AId: TJSONValue; const AParams: TJSONObject);
{ A thin envelope over ComputeHover. Every rule about WHICH symbol a position
  means now lives in one place, so `draglint/hoverBundle` cannot describe a
  different symbol than this reply does for the same cursor. }
var
  Reply   : TJSONObject     ;
  HoverObj: TJSONObject     ;
  Contents: TJSONObject     ;
  Comp    : THoverComputation;
begin
  Reply:= TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);
    if not ComputeHover(AParams, Comp) then
      Reply.AddPair('result', TJSONNull.Create)
    else
    begin
      HoverObj:= TJSONObject.Create;
      Contents:= TJSONObject.Create;
      Contents.AddPair('kind'    , 'markdown' );
      Contents.AddPair('value'   , Comp.MdValue);
      HoverObj.AddPair('contents', Contents   );
      Reply   .AddPair('result'  , HoverObj   );
    end;
    SendMessage(Reply);
  finally
    Reply.Free;
  end; // try
end; // procedure

procedure TLSPServer.HandleCallerCounts(const AId: TJSONValue; const AParams: TJSONObject);
{ The caller count for every routine in one file, in ONE reply.

  WHAT IT REPLACES. DragLint.Plugin.CodeLensCache listed a file's methods and
  then shelled `query find-callers` ONCE PER METHOD, parsing the text output with
  a line-shape heuristic. Measured on DataCopy's uMainZeissCopy.pas: 77 methods
  at ~165 ms per process start is 12.7 SECONDS of serial spawning to label one
  file -- repeated every time the cache repopulates.

  Same argument as draglint/hoverBundle, which replaced four spawns per tooltip:
  every store this touches is ALREADY OPEN on FStores, so the work is a few
  in-process queries. Nothing here opens a database.

  It also removes the text parsing. The old ParseCallerCount guessed at which
  output lines were callers by their shape -- skip blanks, skip '---', skip
  anything starting '[' -- which is a contract nobody wrote down and the engine
  could change without noticing. A number in JSON cannot drift that way.

  ROUTINES ONLY. A field or a property has no caller count worth showing in a
  code lens, and including them would put a '[0 callers]' label on half the
  lines of a form class. }
var
  Reply : TJSONObject;
  Res   : TJSONObject;
  Arr   : TJSONArray ;
  Uri   : string     ;
  Path  : string     ;
  Syms  : TArray<TSymbol>;
  St    : ISymbolStore;
  Seen  : TDictionary<Integer, Integer>;
  Sites : TDictionary<string, Byte>;   { distinct (file:line) call sites }
  Pair  : TPair<Integer, Integer>;
  Total : Integer    ;
begin
  Reply:= TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);

    Res:= TJSONObject.Create;
    Arr:= TJSONArray.Create;

    Uri := '';
    if AParams <> nil then
    begin
      var TdObj: TJSONObject:= AParams.GetValue('textDocument') as TJSONObject;
      if TdObj <> nil then TdObj.TryGetValue<string>('uri', Uri);
    end;
    Path:= FileFromUri(Uri);

    { A file this index does not know is not an error -- it is a file with no
      lenses. An empty array says that unambiguously; an error would make the
      client retry something that will never succeed. }
    if Path <> '' then
    begin
      Seen := TDictionary<Integer, Integer>.Create;
      Sites:= TDictionary<string, Byte>.Create;
      try
        for St in FStores do
        begin
          if St = nil then Continue;
          Syms:= St.FindSymbolsByFile(Path);
          for var Sym: TSymbol in Syms do
          begin
            if not (Sym.Kind in [skProcedure, skFunction, skMethod, skConstructor, skDestructor]) then Continue;
            if Sym.StartLine <= 0 then Continue;
            { ONE PER CALL SITE, not one per reference. FindCallersByName returns
              BOTH a 'call' and a 'member-access' ref for `T.Thrice;`, so a raw
              Length() reports three calls as six. The CLI's text output happens
              to collapse them per line, which is why the plugin's old
              line-counting parser got the right number -- by accident of the
              formatting, not by asking for it. Deduplicating on (file, line)
              asks for it, and keeps a reference that is not a call: a caller the
              user can navigate to is a caller.

              Counted across EVERY open store, because a caller in another
              project still calls this routine. }
            Sites.Clear;
            for var R: TReference in St.FindCallersByName(Sym.Name) do
              Sites.AddOrSetValue(LowerCase(St.GetFilePath(R.FileId)) + ':' + IntToStr(R.StartLine), 1);
            Total:= Sites.Count;
            if Seen.ContainsKey(Sym.StartLine) then
              Seen[Sym.StartLine]:= Seen[Sym.StartLine] + Total
            else
              Seen.Add(Sym.StartLine, Total);
          end;
        end;

        for Pair in Seen do
        begin
          var Item: TJSONObject:= TJSONObject.Create;
          { 0-BASED, matching LSP convention. The store is 1-based and the
            plugin's cache is 0-based; converting HERE means exactly one place
            knows about the offset. }
          Item.AddPair('line' , TJSONNumber.Create(Pair.Key - 1));
          Item.AddPair('count', TJSONNumber.Create(Pair.Value));
          Arr.AddElement(Item);
        end;
      finally
        Sites.Free;
        Seen.Free;
      end;
    end;

    Res.AddPair('counts', Arr);
    Reply.AddPair('result', Res);
    SendMessage(Reply);
  finally
    Reply.Free;
  end;
end;

procedure TLSPServer.HandleUsages(const AId: TJSONValue; const AParams: TJSONObject);
{ WHAT IT REPLACES. The IDE's Find Usages shelled `drag-lint usages` and parsed
  the result: one process start per invocation, measured at 1,678 ms with the
  platform library index in the set against 163 ms without it. Almost all of that
  is opening databases -- and THIS SERVER ALREADY HAS THEM OPEN on FStores. Same
  argument as draglint/hoverBundle (four spawns per tooltip) and
  draglint/callerCounts (77 spawns to label one file).

  THE OTHER OPTION WAS REJECTED, and deliberately. Dropping the library DB from
  the query is ~10x for one line of change, but it CHANGES WHAT IS FOUND -- a
  usage in RTL/VCL/third-party code stops being reported. That is a product
  decision about what Find Usages MEANS, not an optimisation, and it was not
  taken. This path is the one that keeps the answer identical.

  THE REPLY SHAPE IS THE CLI VERB'S, KEY FOR KEY: name, width, declarations,
  reads, writes, calls, types, attributes, events, impact. That is not tidiness
  -- a client that can fall back to spawning the CLI must not have to parse two
  shapes, and a second shape drifts silently. run_lsp_usages_guard.ps1 asserts
  the two agree.

  EVERY store is consulted, not FStores[0]: a symbol's declaration and its usages
  routinely live in different indexes (project + platform library), which is the
  whole reason the CLI accepts several --db. }
var
  Reply  : TJSONObject   ;
  Res    : TJSONObject   ;
  JDecls : TJSONArray    ;
  JReads : TJSONArray    ;
  JWrites: TJSONArray    ;
  JCalls : TJSONArray    ;
  JTypes : TJSONArray    ;
  JAttrs : TJSONArray    ;
  JEvents: TJSONArray    ;
  JImpact: TJSONArray    ;
  Nm     : string        ;
  Width  : string        ;
  Depth  : Integer       ;
  St     : ISymbolStore  ;
  S      : TSymbol       ;
  R      : TReference    ;
  L      : TImpactLevel  ;
  DeclO  : TJSONObject   ;

  procedure AddRefRow(AArr: TJSONArray; const AFile: string; ALine, ACol: Integer);
  var
    O: TJSONObject;
  begin
    O:= TJSONObject.Create;
    O.AddPair('file', AFile);
    O.AddPair('line', TJSONNumber.Create(ALine));
    O.AddPair('col' , TJSONNumber.Create(ACol ));
    AArr.AddElement(O);
  end;

  { The ref-kind -> bucket mapping is the CLI verb's, including its catch-all:
    'call + anything else' lands in calls. Changing it here would make the two
    shapes disagree on a row's bucket while both still "work". }
  function GroupFor(const AKind: string): TJSONArray;
  begin
    if AKind      = 'read'          then Result:= JReads
    else if AKind = 'write'         then Result:= JWrites
    else if AKind = 'type_use'      then Result:= JTypes
    else if AKind = 'attribute'     then Result:= JAttrs
    else if AKind = 'event-binding' then Result:= JEvents
    else Result:= JCalls;
  end;

begin
  Nm:= '';
  Width:= '';
  Depth:= 0;
  if AParams <> nil then
  begin
    AParams.TryGetValue<string>('name', Nm);
    AParams.TryGetValue<string>('width', Width);
    var DepthNum: TJSONNumber:= AParams.GetValue('depth') as TJSONNumber;
    if DepthNum <> nil then Depth:= DepthNum.AsInt;
  end;

  if Nm = '' then
  begin
    { A missing name is a CLIENT error, not an empty result. Returning an empty
      payload here would look exactly like "this symbol has no usages". }
    SendError(AId, -32602, 'draglint/usages requires a non-empty "name"');
    Exit;
  end;

  { Width/depth defaults are the CLI's, restated because they are part of the
    contract the guard compares: anything but 'very-wide' pins depth at 2, and a
    non-positive depth becomes 4. }
  Width:= LowerCase(Width);
  if Width = '' then Width:= 'narrow';
  if Width <> 'very-wide' then Depth:= 2; { only very-wide honours a caller depth }
  if Depth <= 0 then Depth:= 4;

  Reply:= TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);

    JDecls := TJSONArray.Create;
    JReads := TJSONArray.Create;
    JWrites:= TJSONArray.Create;
    JCalls := TJSONArray.Create;
    JTypes := TJSONArray.Create;
    JAttrs := TJSONArray.Create;
    JEvents:= TJSONArray.Create;
    JImpact:= TJSONArray.Create;

    for St in FStores do
    begin
      if St = nil then Continue;
      for S in St.FindSymbolsByExactName(Nm) do
      begin
        DeclO:= TJSONObject.Create;
        DeclO.AddPair('kind'     , S.Kind.ToText);
        DeclO.AddPair('qname'    , S.QualifiedName);
        DeclO.AddPair('file'     , St.GetFilePath(S.FileId));
        DeclO.AddPair('line'     , TJSONNumber.Create(S.StartLine));
        DeclO.AddPair('signature', S.Signature);
        JDecls.AddElement(DeclO);
      end;
      for R in St.FindCallersByName(Nm) do
        AddRefRow(GroupFor(R.Kind), St.GetFilePath(R.FileId), R.StartLine, R.StartCol);
      if Width = 'very-wide' then
        for L in St.FindTransitiveCallers(Nm, Depth) do
        begin
          var IO_: TJSONObject:= TJSONObject.Create;
          IO_.AddPair('depth'  , TJSONNumber.Create(L.Depth      ));
          IO_.AddPair('callers', TJSONNumber.Create(L.CallerCount));
          IO_.AddPair('units'  , TJSONNumber.Create(L.UnitCount  ));
          JImpact.AddElement(IO_);
        end;
    end;

    Res:= TJSONObject.Create;
    Res.AddPair('name'        , Nm     );
    Res.AddPair('width'       , Width  );
    Res.AddPair('declarations', JDecls );
    Res.AddPair('reads'       , JReads );
    Res.AddPair('writes'      , JWrites);
    Res.AddPair('calls'       , JCalls );
    Res.AddPair('types'       , JTypes );
    Res.AddPair('attributes'  , JAttrs );
    Res.AddPair('events'      , JEvents);
    Res.AddPair('impact'      , JImpact);
    Reply.AddPair('result', Res);
    SendMessage(Reply);
  finally
    Reply.Free;
  end;
end;

procedure TLSPServer.HandleHoverBundle(const AId: TJSONValue; const AParams: TJSONObject);
{ ONE reply carrying everything the IDE popup used to gather in four round
  trips. See THoverComputation and the unit header of DRagLint.Query.Callers
  for why this exists.

  Every store consulted here is already open on FStores. Nothing in this handler
  opens a database, which is the whole point -- the spawns it replaces each
  cold-opened the ~1.4 GB library index to answer one tooltip. }
var
  Reply    : TJSONObject     ;
  Res      : TJSONObject     ;
  Comp     : THoverComputation;
  FactLines: TArray<string>  ;
begin
  Reply:= TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);

    if not ComputeHover(AParams, Comp) then
    begin
      Reply.AddPair('result', TJSONNull.Create);
      SendMessage(Reply);
      Exit;
    end;

    Res:= TJSONObject.Create;
    Res.AddPair('markdown', Comp.MdValue);

    if not Comp.HasSymbol then
    begin
      { A COMPILER INTRINSIC. No indexed symbol, so there are no callers and no
        doc facts -- but the name and signature are known, and handing back only
        markdown left the popup with nothing to render but flat text. Synthesise
        a model from what IS known so an intrinsic gets the same coloured
        signature every other symbol gets. Empty arrays rather than omitted
        keys, so a client can tell "nothing to show" from "field missing". }
      Res.AddPair('qname', 'System.' + Comp.IntrinsicName);
      if Comp.IsIntrinsic then
      begin
        { IntrinsicSignature returns the WHOLE declaration
          ("function System.Length(const S): Integer"), where an indexed symbol
          carries only the "(params): ret" tail. Normalise to the tail so the
          model's parameter parser sees the same shape it sees everywhere else
          and the header does not read "System.Length: function System.Length...".
          No parenthesis (an intrinsic taking none) leaves it empty, which just
          renders the name. }
        var SigTail: string:= Comp.IntrinsicSig;
        var ParenAt: Integer:= Pos('(', SigTail);
        if ParenAt > 0 then SigTail:= Copy(SigTail, ParenAt, MaxInt)
        else                SigTail:= '';

        var Syn: TSymbol:= Default(TSymbol);
        Syn.Name         := Comp.IntrinsicName;
        Syn.QualifiedName:= 'System.' + Comp.IntrinsicName;
        Syn.Signature    := SigTail;
        Syn.StartLine    := 1;
        { Kind deliberately NOT skFunction: the popup labels the header from it,
          and calling a compiler built-in a function would claim an indexed
          declaration that does not exist. RenderHoverJson emits the kind text,
          which the plugin shows verbatim. }
        var SynFacts: TArray<string>;
        SetLength(SynFacts, 0);
        var SynModel: THoverModel:= BuildHoverModel(Syn, Default(TParsedDoc), 'System.pas', nil, nil);
        SynModel.Kind:= 'intrinsic';
        var SynJson : string    := DRagLint.Hover.Renderer.RenderHoverJson(SynModel, SynFacts);
        var SynVal  : TJSONValue:= nil;
        try
          SynVal:= TJSONObject.ParseJSONValue(SynJson);
        except
          on E: Exception do
          begin
            Writeln(ErrOutput, 'drag-lint LSP: intrinsic model JSON did not parse for ',
                    Comp.IntrinsicName, ': ', E.Message);
            SynVal:= nil;
          end;
        end;
        if SynVal <> nil then Res.AddPair('model', SynVal)
        else                  Res.AddPair('model', TJSONNull.Create);
      end
      else
        Res.AddPair('model', TJSONNull.Create);
      Res.AddPair('nameCallers'    , TJSONArray.Create );
      Res.AddPair('resolvedCallers', TJSONArray.Create );
      Reply.AddPair('result', Res);
      SendMessage(Reply);
      Exit;
    end;

    Res.AddPair('qname', Comp.Sel.QualifiedName);

    { The model, assembled by the same shared code `hover --format json` calls,
      then re-parsed into the reply. Re-parsing costs a few microseconds and
      buys the guarantee that the two surfaces cannot format differently. }
    var Asm_     : THoverAssembly:= AssembleHover(Comp.Store, Comp.Sel);
    FactLines:= Asm_.FactLines;
    var ModelJson: string:= DRagLint.Hover.Renderer.RenderHoverJson(Asm_.Model, FactLines);
    var ModelVal : TJSONValue := nil;
    try
      ModelVal:= TJSONObject.ParseJSONValue(ModelJson);
    except
      { Our OWN renderer produced this string, so a parse failure is a defect in
        the renderer, not bad input. Report it on stderr -- the plugin captures
        that -- rather than swallowing it: a null model would otherwise look
        exactly like "this symbol has nothing to show". }
      on E: Exception do
      begin
        Writeln(ErrOutput, 'drag-lint LSP: hover model JSON did not parse for ',
                Comp.Sel.QualifiedName, ': ', E.Message);
        ModelVal:= nil;
      end;
    end;
    if ModelVal <> nil then Res.AddPair('model', ModelVal)
    else                    Res.AddPair('model', TJSONNull.Create);

    { CALLER SCOPING. Library stores are dropped from the caller search: callers
      of project code live in the project, and scanning the library index by
      name is what made this query take ~20 s. They are kept only when dropping
      them would leave nothing to search -- a hover on a purely library symbol.
      This rule used to live in the plugin, which had to guess from file names;
      here the store list itself is the answer. }
    var Search: TArray<ISymbolStore>;
    SetLength(Search, 0);
    for var i:= 0 to High(FStores) do
    begin
      var IsLib: Boolean:= (i <= High(FStorePaths))
        and (Pos('library-', LowerCase(ExtractFileName(FStorePaths[i]))) > 0);
      if not IsLib then
      begin
        SetLength(Search, Length(Search) + 1);
        Search[High(Search)]:= FStores[i];
      end;
    end;
    if Length(Search) = 0 then Search:= FStores;

    { A PARAMETER or LOCAL cannot be referenced outside the routine that
      declares it, so every row must come from that routine's own body -- and
      from the store that owns it, since symbol ids are per-database.

      Reported 2026-08-19: hovering `btn` in TTransferLogger.Create listed two
      usages, the second being TErrorLogger.Create's own `btn`. The symbol
      resolved correctly; the usage list was gathered by BARE NAME across the
      whole index, so a different symbol that merely shares a name came back as
      a usage of this one. }
    var LocalScoped: Boolean:= Comp.Sel.Kind in [skParam, skLocalVar];
    if LocalScoped and (Comp.Store <> nil) then
    begin
      SetLength(Search, 1);
      Search[0]:= Comp.Store;
    end;

    var BareName: string:= Comp.Sel.Name;

    { A RESOLVED row is rendered here, not in the query layer, because the text
      a reader wants is the one in the editor's UNSAVED buffer and only this
      process holds it. Cached per file: a widely-called routine yields many
      rows and they cluster in a handful of files, so re-reading per row would
      turn one tooltip into dozens of file reads.

      Reported from the live IDE 2026-08-19: "CALLED FROM shows line numbers but
      no code". Resolved rows were emitted without a `code` key at all, so
      whenever SelectCallers chose the resolved set the popup's grid rendered
      bare line numbers. }
    var SrcCache: TDictionary<string, TArray<string>>:= TDictionary<string, TArray<string>>.Create;
    try
      var JResolved: TJSONArray:= TJSONArray.Create;
      { A parameter is not CALLED, so resolved call edges say nothing about one --
        every row they could return would be about a same-named routine. }
      if not LocalScoped then
      for var i:= 0 to High(Search) do
        for var R in ResolvedCallersForName(Search[i], BareName) do
        begin
          var O: TJSONObject:= TJSONObject.Create;
          O.AddPair('caller_qname', R.CallerQName);
          { The OPENABLE path. R.FilePath is filename-only for resolved rows by
            the CLI's cross-machine contract; the popup navigates to what it is
            given, so handing it a bare name is a dead link. }
          var RowPath: string:= R.FullPath;
          if RowPath = '' then RowPath:= R.FilePath;
          O.AddPair('file'        , RowPath      );
          O.AddPair('confidence'  , R.Confidence );
          O.AddPair('target_qname', R.TargetQName);

          { The CALL SITE, not the caller routine's header. R.Line is
            routine-granular -- correct for the CLI, and it makes a hover say
            "called from line 1200" for a call on line 1247. The exact line was
            in the index all along. }
          var RowLine: Integer:= 0;
          if      R.CallSiteLine > 0 then RowLine:= R.CallSiteLine
          else if R.HasLine          then RowLine:= R.Line;
          if RowLine > 0 then O.AddPair('line', TJSONNumber.Create(RowLine));

          if (RowLine > 0) and (RowPath <> '') then
          begin
            var SrcLines: TArray<string>;
            if not SrcCache.TryGetValue(RowPath, SrcLines) then
            begin
              SetLength(SrcLines, 0);
              { Readable() covers the overlay too, so an unsaved buffer renders. }
              if TLiveDocuments.Readable(RowPath) then
                try
                  SrcLines:= TLiveDocuments.ReadLines(RowPath);
                except
                  { A caller row is worth showing without its text; it is not
                    worth failing the whole tooltip for. }
                  on E: Exception do SetLength(SrcLines, 0);
                end;
              SrcCache.AddOrSetValue(RowPath, SrcLines);
            end;
            if (RowLine <= Length(SrcLines)) then
              O.AddPair('code', Trim(SrcLines[RowLine - 1]));
          end;

          JResolved.AddElement(O);
        end;
      Res.AddPair('resolvedCallers', JResolved);
    finally
      SrcCache.Free;
    end; // try

    var JName: TJSONArray:= TJSONArray.Create;
    for var i:= 0 to High(Search) do
      for var R in NameCallersForName(Search[i], BareName, 1) do
      begin
        { For a param/local, keep only references inside the DECLARING routine.
          ParentId is that routine; a reference enclosed by anything else is a
          different symbol wearing the same name. }
        if LocalScoped and (R.EnclosingSymbolId <> Comp.Sel.ParentId) then Continue;
        var O: TJSONObject:= TJSONObject.Create;
        O.AddPair('file', R.FilePath);
        O.AddPair('line', TJSONNumber.Create(R.Line));
        O.AddPair('code', R.CodeText);
        JName.AddElement(O);
      end;
    Res.AddPair('nameCallers', JName);

    Reply.AddPair('result', Res);
    SendMessage(Reply);
  finally
    Reply.Free;
  end; // try
end; // procedure

procedure TLSPServer.HandleCompletion(const AId: TJSONValue; const AParams: TJSONObject);
var
  Reply   : TJSONObject;
  WrapObj : TJSONObject;
  TextDoc : TJSONObject;
  Position: TJSONObject;
  Uri     : string     ;
  Path    : string     ;
  Line    : Integer    ;
  Col     : Integer    ;
  Items   : TJSONArray ;
begin
  Reply:= TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);
    if (Length(FStores) = 0) or (AParams = nil) then
    begin
      WrapObj:= TJSONObject.Create;
      WrapObj.AddPair('isIncomplete', TJSONBool.Create(False));
      WrapObj.AddPair('items', TJSONArray.Create);
      Reply.AddPair('result', WrapObj);
      SendMessage(Reply);
      Exit;
    end;
    TextDoc := AParams.GetValue('textDocument') as TJSONObject;
    Position:= AParams.GetValue('position'    ) as TJSONObject;
    if (TextDoc = nil) or (Position = nil) then
    begin
      WrapObj:= TJSONObject.Create;
      WrapObj.AddPair('isIncomplete', TJSONBool.Create(False));
      WrapObj.AddPair('items', TJSONArray.Create);
      Reply.AddPair('result', WrapObj);
      SendMessage(Reply);
      Exit;
    end;
    Uri:= TextDoc.GetValue('uri').Value;
    Path:= FileFromUri(Uri);
    // LSP positions are 0-based; completion builder uses 1-based.
    Line:= StrToIntDef(Position.GetValue('line'     ).Value, 0) + 1;
    Col := StrToIntDef(Position.GetValue('character').Value, 0) + 1;
    { FStores, not FStore. FStore is documented above as "kept for legacy
      single-store callers" and this was one of them: the declaring type of a
      local/param is routinely in a different --db than the file being edited,
      so a single-store lookup returned an empty item list. }
    Items:= TLspCompletion.BuildCompletionItems(FStores, Path, Line, Col);
    WrapObj:= TJSONObject.Create;
    WrapObj.AddPair('isIncomplete', TJSONBool.Create(False));
    WrapObj.AddPair('items' , Items  );
    Reply  .AddPair('result', WrapObj);
    SendMessage(Reply);
  finally
    Reply.Free;
  end; // try
end; // procedure

procedure TLSPServer.HandleSignatureHelp(const AId: TJSONValue; const AParams: TJSONObject);
var
  Reply   : TJSONObject;
  TextDoc : TJSONObject;
  Position: TJSONObject;
  Uri     : string     ;
  Path    : string     ;
  Line    : Integer    ;
  Col     : Integer    ;
  SigHelp : TJSONObject;
begin
  Reply:= TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);
    if (FStore = nil) or (AParams = nil) then
    begin
      Exit;
    end;
    TextDoc := AParams.GetValue('textDocument') as TJSONObject;
    Position:= AParams.GetValue('position'    ) as TJSONObject;
    if (TextDoc = nil) or (Position = nil) then
    begin
      Exit;
    end;
    Uri:= TextDoc.GetValue('uri').Value;
    Path:= FileFromUri(Uri);
    // LSP positions are 0-based; signatureHelp builder uses 1-based.
    Line:= StrToIntDef(Position.GetValue('line'     ).Value, 0) + 1;
    Col := StrToIntDef(Position.GetValue('character').Value, 0) + 1;
    SigHelp:= TLspCompletion.BuildSignatureHelp(FStore, Path, Line, Col);
    if SigHelp <> nil then Reply.AddPair('result', SigHelp)
    else Reply.AddPair('result', TJSONNull.Create);
    SendMessage(Reply);
  finally
    Reply.Free;
  end; // try
end; // procedure

procedure TLSPServer.HandleDidOpenOrSave(const AParams: TJSONObject);
var
  TextDoc  : TJSONObject;
  Uri      : string     ;
  Path     : string     ;
  Diags    : TJSONArray ;
  Notif    : TJSONObject;
  ParamsObj: TJSONObject;
begin
  if AParams = nil then Exit;
  TextDoc:= AParams.GetValue('textDocument') as TJSONObject;
  if TextDoc = nil then Exit;
  Uri:= TextDoc.GetValue('uri').Value;
  Path:= FileFromUri(Uri);
  { v(live-buffer): didOpen carries the buffer's text, and didSave may. Seed the
    overlay from it so the very first hover in a session is buffer-accurate
    without waiting for an edit. On didSave WITHOUT text the buffer now equals
    disk, so the stale overlay must go -- keeping it would pin the pre-save text
    and re-create the same blindness in the opposite direction. }
  var OpenText: TJSONValue:= TextDoc.GetValue('text');
  if (OpenText <> nil) and not (OpenText is TJSONNull) then
    TLiveDocuments.SetText(Path, OpenText.Value)
  else
    TLiveDocuments.Remove(Path);
  // v0.26: pass FStore so compiler_findings are merged into publishDiagnostics.
  Diags:= TLspCompletion.BuildDiagnostics(EnsureLinter, Path, FStore);
  Notif:= TJSONObject.Create;
  try
    Notif.AddPair('jsonrpc', '2.0'                            );
    Notif.AddPair('method' , 'textDocument/publishDiagnostics');
    ParamsObj:= TJSONObject.Create;
    ParamsObj.AddPair('uri'        , Uri      );
    ParamsObj.AddPair('diagnostics', Diags    );
    Notif    .AddPair('params'     , ParamsObj);
    SendRawNotification(Notif);
  finally
    Notif.Free;
  end;
end; // procedure

procedure TLSPServer.HandleDidChange(const AParams: TJSONObject);
{ Full-sync document update. The server advertises TextDocumentSyncKind.Full,
  so a conforming client sends ONE contentChange holding the whole buffer and
  no `range`. A client that ignores that and sends incremental ranges would
  hand us a fragment; applying it as the whole document would be far worse
  than staying on disk, so a change carrying a `range` is REJECTED rather than
  stored, and the overlay is dropped so reads fall back to disk. That is the
  conservative direction: stale-but-coherent beats confidently-wrong. }
var
  TextDoc: TJSONObject;
  Changes: TJSONArray ;
  Path   : string     ;
begin
  if AParams = nil then Exit;
  TextDoc:= AParams.GetValue('textDocument') as TJSONObject;
  if TextDoc = nil then Exit;
  Path:= FileFromUri(TextDoc.GetValue('uri').Value);
  if Path = '' then Exit;

  Changes:= AParams.GetValue('contentChanges') as TJSONArray;
  if (Changes = nil) or (Changes.Count = 0) then Exit;

  { Take the LAST change: a client batching several full-text updates into one
    notification means the final one is the current buffer. }
  var Last: TJSONValue:= Changes.Items[Changes.Count - 1];
  if not (Last is TJSONObject) then Exit;

  if TJSONObject(Last).GetValue('range') <> nil then
  begin
    TLiveDocuments.Remove(Path);
    Exit;
  end;

  var TextVal: TJSONValue:= TJSONObject(Last).GetValue('text');
  if (TextVal = nil) or (TextVal is TJSONNull) then Exit;
  TLiveDocuments.SetText(Path, TextVal.Value);
end; // procedure

procedure TLSPServer.HandleDidClose(const AParams: TJSONObject);
{ The buffer is gone, so disk is authoritative again. Not dropping it here is
  a slow leak that also serves the CLOSED file's last-typed text forever. }
var
  TextDoc: TJSONObject;
begin
  if AParams = nil then Exit;
  TextDoc:= AParams.GetValue('textDocument') as TJSONObject;
  if TextDoc = nil then Exit;
  TLiveDocuments.Remove(FileFromUri(TextDoc.GetValue('uri').Value));
end; // procedure

procedure TLSPServer.Run;
var
  Msg      : TJSONObject;
  Method   : string     ;
  Id       : TJSONValue ;
  Params   : TJSONObject;
  ParamsVal: TJSONValue ;
begin
  while not FShuttingDown do
  begin
    Msg:= ReadMessage;
    if Msg = nil then Break;
    try
      Method:= '';
      if Msg.GetValue('method') <> nil then Method:= Msg.GetValue('method').Value;
      Id       := Msg.GetValue('id'    );
      ParamsVal:= Msg.GetValue('params');
      if ParamsVal is TJSONObject then Params:= TJSONObject(ParamsVal)
      else Params:= nil;

      if Method      = 'initialize' then HandleInitialize(Id, Params)
      else if Method = 'initialized' then
        // notification, no response
      else if Method = 'shutdown' then HandleShutdown(Id)
      else if Method = 'exit' then Break
      else if Method = 'workspace/symbol' then HandleWorkspaceSymbol(Id, Params)
      else if Method = 'textDocument/definition' then HandleDefinition(Id, Params)
      else if Method = 'textDocument/references' then HandleReferences(Id, Params)
      else if Method = 'textDocument/hover' then HandleHover(Id, Params)
      { Custom, hence the vendor prefix: one reply carrying hover markdown, the
        structured model and both caller row sets. An engine that predates it
        answers -32601 through the catch-all below, immediately, so a client can
        detect absence in one round trip instead of waiting for a timeout. }
      else if Method = 'draglint/hoverBundle' then HandleHoverBundle(Id, Params)
      else if Method = 'draglint/callerCounts' then HandleCallerCounts(Id, Params)
      else if Method = 'draglint/usages' then HandleUsages(Id, Params)
      else if Method = 'textDocument/completion' then HandleCompletion(Id, Params)
      else if Method = 'textDocument/signatureHelp' then HandleSignatureHelp(Id, Params)
      else if Method = 'textDocument/didOpen' then HandleDidOpenOrSave(Params)
      else if Method = 'textDocument/didSave' then HandleDidOpenOrSave(Params)
      else if Method = 'textDocument/didChange' then HandleDidChange(Params)
      else if Method = 'textDocument/didClose' then HandleDidClose(Params)
      else if (Id <> nil) and (Method <> '') then SendError(Id, -32601, 'method not found: ' + Method);
    finally
      Msg.Free;
    end; // try
  end; // while
end; // procedure

end.
