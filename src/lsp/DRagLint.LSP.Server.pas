unit DRagLint.LSP.Server;

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.Generics.Collections  { v(P7): the per-file source cache in HandleHoverBundle }
  , System.SyncObjs  { LSP-1 CORE: the re-index watcher's lock + stop event }
  , System.JSON
  , System.NetEncoding
  , Winapi.Windows
  , TreeSitter
  , TreeSitterLib
  , DRagLint.Core    .Model
  , DRagLint.Core    .Versions // dl:unit DRagLint.Core.Versions accepted -- INDEXER_FINGERPRINT_META_KEY: the stamp each --db is reported with at startup; LIBRARY_RESOLVE_STATE_META_KEY: the lf-marker key
  , DRagLint.Core    .ControlChannel { W3: the maintenance control channel the lsp host cooperates with in Run }
  , DRagLint.Core    .Interfaces
  , DRagLint.Core    .Encoding
  , DRagLint.Core    .LintBudget { C13: LintChildTimeoutMs -- the --full-rules child budget, shared with the IDE plugin }
  , DRagLint.Storage .SQLite
  , DRagLint.Parser  .Delphi13
  , DRagLint.Core    .Indexer  { INBOX-lsp-hover-unindexed-file: TIndexer.IndexFile builds the ephemeral single-unit index }
  , DRagLint.Hover   .Renderer
  , DRagLint.Hover   .Returns
  , DRagLint.Resolver.TypeAt
  , DRagLint.Lint    .Linter
  , DRagLint.LSP     .Completion
  , DRagLint.LSP     .SyntaxTree  { C15: ParseDelphiUtf8 -- the preprocessed parse }
  , DRagLint.Core    .LiveDocs  { v(live-buffer): unsaved editor text, consulted before disk }
  , DRagLint.Doc     .Facts     { v(ADP2 T9): TDocFactsBuilder.Build -- hover's Phase-2 facts }
  , DRagLint.Doc     .Regions   { v(ADP2 T9): TDocRegions.FormatPhase2FactLines -- the shared formatter }
  , DRagLint.Index   .Manifest  { v(ADP2 T9): LoadDocComplexityMin -- same threshold `document` uses }
  , DRagLint.Query   .Callers   { v(hover bundle): the shared caller queries the CLI also renders from }
  , DRagLint.Query   .HoverModel{ v(hover bundle): the shared model assembly `hover --format json` uses }
  , DRagLint.LSP     .Context   { S0: ILspServerContext + the feature registry }
  , DRagLint.Project .ContextFile { LSP-1 CORE: .dlcontext.json + central context defaults }
  , DRagLint.Lint    .TargetCompiler { 1.38: the target-compiler gate of each file's diagnostics }
  , DRagLint.Charts  .Index     { 151 CF: FExcIndex -- the Raises: line's open index }
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
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.LSP.Server.pas) ?, DRagLint.LSP.Server.TLSPServer.ComputeHover (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ComputeHoverAt (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ComputeHoverMarkdown (DRagLint.LSP.Server.pas) ?, DRagLint.LSP.Server.TLSPServer.HandleHover (DRagLint.LSP.Server.pas) ? (+1 more)</para>
  /// <para>Used in units: DRagLint.LSP.Server</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THoverComputation = record
    MdValue  : string      ;
    HasSymbol: Boolean     ;
    Sel      : TSymbol     ;
    Store    : ISymbolStore;
    /// <summary>Wave 149 LX: the document the hover was asked for, so hoverBundle can name the
    /// file's extra stores (HoverExtraStores) the same way the markdown did.</summary>
    Path     : string      ;
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

  /// <summary>Which indexed symbol a cursor position means, before anything
  /// is rendered: the selection half of hover, shared with ResolveSymbolAt so
  /// the two can never pick different symbols for one position.</summary>
  /// <remarks>
  /// <para>Sel and HitStore belong together: further queries about Sel must
  /// run against HitStore. Symbols is every same-named candidate in HitStore.</para>
  /// <para>Narrowed is True when Sel was picked by the cursor itself (on its
  /// declaration, its implementation, a forward stub, or via TTypeAtResolver
  /// at a call site); False when Sel is merely the first candidate.</para>
  /// <para>HaveOwnerFloor: the resolver found the owner TYPE but not the
  /// member; OwnerFloorType is that type and Sel is NOT the hovered symbol.</para>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.LSP.Server.pas) ?, DRagLint.LSP.Server.TLSPServer.ComputeHoverAt (DRagLint.LSP.Server.pas) ?, DRagLint.LSP.Server.TLSPServer.ResolveSymbolAt (DRagLint.LSP.Server.pas) ?, DRagLint.LSP.Server.TLSPServer.SelectSymbolAt (DRagLint.LSP.Server.pas)</para>
  /// <para>Used in units: DRagLint.LSP.Server</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSymbolSelection = record
    Symbols       : TArray<TSymbol>;
    HitStore      : ISymbolStore   ;
    Sel           : TSymbol        ;
    Narrowed      : Boolean        ;
    OnForwardStub : Boolean        ;
    HaveOwnerFloor: Boolean        ;
    OwnerFloorType: TSymbol        ;
    /// <summary>151 CF (LX-5 hover cost): the TTypeAtResolver.Resolve answer SelectSymbolAt
    /// computed for this position, valid only while HasTypeAt is True. The undocumented-symbol
    /// branch of ComputeHoverAt asks the SAME question (same stores, path, line, column), so it
    /// reuses this instead of resolving twice -- measured 135 resolves for 100 hovers on a CLIENT
    /// copy, each one an index round-trip of several queries.</summary>
    HasTypeAt     : Boolean        ;
    TypeAt        : TTypeAtResult  ;
  end;

  /// <summary>Which precedence step decided a file's project context (spec 1b):
  /// startup args, the client/IDE, the owning .dproj, a .dlcontext.json (only
  /// when no .dproj exists), the central defaults, or nothing (placeholder).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.LSP.Server.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TLspContextSource = (lcsStartup, lcsClient, lcsDproj, lcsContextFile, lcsDefaults, lcsPlaceholder);

  /// <summary>The resolved build context of one source file -- what the Delphi
  /// IDE would call the active project and platform for it.</summary>
  /// <remarks>
  /// Plain value record. Project = '' means no project is known; the
  /// answer set is then the platform library (plus an ephemeral index of the
  /// file). PlatformDefaulted = the platform came from the central defaults or
  /// the Win64 placeholder, not from the project.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.LSP.Server.pas) ?, DRagLint.LSP.Server.TLSPServer.ComputeFileContext (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ContextNotice (DRagLint.LSP.Server.pas) ?, DRagLint.LSP.Server.TLSPServer.DbSetFor (DRagLint.LSP.Server.pas) ?, DRagLint.LSP.Server.TLSPServer.FileContext (DRagLint.LSP.Server.pas) ? (+4 more)</para>
  /// <para>Used in units: DRagLint.LSP.Server</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TLspFileContext = record
    Project, Platform, Config, TargetCompiler: string;
    Source           : TLspContextSource;
    PlatformDefaulted: Boolean;
    /// <summary>`projectDb` / `libraryDb` of the .dlcontext.json that applied, or ''.</summary>
    ProjectDbOverride, LibraryDbOverride: string;
    /// <summary>A .dlcontext.json found stale (its .dproj changed) and bypassed, or ''.</summary>
    StaleContextFile: string;
    /// <summary>The other projects that also hold this file, for display, or ''. The one
    /// in Project is the first in a fixed order (manifest order for an index, nearest
    /// then path order for a project file); this names what it was chosen over.</summary>
    AlsoHeldBy: string;
  end;

  /// <summary>The authoritative DB pair for one (project, platform): the
  /// project's own index and that platform's library index; '' = none.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.LSP.Server.pas) ?, DRagLint.CLI.MakeLspContextDbResolver (DRagLint.CLI.pas) ?, DRagLint.LSP.Server.TLSPServer.Create/1 (DRagLint.LSP.Server.pas) ?, DRagLint.LSP.Server.TLSPServer.DbSetFor (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.StoreSet (DRagLint.LSP.Server.pas) ? (+5 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.LSP.Server</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TLspDbSet = record
    ProjectDb, LibraryDb: string;
  end;

  /// <summary>Resolves (project file, platform) to its DB pair with the CLI's
  /// consumer-DB logic (`resolve-dbs --project X --platform P`). AProject = ''
  /// asks for the platform library only.</summary>
  /// <param name="AProject"><!-- drag-lint:auto type -->const string</param>
  /// <param name="APlatform"><!-- drag-lint:auto type -->const string</param>
  /// <returns><!-- drag-lint:auto type -->TLspDbSet</returns>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.LSP.Server.pas), DRagLint.CLI.MakeLspContextDbResolver (DRagLint.CLI.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TLspContextDbResolver = reference to function(const AProject, APlatform: string): TLspDbSet;

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
  /// <summary><!-- drag-lint:auto sum -->Language Server Protocol over stdio with
  /// Content-Length framing. Implements the subset that's actually useful when backed by
  /// a static symbol index: initialize, shutdown, workspace/symbol,
  /// textDocument/definition, textDocument/references.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto -->v0.6 did NOT implement textDocument/didChange - files are indexed via
  /// `drag-lint index` ahead of time, and a re-index is sub-second per file.
  ///
  /// v(live-buffer) REVISITED, and the distinction the original note missed: that argument is about
  /// the INDEX, but didChange is about the CURSOR. A client's position describes its BUFFER, and
  /// the buffer diverges from disk on the first keystroke. Without an overlay every position lookup
  /// read disk, so a symbol the user could see on screen resolved to '' and hover returned null --
  /// reported 2026-08-18 for `AExceptionInfo.Assign`, typed but unsaved. didChange is now accepted
  /// (full sync) and stored in TLiveDocuments; SYMBOL RESOLUTION still comes from the index, so the
  /// original reasoning is intact -- only the text under the caret is live.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.MergeDiagnostics (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.PickupContext (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.RecordRequest (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Server (DRagLint.LSP.Proxy.Merge.pas) (+11 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.LSP.Proxy.Merge, DRagLint.LSP.Server</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
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
      { INBOX-lsp-hover-unindexed-file-resolves-library-symbol (2026-08-27).
      An EPHEMERAL, single-unit index for a hovered file that NO configured
      store owns -- a loose unit, another repo, anything open after Close All.

      WHY IT HAS TO EXIST. ComputeHover takes the first store that has the
      NAME, and the call-site safety net (TTypeAtResolver.Resolve) anchors to
      the store that OWNS the hovered file. With no owner there is nothing to
      anchor to, so hovering `Apply` in a loose file rendered
      Bde.DBTables.TDataSetUpdateObject.Apply -- measured 0 hits in DataCopy's
      index, 192 in library-Win64, and the file itself in neither. Confidently
      wrong, with no wording anywhere saying the answer came from a different
      program.

      SCOPE IS ONE UNIT, and that is the owner's ruling, not an optimisation:
      a loose file can sit in a directory of thousands, and hover must stay
      interactive. The store is PREPENDED, never substituted, so every library
      answer a loose file legitimately needs still arrives (guarded as NC1 in
      run_lsp_hover_unindexed_file.ps1).

      CACHE KEY is path + last-write time, so repeated hovers in the same file
      cost one parse; evicted on didClose and on Destroy. It indexes what is
      ON DISK -- TIndexer reads the file itself and knows nothing of
      TLiveDocuments -- so symbols typed since the last save are not in it.
      The live overlay still supplies the TEXT under the caret, which is the
      half that decides which identifier was hovered. }
      FEphemStore  : ISymbolStore        ;
      FEphemFile   : string              ; { the one path FEphemStore covers }
      FEphemStamp  : TDateTime           ; { its last-write time when indexed }
      FEphemDbPath : string              ; { temp .sqlite to delete on eviction }
      FEphemSeq    : Integer             ; { never reuse a name a dead handle may still hold }
      FStdIn       : THandleStream       ;
      FLinter      : TLinter             ;
      FInitialized : Boolean             ;
      FShuttingDown: Boolean             ;
      FControl     : TControlChannel     ; { nil = no channel (every mode but lsp); not owned }
      FFullRules   : Boolean             ; { C1: --full-rules; OFF by default }
      FExceptionFacts: Boolean           ; { D1 (wave 148): Raises: hover line + exception code lens; ON by default, lsp --no-exception-facts }
      { 151 CF (LX-5 hover cost): the last tree IdentifierAtPosition parsed, keyed by the path
        and the PREPROCESSED bytes the parser saw (so a context switch that changes the active
        IFDEF branches, or an edit, is a miss). Owned; freed on replacement and in Destroy.
        Main-thread only, like every hover. See IdentTreeFor. }
      FIdentTree    : TTSTree            ;
      FIdentTreePath: string             ;
      FIdentTreePre : TBytes             ;
      { 151 CF (LX-5 hover cost): the index ExceptionFactLines reads the Raises: line from,
        kept open for the last DB path instead of opened per hover. Owned; dropped when that
        DB is re-indexed (ReindexFinished) and in Destroy. Main thread only. }
      FExcIndex     : TChartsIndex       ;
      FExcIndexPath : string             ;
      FFullRulesSuperseded: Boolean      ; { the last RunFullRulesLint child was discarded because a newer save of the same file was waiting }
      FStartProject : string             ; { C15: explicit --project the CLI was started with, or '' }
      FStartPlatform: string             ; { C15: explicit --platform the CLI was started with, or '' }
      FStartupTargetCompiler  : string             ; { 1.38: explicit --target-compiler the CLI was started with, or '' }
      { S0 feature registry: one instance per registered TLspFeature class, owned;
        the method table points into it (not owned). FContext is the adapter
        every feature is handed -- see DRagLint.LSP.Context. }
      FFeatures       : TObjectList<TLspFeature>         ;
      FFeatureByMethod: TDictionary<string, TLspFeature> ;
      FContext        : ILspServerContext                ;
    strict private type
      { LSP-1 CORE: one opened (project DB, library DB) pair; Stores excludes
        the ephemeral index. }
      /// <summary><!-- drag-lint:auto sum -->LSP-1 CORE: one opened (project DB, library
      /// DB) pair; Stores excludes the ephemeral index.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Used by: declaration (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.Create/1 (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ProjectDbIncompleteReason (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.StorePathOf (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.StoreSet (DRagLint.LSP.Server.pas)</para>
      /// <para>Used in units: DRagLint.LSP.Server</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      TStoreSet = record
        Key   : string;
        Stores: TArray<ISymbolStore>;
        Paths : TArray<string>;
      end;
      { LSP-1 CORE: one background re-index of a project DB that needs re-resolve. }
      /// <summary><!-- drag-lint:auto sum -->LSP-1 CORE: one background re-index of a
      /// project DB that needs re-resolve.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Used by: declaration (DRagLint.LSP.Server.pas)</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      TReindexState = (risRunning, risDone, risFailed);
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Used by: declaration (DRagLint.LSP.Server.pas) ?, DRagLint.LSP.Server.TLSPServer.Create/1 (DRagLint.LSP.Server.pas) ?, DRagLint.LSP.Server.TLSPServer.Destroy (DRagLint.LSP.Server.pas) ?, DRagLint.LSP.Server.TLSPServer.ProjectDbIncompleteReason (DRagLint.LSP.Server.pas) ?, DRagLint.LSP.Server.TLSPServer.StartReindex (DRagLint.LSP.Server.pas) (+2 more)</para>
      /// <para>Used in units: DRagLint.LSP.Server</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      TReindexRun = record
        Db, Dproj, LogPath, Reason: string;
        State  : TReindexState;
        Process: THandle;
      end;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Used by: declaration (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.Create/1 (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.FileContext (DRagLint.LSP.Server.pas)</para>
      /// <para>Used in units: DRagLint.LSP.Server</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      TCtxEntry = record
        Ctx  : TLspFileContext;
        Stamp: string;   { the .dproj / .dlcontext.json write stamp the entry was resolved against }
        Checked: UInt64; { 148 LS: GetTickCount64 of the last stamp check of a project-less entry }
      end;
    strict private
      { LSP-1 CORE: per-file project context (SPEC.md 1b / 3). }
      FDbResolver    : TLspContextDbResolver;   { nil = the startup store list is the whole universe }
      FExplicitDbs   : Boolean;                 { --db was given: those DBs are the authoritative universe }
      FClientProject : string;
      FClientPlatform: string;
      FClientConfig  : string;
      FClientCtx     : TProjectContext;         { when the client named a .dlcontext.json }
      FHaveClientCtx : Boolean;
      FDefaults      : TContextDefaults;
      FDefaultsRead  : Boolean;
      FSets          : TList<TStoreSet>;        { LRU, most recent first, at most LSP_STORE_SET_LRU }
      FCtxCache      : TDictionary<string, TCtxEntry>;
      FNoticed       : TDictionary<string, Byte>; { lower(path or folder)|reason already shown }
      FNoticeWarns   : Boolean;                   { the last ContextNotice text holds a warning-level reason }
      FNearProjects  : TDictionary<string, TArray<string>>; { lower(folder) -> project files in and just under it }
      FNearStamps    : TDictionary<string, string>;          { 148 LS: lower(folder) -> the NearStamp its FNearProjects entry was listed at }
      FProjectUnits  : TObjectDictionary<string, TDictionary<string, Byte>>; { lower(project)|stamp -> lower(listed unit paths) }
      FPending       : TObjectList<TJSONObject>;  { notifications queued for the stdio loop }
      FQueueNotices  : Boolean;                   { True only inside Run: proxy mode never writes to stdout }
      FNoticeSink    : TProc<string>;           { proxy mode: where queued notifications go (the relay's client writer); nil = stdout via SendRawNotification }
      FProxyPaths    : TList<string>;           { proxy mode: files announced, re-announced when a re-index finishes }
      FLastOpenPath  : string;
      FResolved      : TDictionary<string, TLspDbSet>; { project|platform -> FDbResolver's answer }
      { LSP-1 CORE (owner ruling 2026-10-28): a project DB that needs re-resolve
        is re-indexed by a SEPARATE engine process, at most one run per DB, never
        retried after a failure. The watcher thread holds FWorkLock while it
        swaps stores, so it never interleaves with a request Run is answering. }
      FWorkLock      : TCriticalSection;
      FStopEvent     : TEvent;
      FReindex       : TDictionary<string, TReindexRun>; { lower(db) -> run }
      FReindexThreads: TObjectList<TThread>;
      FOpenDocs      : TDictionary<string, string>;      { lower(path) -> uri of every open document }
      { 1.38 target compiler: the client's targetCompiler (initializationOptions /
        draglint.setContext / didChangeConfiguration), the last gate built (one
        catalog walk per distinct target) and the target each open document's
        diagnostics were last published under. }
      FClientTarget   : string;
      FTargetGate     : TTargetRuleGate;
      FPublishedTarget: TDictionary<string, Integer>;    { lower(path) -> CompilerVersion }
      { Yield (INBOX-ide-hang-on-slow-engine section 2): messages read while a
        long request yielded, to be dispatched by Run before its next read, in
        arrival order. FInputEnded: such a read hit EOF / a cancelled read. }
      FDeferred       : TQueue<TJSONObject>              ;
      FInputEnded     : Boolean                          ;
      FYielding       : Boolean                          ;
      { 1.38: resolves APath's target compiler (startup > lint config > context),
        publishes it (SetActiveTargetCompiler) and returns its gate; AError <> ''
        when the winning token is invalid -- the gate is then the default's. }
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ACtx"><!-- drag-lint:auto type -->const TLspFileContext</param>
      /// <param name="AError"><!-- drag-lint:auto type -->out string</param>
      /// <returns><!-- drag-lint:auto -->TTargetRuleGate -- Observed: FTargetGate.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto -->1.38: resolves APath's target compiler (startup &gt; lint config
      /// &gt; context), publishes it (SetActiveTargetCompiler) and returns its gate; AError
      /// &lt;&gt; '' when the winning token is invalid -- the gate is then the default's.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ContextNotice (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.PublishDiagnostics (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.RepublishRetargeted (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Lint.TargetCompiler.ResolveTargetCompiler, DRagLint.Lint.TargetCompiler.SetActiveTargetCompiler, DRagLint.LSP.Completion.TLspCompletion.BuildTargetGate, DRagLint.LSP.Completion.TLspCompletion.LintConfigTargetCompiler, ExtractFileExt, SameText</para>
      /// <para>Reads: FStartupTargetCompiler, FTargetGate   Writes: FTargetGate</para>
      /// <seealso cref="DRagLint.Lint.TargetCompiler.ResolveTargetCompiler"/>
      /// <seealso cref="DRagLint.Lint.TargetCompiler.SetActiveTargetCompiler"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildTargetGate"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.LintConfigTargetCompiler"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  TargetGateFor(const APath: string; const ACtx: TLspFileContext; out AError: string): TTargetRuleGate;
      { 1.38: re-publishes every open document whose target changed with the context. }
      /// <summary><!-- drag-lint:auto sum -->1.38: re-publishes every open document whose
      /// target changed with the context.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ApplyClientContext (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.FileContext, DRagLint.LSP.Server.TLSPServer.FileFromUri, DRagLint.LSP.Server.TLSPServer.PublishDiagnostics, DRagLint.LSP.Server.TLSPServer.TargetGateFor</para>
      /// <para>Reads: FOpenDocs, FPublishedTarget</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.PublishDiagnostics"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.TargetGateFor"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure RepublishRetargeted;
      /// <param name="ADb"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ADproj"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ContextNotice (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: CloseHandle, CreateFile, CreateProcess, Default, DRagLint.LSP.Server.TLSPServer.ReindexFinished, ExtractFileExt, FillChar, Format, GetEnvironmentVariable, LowerCase (+7 more)</para>
      /// <para>Complexity: 12 (cyclomatic, outer body), 87 lines (full implementation)</para>
      /// <para>Reads: FReindex, FStopEvent, FWorkLock, FReindexThreads</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ReindexFinished"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure StartReindex(const ADb, ADproj: string);
      /// <param name="AKey"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.StartReindex (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: CloseHandle, DRagLint.Convert.PropTree.ClearPropertyDeclaredTypeCache, DRagLint.LSP.Server.LastLogLine, DRagLint.LSP.Server.TLSPServer.FileFromUri, DRagLint.LSP.Server.TLSPServer.FlushPending, DRagLint.LSP.Server.TLSPServer.OpenReaderStore, DRagLint.LSP.Server.TLSPServer.PublishDiagnostics, DRagLint.LSP.Server.TLSPServer.QueueContextNotification, DRagLint.LSP.Server.TLSPServer.StoresForFile, Format, GetExitCodeProcess, SameText, Writeln</para>
      /// <para>Complexity: 10 (cyclomatic, outer body), 65 lines (full implementation)</para>
      /// <para>Reads: FReindex, FSets, FStorePaths, FStores, FCtxCache, FProxyPaths, FOpenDocs   Writes: FStores, FStore</para>
      /// <para>Catches: Exception (swallowed)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Convert.PropTree.ClearPropertyDeclaredTypeCache"/>
      /// <seealso cref="DRagLint.LSP.Server.LastLogLine"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FlushPending"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.OpenReaderStore"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ReindexFinished(const AKey: string);
      /// <param name="AUri"><!-- drag-lint:auto type -->const string</param>
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.HandleDidOpenOrSave (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.RefreshFileFromDisk (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ReindexFinished (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.RepublishRetargeted (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Lint.TargetCompiler.TTargetRuleGate.Drops, DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics/4, DRagLint.LSP.Completion.TLspCompletion.BuildMissingUsesDiagnostics, DRagLint.LSP.Completion.TLspCompletion.DiagnosticsFromLintJson, DRagLint.LSP.Server.TLSPServer.AnyStoreOwns, DRagLint.LSP.Server.TLSPServer.EnsureLinter, DRagLint.LSP.Server.TLSPServer.FileContext, DRagLint.LSP.Server.TLSPServer.RunFullRulesLint, DRagLint.LSP.Server.TLSPServer.SendRawNotification, DRagLint.LSP.Server.TLSPServer.StoresForFile, DRagLint.LSP.Server.TLSPServer.TargetGateFor, Format, LowerCase, SameText, Writeln</para>
      /// <para>Complexity: 15 (cyclomatic, outer body), 75 lines (full implementation)</para>
      /// <para>Reads: FPublishedTarget, FStore, FFullRules, FFullRulesSuperseded</para>
      /// <seealso cref="DRagLint.Lint.TargetCompiler.TTargetRuleGate.Drops"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildMissingUsesDiagnostics"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.DiagnosticsFromLintJson"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure PublishDiagnostics(const AUri, APath: string);
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: ''.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.CallerSearchStores (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ComputeExceptionFactsAt (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ComputeExceptionLenses (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ExceptionFactLines (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HoverExtraStores (DRagLint.LSP.Server.pas)</para>
      /// <para>Reads: FStores, FStorePaths, FSets</para>
      /// <para>Effect-free (proven)</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  StorePathOf(const AStore: ISymbolStore): string;
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto type -->TArray&lt;ISymbolStore&gt;</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.HandleHoverBundle (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.IsLibraryPath, DRagLint.LSP.Server.TLSPServer.StorePathOf, DRagLint.LSP.Server.TLSPServer.StoresForFile</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.IsLibraryPath"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.StorePathOf"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.StoresForFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  CallerSearchStores(const APath: string): TArray<ISymbolStore>;
      /// <returns><!-- drag-lint:auto -->TContextDefaults -- Observed: FDefaults.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ComputeFileContext (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.DbSetFor (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: Default, DRagLint.LSP.Server.LibrariesVisibleToThisEngine, DRagLint.Project.ContextFile.TryLoadContextDefaults</para>
      /// <para>Reads: FDefaultsRead, FDefaults   Writes: FDefaultsRead, FDefaults</para>
      /// <seealso cref="DRagLint.LSP.Server.LibrariesVisibleToThisEngine"/>
      /// <seealso cref="DRagLint.Project.ContextFile.TryLoadContextDefaults"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  Defaults: TContextDefaults;
      /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: '';
      /// FormatDateTime('yyyymmddhhnnsszzz', TFile.GetLastWriteTime(AFile)).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.FileContext (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ProjectListsUnit (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: FormatDateTime</para>
      /// <para>Catches: Exception (swallowed)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  DprojStamp(const AFile: string): string;
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->TLspFileContext -- Observed:
      /// Default(TLspFileContext).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.FileContext (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: ChangeFileExt, Default, DRagLint.LSP.Server.MarkerlessDprojPlatform, DRagLint.LSP.Server.TLSPServer.Defaults, DRagLint.LSP.Server.TLSPServer.FindListingProject, DRagLint.LSP.Server.TLSPServer.OtherOwningStores, DRagLint.LSP.Server.TLSPServer.StartupLibraryPlatformOf, DRagLint.Project.ContextFile.ContextFileFor, DRagLint.Project.ContextFile.FindProjectContextForUnit, DRagLint.Project.DefineProfile.ReadDelphiLspDefines, DRagLint.Project.DefineProfile.ReadDprojActiveSelection, DRagLint.Project.DefineProfile.TProjectProfileCache.BuildForFile, ExpandFileName, ExtractFileExt, SameText</para>
      /// <para>Complexity: 41 (cyclomatic, outer body), 115 lines (full implementation)</para>
      /// <para>Reads: FStartProject, FClientProject, FHaveClientCtx, FClientCtx, FStartPlatform, FClientPlatform, FClientConfig, FClientTarget</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.LSP.Server.MarkerlessDprojPlatform"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Defaults"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FindListingProject"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.OtherOwningStores"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.StartupLibraryPlatformOf"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  ComputeFileContext(const APath: string): TLspFileContext;
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed:
      /// LowerCase(ExtractFileName(APath)).StartsWith('library-').</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.CallerSearchStores (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HoverExtraStores (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.OtherOwningStores (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.OwningStartupProjectDb (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.StartupLibraryPlatformOf (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: ExtractFileName, LowerCase</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  IsLibraryPath(const APath: string): Boolean;
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: ''; FStorePaths[I].</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DbSetFor (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.LSP.Server.TLSPServer.IsLibraryPath</para>
      /// <para>Reads: FStores, FStorePaths</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.IsLibraryPath"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  OwningStartupProjectDb(const APath: string): string;
      /// <param name="ADir"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto type -->TArray&lt;string&gt;</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.FindListingProject (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.IsProjectSearchSkipped, DRagLint.LSP.Server.NearStamp, DRagLint.LSP.Server.ProjectFilesIn, ExtractFileName, LowerCase, Writeln</para>
      /// <para>Reads: FNearProjects, FNearStamps</para>
      /// <para>Catches: Exception (swallowed)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.LSP.Server.IsProjectSearchSkipped"/>
      /// <seealso cref="DRagLint.LSP.Server.NearStamp"/>
      /// <seealso cref="DRagLint.LSP.Server.ProjectFilesIn"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  NearProjects(const ADir: string): TArray<string>;
      /// <summary><!-- drag-lint:auto sum -->Does the project file LIST this exact unit
      /// path? A .dproj's DCCReference, a .dpr's `in '...'`, each resolved from the
      /// project's own folder -- so a relocated checkout still matches, and a same-named
      /// unit elsewhere never does. Memoised per project + stamp: the files of one folder
      /// share one read.</summary>
      /// <param name="AProject"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AUnitLower"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False;
      /// Units.ContainsKey(AUnitLower).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.FindListingProject (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.DprojStamp, ExpandFileName, ExtractFileExt, ExtractFilePath, LowerCase, SameText, Writeln</para>
      /// <para>Reads: FProjectUnits</para>
      /// <para>Catches: Exception (swallowed)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.DprojStamp"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  ProjectListsUnit(const AProject, AUnitLower: string): Boolean;
      /// <summary><!-- drag-lint:auto sum -->1.44 lspctx: the project of a unit no index
      /// holds -- a worktree, a copy, a unit not indexed yet, an index mid-rebuild.
      /// Climbs from the unit's folder to the repository root (at most
      /// LSP_PROJECT_SEARCH_LEVELS without one), looking at each level in the folder and
      /// its immediate sub-folders, because a project is often a SIBLING of the unit's
      /// folder (src\cli\drag-lint.dproj, src\report\X.pas), not an ancestor. The nearest
      /// level with a project LISTING the unit wins, then path order; AOthers names the
      /// rest. Only ever a project that lists this exact path: never a guess.</summary>
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AOthers"><!-- drag-lint:auto type -->out string</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: ''; P.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ComputeFileContext (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.IsRepositoryRoot, DRagLint.LSP.Server.TLSPServer.NearProjects, DRagLint.LSP.Server.TLSPServer.ProjectListsUnit, ExcludeTrailingPathDelimiter, ExpandFileName, ExtractFileName, ExtractFilePath, LowerCase, SameText</para>
      /// <para>Mutates: AOthers (out)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.LSP.Server.IsRepositoryRoot"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.NearProjects"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ProjectListsUnit"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  FindListingProject(const APath: string; out AOthers: string): string;
      /// <summary><!-- drag-lint:auto sum -->The startup project stores holding APath
      /// other than AProject's own, by DB file name, or ''. Already-open stores, one
      /// indexed lookup each, once per file (FCtxCache).</summary>
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AProject"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto type -->string</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ComputeFileContext (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: ChangeFileExt, DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.LSP.Server.TLSPServer.IsLibraryPath, ExtractFileName, SameText</para>
      /// <para>Reads: FStores, FStorePaths</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.IsLibraryPath"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  OtherOwningStores(const APath, AProject: string): string;
      /// <summary><!-- drag-lint:auto sum -->The platform of the startup library store
      /// holding APath, or '': a library unit's platform is known even though it has no
      /// project.</summary>
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: '';
      /// Copy(ChangeFileExt(ExtractFileName(FStorePaths[I]), ''), Length(LIBRARY_PREFIX)
      /// + 1, MaxInt).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ComputeFileContext (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: ChangeFileExt, Copy, DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.LSP.Server.TLSPServer.IsLibraryPath, ExtractFileName</para>
      /// <para>Reads: FStores, FStorePaths</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.IsLibraryPath"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  StartupLibraryPlatformOf(const APath: string): string;
      /// <param name="APlatform"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: ''.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ContextNotice (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.DbSetFor (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: ChangeFileExt, ExtractFileName, SameText</para>
      /// <para>Reads: FStorePaths</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  StartupLibraryFor(const APlatform: string): string;
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ACtx"><!-- drag-lint:auto type -->const TLspFileContext</param>
      /// <returns><!-- drag-lint:auto -->TLspDbSet -- Observed: Default(TLspDbSet).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ContextFooter (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.QueueContextNotification (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.RunFullRulesLint (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.StoresForFile (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: Default, DRagLint.LSP.Server.DefaultsLibraryDbFor, DRagLint.LSP.Server.TLSPServer.Defaults, DRagLint.LSP.Server.TLSPServer.OwningStartupProjectDb, DRagLint.LSP.Server.TLSPServer.StartupLibraryFor, FDbResolver, LowerCase, Writeln</para>
      /// <para>Complexity: 21 (cyclomatic, outer body), 51 lines (full implementation)</para>
      /// <para>Reads: FDbResolver, FExplicitDbs, FResolved</para>
      /// <para>Catches: Exception (swallowed)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.LSP.Server.DefaultsLibraryDbFor"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Defaults"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.OwningStartupProjectDb"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.StartupLibraryFor"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  DbSetFor(const APath: string; const ACtx: TLspFileContext): TLspDbSet;
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->ISymbolStore -- Observed: nil; S.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.Create/1 (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ReindexFinished (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.StoreSet (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetMetaValue, DRagLint.Core.Interfaces.ISymbolStore.IsSchemaCurrent, DRagLint.Storage.Schema.IsSchemaReadable, DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create, Format, Writeln</para>
      /// <para>Catches: Exception (swallowed)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetMetaValue"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.IsSchemaCurrent"/>
      /// <seealso cref="DRagLint.Storage.Schema.IsSchemaReadable"/>
      /// <seealso cref="DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  OpenReaderStore(const APath: string): ISymbolStore;
      /// <param name="ADbs"><!-- drag-lint:auto type -->const TLspDbSet</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;ISymbolStore&gt; -- Observed:
      /// E.Stores.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ContextFooter (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.StoresForFile (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.OpenReaderStore, LowerCase, SameText</para>
      /// <para>Complexity: 15 (cyclomatic, outer body), 38 lines (full implementation)</para>
      /// <para>Reads: FSets, FStorePaths, FStores</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.OpenReaderStore"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  StoreSet(const ADbs: TLspDbSet): TArray<ISymbolStore>;
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ACtx"><!-- drag-lint:auto type -->const TLspFileContext</param>
      /// <param name="ADbs"><!-- drag-lint:auto type -->const TLspDbSet</param>
      /// <param name="AQueue"><!-- drag-lint:auto type -->Boolean</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: ''; ContextNotice(APath,
      /// ACtx, ADbs, AQueue); Acc.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ContextFooter (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ContextNotice (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.QueueContextNotification (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.StoresForFile (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Lint.TargetCompiler.CompilerDisplayName, DRagLint.LSP.Server.TLSPServer.ContextNotice, DRagLint.LSP.Server.TLSPServer.ContextNotice.Add, DRagLint.LSP.Server.TLSPServer.ContextNotice.AddAdvice, DRagLint.LSP.Server.TLSPServer.ProjectDbIncompleteReason, DRagLint.LSP.Server.TLSPServer.StartReindex, DRagLint.LSP.Server.TLSPServer.StartupLibraryFor, DRagLint.LSP.Server.TLSPServer.TargetGateFor, DRagLint.Project.ContextFile.ContextDefaultsFile, ExtractFileDir (+6 more)</para>
      /// <para>Complexity: 25 (cyclomatic, outer body), 104 lines (full implementation)</para>
      /// <para>Reads: FExplicitDbs, FReindex, FQueueNotices   Writes: FNoticeWarns</para>
      /// <para>Recursive</para>
      /// <seealso cref="DRagLint.Lint.TargetCompiler.CompilerDisplayName"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ContextNotice.Add"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ContextNotice.AddAdvice"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ProjectDbIncompleteReason"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.StartReindex"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  ContextNotice(const APath: string; const ACtx: TLspFileContext; const ADbs: TLspDbSet; AQueue: Boolean): string;
      /// <param name="AProjectDb"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto type -->string</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ContextNotice (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetMetaValue, DRagLint.LSP.Server.JsonStrOf, ExpandFileName, GetEnvironmentVariable, LowerCase, SameText, TJSONObject, Trim</para>
      /// <para>Complexity: 16 (cyclomatic, outer body), 43 lines (full implementation)</para>
      /// <para>Reads: FReindex, FStorePaths, FStores, FSets</para>
      /// <para>Catches: Exception (swallowed)</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetMetaValue"/>
      /// <seealso cref="DRagLint.LSP.Server.JsonStrOf"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  ProjectDbIncompleteReason(const AProjectDb: string): string;
      /// <param name="AMethod"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AParams"><!-- drag-lint:auto type -->TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ContextNotice.Add (DRagLint.LSP.Server.pas) ?, DRagLint.LSP.Server.TLSPServer.ContextNotice.AddAdvice (DRagLint.LSP.Server.pas) ?, DRagLint.LSP.Server.TLSPServer.QueueContextNotification (DRagLint.LSP.Server.pas)</para>
      /// <para>Reads: FQueueNotices, FPending</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure QueueNotification(const AMethod: string; AParams: TJSONObject);
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ApplyClientContext (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleDidOpenOrSave (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ReindexFinished (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.ContextNotice, DRagLint.LSP.Server.TLSPServer.DbSetFor, DRagLint.LSP.Server.TLSPServer.FileContext, DRagLint.LSP.Server.TLSPServer.FileToUri, DRagLint.LSP.Server.TLSPServer.QueueNotification</para>
      /// <para>Reads: FQueueNotices, FNoticeWarns</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ContextNotice"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.DbSetFor"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileToUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.QueueNotification"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure QueueContextNotification(const APath: string);
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ReindexFinished (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.Run (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.SendRawNotification, FNoticeSink</para>
      /// <para>Reads: FPending, FNoticeSink</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendRawNotification"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure FlushPending;
      /// <param name="AObj"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.HandleDidChangeConfiguration (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleInitialize (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleSetContext (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: Default, DRagLint.LSP.Server.JsonStrOf, DRagLint.LSP.Server.TLSPServer.QueueContextNotification, DRagLint.LSP.Server.TLSPServer.RepublishRetargeted, DRagLint.Project.ContextFile.TryLoadProjectContext, ExpandFileName, Writeln</para>
      /// <para>Reads: FClientCtx, FCtxCache, FLastOpenPath   Writes: FHaveClientCtx, FClientCtx, FClientProject, FClientPlatform, FClientConfig, FClientTarget</para>
      /// <seealso cref="DRagLint.LSP.Server.JsonStrOf"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.QueueContextNotification"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.RepublishRetargeted"/>
      /// <seealso cref="DRagLint.Project.ContextFile.TryLoadProjectContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ApplyClientContext(const AObj: TJSONObject);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: JsonStrOf(AParams,
      /// 'command') = LSP_CMD_SET_CONTEXT.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DispatchMessage (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.JsonStrOf, DRagLint.LSP.Server.TLSPServer.ApplyClientContext, DRagLint.LSP.Server.TLSPServer.SendError, DRagLint.LSP.Server.TLSPServer.SendResult, TJSONArray, TJSONObject</para>
      /// <seealso cref="DRagLint.LSP.Server.JsonStrOf"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendError"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendResult"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  HandleSetContext(const AId: TJSONValue; const AParams: TJSONObject): Boolean;
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DispatchMessage (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.HasContextKeys, DRagLint.LSP.Server.JsonStrOf, DRagLint.LSP.Server.TLSPServer.ApplyClientContext, DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile, DRagLint.LSP.Server.TLSPServer.FileFromUri, TJSONObject</para>
      /// <seealso cref="DRagLint.LSP.Server.HasContextKeys"/>
      /// <seealso cref="DRagLint.LSP.Server.JsonStrOf"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleDidChangeConfiguration(const AParams: TJSONObject);
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto type -->string</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.WithContextFooter (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.LSP.Server.TLSPServer.ContextNotice, DRagLint.LSP.Server.TLSPServer.DbSetFor, DRagLint.LSP.Server.TLSPServer.FileContext, DRagLint.LSP.Server.TLSPServer.StoreSet, ExtractFileName, Format</para>
      /// <para>Reads: FStores</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ContextNotice"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.DbSetFor"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.StoreSet"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  ContextFooter(const APath: string): string;
      { battery-138: hover and draglint/hoverBundle append the SAME footer, so the
        bundle's markdown stays byte-identical to textDocument/hover (R5). }
      /// <summary><!-- drag-lint:auto sum -->battery-138: hover and draglint/hoverBundle
      /// append the SAME footer, so the bundle's markdown stays byte-identical to
      /// textDocument/hover (R5).</summary>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <param name="AMd"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto type -->string</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.HandleHover (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleHoverBundle (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.ContextFooter, DRagLint.LSP.Server.TLSPServer.PositionParams</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ContextFooter"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.PositionParams"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  WithContextFooter(const AParams: TJSONObject; const AMd: string): string;
      /// <summary>Dispatches one JSON-RPC message to its handler.</summary>
      /// <param name="AMsg">The message; not freed here, the caller owns it.</param>
      /// <returns>False for `exit` (the loop must end), True otherwise.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.Run (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.YieldToPendingRequests (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Context.TLspFeature.Handle, DRagLint.LSP.Server.TLSPServer.HandleCallerCounts, DRagLint.LSP.Server.TLSPServer.HandleCodeAction, DRagLint.LSP.Server.TLSPServer.HandleCompletion, DRagLint.LSP.Server.TLSPServer.HandleDefinition, DRagLint.LSP.Server.TLSPServer.HandleDidChange, DRagLint.LSP.Server.TLSPServer.HandleDidChangeConfiguration, DRagLint.LSP.Server.TLSPServer.HandleDidChangeWatchedFiles, DRagLint.LSP.Server.TLSPServer.HandleDidClose, DRagLint.LSP.Server.TLSPServer.HandleDidOpenOrSave (+13 more)</para>
      /// <para>Returns: True; False</para>
      /// <para>Complexity: 28 (cyclomatic, outer body), 60 lines (full implementation)</para>
      /// <para>Reads: FFeatureByMethod, FContext</para>
      /// <para>Catches: Exception (swallowed)</para>
      /// <seealso cref="DRagLint.LSP.Context.TLspFeature.Handle"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.HandleCallerCounts"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.HandleCodeAction"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.HandleCompletion"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.HandleDefinition"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function DispatchMessage(const AMsg: TJSONObject): Boolean;
      /// <summary>True when a whole message can be read from stdin without
      /// blocking: a pipe with bytes waiting (PeekNamedPipe) or a file not at
      /// its end. A console or any other handle answers False -- never yield.</summary>
      /// <returns>True when a read would not block; False after FInputEnded.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.YieldToPendingRequests (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: GetFileType, PeekNamedPipe</para>
      /// <para>Returns: False; PeekNamedPipe(H, nil, 0, nil, @Avail, nil) and (Avail &gt; 0); FStdIn.Position &lt; FStdIn.Size</para>
      /// <para>Reads: FInputEnded, FStdIn</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function InputPending: Boolean;
      /// <summary>Called by a long request between its batches: reads every
      /// message already waiting and dispatches the hover-class ones at once,
      /// deferring anything else (and everything after it) to Run.</summary>
      /// <remarks>
      /// Single-threaded: it runs INSIDE the long handler, so a served
      /// hover sees the same stores. Order-preserving: once one message is
      /// deferred no later one is served early, so a hover can never overtake
      /// a didChange it was sent after. Not re-entrant (FYielding).
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ComputeCallerCounts (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.WaitFullRulesChild (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.DispatchMessage, DRagLint.LSP.Server.TLSPServer.InputPending, DRagLint.LSP.Server.TLSPServer.ReadMessage, DRagLint.LSP.Server.TLSPServer.SendError, Writeln</para>
      /// <para>Complexity: 11 (cyclomatic, outer body), 53 lines (full implementation)</para>
      /// <para>Reads: FYielding, FDeferred   Writes: FYielding, FInputEnded</para>
      /// <para>Catches: Exception (swallowed)</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.DispatchMessage"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.InputPending"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ReadMessage"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendError"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure YieldToPendingRequests;
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: (FControl &lt;&gt; nil) and
      /// FControl.StandDownRequested.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.Run (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.ControlChannel.TControlChannel.StandDownRequested</para>
      /// <para>Reads: FControl</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.StandDownRequested"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function StandDownTaken: Boolean;
      /// <returns><!-- drag-lint:auto -->TJSONObject -- Observed: ReadMessage.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.Run (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.ControlChannel.TControlChannel.EnterRead, DRagLint.Core.ControlChannel.TControlChannel.LeaveRead, DRagLint.LSP.Server.TLSPServer.ReadMessage</para>
      /// <para>Reads: FControl</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.EnterRead"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.LeaveRead"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ReadMessage"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ReadMessageGuarded: TJSONObject;
      /// <summary>Does any CONFIGURED store hold a files row for this path?</summary>
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
      /// <remarks>
      /// The same probe TTypeAtResolver.Resolve uses to pick its
      /// Primary store, run against the already-open stores. Deliberately NOT
      /// DRagLint.Storage.FileMembership.DbContainsFile, which opens a second
      /// connection per database and would put a file-open on the hover path
      /// for the common, owned case.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.PublishDiagnostics (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath</para>
      /// <para>Reads: FStores</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  AnyStoreOwns(const APath: string): Boolean;
      /// <summary>Release the ephemeral index and delete its temp database.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.Destroy (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleDidChangeWatchedFiles (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleDidClose (DRagLint.LSP.Server.pas)</para>
      /// <para>Reads: FEphemDbPath   Writes: FEphemStore, FEphemFile, FEphemStamp, FEphemDbPath</para>
      /// <para>Catches: Exception (empty)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DropEphemeralStore;
      /// <summary>Index APath alone into a fresh ephemeral store.</summary>
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AStamp"><!-- drag-lint:auto type -->TDateTime</param>
      /// <returns>True when the store now holds a files row for APath.</returns>
      /// <remarks>
      /// Never raises: a failure leaves the caller with the ordinary
      /// store list, i.e. the old behaviour. A wrong hover is a defect; a dead
      /// server is a worse one.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.StoresForFile (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: AssignFile, CloseFile, DRagLint.Core.Indexer.TIndexer.ApplyInheritedFieldFacts, DRagLint.Core.Indexer.TIndexer.Create/2, DRagLint.Core.Indexer.TIndexer.IndexFile, DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.Core.Interfaces.ISymbolStore.Migrate, DRagLint.Core.Interfaces.ISymbolStore.ResolveAncestry, DRagLint.Core.Interfaces.ISymbolStore.ResolveHelpers, DRagLint.Core.Interfaces.ISymbolStore.ResolveUnitUseTargets (+9 more)</para>
      /// <para>Returns: False; True</para>
      /// <para>Reads: FEphemSeq, FEphemDbPath   Writes: FEphemSeq, FEphemDbPath, FEphemStore, FEphemFile, FEphemStamp</para>
      /// <para>Catches: Exception (empty); Exception (swallowed)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.ApplyInheritedFieldFacts"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFile"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.Migrate"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  BuildEphemeralStore(const APath: string; AStamp: TDateTime): Boolean;
    public { proxy notices }
      /// <summary>Proxy mode: lets this server queue draglint/context and window/showMessage notifications and auto re-index a DB marked needs-re-resolve, delivering every notification through ASink instead of stdout.</summary>
      /// <param name="ASink">Receives the notification as one JSON-RPC text (no framing); called under the work lock, from the announcing worker or a re-index watcher thread. Must be thread-safe.</param>
      /// <remarks>
      /// Direct mode (Run) is unchanged and never calls this. A started re-index is keyed by DB, so it runs at most once per DB and is never retried.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen (DRagLint.LSP.Proxy.Merge.pas)</para>
      /// <para>Writes: FNoticeSink, FQueueNotices</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure EnableProxyNotices(const ASink: TProc<string>);
      /// <summary>Proxy mode: announces APath's context (draglint/context with its notice) to the sink and starts the background re-index when its project DB needs one.</summary>
      /// <param name="APath">Full path of the document the client opened.</param>
      /// <remarks>
      /// No-op unless EnableProxyNotices was called. Call from the merge worker, never from the relay pumps.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen (DRagLint.LSP.Proxy.Merge.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.FlushPending, DRagLint.LSP.Server.TLSPServer.QueueContextNotification, DRagLint.LSP.Server.TLSPServer.StoresForFile</para>
      /// <para>Reads: FNoticeSink, FWorkLock, FProxyPaths   Writes: FLastOpenPath</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FlushPending"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.QueueContextNotification"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.StoresForFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure AnnounceProxyOpen(const APath: string);
    public { S0: reached by TLspServerContextAdapter; A3 fix 2: and by the merge proxy (DRagLint.LSP.Proxy.Merge), so its completion sees a file no index owns }
      /// <summary>The store list to answer a request about APath with: FStores
      /// unchanged when some store owns the file, else the ephemeral
      /// single-unit store PREPENDED to FStores.</summary>
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto type -->TArray&lt;ISymbolStore&gt;</returns>
      /// <remarks>
      /// NOT thread-safe: building or replacing the ephemeral store mutates
      /// FEphemStore / FEphemFile / FEphemStamp. Call it only from the thread
      /// that owns this server (the stdio loop, or the merge proxy's worker).
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeCompletion (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.CallerSearchStores (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ComputeCallerCounts (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ComputeDefinition (DRagLint.LSP.Server.pas) (+13 more)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore, DRagLint.LSP.Server.TLSPServer.ContextNotice, DRagLint.LSP.Server.TLSPServer.DbSetFor, DRagLint.LSP.Server.TLSPServer.FileContext, DRagLint.LSP.Server.TLSPServer.StoreSet, ExtractFileExt, LowerCase, SameText</para>
      /// <para>Complexity: 12 (cyclomatic, outer body), 42 lines (full implementation)</para>
      /// <para>Reads: FStores, FEphemStore, FEphemFile, FEphemStamp</para>
      /// <para>Catches: Exception (swallowed)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ContextNotice"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.DbSetFor"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileContext"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  StoresForFile(const APath: string): TArray<ISymbolStore>;
    strict private
      /// <summary><!-- drag-lint:auto sum -->Callers use it to let the file's OWN
      /// declaration win outright. Accumulating across every store is right for a
      /// multi-DB project, where the same name legitimately lives in several project
      /// databases; it is wrong for a loose file, where the library's namesakes are noise
      /// in front of the declaration the reader is standing on. Scoped deliberately: for
      /// a file some index DOES own, StoresForFile returns FStores unchanged, this
      /// returns False, and every request behaves exactly as it did before.</summary>
      /// <param name="AStores"><!-- drag-lint:auto type -->const TArray&lt;ISymbolStore&gt;</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: (FEphemStore &lt;&gt; nil)
      /// and (Length(AStores) &gt; 0) and (AStores[0] = FEphemStore).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ComputeDefinition (DRagLint.LSP.Server.pas)</para>
      /// <para>Reads: FEphemStore</para>
      /// <para>Effect-free (proven)</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  EphemeralLeads(const AStores: TArray<ISymbolStore>): Boolean;
      /// <returns><!-- drag-lint:auto -->TJSONObject -- Observed: nil;
      /// TJSONObject(Parsed).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ReadMessageGuarded (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.YieldToPendingRequests (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: Char, Copy, StrToIntDef, TJSONObject, Trim</para>
      /// <para>Complexity: 14 (cyclomatic, outer body), 64 lines (full implementation)</para>
      /// <para>Reads: FStdIn</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ReadMessage: TJSONObject  ;
    private { S0: the send/URI helpers TLspServerContextAdapter forwards to }
      /// <param name="AObj"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.HandleCodeAction (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleCompletion (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleHoverBundle (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleInitialize (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleShutdown (DRagLint.LSP.Server.pas) (+5 more)</para>
      /// <para>Calls: AnsiString, GetStdHandle, IntToStr, Move, WriteFile</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SendMessage        (const AObj: TJSONObject);
      /// <summary><!-- drag-lint:auto sum -->SendRawNotification sends a notification (no
      /// id) with Content-Length framing. Identical to SendMessage but semantically
      /// distinct -- used for server-pushed notifications such as
      /// textDocument/publishDiagnostics.</summary>
      /// <param name="AObj"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.FlushPending (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.PublishDiagnostics (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.PublishEmptyDiagnostics (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLspServerContextAdapter.Notify (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.SendMessage</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendMessage"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SendRawNotification(const AObj: TJSONObject);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="ACode"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="AMessage"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DispatchMessage (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleSetContext (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleUsages (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.YieldToPendingRequests (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLspServerContextAdapter.ReplyError (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.SendMessage</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendMessage"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SendError(const AId: TJSONValue; ACode: Integer; const AMessage: string);
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: PathToFileUri(APath).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.BuildRemoveUnusedSourceAction (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ComputeExceptionFactsAt (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleCodeAction (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.LocationFromRef/2 (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.LocationFromSymbol/2 (DRagLint.LSP.Server.pas) (+2 more)</para>
      /// <para>Calls: DRagLint.LSP.Completion.PathToFileUri</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.LSP.Completion.PathToFileUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function FileToUri  (const APath: string): string;
      /// <summary>Sends {jsonrpc, id, result} -- the envelope every request
      /// handler answers with.</summary>
      /// <param name="AId">The request id, cloned; nil omits the id pair (the
      /// shape the handlers have always sent).</param>
      /// <param name="AResult">CONSUMED, also when sending raises; nil sends
      /// result null.</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.HandleCallerCounts (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleDefinition (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleHover (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleReferences (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleSetContext (DRagLint.LSP.Server.pas) (+2 more)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.SendMessage</para>
      /// <para>Catches: Exception (re-raise)</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendMessage"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SendResult(const AId: TJSONValue; AResult: TJSONValue);
    strict private
      /// <summary>Reads textDocument.uri and position.line/character.</summary>
      /// <param name="AParams">The request params; may be nil.</param>
      /// <param name="APath">Receives the local path.</param>
      /// <param name="ALine0">Receives the 0-based line (0 when unparsable).</param>
      /// <param name="ACol0">Receives the 0-based column (0 when unparsable).</param>
      /// <returns>False when AParams, textDocument or position is missing.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ComputeHover (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleDefinition (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleHoverBundle (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleReferences (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.WithContextFooter (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.FileFromUri, StrToIntDef</para>
      /// <para>Returns: True</para>
      /// <para>Mutates: APath (out), ALine0 (out), ACol0 (out)</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function PositionParams(const AParams: TJSONObject; out APath: string; out ALine0, ACol0: Integer): Boolean;
      /// <summary>The selection half of hover: which symbol APath:ALine0:ACol0
      /// means, given the identifier already read there.</summary>
      /// <param name="AStores">StoresForFile(APath).</param>
      /// <param name="APath">The local path.</param>
      /// <param name="AIdent">IdentifierAtPosition at the position; not an intrinsic.</param>
      /// <param name="ALine0">0-based line.</param>
      /// <param name="ACol0">0-based column.</param>
      /// <param name="ASel">Receives the selection; valid only on True.</param>
      /// <returns>False when no store has a symbol named AIdent.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ComputeHoverAt (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ResolveSymbolAt (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Resolver.TypeAt.TTypeAtResolver.Resolve/4, SameText</para>
      /// <para>Returns: False; True</para>
      /// <para>Complexity: 25 (cyclomatic, outer body), 118 lines (full implementation)</para>
      /// <para>Mutates: ASel (out)</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
      /// <seealso cref="DRagLint.Resolver.TypeAt.TTypeAtResolver.Resolve"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function SelectSymbolAt(const AStores: TArray<ISymbolStore>; const APath, AIdent: string; ALine0, ACol0: Integer; out ASel: TSymbolSelection): Boolean;
      /// <summary>ComputeHover for an already-parsed position.</summary>
      /// <param name="APath">The local path.</param>
      /// <param name="ALine">0-based line.</param>
      /// <param name="ACol">0-based column.</param>
      /// <param name="AOut">As for ComputeHover.</param>
      /// <returns>As for ComputeHover.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ComputeHover (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ComputeHoverMarkdown (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: Copy, Default, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolDoc, DRagLint.Core.LiveDocs.TLiveDocuments.Readable, DRagLint.Core.LiveDocs.TLiveDocuments.ReadLines, DRagLint.Core.Model.IntrinsicSignature, DRagLint.Core.Model.IsCompilerIntrinsic, DRagLint.Doc.Facts.FormatHoverCalledFromLine, DRagLint.Doc.Facts.TDocFactsBuilder.Build (+20 more)</para>
      /// <para>Returns: False; True</para>
      /// <para>Complexity: 37 (cyclomatic, outer body), 281 lines (full implementation)</para>
      /// <para>Reads: FStores</para>
      /// <para>Mutates: AOut (out)</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolDoc"/>
      /// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.Readable"/>
      /// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.ReadLines"/>
      /// <seealso cref="DRagLint.Core.Model.IntrinsicSignature"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ComputeHoverAt(const APath: string; ALine, ACol: Integer; out AOut: THoverComputation): Boolean;
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DispatchMessage (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Context.TLspFeature.AddCapabilities, DRagLint.LSP.Server.HasContextKeys, DRagLint.LSP.Server.JsonStrOf, DRagLint.LSP.Server.TLSPServer.ApplyClientContext, DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile, DRagLint.LSP.Server.TLSPServer.FileFromUri, DRagLint.LSP.Server.TLSPServer.SendMessage, TJSONArray, TJSONObject</para>
      /// <para>Complexity: 15 (cyclomatic, outer body), 98 lines (full implementation)</para>
      /// <para>Reads: FFeatures, FExceptionFacts   Writes: FInitialized</para>
      /// <seealso cref="DRagLint.LSP.Context.TLspFeature.AddCapabilities"/>
      /// <seealso cref="DRagLint.LSP.Server.HasContextKeys"/>
      /// <seealso cref="DRagLint.LSP.Server.JsonStrOf"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleInitialize(const AId: TJSONValue; const AParams: TJSONObject);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DispatchMessage (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.SendMessage</para>
      /// <para>Writes: FShuttingDown</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendMessage"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleShutdown(const AId: TJSONValue);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DispatchMessage (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.ComputeWorkspaceSymbols, DRagLint.LSP.Server.TLSPServer.SendResult</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ComputeWorkspaceSymbols"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendResult"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleWorkspaceSymbol(const AId: TJSONValue; const AParams: TJSONObject);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DispatchMessage (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.ComputeDefinition, DRagLint.LSP.Server.TLSPServer.PositionParams, DRagLint.LSP.Server.TLSPServer.SendResult</para>
      /// <para>Reads: FStores</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ComputeDefinition"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.PositionParams"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendResult"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleDefinition     (const AId: TJSONValue; const AParams: TJSONObject);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DispatchMessage (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.ComputeReferences, DRagLint.LSP.Server.TLSPServer.PositionParams, DRagLint.LSP.Server.TLSPServer.SendResult, TJSONBool</para>
      /// <para>Reads: FStores</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ComputeReferences"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.PositionParams"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendResult"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleReferences     (const AId: TJSONValue; const AParams: TJSONObject);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DispatchMessage (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.ComputeHover, DRagLint.LSP.Server.TLSPServer.SendResult, DRagLint.LSP.Server.TLSPServer.WithContextFooter</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ComputeHover"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendResult"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.WithContextFooter"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
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
      /// <remarks>
      /// Extracted verbatim from HandleHover so the bundle cannot
      /// resolve a different symbol than the plain hover does for the same
      /// position. Every former `result: null` exit became `Exit(False)`; no
      /// resolution rule changed.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.HandleHover (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleHoverBundle (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: Default, DRagLint.LSP.Server.TLSPServer.ComputeHoverAt, DRagLint.LSP.Server.TLSPServer.PositionParams</para>
      /// <para>Returns: False; ComputeHoverAt(Path, Line, Col, AOut)</para>
      /// <para>Reads: FStores</para>
      /// <para>Mutates: AOut (out)</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ComputeHoverAt"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.PositionParams"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  ComputeHover         (const AParams: TJSONObject; out AOut: THoverComputation): Boolean;
      /// <summary>Answers `draglint/hoverBundle`: hover markdown, the structured
      /// hover model, and both caller row sets, in ONE reply.</summary>
      /// <param name="AId">The request id; the reply is addressed to it.</param>
      /// <param name="AParams">A textDocument/position pair, as for hover.</param>
      /// <remarks>
      /// Exists because the IDE popup previously cost four engine round
      /// trips -- this request plus three drag-lint.exe spawns that re-opened,
      /// from cold, the very indexes this server already holds open. Opens no
      /// database of its own.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DispatchMessage (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: Copy, Default, DRagLint.Core.LiveDocs.TLiveDocuments.Readable, DRagLint.Core.LiveDocs.TLiveDocuments.ReadLines, DRagLint.Hover.Renderer.BuildHoverModel, DRagLint.Hover.Renderer.RenderHoverJson/2, DRagLint.LSP.Server.AddViaKeys, DRagLint.LSP.Server.HoverResolvedCallers, DRagLint.LSP.Server.TLSPServer.CallerSearchStores, DRagLint.LSP.Server.TLSPServer.ComputeHover (+10 more)</para>
      /// <para>Complexity: 25 (cyclomatic, outer body), 235 lines (full implementation)</para>
      /// <para>Reads: FStores</para>
      /// <para>Catches: Exception (swallowed)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.Readable"/>
      /// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.ReadLines"/>
      /// <seealso cref="DRagLint.Hover.Renderer.BuildHoverModel"/>
      /// <seealso cref="DRagLint.Hover.Renderer.RenderHoverJson"/>
      /// <seealso cref="DRagLint.LSP.Server.AddViaKeys"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleHoverBundle    (const AId: TJSONValue; const AParams: TJSONObject);
      /// <summary>Answers `draglint/callerCounts`: the caller count for EVERY
      /// routine in one file, in a single round trip.</summary>
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="AParams">`{textDocument:{uri}}`.</param>
      /// <remarks>
      /// Reply: {counts:[{line,count}], implementors:[{line,count}], exceptions:[{line,title}]},
      /// every line 0-based; `exceptions` (wave 149 LX) carries the exception lens title
      /// ('raises 2 types, handles 1 type') per routine declaration line, [] under
      /// lsp --no-exception-facts -- the RAD Studio lens reads this reply, not textDocument/codeLens.
      /// Replaces one engine SPAWN PER METHOD in the plugin's code-lens
      /// cache. Measured on DataCopy's uMainZeissCopy: 77 methods x 165 ms =
      /// 12.7 s of serial process starts to label one file. Every store consulted
      /// here is already open.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DispatchMessage (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.ComputeCallerCounts, DRagLint.LSP.Server.TLSPServer.ComputeExceptionLenses, DRagLint.LSP.Server.TLSPServer.FileFromUri, DRagLint.LSP.Server.TLSPServer.SendResult, DRagLint.LSP.Server.TLSPServer.StoresForFile, DRagLint.Query.Implementors.ImplementorCountsForFile</para>
      /// <para>Pure</para>
      /// <para>Catches: Exception (re-raise)</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ComputeCallerCounts"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ComputeExceptionLenses"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendResult"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.StoresForFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleCallerCounts   (const AId: TJSONValue; const AParams: TJSONObject);
      /// <summary>Answers `draglint/usages`: the same payload
      /// `usages --format json` prints, built from the stores already open on
      /// this server.</summary>
      /// <param name="AId">JSON-RPC id; nil for a notification.</param>
      /// <param name="AParams">`name` (required), `width`, `depth`.</param>
      /// <remarks>
      /// Replaces a PROCESS SPAWN per user-initiated Find Usages --
      /// measured at 1,678 ms with the library index open versus 163 ms without,
      /// nearly all of it opening databases this server already holds. The reply
      /// shape is deliberately identical to the CLI verb's, and
      /// tests\autotest\run_lsp_usages_guard.ps1 compares the two so they cannot
      /// drift apart.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DispatchMessage (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName, DRagLint.Core.Interfaces.ISymbolStore.FindTransitiveCallers, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Model.TSymbolKindHelper.ToText, DRagLint.LSP.Server.TLSPServer.HandleUsages.AddRefRow, DRagLint.LSP.Server.TLSPServer.HandleUsages.GroupFor, DRagLint.LSP.Server.TLSPServer.SendError, DRagLint.LSP.Server.TLSPServer.SendMessage, DRagLint.Query.Callers.UsageRefsForName, LowerCase, UsageBucketIn</para>
      /// <para>Complexity: 10 (cyclomatic, outer body), 162 lines (full implementation)</para>
      /// <para>Reads: FStores</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindTransitiveCallers"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
      /// <seealso cref="DRagLint.Core.Model.TSymbolKindHelper.ToText"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.HandleUsages.AddRefRow"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleUsages         (const AId: TJSONValue; const AParams: TJSONObject);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DispatchMessage (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems/4, DRagLint.LSP.Server.TLSPServer.FileFromUri, DRagLint.LSP.Server.TLSPServer.SendMessage, DRagLint.LSP.Server.TLSPServer.StoresForFile, StrToIntDef</para>
      /// <para>Reads: FStores</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendMessage"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.StoresForFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleCompletion     (const AId: TJSONValue; const AParams: TJSONObject);
      /// <param name="AId"><!-- drag-lint:auto type -->const TJSONValue</param>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DispatchMessage (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Completion.TLspCompletion.BuildSignatureHelp, DRagLint.LSP.Server.TLSPServer.FileFromUri, DRagLint.LSP.Server.TLSPServer.SendMessage, StrToIntDef</para>
      /// <para>Reads: FStore</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildSignatureHelp"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendMessage"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleSignatureHelp  (const AId: TJSONValue; const AParams: TJSONObject);
      /// <summary>Code actions for a given range. Generates actions to insert
      /// reviewed-markers for drag-lint findings.</summary>
      /// <param name="AId">Request id from the client.</param>
      /// <param name="AParams">textDocument/codeAction request parameters (textDocument, range, context).</param>
      /// <remarks>
      /// Responds with a JSON array of CodeAction objects or null.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DispatchMessage (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.LiveDocs.TLiveDocuments.ReadBytes, DRagLint.LSP.Completion.TLspCompletion.BuildCodeActions, DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics/3, DRagLint.LSP.Completion.TLspCompletion.BuildFixActions, DRagLint.LSP.Completion.TLspCompletion.BuildMissingUsesActions, DRagLint.LSP.Completion.TLspCompletion.BuildMissingUsesDiagnostics, DRagLint.LSP.Server.CodeActionKindRequested, DRagLint.LSP.Server.TLSPServer.BuildRemoveUnusedSourceAction, DRagLint.LSP.Server.TLSPServer.EnsureLinter, DRagLint.LSP.Server.TLSPServer.FileFromUri, DRagLint.LSP.Server.TLSPServer.FileToUri, DRagLint.LSP.Server.TLSPServer.SendMessage, DRagLint.LSP.Server.TLSPServer.StoresForFile, DRagLint.LSP.UsesOnSave.TUsesOnSave.RemoveUnusedQuickfixes, StrToIntDef</para>
      /// <para>Complexity: 15 (cyclomatic, outer body), 117 lines (full implementation)</para>
      /// <para>Reads: FStore</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.ReadBytes"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildCodeActions"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildFixActions"/>
      /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildMissingUsesActions"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleCodeAction(const AId: TJSONValue; const AParams: TJSONObject);
      /// <summary>Publishes diagnostics for an opened or saved document. When no store owns the file (AnyStoreOwns false, e.g. another worktree's copy) every drag-lint finding is tagged source "drag-lint (unowned)" instead of "drag-lint", so the reader can see it is not backed by a project index; owned files keep "drag-lint".</summary>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DispatchMessage (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.LiveDocs.TLiveDocuments.Remove, DRagLint.Core.LiveDocs.TLiveDocuments.SetText, DRagLint.LSP.Server.TLSPServer.FileFromUri, DRagLint.LSP.Server.TLSPServer.PublishDiagnostics, DRagLint.LSP.Server.TLSPServer.QueueContextNotification, DRagLint.LSP.Server.TLSPServer.StoresForFile, LowerCase</para>
      /// <para>Reads: FOpenDocs   Writes: FLastOpenPath</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.Remove"/>
      /// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.SetText"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.PublishDiagnostics"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.QueueContextNotification"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleDidOpenOrSave(const AParams: TJSONObject);
      /// <summary>C1: runs `ParamStr(0) lint "AFile" --json` out-of-process and returns its stdout.</summary>
      /// <param name="AFile">Absolute path of the saved file.</param>
      /// <param name="AJson">Receives lint's stdout when the run succeeded.</param>
      /// <param name="ARule">When non-empty, passed as `--rule` so the child computes that rule only
      /// (auto uses on save asks for unused-unit-in-uses alone).</param>
      /// <returns>True when the child exited 0 or 1 with a JSON array. The budget (LintChildTimeoutMs: 8 s, 16 s for a library-owned file) is a
      /// STALL budget: a child still printing or burning CPU is never killed, however long it takes; False on a spawn failure, a stall
      /// (no output and no CPU for the whole budget; the child is terminated), a child superseded by a newer save of the same file
      /// (terminated, FFullRulesSuperseded) or a bad exit.</returns>
      /// <remarks>
      /// Blocks the calling thread while the child makes progress (hovers are served between slices). The child never inherits the
      /// server's stdin/stdout: its handles are a temp file and NUL.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.BuildRemoveUnusedSourceAction (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.PublishDiagnostics (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: CloseHandle, CreateFile, CreateProcess, DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.Core.LintBudget.LintChildTimeoutMs, DRagLint.LSP.Server.TLSPServer.DbSetFor, DRagLint.LSP.Server.TLSPServer.FileContext, DRagLint.LSP.Server.TLSPServer.WaitFullRulesChild, FillChar, GetEnvironmentVariable (+7 more)</para>
      /// <para>Returns: False; (ExitCode &lt;= 1) and AJson.TrimLeft.StartsWith('[')</para>
      /// <para>Complexity: 21 (cyclomatic, outer body), 100 lines (full implementation)</para>
      /// <para>Reads: FStores, FStorePaths, FStartProject, FStartPlatform</para>
      /// <para>Catches: Exception (swallowed)</para>
      /// <para>Mutates: AJson (out)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
      /// <seealso cref="DRagLint.Core.LintBudget.LintChildTimeoutMs"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.DbSetFor"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.WaitFullRulesChild"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function RunFullRulesLint(const AFile: string; out AJson: string; const ARule: string = ''): Boolean;
      /// <summary>True when a didSave/didOpen of AFile is already waiting in the deferred queue (a NEWER save of the same file).</summary>
      /// <param name="AFile">Absolute path of the file whose lint child is running.</param>
      /// <returns>True when that child's result would be stale on arrival.</returns>
      /// <remarks>
      /// Single-threaded: reads FDeferred, which only the stdio loop (and the yield inside it) fills.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.WaitFullRulesChild (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.FileFromUri, SameText</para>
      /// <para>Returns: False</para>
      /// <para>Reads: FDeferred</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function NewerSavePending(const AFile: string): Boolean;
      /// <summary>Waits for the lint --json child of --full-rules under a STALL budget (owner ruling 2026-11-01).</summary>
      /// <param name="AProcess">The child process.</param>
      /// <param name="AOut">The child's stdout file handle (its growth is progress).</param>
      /// <param name="ABudget">Stall budget in ms: the child is given up on only after this long with no output and no CPU.</param>
      /// <param name="AFile">The linted file; a newer save of it supersedes the child.</param>
      /// <param name="ASupersedable">False for rule-scoped runs (code action), which are never superseded.</param>
      /// <returns>True when the child exited by itself; False on a stall or when superseded (FFullRulesSuperseded tells which).
      /// The caller terminates the child on False.</returns>
      /// <remarks>
      /// Between 200 ms slices it serves waiting hovers (YieldToPendingRequests), so a slow child never freezes the editor.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.RunFullRulesLint (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.NewerSavePending, DRagLint.LSP.Server.TLSPServer.YieldToPendingRequests, GetFileSize, GetProcessTimes, PInt64, WaitForSingleObject</para>
      /// <para>Returns: False; True</para>
      /// <para>Writes: FFullRulesSuperseded</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.NewerSavePending"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.YieldToPendingRequests"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function WaitFullRulesChild(AProcess, AOut: THandle; ABudget: Cardinal; const AFile: string; ASupersedable: Boolean): Boolean;
      /// <summary>Auto uses on save: the source.removeUnusedImports action for APath, or nil.</summary>
      /// <param name="APath">The file the codeAction request names.</param>
      /// <param name="ABufferText">The editor's text, ANSI-decoded as the indexer decodes bytes.</param>
      /// <returns>A new action the caller owns; nil when the drop gate is closed, the child
      /// lint fails, or nothing is removable.</returns>
      /// <remarks>
      /// The gate (buffer hash = indexed hash AND whole index fresh) is checked
      /// BEFORE the child lint runs, so a closed gate costs one hash lookup and one
      /// stat sweep. Only warning-level findings are removed: an info-level one names a unit
      /// with an initialization section. The findings are recomputed by the child from the fresh index, never
      /// taken from the client: its diagnostics may predate the reference just typed.
      /// The verdict goes to stderr as `uses-on-save: drop gate buffer=.. fresh=.. directive=..`.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.HandleCodeAction (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: BoolToStr, DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.LSP.Server.TLSPServer.FileToUri, DRagLint.LSP.Server.TLSPServer.RunFullRulesLint, DRagLint.LSP.UsesOnSave.TUsesOnSave.ComputeDropGate, DRagLint.LSP.UsesOnSave.TUsesOnSave.DiagnosticOfFinding, DRagLint.LSP.UsesOnSave.TUsesOnSave.RemoveUnusedEntries, DRagLint.LSP.UsesOnSave.TUsesOnSave.RemoveUnusedImportAction, DRagLint.LSP.UsesOnSave.TUsesOnSave.TextChangeEdit, DRagLint.LSP.UsesOnSave.TUsesOnSave.UnusedFindingsFromLintJson, DRagLint.LSP.UsesOnSave.TUsesOnSave.UsesClauseHasDirectiveAt, Format, SameText, Writeln</para>
      /// <para>Returns: nil; TUsesOnSave.RemoveUnusedImportAction(Diags, Edit, Gate)</para>
      /// <para>Complexity: 11 (cyclomatic, outer body), 39 lines (full implementation)</para>
      /// <para>Reads: FStores</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileToUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.RunFullRulesLint"/>
      /// <seealso cref="DRagLint.LSP.UsesOnSave.TUsesOnSave.ComputeDropGate"/>
      /// <seealso cref="DRagLint.LSP.UsesOnSave.TUsesOnSave.DiagnosticOfFinding"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function BuildRemoveUnusedSourceAction(const APath, ABufferText: string): TJSONObject;
      /// <summary>Stores the client's live buffer text (full sync) so position
      /// lookups see unsaved edits. See TLiveDocuments for why.</summary>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DispatchMessage (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.LiveDocs.TLiveDocuments.Remove, DRagLint.Core.LiveDocs.TLiveDocuments.SetText, DRagLint.LSP.Server.TLSPServer.FileFromUri, TJSONObject</para>
      /// <para>Complexity: 10 (cyclomatic, outer body), 36 lines (full implementation)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.Remove"/>
      /// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.SetText"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleDidChange(const AParams: TJSONObject);
      /// <summary>Drops the live buffer, making disk authoritative again.</summary>
      /// <param name="AParams"><!-- drag-lint:auto type -->const TJSONObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DispatchMessage (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.LiveDocs.TLiveDocuments.Remove, DRagLint.LSP.Server.TLSPServer.DropEphemeralStore, DRagLint.LSP.Server.TLSPServer.FileFromUri, DRagLint.LSP.Server.TLSPServer.PublishEmptyDiagnostics, DRagLint.Project.DefineProfile.TProjectProfileCache.Forget, LowerCase, SameText</para>
      /// <para>Reads: FCtxCache, FOpenDocs, FEphemFile</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.Remove"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.DropEphemeralStore"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.PublishEmptyDiagnostics"/>
      /// <seealso cref="DRagLint.Project.DefineProfile.TProjectProfileCache.Forget"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleDidClose(const AParams: TJSONObject);
      /// <summary>Publishes an empty diagnostics array for AUri so the client drops the entries it holds.</summary>
      /// <param name="AUri">The uri string exactly as the client sent it (never re-encoded from a path), or the client keys the clear to a different document.</param>
      /// <remarks>
      /// WHY: the server publishes but never cleared, so a closed or deleted file kept its warnings in Problems forever.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.HandleDidChangeWatchedFiles (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleDidClose (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.RefreshFileFromDisk (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.SendRawNotification</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SendRawNotification"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure PublishEmptyDiagnostics(const AUri: string);
      /// <summary>Handles workspace/didChangeWatchedFiles: type 3 (Deleted) clears the file diagnostics and drops its overlay/memo state; types 1/2 on a .pas/.dpr/.dpk the client has NOT open re-lint it from disk and publish.</summary>
      /// <param name="AParams">Notification params; params.changes[] of {uri, type}. nil is ignored.</param>
      /// <remarks>
      /// Notification: no response. An open document is left alone (the editor buffer is authoritative). De-duplicated per message and capped at WATCH_REFRESH_MAX files. Never reindexes the project.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DispatchMessage (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.LiveDocs.TLiveDocuments.Remove, DRagLint.LSP.Server.IsLintableSource, DRagLint.LSP.Server.TLSPServer.DropEphemeralStore, DRagLint.LSP.Server.TLSPServer.FileFromUri, DRagLint.LSP.Server.TLSPServer.PublishEmptyDiagnostics, DRagLint.LSP.Server.TLSPServer.RefreshFileFromDisk, DRagLint.Project.DefineProfile.TProjectProfileCache.Forget, LowerCase, SameText</para>
      /// <para>Complexity: 12 (cyclomatic, outer body), 46 lines (full implementation)</para>
      /// <para>Reads: FEphemFile, FOpenDocs</para>
      /// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.Remove"/>
      /// <seealso cref="DRagLint.LSP.Server.IsLintableSource"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.DropEphemeralStore"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.PublishEmptyDiagnostics"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleDidChangeWatchedFiles(const AParams: TJSONObject);
      /// <summary>Re-lints from disk every file listed in params.uris and publishes the result (draglint/refreshDiagnostics, sent by the VS Code command "Drag-Lint: Refresh Problems").</summary>
      /// <param name="AParams">Notification params; params.uris[] of uri strings. nil is ignored.</param>
      /// <remarks>
      /// Unlike didChangeWatchedFiles this also refreshes OPEN documents (the user asked explicitly), using the live buffer overlay when one exists. Bounded to WATCH_REFRESH_MAX uris per message. Never reindexes the project.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.DispatchMessage (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.RefreshFileFromDisk</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.RefreshFileFromDisk"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleRefreshDiagnostics(const AParams: TJSONObject);
      /// <summary>Re-lints one on-disk file (or clears it when the file is gone) and publishes the result.</summary>
      /// <param name="AUri">The uri string exactly as the client sent it.</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.HandleDidChangeWatchedFiles (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleRefreshDiagnostics (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.LiveDocs.TLiveDocuments.Remove, DRagLint.LSP.Server.TLSPServer.FileFromUri, DRagLint.LSP.Server.TLSPServer.PublishDiagnostics, DRagLint.LSP.Server.TLSPServer.PublishEmptyDiagnostics, DRagLint.Project.DefineProfile.TProjectProfileCache.Forget, LowerCase</para>
      /// <para>Reads: FOpenDocs</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.Remove"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.PublishDiagnostics"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.PublishEmptyDiagnostics"/>
      /// <seealso cref="DRagLint.Project.DefineProfile.TProjectProfileCache.Forget"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure RefreshFileFromDisk(const AUri: string);
      /// <param name="ASym"><!-- drag-lint:auto type -->const TSymbol</param>
      /// <returns><!-- drag-lint:auto -->TJSONObject -- Observed:
      /// LocationFromSymbol(ASym, FStore).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.LocationFromSymbol/2</para>
      /// <para>Overload 1 of 2</para>
      /// <para>Pure</para>
      /// <para>Reads: FStore</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.LocationFromSymbol"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function LocationFromSymbol(const ASym: TSymbol   ): TJSONObject; overload;
      /// <param name="ARef"><!-- drag-lint:auto type -->const TReference</param>
      /// <returns><!-- drag-lint:auto -->TJSONObject -- Observed: LocationFromRef(ARef,
      /// FStore).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.LocationFromRef/2</para>
      /// <para>Overload 1 of 2</para>
      /// <para>Reads: FStore</para>
      /// <para>Pure</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.LocationFromRef"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function LocationFromRef   (const ARef: TReference): TJSONObject; overload;
      { v0.40.3: explicit-store overloads -- preferred for multi-DB queries
      so each Location URI resolves against the store that owns the row. }
      /// <summary><!-- drag-lint:auto sum -->v0.40.3: explicit-store overloads --
      /// preferred for multi-DB queries so each Location URI resolves against the store
      /// that owns the row.</summary>
      /// <param name="ASym"><!-- drag-lint:auto type -->const TSymbol</param>
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <returns><!-- drag-lint:auto -->TJSONObject -- Observed: TJSONObject.Create.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ComputeDefinition (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ComputeReferences (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ComputeWorkspaceSymbols (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.LocationFromSymbol/1 (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.LSP.Server.TLSPServer.FileToUri</para>
      /// <para>Overload 2 of 2</para>
      /// <para>Owns returned: new (caller owns)</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileToUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function LocationFromSymbol(const ASym: TSymbol   ; const AStore: ISymbolStore): TJSONObject; overload;
      /// <param name="ARef"><!-- drag-lint:auto type -->const TReference</param>
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <returns><!-- drag-lint:auto -->TJSONObject -- Observed: TJSONObject.Create.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ComputeReferences (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.LocationFromRef/1 (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.LSP.Server.TLSPServer.FileToUri</para>
      /// <para>Overload 2 of 2</para>
      /// <para>Owns returned: new (caller owns)</para>
      /// <para>Pure</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileToUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function LocationFromRef   (const ARef: TReference; const AStore: ISymbolStore): TJSONObject; overload;
    private { S0: TLspServerContextAdapter forwards to these two }
      // v0.7: reparse the file at APath and find the identifier text under
      // (ALine, ACol) - both 0-based (LSP convention). Returns empty string
      // if the file doesn't exist or the cursor isn't on an identifier.
      /// <summary><!-- drag-lint:auto sum -->v0.7: reparse the file at APath and find the
      /// identifier text under (ALine, ACol) - both 0-based (LSP convention). Returns
      /// empty string if the file doesn't exist or the cursor isn't on an identifier.</summary>
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ALine"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="ACol"><!-- drag-lint:auto type -->Integer</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: ''; Trim(NodeTextLocal(Node,
      /// Source)).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ComputeDefinition (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ComputeHoverAt (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ComputeReferences (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.ResolveSymbolAt (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLspServerContextAdapter.IdentifierAtPosition (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Encoding.EnsureUtf8Bytes, DRagLint.Core.LiveDocs.TLiveDocuments.Readable, DRagLint.Core.LiveDocs.TLiveDocuments.ReadBytes, DRagLint.LSP.Server.ContainsPosition, DRagLint.LSP.Server.FindSmallestNamedAt, DRagLint.LSP.Server.NodeTextLocal, DRagLint.LSP.SyntaxTree.ParseDelphiUtf8, TreeSitter.TTSNodeHelper.ChildByField/1, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NodeType, TreeSitter.TTSTree.RootNode, Trim</para>
      /// <para>Complexity: 18 (cyclomatic, outer body), 61 lines (full implementation)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.Encoding.EnsureUtf8Bytes"/>
      /// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.Readable"/>
      /// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.ReadBytes"/>
      /// <seealso cref="DRagLint.LSP.Server.ContainsPosition"/>
      /// <seealso cref="DRagLint.LSP.Server.FindSmallestNamedAt"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function IdentifierAtPosition(const APath: string; ALine, ACol: Integer): string;
      /// <summary>151 CF: the parse tree of ASource for APath, reused from the last call when
      /// the path and the preprocessed bytes are identical, else parsed and cached.</summary>
      /// <param name="ASource">UTF-8 source of APath (overlay or disk).</param>
      /// <param name="APath">The file the source belongs to (define profile + cache key).</param>
      /// <returns>The cached tree, OWNED BY THE SERVER -- never free it; nil when the parse failed.</returns>
      /// <remarks>Measured on a CLIENT copy: 100 hovers in 8 files parsed 100 times
      /// (~9 ms each); with the cache 8 parses. Not thread-safe: main thread only.</remarks>
      function IdentTreeFor(const ASource: TBytes; const APath: string): TTSTree;
      /// <returns><!-- drag-lint:auto -->TLinter -- Observed: FLinter.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.HandleCodeAction (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.PublishDiagnostics (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLspServerContextAdapter.Linter (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Lint.Linter.TLinter.Create</para>
      /// <para>Reads: FLinter   Writes: FLinter</para>
      /// <para>Owns returned: borrowed</para>
      /// <seealso cref="DRagLint.Lint.Linter.TLinter.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function EnsureLinter: TLinter                                                  ;
    public
      /// <summary>Maps an LSP file:/// URI to a Windows path (percent-decoded, backslashes). Stateless.</summary>
      /// <param name="AUri"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto type -->string</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.MergeDiagnostics (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.PickupContext (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.RecordRequest (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.TrackDocument (DRagLint.LSP.Proxy.Merge.pas) (+16 more)</para>
      /// <para>Calls: Copy, DRagLint.LSP.Completion.NoteClientFileUri, StringReplace</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.LSP.Completion.NoteClientFileUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function FileFromUri(const AUri : string): string;
      /// <param name="ADbPath"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.Run (DRagLint.CLI.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Server (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Server.TLSPServer.Create/1 (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.Create/1</para>
      /// <para>Overload 1 of 2</para>
      /// <para>constructor</para>
      /// <para>Recursive</para>
      /// <para>Pure</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(const ADbPath: string); overload;
      /// <summary>Multi-DB constructor. Opens every path READ-ONLY; a missing
      /// path, an unopenable one, and one whose schema predates this engine are
      /// each reported on stderr (the protocol channel is stdout) and skipped.
      /// The first surviving store becomes FStore for legacy code paths.</summary>
      /// <param name="ADbPaths">Index paths in priority order -- the project DB
      /// first, the platform library behind it. Empty entries are ignored.</param>
      /// <remarks>
      /// A READER. Never calls Migrate on a --db: the owner's ruling of
      /// 2026-09-14 is that only the IDE writes an index, and a reader that
      /// migrated would upgrade the database underneath its owner. The one
      /// writable store this server owns is the ephemeral single-unit index in
      /// %TEMP% (BuildEphemeralStore), which is never a project DB.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: DRagLint.LSP.Context.RegisteredLspFeatures, DRagLint.LSP.Server.TLSPServer.OpenReaderStore, DRagLint.LSP.Server.TLspServerContextAdapter.Create, GetStdHandle</para>
      /// <para>Overload 2 of 2</para>
      /// <para>constructor</para>
      /// <para>Reads: FStores, FStorePaths, FFeatures, FFeatureByMethod   Writes: FExceptionFacts, FStdIn, FLinter, FStores, FStorePaths, FStore, FSets, FCtxCache (+17 more)</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="DRagLint.LSP.Context.RegisteredLspFeatures"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.OpenReaderStore"/>
      /// <seealso cref="DRagLint.LSP.Server.TLspServerContextAdapter.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(const ADbPaths: TArray<string>); overload;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: CloseHandle, DRagLint.LSP.Server.TLSPServer.DropEphemeralStore</para>
      /// <para>Reads: FStopEvent, FReindexThreads, FDeferred, FFeatureByMethod, FFeatures, FLinter, FStdIn, FReindex (+12 more)   Writes: FContext, FStore</para>
      /// <para>Directives: override</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.DropEphemeralStore"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      destructor Destroy; override;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: DRagLint.Core.ControlChannel.BeatBegin, DRagLint.Core.ControlChannel.TControlChannel.BeginWork, DRagLint.Core.ControlChannel.TControlChannel.EndWork, DRagLint.LSP.Server.TLSPServer.DispatchMessage, DRagLint.LSP.Server.TLSPServer.FlushPending, DRagLint.LSP.Server.TLSPServer.ReadMessageGuarded, DRagLint.LSP.Server.TLSPServer.StandDownTaken</para>
      /// <para>Reads: FShuttingDown, FDeferred, FInputEnded, FWorkLock, FControl   Writes: FQueueNotices</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.ControlChannel.BeatBegin"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.BeginWork"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.EndWork"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.DispatchMessage"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FlushPending"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure Run;
      /// <summary>The maintenance control channel Run cooperates with, or nil.</summary>
      /// <remarks>Not owned: the CLI creates it AFTER the stores are open (so
      /// `status` can name them) and signals it AFTER Free (so `exiting` is
      /// only ever sent once every store is closed). Run brackets its blocking
      /// stdin read and each handler for it, and leaves the loop the moment a
      /// stand-down is taken. docs\PLAN-maintenance-shutdown-channel.md.</remarks>
      property ControlChannel: TControlChannel read FControl write FControl;
      /// <summary>C1 (lsp --full-rules): when True each didOpen/didSave publishes the FULL
      /// built-in rule set, obtained by running lint --json out-of-process, instead of the
      /// BuildDiagnostics subset; compiler findings are kept. Default False.</summary>
      /// <remarks>Costs one lint run per save; the measured ms is written to stderr as
      /// drag-lint lsp: full-rules <file> <ms> ms <n> findings. Falls back to the subset (and
      /// says so on stderr) on timeout, non-zero exit or invalid JSON.</remarks>
      property FullRules: Boolean read FFullRules write FFullRules;
      /// <summary>D1 (owner ruling, wave 148): when True (the default) hover adds the routine's
      /// 'Raises:' line and textDocument/codeLens adds 'raises N types, handles M types' on a
      /// routine header, both read through DRagLint.Query.ExceptionFacts (the reader the
      /// `exception-facts verb and the MCP tool use). False = lsp --no-exception-facts:
      /// hover and lenses byte-identical to 1.46.</summary>
      property ExceptionFacts: Boolean read FExceptionFacts write FExceptionFacts;
      /// <summary>C15: the explicit --project the CLI was started with ('' when none was typed).</summary>
      /// <remarks>Set by the CLI from its parsed arguments. Forwarded to the --full-rules lint child so
      /// it resolves the same profile as the in-process lint; '' forwards nothing.</remarks>
      property StartupProject: string read FStartProject write FStartProject;
      /// <summary>C15: the explicit --platform the CLI was started with ('' when none was typed).</summary>
      /// <remarks>Set by the CLI from its parsed arguments; forwarded like StartupProject.</remarks>
      property StartupPlatform: string read FStartPlatform write FStartPlatform;
      /// <summary>1.38: the explicit --target-compiler the CLI was started with ('' when none was typed).</summary>
      /// <remarks>Set by the CLI from its parsed arguments. It beats the lint config's
      /// target_compiler and the project context's targetCompiler for every file
      /// (ResolveTargetCompiler's precedence); an invalid token is reported as a
      /// context notice and the file is linted at the default target.</remarks>
      property StartupTargetCompiler: string read FStartupTargetCompiler write FStartupTargetCompiler;
      /// <summary>LSP-1 CORE: resolves (project, platform) to its DB pair with the
      /// CLI's resolve-dbs logic; nil = only the startup stores are ever used.</summary>
      /// <remarks>Set by the CLI before Run. Called on the server's own thread.</remarks>
      property DbResolver: TLspContextDbResolver read FDbResolver write FDbResolver;
      /// <summary>LSP-1 CORE: True when the store list came from explicit --db
      /// flags. Those DBs are then the whole universe: the resolver is not
      /// consulted, the owning store is the project DB and a startup store named
      /// library-&lt;platform&gt; is that platform's library.</summary>
      property ExplicitDbs: Boolean read FExplicitDbs write FExplicitDbs;
      /// <summary>LSP-1 CORE: the resolved project context of APath (SPEC.md 1b):
      /// startup args &gt; client/IDE &gt; owning .dproj &gt; .dlcontext.json (no
      /// .dproj) &gt; central defaults &gt; Win64 placeholder.</summary>
      /// <param name="APath">A source file path.</param>
      /// <returns>The context; Project = '' when none is known.</returns>
      /// <remarks>
      /// Memoised per file against the project file's write stamp; the
      /// memo is dropped on didClose and on every client context change.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ContextFooter (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.PublishDiagnostics (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.QueueContextNotification (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.RepublishRetargeted (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.RunFullRulesLint (DRagLint.LSP.Server.pas) (+1 more)</para>
      /// <para>Calls: DRagLint.LSP.Server.ProjectSearchStamp, DRagLint.LSP.Server.TLSPServer.ComputeFileContext, DRagLint.LSP.Server.TLSPServer.DprojStamp, DRagLint.Project.DefineProfile.TProjectProfileCache.Forget, LowerCase</para>
      /// <para>Returns: Entry.Ctx</para>
      /// <para>Reads: FCtxCache</para>
      /// <seealso cref="DRagLint.LSP.Server.ProjectSearchStamp"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ComputeFileContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.DprojStamp"/>
      /// <seealso cref="DRagLint.Project.DefineProfile.TProjectProfileCache.Forget"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function  FileContext(const APath: string): TLspFileContext;
      /// <summary>LSP-1 CORE: adopts the IDE's `&lt;Project&gt;.delphilsp.json` as the
      /// client context -- its sibling .dproj (else .dpr) is the project and its
      /// dllname the platform.</summary>
      /// <param name="AFile">The .delphilsp.json path (not a URI).</param>
      /// <remarks>
      /// Not thread-safe; call from the thread that owns this server.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Server (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Server.TLSPServer.HandleDidChangeConfiguration (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleInitialize (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: ChangeFileExt, Default, DRagLint.LSP.Server.TLSPServer.QueueContextNotification, DRagLint.LSP.Server.TLSPServer.RepublishRetargeted, DRagLint.Project.DefineProfile.ReadDelphiLspDefines, ExpandFileName, Writeln</para>
      /// <para>Reads: FCtxCache, FLastOpenPath   Writes: FHaveClientCtx, FClientCtx, FClientProject, FClientPlatform, FClientConfig, FClientTarget</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.QueueContextNotification"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.RepublishRetargeted"/>
      /// <seealso cref="DRagLint.Project.DefineProfile.ReadDelphiLspDefines"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ApplyClientSettingsFile(const AFile: string);
      /// <summary>The databases this server actually opened, in FStores order.</summary>
      /// <returns>Paths of the stores that opened and passed the schema check;
      /// a --db that was skipped is not in it.</returns>
      property StorePaths: TArray<string> read FStorePaths;
      /// <summary>The configured --db stores in command-line order; for a
      /// position in a file use StoresForFile, which prepends that file's own
      /// ephemeral index.</summary>
      /// <returns>A new array; empty when nothing opened. Never contains the
      /// cached loose-file index, so the answer does not depend on which file
      /// was hovered earlier.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLspServerContextAdapter.Stores (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: Copy</para>
      /// <para>Returns: Copy(FStores)</para>
      /// <para>Reads: FStores</para>
      /// <para>Effect-free (proven)</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.BuildEphemeralStore"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function OpenStores: TArray<ISymbolStore>;
      /// <summary>The body `textDocument/definition` answers for a position.</summary>
      /// <param name="APath">Local path of the document.</param>
      /// <param name="ALine0">0-based line.</param>
      /// <param name="ACol0">0-based column.</param>
      /// <returns>A NEW Location[] array, possibly empty; the caller owns it.</returns>
      /// <remarks>
      /// Every same-named declaration across StoresForFile(APath); when
      /// the file's ephemeral index leads and declares the name, only those.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeDefinition (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Server.TLSPServer.HandleDefinition (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLspServerContextAdapter.Definition (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName, DRagLint.LSP.Server.TLSPServer.EphemeralLeads, DRagLint.LSP.Server.TLSPServer.IdentifierAtPosition, DRagLint.LSP.Server.TLSPServer.LocationFromSymbol/2, DRagLint.LSP.Server.TLSPServer.StoresForFile</para>
      /// <para>Returns: Arr</para>
      /// <para>Reads: FStores</para>
      /// <para>Catches: Exception (re-raise)</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.EphemeralLeads"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.IdentifierAtPosition"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.LocationFromSymbol"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.StoresForFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ComputeDefinition(const APath: string; ALine0, ACol0: Integer): TJSONArray;
      /// <summary>The body `textDocument/references` answers for a position.</summary>
      /// <param name="APath">Local path of the document.</param>
      /// <param name="ALine0">0-based line.</param>
      /// <param name="ACol0">0-based column.</param>
      /// <param name="AIncludeDecl">Append the name's declarations after its references, per store.</param>
      /// <returns>A NEW Location[] array, possibly empty; the caller owns it.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Server.TLSPServer.HandleReferences (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLspServerContextAdapter.References (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName, DRagLint.LSP.Server.TLSPServer.IdentifierAtPosition, DRagLint.LSP.Server.TLSPServer.LocationFromRef/2, DRagLint.LSP.Server.TLSPServer.LocationFromSymbol/2, DRagLint.LSP.Server.TLSPServer.StoresForFile</para>
      /// <para>Returns: Arr</para>
      /// <para>Reads: FStores</para>
      /// <para>Catches: Exception (re-raise)</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.IdentifierAtPosition"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.LocationFromRef"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.LocationFromSymbol"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ComputeReferences(const APath: string; ALine0, ACol0: Integer; AIncludeDecl: Boolean): TJSONArray;
      /// <summary>What a registered LSP feature answers for a request, without
      /// writing it anywhere: the merge proxy's way to serve a feature (stdout is
      /// the relay's, never this server's, in that mode).</summary>
      /// <param name="AMethod">The LSP method name.</param>
      /// <param name="AParams">The request's params; may be nil. Stays the caller's.</param>
      /// <returns>A NEW value the caller owns (JSON null included); nil when no
      /// feature owns AMethod or the feature answered with an error (one stderr
      /// line).</returns>
      /// <remarks>
      /// Takes the same work lock a request takes in plain mode. A raising
      /// feature raises through to the caller, which fails open.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.NavAnswer (DRagLint.LSP.Proxy.Merge.pas)</para>
      /// <para>Calls: DRagLint.LSP.Context.TLspFeature.Handle, DRagLint.LSP.Server.TLspCaptureContext.TakeResult, DRagLint.LSP.Server.TLspServerContextAdapter.Create</para>
      /// <para>Returns: nil; Capture.TakeResult</para>
      /// <para>Reads: FFeatureByMethod, FWorkLock</para>
      /// <seealso cref="DRagLint.LSP.Context.TLspFeature.Handle"/>
      /// <seealso cref="DRagLint.LSP.Server.TLspCaptureContext.TakeResult"/>
      /// <seealso cref="DRagLint.LSP.Server.TLspServerContextAdapter.Create"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ComputeFeatureResult(const AMethod: string; const AParams: TJSONObject): TJSONValue;
      /// <summary>The body `workspace/symbol` answers for a query.</summary>
      /// <param name="AQuery">The client's query; '' answers an empty array.</param>
      /// <returns>A NEW SymbolInformation[] array, possibly empty; the caller owns it.</returns>
      /// <remarks>
      /// Per store, exact-name matches, else up to 50 fuzzy ones; every
      /// store contributes. HandleWorkspaceSymbol and the merge proxy (A5) both
      /// answer from it, so they cannot disagree.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Server.TLSPServer.HandleWorkspaceSymbol (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsFuzzy, DRagLint.LSP.Server.TLSPServer.LocationFromSymbol/2</para>
      /// <para>Returns: Arr</para>
      /// <para>Complexity: 19 (cyclomatic, outer body), 57 lines (full implementation)</para>
      /// <para>Reads: FStores</para>
      /// <para>Catches: Exception (re-raise)</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsFuzzy"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.LocationFromSymbol"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ComputeWorkspaceSymbols(const AQuery: string): TJSONArray;
      /// <summary>The `counts` array `draglint/callerCounts` answers for a file:
      /// one {line, count} per routine line, 0-based, counting distinct call
      /// sites across every --db store.</summary>
      /// <param name="APath">Local path; '' answers an empty array.</param>
      /// <returns>A NEW array, empty for a file no store knows; the caller owns it.</returns>
      /// <remarks>
      /// <para>Bounded: one CountCallerSitesByNames statement per 64 distinct names, not one
      /// row set per routine; between statements it calls YieldToPendingRequests, so hovers
      /// sent meanwhile are answered before this returns.</para>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.HandleCallerCounts (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLspServerContextAdapter.CallerCounts (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: Copy, DRagLint.Core.Interfaces.ISymbolStore.CountCallerSitesByNames, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile, DRagLint.LSP.Server.TLSPServer.ComputeCallerCounts.NameOf, DRagLint.LSP.Server.TLSPServer.ComputeCallerCounts.StoreOf, DRagLint.LSP.Server.TLSPServer.ComputeCallerCounts.UnionCount, DRagLint.LSP.Server.TLSPServer.StoresForFile, DRagLint.LSP.Server.TLSPServer.YieldToPendingRequests, Int64, IntToStr, LowerCase, Pos, StrToInt</para>
      /// <para>Returns: Arr</para>
      /// <para>Complexity: 14 (cyclomatic, outer body), 173 lines (full implementation)</para>
      /// <para>Catches: Exception (re-raise)</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CountCallerSitesByNames"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ComputeCallerCounts.NameOf"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ComputeCallerCounts.StoreOf"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ComputeCallerCounts.UnionCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ComputeCallerCounts(const APath: string): TJSONArray;
      /// <summary>The exception code lenses of one file: [{line, title}], line 0-based on the
      /// routine's declaration (the caller lens line).</summary>
      /// <param name="APath">Local path of the document.</param>
      /// <returns>A new array the caller frees; [] when ExceptionFacts is off, the file is not
      /// indexed, or no routine in it raises or handles.</returns>
      /// <remarks>
      /// One read of DRagLint.Query.ExceptionFacts.ExceptionFactsOfFile on the first
      /// store of the file's context set that holds the file.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.HandleCallerCounts (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLspServerContextAdapter.ExceptionLenses (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.LSP.Server.TLSPServer.StorePathOf, DRagLint.LSP.Server.TLSPServer.StoresForFile, DRagLint.Query.ExceptionFacts.ExceptionFactsOfFile, DRagLint.Query.ExceptionFacts.ExceptionLensTitle</para>
      /// <para>Returns: TJSONArray.Create</para>
      /// <para>Complexity: 10 (cyclomatic, outer body), 42 lines (full implementation)</para>
      /// <para>Reads: FExceptionFacts</para>
      /// <para>Owns returned: new (caller owns)</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.StorePathOf"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.StoresForFile"/>
      /// <seealso cref="DRagLint.Query.ExceptionFacts.ExceptionFactsOfFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ComputeExceptionLenses(const APath: string): TJSONArray;
      /// <summary>Wave 149 LX: the sites behind one exception lens, for workspace/executeCommand
      /// draglint.exceptionFacts (ILspServerContext.ExceptionFactsAt).</summary>
      /// <param name="APath">Local path of the document.</param>
      /// <param name="ALine0">0-based declaration line of the routine (the lens line).</param>
      /// <returns>A new array the caller frees: [{uri, line, character, action, type, via,
      /// routine}], 0-based; [] when ExceptionFacts is off, the file is not indexed or nothing on
      /// that routine line raises or handles.</returns>
      /// <remarks>
      /// One read of ExceptionFactsOfFile, filtered on TExceptionFact.RoutineLine -- the
      /// same rows ComputeExceptionLenses titles, so the pick and the lens count agree.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLspServerContextAdapter.ExceptionFactsAt (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.LSP.Server.TLSPServer.FileToUri, DRagLint.LSP.Server.TLSPServer.StorePathOf, DRagLint.LSP.Server.TLSPServer.StoresForFile, DRagLint.Query.ExceptionFacts.ExceptionFactsOfFile</para>
      /// <para>Returns: TJSONArray.Create</para>
      /// <para>Reads: FExceptionFacts</para>
      /// <para>Catches: Exception (re-raise)</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileToUri"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.StorePathOf"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.StoresForFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ComputeExceptionFactsAt(const APath: string; ALine0: Integer): TJSONArray;
      /// <summary>Wave 149 LX (UP 149): the extra stores a hover's facts read, so the card's
      /// 'Used in:' / 'Used in (via property X):' carry a use that lives only in another project's
      /// DB -- as `document --db A --db B` writes the doc block.</summary>
      /// <param name="APath">Local path of the hovered document.</param>
      /// <param name="AHit">The store the symbol came from (never in the result).</param>
      /// <returns>The non-library stores that own APath -- the file's context set plus every
      /// startup project store holding it (a shared unit) -- minus AHit and the ephemeral
      /// single-unit store, each once; nil when there is none.</returns>
      /// <remarks>
      /// A library is never an extra: its name fan-out is the 2026-08-13 junk-facts
      /// channel and its size is paid on every hover.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ComputeHoverAt (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleHoverBundle (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.LSP.Server.TLSPServer.IsLibraryPath, DRagLint.LSP.Server.TLSPServer.StorePathOf, DRagLint.LSP.Server.TLSPServer.StoresForFile</para>
      /// <para>Complexity: 12 (cyclomatic, outer body), 18 lines (full implementation)</para>
      /// <para>Reads: FStores, FStorePaths, FEphemStore</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.IsLibraryPath"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.StorePathOf"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.StoresForFile"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function HoverExtraStores(const APath: string; const AHit: ISymbolStore): TArray<ISymbolStore>;
      /// <summary>The 'Raises:' hover line of ASym as a one-element array, or [] (switch off,
      /// not a routine, a store with no path, nothing raised).</summary>
      /// <param name="AStore">The store ASym came from.</param>
      /// <param name="ASym">The hovered symbol.</param>
      /// <returns>[ExceptionRaisesLine(...)] or [].</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ComputeHoverAt (DRagLint.LSP.Server.pas), DRagLint.LSP.Server.TLSPServer.HandleHoverBundle (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.StorePathOf, DRagLint.Query.ExceptionFacts.ExceptionFactsOf, DRagLint.Query.ExceptionFacts.ExceptionRaisesLine</para>
      /// <para>Returns: []; [Line]</para>
      /// <para>Reads: FExceptionFacts</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.StorePathOf"/>
      /// <seealso cref="DRagLint.Query.ExceptionFacts.ExceptionFactsOf"/>
      /// <seealso cref="DRagLint.Query.ExceptionFacts.ExceptionRaisesLine"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ExceptionFactLines(const AStore: ISymbolStore; const ASym: TSymbol): TArray<string>;
      /// <summary>The markdown `textDocument/hover` shows for a position.</summary>
      /// <param name="APath">Local path of the document.</param>
      /// <param name="ALine0">0-based line.</param>
      /// <param name="ACol0">0-based column.</param>
      /// <returns>The markdown; '' exactly when hover answers null.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeHover (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Server.TLspServerContextAdapter.HoverMarkdown (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.LSP.Server.TLSPServer.ComputeHoverAt</para>
      /// <para>Returns: Comp.MdValue; ''</para>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ComputeHoverAt"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnyStoreOwns"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientContext"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ComputeHoverMarkdown(const APath: string; ALine0, ACol0: Integer): string;
      /// <summary>The single symbol a position refers to -- the selection hover
      /// makes (SelectSymbolAt), with DedupAndPreferSource applied when the
      /// cursor did not narrow it.</summary>
      /// <param name="APath">Local path of the document.</param>
      /// <param name="ALine0">0-based line.</param>
      /// <param name="ACol0">0-based column.</param>
      /// <param name="ASym">Receives the symbol; valid only on True.</param>
      /// <param name="AStore">Receives the store ASym lives in; valid only on True.</param>
      /// <returns>False for no identifier, a compiler intrinsic, no indexed
      /// symbol, or the inherited-member owner-type floor.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLspServerContextAdapter.ResolveSymbolAt (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: Default, DRagLint.Core.Model.IsCompilerIntrinsic, DRagLint.LSP.Server.DedupAndPreferSource, DRagLint.LSP.Server.TLSPServer.IdentifierAtPosition, DRagLint.LSP.Server.TLSPServer.SelectSymbolAt, DRagLint.LSP.Server.TLSPServer.StoresForFile</para>
      /// <para>Returns: False; True</para>
      /// <para>Reads: FStores</para>
      /// <para>Mutates: ASym (out), AStore (out)</para>
      /// <seealso cref="DRagLint.Core.Model.IsCompilerIntrinsic"/>
      /// <seealso cref="DRagLint.LSP.Server.DedupAndPreferSource"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.IdentifierAtPosition"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.SelectSymbolAt"/>
      /// <seealso cref="DRagLint.LSP.Server.TLSPServer.StoresForFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ResolveSymbolAt(const APath: string; ALine0, ACol0: Integer; out ASym: TSymbol; out AStore: ISymbolStore): Boolean;
      /// <summary>The surface handed to every registered TLspFeature.</summary>
      /// <remarks>Owned by this server (reference counted, held in FContext);
      /// it reaches back into the server, so it must not outlive it.</remarks>
      property Context: ILspServerContext read FContext;
  end;

implementation

uses
  System.StrUtils, { LSP-1 CORE: MatchText }
  DRagLint.Storage.Schema, { 150 SC: IsSchemaReadable, the read gate of the store opener }  // dl:unit DRagLint.Storage.Schema accepted -- 150 SC: SCHEMA_READ_MIN (and SCHEMA_VERSION) are the read-compat bounds every read gate compares; they travel with the schema
  System.RegularExpressions, { 1.44 lspctx: a project file's units and declared platform }
  DRagLint.Query.Implementors, { 1.40 ifrpt: the implementors counts of draglint/callerCounts }
  DRagLint.Query.ExceptionFacts, { D1 (wave 148): the Raises: hover line and the exception lens }
  DRagLint.Lint.MissingUses, { MISSING_USES_RULE: publish + codeAction } // dl:unit DRagLint.Lint.MissingUses accepted -- MISSING_USES_RULE is the rule id the checker reports under, so the id travels with TMissingUsesChecker
  DRagLint.Project.DefineProfile,
  DRagLint.Symbol.Describe,  // DescribeDeclaredType: the type a hover shows for a value kind
  DRagLint.Convert.PropTree, // ClearPropertyDeclaredTypeCache: a reopened DB must not answer from old rows
  DRagLint.Diagnostics.ParseCache, // 151 CF: TAstParseCache.ApplyPreprocess -- the key of IdentTreeFor's parse cache
  DRagLint.LSP.Features,  // linked for its feature units' initialization (RegisterLspFeature); no identifier is referenced
  DRagLint.LSP.UsesOnSave  { KINDS_ON_SAVE: the codeActionKinds initialize advertises } // dl:unit DRagLint.LSP.UsesOnSave accepted -- KINDS_ON_SAVE and UNUSED_UNIT_RULE are the protocol kinds and rule id TUsesOnSave builds for, so they travel with it
  ;

const
  { C1/C12/C13: the budget for the out-of-process `lint --json` that --full-rules
    runs on each didOpen/didSave is DRagLint.Core.LintBudget.LintChildTimeoutMs --
    the same function the IDE plugin's live runner asks, so the two cannot drift. }
  { Bounded wait for the killed child to be reaped after TerminateProcess. }
  LSP_FULL_RULES_REAP_MS = 2000;
  { Slice of the child wait: how often progress, hovers and a newer save are looked at. }
  LSP_FULL_RULES_POLL_MS = 200;
  { Child CPU (100 ns units) that counts as progress between two looks: 50 ms (Windows charges CPU in ticks). }
  LSP_FULL_RULES_CPU_PROGRESS_100NS = 50 * 10000;
  { S8: JSON-RPC internal error, answered when a registered feature raises. }
  LSP_ERR_INTERNAL = -32603;
  /// <summary>JSON-RPC 'method not found': the answer to a request no handler claims.</summary>
  LSP_ERR_METHOD_NOT_FOUND = -32601;
  { LSP-1 CORE: SPEC.md 3 -- opened (project DB, library DB) pairs kept. }
  LSP_STORE_SET_LRU = 3;
  { Most files re-linted from disk per watched-files / refresh message; a burst of agent writes stays bounded. }
  WATCH_REFRESH_MAX = 64;
  { LSP-1 CORE: longest log line quoted in a failed re-index notice. }
  LSP_REINDEX_REASON_MAX = 200;
  { LSP-1 CORE: SPEC.md 1b -- the placeholder platform when nothing names one. }
  LSP_PLACEHOLDER_PLATFORM = 'Win64';
  LSP_CMD_SET_CONTEXT      = 'draglint.setContext';
  { 150 LX2: the exception-lens command; withdrawn from executeCommandProvider under --no-exception-facts. }
  LSP_CMD_EXCEPTION_FACTS  = 'draglint.exceptionFacts';
  LSP_NOTIFY_CONTEXT      = 'draglint/context';
  LSP_MSG_TYPE_WARNING     = 2; // window/showMessage MessageType.Warning
  LSP_MSG_TYPE_INFO        = 3; // window/showMessage MessageType.Info
  { 1.44 lspctx: how far FindListingProject climbs when no repository root stops it. }
  LSP_PROJECT_SEARCH_LEVELS = 4;
  { 1.44 lspctx: most sub-folders one NearProjects look lists; a huge parent stays cheap. }
  LSP_PROJECT_SEARCH_DIRS = 256;
  { 148 LS: how often a project-less file's context re-checks the folders the project search reads. }
  LSP_CTX_RECHECK_MS = 2000;
  { 148 LS: the folder write-time format of a NearStamp (ms; NTFS keeps 100 ns). }
  LSP_DIR_STAMP_FMT = 'yyyymmddhhnnsszzz';
  LSP_ERR_INVALID_PARAMS   = -32602;
  LSP_CONFIG_SECTION       = 'dragLint';
  LSP_CONTEXT_FILE_EXT     = '.dlcontext.json';
  LSP_SOURCE_NAMES: array[TLspContextSource] of string =
    ('startup', 'client', 'dproj', 'dlcontext', 'defaults', 'placeholder');

{ LSP-1 CORE: JSON helpers for the client-context messages. }
function JsonStrOf(const AObj: TJSONObject; const AName: string): string;
var
  V: TJSONValue;
begin
  Result:= '';
  if AObj = nil then Exit;
  V:= AObj.GetValue(AName);
  if V is TJSONString then Result:= V.Value;
end;

function HasContextKeys(const AObj: TJSONObject): Boolean;
begin
  Result:= (AObj <> nil) and ((AObj.GetValue('project') <> nil) or (AObj.GetValue('platform') <> nil)
    or (AObj.GetValue('config') <> nil) or (AObj.GetValue('targetCompiler') <> nil));
end;

type
  { S0: the ILspServerContext a feature is handed. A thin forwarder: every
    answer is the server's own method, so a feature cannot drift from what the
    built-in handlers send. Holds a RAW back-pointer -- the server owns the
    adapter through FContext, so a counted one would be a cycle. }
  TLspServerContextAdapter = class(TInterfacedObject, ILspServerContext)
  strict private
    FServer: TLSPServer;
  public
    constructor Create(AServer: TLSPServer);
    function FileFromUri(const AUri: string): string;
    function FileToUri(const APath: string): string;
    function Stores: TArray<ISymbolStore>;
    function StoresForFile(const APath: string): TArray<ISymbolStore>;
    function IdentifierAtPosition(const APath: string; ALine0, ACol0: Integer): string;
    function ResolveSymbolAt(const APath: string; ALine0, ACol0: Integer; out ASym: TSymbol; out AStore: ISymbolStore): Boolean;
    function Definition(const APath: string; ALine0, ACol0: Integer): TJSONArray;
    function References(const APath: string; ALine0, ACol0: Integer; AIncludeDecl: Boolean): TJSONArray;
    function CallerCounts(const APath: string): TJSONArray;
    function ExceptionLenses(const APath: string): TJSONArray;
    function ExceptionFactsAt(const APath: string; ALine0: Integer): TJSONArray;
    function HoverMarkdown(const APath: string; ALine0, ACol0: Integer): string;
    function Linter: TLinter;
    procedure Reply(const AId: TJSONValue; AResult: TJSONValue); virtual;
    procedure ReplyError(const AId: TJSONValue; ACode: Integer; const AMessage: string); virtual;
    procedure Notify(const AMethod: string; AParams: TJSONObject);
  end;

  { The context TLSPServer.ComputeFeatureResult hands a feature: keeps the reply
    instead of writing it to stdout. One instance per call. }
  TLspCaptureContext = class(TLspServerContextAdapter)
  strict private
    FResult: TJSONValue;
  public
    destructor Destroy; override;
    procedure Reply(const AId: TJSONValue; AResult: TJSONValue); override;
    procedure ReplyError(const AId: TJSONValue; ACode: Integer; const AMessage: string); override;
    function TakeResult: TJSONValue;
  end;

constructor TLspServerContextAdapter.Create(AServer: TLSPServer);
begin
  inherited Create;
  FServer:= AServer;
end;

function TLspServerContextAdapter.FileFromUri(const AUri: string): string;
begin
  Result:= FServer.FileFromUri(AUri);
end;

function TLspServerContextAdapter.FileToUri(const APath: string): string;
begin
  Result:= FServer.FileToUri(APath);
end;

function TLspServerContextAdapter.Stores: TArray<ISymbolStore>;
begin
  Result:= FServer.OpenStores;
end;

function TLspServerContextAdapter.StoresForFile(const APath: string): TArray<ISymbolStore>;
begin
  Result:= FServer.StoresForFile(APath);
end;

function TLspServerContextAdapter.IdentifierAtPosition(const APath: string; ALine0, ACol0: Integer): string;
begin
  Result:= FServer.IdentifierAtPosition(APath, ALine0, ACol0);
end;

function TLspServerContextAdapter.ResolveSymbolAt(const APath: string; ALine0, ACol0: Integer; out ASym: TSymbol; out AStore: ISymbolStore): Boolean;
begin
  Result:= FServer.ResolveSymbolAt(APath, ALine0, ACol0, ASym, AStore);
end;

function TLspServerContextAdapter.Definition(const APath: string; ALine0, ACol0: Integer): TJSONArray;
begin
  Result:= FServer.ComputeDefinition(APath, ALine0, ACol0);
end;

function TLspServerContextAdapter.References(const APath: string; ALine0, ACol0: Integer; AIncludeDecl: Boolean): TJSONArray;
begin
  Result:= FServer.ComputeReferences(APath, ALine0, ACol0, AIncludeDecl);
end;

function TLspServerContextAdapter.CallerCounts(const APath: string): TJSONArray;
begin
  Result:= FServer.ComputeCallerCounts(APath);
end;

function TLspServerContextAdapter.ExceptionLenses(const APath: string): TJSONArray;
begin
  Result:= FServer.ComputeExceptionLenses(APath);
end;

function TLspServerContextAdapter.ExceptionFactsAt(const APath: string; ALine0: Integer): TJSONArray;
begin
  Result:= FServer.ComputeExceptionFactsAt(APath, ALine0);
end;

function TLspServerContextAdapter.HoverMarkdown(const APath: string; ALine0, ACol0: Integer): string;
begin
  Result:= FServer.ComputeHoverMarkdown(APath, ALine0, ACol0);
end;

function TLspServerContextAdapter.Linter: TLinter;
begin
  Result:= FServer.EnsureLinter;
end;

procedure TLspServerContextAdapter.Reply(const AId: TJSONValue; AResult: TJSONValue);
begin
  FServer.SendResult(AId, AResult);
end;

procedure TLspServerContextAdapter.ReplyError(const AId: TJSONValue; ACode: Integer; const AMessage: string);
begin
  FServer.SendError(AId, ACode, AMessage);
end;

procedure TLspServerContextAdapter.Notify(const AMethod: string; AParams: TJSONObject);
begin
  var Obj: TJSONObject:= TJSONObject.Create;
  try
    Obj.AddPair('jsonrpc', '2.0');
    Obj.AddPair('method' , AMethod);
    if AParams <> nil then
    begin
      Obj.AddPair('params', AParams);
      AParams:= nil; { Obj owns it now }
    end;
    FServer.SendRawNotification(Obj);
  finally
    Obj.Free;
    AParams.Free; { only when AddPair never ran }
  end;
end;

constructor TLSPServer.Create(const ADbPath: string);
begin
  Create(TArray<string>.Create(ADbPath));
end;

function TLSPServer.OpenReaderStore(const APath: string): ISymbolStore;
var
  S: ISymbolStore;
begin
  Result:= nil;
  if APath = '' then Exit;
  if not TFile.Exists(APath) then
  begin
    { Server protocol doesn't have a startup-message channel; write to
      stderr so the spawning plugin / shell can surface it. The plugin's
      DebugLog will capture this if redirected. }
    Writeln(ErrOutput, 'drag-lint LSP: db not found, skipping: ', APath);
    Exit;
  end;
  try
    { A READER, since 2026-09-15 (owner ruling 2: only the IDE writes; every
      other client reads -- docs\PLAN-multi-client-index-safety.md). Until
      then this loop opened every --db WRITABLE and ran Migrate (DDL), so each
      editor held a writable, migrated connection to the real project index
      and the 2.98 GB library index, and an editor on an OLDER engine migrated
      the database it was only meant to read. The open is read-write (never
      create) under query_only, with the journal mode the file already has
      (HeaderSaysWal), so the header is left alone too. NOT a true
      SQLITE_OPEN_READONLY, though D25 measured that it opens a WAL index
      fine: this server is often the LAST connection to close, and a
      read-only last closer can neither checkpoint nor delete the -wal/-shm
      -- a graceful `drag-lint shutdown` left both behind, and WAL pages an
      indexer left stayed outside the main file (ruling R21; pinned by
      run_control_channel_guard.ps1 S5 / F1-4).

      A reader does not migrate. A database whose schema predates this engine
      is REFUSED with the same actionable line the read verbs print, and the
      caller moves on: the stores behind it still serve, and the IDE is the
      side that brings the index forward. Pinned by run_lsp_reader_guard.ps1. }
    S:= TSQLiteSymbolStore.Create(APath, {AReadOnly=}True);
    var Found, Expected: Integer;
    S.IsSchemaCurrent(Found, Expected);
    if not IsSchemaReadable(Found) then // 150 SC: the schema read gate (>= SCHEMA_READ_MIN)
    begin
      Expected:= SCHEMA_READ_MIN;
      Writeln(ErrOutput, Format('drag-lint LSP: index schema v%d < v%d, refusing %s -- a reader does not migrate; '
        + 'to migrate, run "drag-lint index --project <file.dproj> --db <db>" for a project index, '
        + 'or "drag-lint index <dir> --db <db>" for a library index', [Found, Expected, APath]));
      Exit;
    end;
    { The skew this server can see is stated once per store, on stderr, where
      the editor's engine log captures it: which engine this is and what the
      index was built by. T4 of the plan -- the skew is now SAFE (T1, T2);
      this line is what makes it VISIBLE. }
    var Stamp: string:= S.GetMetaValue(INDEXER_FINGERPRINT_META_KEY);
    if Stamp = '' then Stamp:= 'unstamped';
    Writeln(ErrOutput, Format('drag-lint LSP: %s (extractor %s) opened read-only %s [index %s]',
      [DRAGLINT_VERSION, DRAGLINT_EXTRACTOR_VERSION, APath, Stamp]));
    Result:= S;
  except
    on E: Exception do Writeln(ErrOutput, 'drag-lint LSP: could not open ', APath, ': ', E.Message);
  end;
end; // function

constructor TLSPServer.Create(const ADbPaths: TArray<string>);var
  I   : Integer     ;
  Path: string      ;
  S   : ISymbolStore;
begin
  inherited Create;
  FExceptionFacts:= True; { D1: owner ruling, default ON }
  FStdIn:= THandleStream.Create(GetStdHandle(STD_INPUT_HANDLE));
  FLinter:= nil;
  SetLength(FStores    , 0);
  SetLength(FStorePaths, 0);
  for I:= 0 to High(ADbPaths) do
  begin
    Path:= ADbPaths[I];
    if Path = '' then Continue;
    { LSP-1 CORE: the open + schema check moved to OpenReaderStore, which the
      lazily opened per-context sets use too. }
    S:= OpenReaderStore(Path);
    if S = nil then Continue;
    SetLength(FStores, Length(FStores) + 1);
    FStores[High(FStores)]:= S;
    { Kept in lockstep with FStores -- appended only on the success path, so
      a db that failed to open never shifts the two out of alignment. }
    SetLength(FStorePaths, Length(FStores));
    FStorePaths[High(FStorePaths)]:= Path;
  end; // for
  if Length(FStores) > 0 then FStore:= FStores[0];
  FSets    := TList<TStoreSet>.Create;
  FCtxCache:= TDictionary<string, TCtxEntry>.Create;
  FNoticed := TDictionary<string, Byte>.Create;
  FNearProjects:= TDictionary<string, TArray<string>>.Create;
  FNearStamps  := TDictionary<string, string>.Create;
  FProjectUnits:= TObjectDictionary<string, TDictionary<string, Byte>>.Create([doOwnsValues]);
  FResolved:= TDictionary<string, TLspDbSet>.Create;
  FWorkLock      := TCriticalSection.Create;
  FStopEvent     := TEvent.Create(nil, True, False, '');
  FReindex       := TDictionary<string, TReindexRun>.Create;
  FReindexThreads:= TObjectList<TThread>.Create({AOwnsObjects=}True);
  FOpenDocs      := TDictionary<string, string>.Create;
  FPublishedTarget:= TDictionary<string, Integer>.Create;
  FProxyPaths    := TList<string>.Create;
  FPending := TObjectList<TJSONObject>.Create({AOwnsObjects=}True);

  { S0 feature registry: one instance per registered class; the first feature
    to claim a method keeps it. Built-in methods never reach this table --
    Run consults it only after its own chain -- so a feature cannot shadow one. }
  FFeatures       := TObjectList<TLspFeature>.Create({AOwnsObjects=}True);
  FFeatureByMethod:= TDictionary<string, TLspFeature>.Create;
  for var FC: TLspFeatureClass in RegisteredLspFeatures do
  begin
    var Feature: TLspFeature:= FC.Create;
    FFeatures.Add(Feature);
    for var M: string in FC.Methods do
      if not FFeatureByMethod.ContainsKey(M) then FFeatureByMethod.Add(M, Feature);
  end;
  FContext:= TLspServerContextAdapter.Create(Self);
  FDeferred:= TQueue<TJSONObject>.Create;
end; // constructor

destructor TLSPServer.Destroy;
begin
  { LSP-1 CORE: watchers first -- each holds FWorkLock while it touches the
    stores and the linter. A child still running is left to finish: it is a
    writer completing its own work. }
  FStopEvent.SetEvent;
  for var T: TThread in FReindexThreads do T.WaitFor;
  if FDeferred <> nil then
    while FDeferred.Count > 0 do FDeferred.Dequeue.Free;
  FDeferred.Free;
  FIdentTree.Free;  { 151 CF: IdentTreeFor's cached parse }
  FExcIndex.Free;   { 151 CF: ExceptionFactLines' open index }
  FContext:= nil;
  FFeatureByMethod.Free;
  FFeatures.Free;
  FLinter.Free;
  FStdIn.Free;
  DropEphemeralStore; { closes the ephemeral connection and removes its %TEMP% database }
  FReindexThreads.Free;
  for var Run: TReindexRun in FReindex.Values do
    if Run.Process <> 0 then CloseHandle(Run.Process);
  FReindex.Free;
  FOpenDocs.Free;
  FPublishedTarget.Free;
  FStopEvent.Free;
  FProxyPaths.Free;
  FWorkLock.Free;
  FPending.Free;
  FNoticed.Free;
  FProjectUnits.Free;
  FNearProjects.Free;
  FNearStamps.Free;
  FResolved.Free;
  FCtxCache.Free;
  FSets.Free;
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
end;

procedure TLSPServer.SendResult(const AId: TJSONValue; AResult: TJSONValue);
var
  Reply: TJSONObject;
begin
  if AResult = nil then AResult:= TJSONNull.Create;
  try
    Reply:= TJSONObject.Create;
  except  // dl:ok bare-except@5cc8 -- frees the not-yet-handed-over JSON value and re-raises; nothing is swallowed
    AResult.Free;
    raise;
  end;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);
    Reply.AddPair('result', AResult);
    AResult:= nil; { Reply owns it now }
    SendMessage(Reply);
  finally
    Reply.Free;
    AResult.Free; { only when the pair was never added }
  end;
end;

function TLSPServer.PositionParams(const AParams: TJSONObject; out APath: string; out ALine0, ACol0: Integer): Boolean;
begin
  APath := '';
  ALine0:= 0;
  ACol0 := 0;
  if AParams = nil then Exit(False);
  var TextDoc : TJSONObject:= AParams.GetValue('textDocument') as TJSONObject;
  var Position: TJSONObject:= AParams.GetValue('position'    ) as TJSONObject;
  if (TextDoc = nil) or (Position = nil) then Exit(False);
  APath := FileFromUri(TextDoc.GetValue('uri').Value);
  ALine0:= StrToIntDef(Position.GetValue('line'     ).Value, 0);
  ACol0 := StrToIntDef(Position.GetValue('character').Value, 0);
  Result:= True;
end; // procedure

class function TLSPServer.FileFromUri(const AUri: string): string;
var
  Decoded: string;
begin
  NoteClientFileUri(AUri); { 148 LS: later server-built URIs follow this client's drive form (c%3A or C:) }
  Result:= AUri;
  if Result.StartsWith('file:///') then Result:= Copy(Result, 9, MaxInt);
  Decoded:= TNetEncoding.URL.Decode(Result);
  Result:= StringReplace(Decoded, '/', '\', [rfReplaceAll]);
end;

function TLSPServer.FileToUri(const APath: string): string;
begin
  Result:= PathToFileUri(APath); { 148 LS: one builder; drive form follows the client }
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
    { Auto uses on save: the kinds are listed so editor.codeActionsOnSave can name them. }
    var CaKinds: TJSONArray:= TJSONArray.Create;
    CaKinds.Add('quickfix');
    for var OnSaveKind: string in KINDS_ON_SAVE do CaKinds.Add(OnSaveKind);
    var CaProvider: TJSONObject:= TJSONObject.Create;
    CaProvider.AddPair('codeActionKinds', CaKinds);
    Caps.AddPair('codeActionProvider'     , CaProvider);
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
    { S0: every registered feature adds its own pairs; HandleInitialize never
      names a feature. }
    for var Feature: TLspFeature in FFeatures do Feature.AddCapabilities(Caps);
    { LSP-1 CORE: draglint.setContext is answered by Run itself, ahead of the
      feature table; it joins whatever command list a feature advertised. }
    var ExecProv: TJSONValue:= Caps.GetValue('executeCommandProvider');
    if (ExecProv is TJSONObject) and (TJSONObject(ExecProv).GetValue('commands') is TJSONArray) then
      TJSONArray(TJSONObject(ExecProv).GetValue('commands')).Add(LSP_CMD_SET_CONTEXT)
    else if ExecProv = nil then
    begin
      var Cmds: TJSONArray:= TJSONArray.Create;
      Cmds.Add(LSP_CMD_SET_CONTEXT);
      var NewProv: TJSONObject:= TJSONObject.Create;
      NewProv.AddPair('commands', Cmds);
      Caps.AddPair('executeCommandProvider', NewProv);
    end;
    { 150 LX2: the capability follows the switch. Under --no-exception-facts no lens runs
      draglint.exceptionFacts and it answers [], so advertising it promised a command that
      does nothing. The feature table cannot see the switch; the server withdraws it here. }
    if (not FExceptionFacts) and (ExecProv is TJSONObject) and (TJSONObject(ExecProv).GetValue('commands') is TJSONArray) then
    begin
      var ExcCmds: TJSONArray:= TJSONArray(TJSONObject(ExecProv).GetValue('commands'));
      for var Ci:= ExcCmds.Count - 1 downto 0 do
        if ExcCmds.Items[Ci].Value = LSP_CMD_EXCEPTION_FACTS then ExcCmds.Remove(Ci).Free;
    end;
    { LSP-1 CORE: initializationOptions (project, platform, config), or the
      IDE's settingsFile (.delphilsp.json), is the client context. }
    if AParams <> nil then
    begin
      var InitOpt: TJSONValue:= AParams.GetValue('initializationOptions');
      if (InitOpt is TJSONObject) and HasContextKeys(TJSONObject(InitOpt)) then ApplyClientContext(TJSONObject(InitOpt))
      else if (InitOpt is TJSONObject) and (JsonStrOf(TJSONObject(InitOpt), 'settingsFile') <> '') then
        ApplyClientSettingsFile(FileFromUri(JsonStrOf(TJSONObject(InitOpt), 'settingsFile')));
    end;
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
  // C15: the C9 preprocessed parse (inactive IFDEF branches blanked, length-preserving, so
  // Source still slices the identifier text) with a bounded read callback.
  Tree:= IdentTreeFor(Source, APath);  { 151 CF: cached; owned by the server, not freed here }
  if Tree = nil then Exit;
  begin
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
  end;
end; // function

function TLSPServer.IdentTreeFor(const ASource: TBytes; const APath: string): TTSTree;
begin
  { The key is what the PARSER sees: ParseDelphiUtf8 preprocesses with the file's define
    profile, which a setContext can change without the source changing. Comparing the
    preprocessed bytes makes that a miss; a change confined to an inactive branch is a hit,
    and the tree for it is the same tree (the blanking is length-preserving). }
  var Pre: TBytes:= TAstParseCache.ApplyPreprocess(ASource, APath);
  if (FIdentTree <> nil) and SameText(FIdentTreePath, APath) and (Length(Pre) = Length(FIdentTreePre))
     and ((Length(Pre) = 0) or CompareMem(@Pre[0], @FIdentTreePre[0], Length(Pre))) then
    Exit(FIdentTree);
  FreeAndNil(FIdentTree);
  FIdentTreePath:= '';
  FIdentTreePre := nil;
  FIdentTree:= ParseDelphiUtf8(ASource, APath);
  if FIdentTree <> nil then
  begin
    FIdentTreePath:= APath;
    FIdentTreePre := Pre  ;
  end;
  Result:= FIdentTree;
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
{ A5: a thin envelope over ComputeWorkspaceSymbols, which the merge proxy also
  answers from. }
var
  QueryStr: string;
begin
  QueryStr:= '';
  if (AParams <> nil) and (AParams.GetValue('query') <> nil) then QueryStr:= AParams.GetValue('query').Value;
  SendResult(AId, ComputeWorkspaceSymbols(QueryStr));
end; // procedure

function TLSPServer.ComputeWorkspaceSymbols(const AQuery: string): TJSONArray;
const
  { At most this many fuzzy matches per store when no exact name matches. }
  FUZZY_MAX_PER_STORE = 50;
var
  Arr    : TJSONArray     ;
  Symbols: TArray<TSymbol>;
  Sym    : TSymbol        ;
  SymObj : TJSONObject    ;
  StIdx  : Integer        ;
  StCur  : ISymbolStore   ;
  Kind   : Integer        ;
begin
  Arr:= TJSONArray.Create;
  try
    if (Length(FStores) = 0) or (AQuery = '') then Exit(Arr);
    { v0.40.3: iterate every store, merge results. For each store, prefer
      exact-name matches; fall back to fuzzy when exact returns nothing.
      Per-store fallback is intentional -- if project DB has an exact hit
      we don't want library DB's fuzzy noise diluting the result. }
    for StIdx:= 0 to High(FStores) do
    begin
      StCur:= FStores[StIdx];
      Symbols:= StCur.FindSymbolsByExactName(AQuery);
      if Length(Symbols) = 0 then Symbols:= StCur.FindSymbolsFuzzy(AQuery, FUZZY_MAX_PER_STORE);
      for Sym in Symbols do
      begin
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
        SymObj:= TJSONObject.Create;
        Arr.AddElement(SymObj);
        SymObj.AddPair('name', Sym.Name);
        SymObj.AddPair('kind', TJSONNumber.Create(Kind));
        SymObj.AddPair('containerName', Sym.QualifiedName);
        SymObj.AddPair('location', LocationFromSymbol(Sym, StCur));
      end; // for
    end; // for
  except  // dl:ok bare-except@bb6b -- frees the not-yet-handed-over JSON value and re-raises; nothing is swallowed
    Arr.Free;
    raise;
  end; // try
  Result:= Arr;
end; // function

procedure TLSPServer.HandleDefinition(const AId: TJSONValue; const AParams: TJSONObject);
{ S0: a thin envelope over ComputeDefinition, which features reach through
  ILspServerContext.Definition -- one body, so the two cannot disagree. }
var
  Path: string ;
  Line: Integer;
  Col : Integer;
begin
  if (Length(FStores) = 0) or not PositionParams(AParams, Path, Line, Col) then
    SendResult(AId, TJSONArray.Create)
  else
    SendResult(AId, ComputeDefinition(Path, Line, Col));
end; // procedure

function TLSPServer.ComputeDefinition(const APath: string; ALine0, ACol0: Integer): TJSONArray;
var
  Arr    : TJSONArray     ;
  Path   : string         ;
  Ident  : string         ;
  Symbols: TArray<TSymbol>;
  Sym    : TSymbol        ;
begin
  Arr:= TJSONArray.Create;
  try
    Path:= APath;
    if Length(FStores) = 0 then Exit(Arr);
    Ident:= IdentifierAtPosition(Path, ALine0, ACol0);
    if Ident <> '' then
    begin
      { v0.40.3: iterate every store, accumulate definitions.

        THROUGH StoresForFile, exactly as ComputeHover does. Hover was taught to
        put a loose file's own unit in front of the library; F12 was not, so
        hovering a symbol named the local declaration and pressing F12 on the
        same symbol jumped into the RTL. Measured on the guard fixture: Apply in
        an unowned unit returned FarAwayLib.pas and never LooseUnit.pas. }
      var DefStores: TArray<ISymbolStore>:= StoresForFile(Path);
      for var StIdx:= 0 to High(DefStores) do
      begin
        Symbols:= DefStores[StIdx].FindSymbolsByExactName(Ident);
        for Sym in Symbols do Arr.AddElement(LocationFromSymbol(Sym, DefStores[StIdx]));
        { The file's own declaration wins outright -- see EphemeralLeads. A name
          the loose unit does NOT declare finds nothing here and falls through to
          the library, which is how a library-only symbol stays reachable. }
        if (StIdx = 0) and (Length(Symbols) > 0) and EphemeralLeads(DefStores) then Break;
      end;
    end;
  except  // dl:ok bare-except@bb6b -- frees the not-yet-handed-over JSON value and re-raises; nothing is swallowed
    Arr.Free;
    raise;
  end; // try
  Result:= Arr;
end; // function

procedure TLSPServer.HandleReferences(const AId: TJSONValue; const AParams: TJSONObject);
{ S0: a thin envelope over ComputeReferences (ILspServerContext.References). }
var
  Path       : string     ;
  Line       : Integer    ;
  Col        : Integer    ;
  Context    : TJSONObject;
  IncludeDecl: Boolean    ;
begin
  if (Length(FStores) = 0) or not PositionParams(AParams, Path, Line, Col) then
  begin
    SendResult(AId, TJSONArray.Create);
    Exit;
  end;
  IncludeDecl:= True;
  Context:= AParams.GetValue('context') as TJSONObject;
  if Context <> nil then
  begin
    var IncDeclVal:= Context.GetValue('includeDeclaration');
    if IncDeclVal is TJSONBool then IncludeDecl:= TJSONBool(IncDeclVal).AsBoolean;
  end;
  SendResult(AId, ComputeReferences(Path, Line, Col, IncludeDecl));
end; // procedure

destructor TLspCaptureContext.Destroy;
begin
  FResult.Free;
  inherited Destroy;
end;

procedure TLspCaptureContext.Reply(const AId: TJSONValue; AResult: TJSONValue);
begin
  FResult.Free;
  FResult:= if AResult = nil then TJSONNull.Create else AResult;
end;

procedure TLspCaptureContext.ReplyError(const AId: TJSONValue; ACode: Integer; const AMessage: string);
begin
  Writeln(ErrOutput, 'drag-lint LSP: a feature answered an error (', ACode, '): ', AMessage);   { stderr only: stdout is the relay's }
end;

function TLspCaptureContext.TakeResult: TJSONValue;
begin
  Result := FResult;
  FResult:= nil;
end;

function TLSPServer.ComputeFeatureResult(const AMethod: string; const AParams: TJSONObject): TJSONValue;
var
  Feature: TLspFeature;
begin
  Result:= nil;
  if not FFeatureByMethod.TryGetValue(AMethod, Feature) then Exit;
  var Capture: TLspCaptureContext:= TLspCaptureContext.Create(Self);
  var Ctx: ILspServerContext:= Capture;   { the interface reference owns the instance }
  var Id: TJSONValue:= TJSONNumber.Create(0);   { a feature replies only to a request; the id goes nowhere }
  try
    FWorkLock.Enter;
    try
      Feature.Handle(Ctx, AMethod, Id, AParams);
    finally
      FWorkLock.Leave;
    end;
    Result:= Capture.TakeResult;
  finally
    Id.Free;
  end;
end;

function TLSPServer.ComputeReferences(const APath: string; ALine0, ACol0: Integer; AIncludeDecl: Boolean): TJSONArray;
var
  Arr        : TJSONArray        ;
  Path       : string            ;
  Ident      : string            ;
  Refs       : TArray<TReference>;
  Symbols    : TArray<TSymbol>   ;
  IncludeDecl: Boolean           ;
  R          : TReference        ;
  Sym        : TSymbol           ;
begin
  Arr:= TJSONArray.Create;
  try
    Path       := APath;
    IncludeDecl:= AIncludeDecl;  // dl:ok duplicate-code@106a -- the Arr/try/IdentifierAtPosition prologue ComputeDefinition shares; both bodies were already duplicated in the pre-S0 handlers and S0 moved them verbatim
    if Length(FStores) = 0 then Exit(Arr);
    Ident:= IdentifierAtPosition(Path, ALine0, ACol0);
    if Ident <> '' then
    begin
      { v0.40.3: iterate every store for both callers and declarations.
        Through StoresForFile for the same reason HandleDefinition does. }
      var RefStores: TArray<ISymbolStore>:= StoresForFile(Path);
      for var StIdx:= 0 to High(RefStores) do
      begin
        Refs:= RefStores[StIdx].FindCallersByName(Ident);
        for R in Refs do Arr.AddElement(LocationFromRef(R, RefStores[StIdx]));
        if IncludeDecl then
        begin
          Symbols:= RefStores[StIdx].FindSymbolsByExactName(Ident);
          for Sym in Symbols do Arr.AddElement(LocationFromSymbol(Sym, RefStores[StIdx]));
        end;
        { NO early Break here, unlike HandleDefinition, and the difference is
          deliberate. 'Go to definition' wants the ONE declaration the reader is
          standing on; 'find all references' wants BREADTH, so stopping at the
          first store that answered would drop exactly what was asked for.
          Measured while writing this: with the Break in, references on a
          library-only routine returned the loose file's call site and silently
          LOST the library declaration that includeDeclaration had requested.
          The defect being fixed here is that the loose unit's own refs were
          MISSING, not that the other stores' were present. }
      end;
    end;
  except  // dl:ok bare-except@bb6b -- frees the not-yet-handed-over JSON value and re-raises; nothing is swallowed
    Arr.Free;
    raise;
  end; // try
  Result:= Arr;
end; // function

// v0.42: render a symbol as a Code-Insight-style declaration line, e.g.
//   function TShape.Area: Double          (proc-likes: sig has params+return)
//   constructor Create(const AName: string)
//   property Name: string                 (prop/field/const/var: sig is type)
//   class TShape                          (containers: no signature)
// Signature already carries the leading '(' or ': ' for proc-likes, so we
// concatenate directly; for type-valued kinds we insert ': ' before the type.
// Value kinds take their type from DescribeDeclaredType -- the describer the
// hover model uses -- so a bare re-published property ('property Text;')
// shows the type its ancestor declares, plus a '// declared in' note, and a
// local var / parameter shows its type at all. AStore owns ASym.
function DeclLineFor(const ASym: TSymbol; const AStore: ISymbolStore): string;
var
  Keyword : string;
  Sig     : string;
  Declared: TDeclaredType;
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
    skField, skVarDecl, skLocalVar: Keyword:= 'var';
    skConstDecl: Keyword:= 'const';
    skParam    : Keyword:= '';
    else Keyword:= ASym.Kind.ToText;
  end; // case
  { 1.40 (CLASSCTOR-KIND): 'class constructor Create', as declared. }
  if ASym.IsClassMethod and (Keyword <> '') then Keyword:= 'class ' + Keyword;

  case ASym.Kind of
    skFunction, skProcedure, skConstructor, skDestructor, skMethod:
      // Sig is '(args): Ret' or ': Ret' or '(args)' or '' -- concat directly.
      Result:= Format('%s %s%s', [Keyword, ASym.Name, Sig]);
    skProperty, skField, skVarDecl, skConstDecl, skLocalVar, skParam:
      begin
        Declared:= DescribeDeclaredType(ASym, AStore);
        { A const keeps its whole signature ('Integer = 5'): the value is the
          point of hovering one. }
        if (ASym.Kind <> skConstDecl) and (Declared.TypeName <> '') then Sig:= Declared.TypeName;
        Result:= if Sig <> '' then Trim(Format('%s %s: %s', [Keyword, ASym.Name, Sig]))
                  else Trim(Format('%s %s', [Keyword, ASym.Name]));
        if Declared.DeclaredIn <> '' then Result:= Result + '  // declared in ' + Declared.DeclaredIn;
      end;
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

{ ---- ephemeral single-unit index -------------------------------------------
  INBOX-lsp-hover-unindexed-file-resolves-library-symbol. See the field block
  on TLSPServer for the defect and the owner's ruling; only the mechanics are
  here. Guarded by tests\autotest\run_lsp_hover_unindexed_file.ps1, which was
  run RED first: CASE 1 and CASE 2 named FarAwayLib.TFarAwayThing.Apply while
  PC1/PC2/NC1/NC2 passed. }

function TLSPServer.AnyStoreOwns(const APath: string): Boolean;
begin
  Result:= False;
  if APath = '' then Exit;
  for var St in FStores do
    if St.FindFileIdByPath(APath) > 0 then Exit(True);
end; // function

procedure TLSPServer.DropEphemeralStore;
{ Releasing the interface closes the connection; the -wal/-shm companions are
  WAL-mode siblings of the same database and go with it. Best-effort by design:
  a file left behind in %TEMP% is a nuisance, an exception raised on didClose is
  a broken session. }
begin
  FEphemStore:= nil;
  FEphemFile := '';
  FEphemStamp:= 0;
  if FEphemDbPath = '' then Exit;
  for var Suffix in TArray<string>.Create('', '-wal', '-shm') do
    try
      if TFile.Exists(FEphemDbPath + Suffix) then TFile.Delete(FEphemDbPath + Suffix);
    except
      { see above -- deliberately swallowed }
    end;
  FEphemDbPath:= '';
end; // procedure

function TLSPServer.BuildEphemeralStore(const APath: string; AStamp: TDateTime): Boolean;
var
  SavedOut: TTextRec;
begin
  Result:= False;
  DropEphemeralStore;
  Inc(FEphemSeq);
  { The database goes to %TEMP%, never beside the user's source -- a stray
    .sqlite dropped next to a file someone merely HOVERED would be a second
    defect, and this repo has already paid for one of those
    (stray-empty-index-on-retired-default-path). Named by pid + sequence so a
    handle a previous attempt failed to release can never be reopened by
    accident. Recorded on the field immediately, so the except below can
    delete it. }
  FEphemDbPath:= TPath.Combine(TPath.GetTempPath,
    Format('drag-lint-lsp-ephem-%d-%d.sqlite', [GetCurrentProcessId, FEphemSeq]));
  try
    if TFile.Exists(FEphemDbPath) then TFile.Delete(FEphemDbPath);

    var S: ISymbolStore:= TSQLiteSymbolStore.Create(FEphemDbPath);
    S.Migrate;

    { Delphi parser only. A .dfm carries no hover positions of its own and the
      SQL parser would claim nothing here; both would only widen what this path
      can fail at. }
    var Idx: TIndexer:= TIndexer.Create(S, [TDelphi13Parser.Create]);
    try
      { TIndexer reports per-file progress with a BARE Writeln -- that is
        System.Output, and in THIS process stdout IS the JSON-RPC transport
        (SendMessage writes STD_OUTPUT_HANDLE directly). A single
        '  <path> -> N symbols' line ahead of a Content-Length header
        desynchronises the client for the rest of the session, which is a worse
        failure than the hover this fixes. Redirect for the duration, exactly as
        DoReconcileProject does for the same reason, and restore in the finally
        so an exception cannot leak the redirect.

        Editing Indexer.pas to take a quiet flag would be the tidier fix and is
        FORBIDDEN here: that unit is inside the DRAGLINT_EXTRACTOR_VERSION hash
        surface, so touching it re-parses every database on the machine.

        run_lsp_hover_unindexed_file.ps1 asserts on the RAW stdout of the very
        reply that builds the index (NC2), because a redirect that silently
        stopped working would otherwise look exactly like success. }
      try
        Move(TTextRec(Output), SavedOut, SizeOf(TTextRec));
        AssignFile(Output, 'NUL');
        Rewrite(Output);
        Idx.IndexFile(APath);
      finally
        { Guarded, unlike the CLI precedent: if Rewrite itself failed, Output is
          assigned-but-not-open and Flush would raise from inside a finally --
          losing the real error AND leaving stdout redirected. The Move has to
          happen either way. }
        try
          Flush    (Output);
          CloseFile(Output);
        except
          { NUL may never have opened }
        end;
        Move(SavedOut, TTextRec(Output), SizeOf(TTextRec));
      end;

      { The link passes an ordinary scan runs, MINUS ResolveCallTargets. Hover
        needs declarations, uses and ancestry; call edges it does not, and
        ResolveCallTargets is the one pass that would reach across into the
        library index -- unbounded work on the hover path. One file, so these
        four are microseconds.

        The fourth, ApplyInheritedFieldFacts (v23, spec F2), is why Idx is
        still alive here: it consumes the held-identifier list the parse left
        on THIS indexer instance, so it must run on the same Idx, AFTER
        ResolveAncestry (it reads the ancestry that pass just wrote) and
        BEFORE Idx.Free. Without it a hover on a method of a file no store
        owns showed 'Writes: FOwn' and dropped a field the method assigns
        on its base class -- the one fact an ephemeral store CAN know, when
        the base is declared in the same unit. A base in another unit is out
        of reach here by construction (one-file store, F6: absence, never a
        guess). It writes nothing to stdout itself (the CLI's Stage wrapper
        prints the 'facts-inherited' line, not the method), so it runs
        outside the redirect; NC2 in run_lsp_hover_unindexed_file.ps1 reads
        the raw stdout of this very reply and would catch a print. }
      S.ResolveUnitUseTargets;
      S.ResolveAncestry;
      S.ResolveHelpers;
      Idx.ApplyInheritedFieldFacts;
    finally
      Idx.Free;
    end;

    { EXISTENCE IS NOT SUFFICIENCY. A store that opened cleanly and holds
      nothing answers 'not mine' for everything and would push the real answer
      one place further away, so the ephemeral store is adopted only once it
      demonstrably contains the file. }
    if S.FindFileIdByPath(APath) <= 0 then
    begin
      S:= nil;
      DropEphemeralStore;
      Exit;
    end;

    FEphemStore:= S;
    FEphemFile := APath;
    FEphemStamp:= AStamp;
    Result     := True;
  except
    on E: Exception do
    begin
      { Never fatal. The caller falls back to the ordinary store list, i.e. the
        behaviour that shipped before this existed. stderr, never stdout. }
      Writeln(ErrOutput, 'drag-lint LSP: ephemeral index failed for ', APath, ': ', E.Message);
      DropEphemeralStore;
    end;
  end; // try
end; // function

{ Does AStores lead with the ephemeral single-unit store -- i.e. was this list
  built for a file NO configured index owns?

  Callers use it to let the file's OWN declaration win outright. Accumulating
  across every store is right for a multi-DB project, where the same name
  legitimately lives in several project databases; it is wrong for a loose file,
  where the library's namesakes are noise in front of the declaration the reader
  is standing on. Scoped deliberately: for a file some index DOES own,
  StoresForFile returns FStores unchanged, this returns False, and every request
  behaves exactly as it did before. }
function TLSPServer.EphemeralLeads(const AStores: TArray<ISymbolStore>): Boolean;
begin
  Result:= (FEphemStore <> nil) and (Length(AStores) > 0) and (AStores[0] = FEphemStore);
end;

{ ---- LSP-1 CORE: per-file project context ----------------------------------
  SPEC.md (C:\TEMP\claude\lanes\lsp-context) 1b + 3; owner ruling D1: the LSP
  answers like the IDE -- the file's active project + platform select THAT
  project's DB and THAT platform's library DB, never another project's store.
  Guarded by tests\autotest\run_lsp_context_*.ps1. }

{ The libraries.<APlatform>.libraryDb of the central defaults, or ''. }
function DefaultsLibraryDbFor(const ADefaults: TContextDefaults; const APlatform: string): string;
begin
  Result:= '';
  for var L: TLibraryDefault in ADefaults.Libraries do
    if SameText(L.PlatformName, APlatform) then Exit(L.LibraryDb);
end;

{ The outDir a PRIVATE engine copy's own drag-lint.json declares, with a trailing
  delimiter; '' for an engine at a deployed location, for no json, for no outDir. }
function PrivateEngineOutDir: string;
begin
  Result:= '';
  var ExeDir: string:= ExtractFilePath(ParamStr(0));
  var LowDir: string:= LowerCase(ExeDir);
  if LowDir.Contains('\third_party\dll-win64\') or LowDir.Contains('\program files')
    or LowDir.Contains('\appdata\local\programs\') or LowDir.Contains('\globalstorage\') then Exit;
  var Cfg: string:= ExeDir + 'drag-lint.json';
  if not TFile.Exists(Cfg) then Exit;
  try
    var Manifest: TIndexManifest:= TManifestIO.ParseText(TFile.ReadAllText(Cfg), ExeDir);
    if Manifest.OutDir <> '' then
      Result:= IncludeTrailingPathDelimiter(TPath.GetFullPath(TPath.Combine(ExeDir, Manifest.OutDir)));
  except
    on E: Exception do Result:= ''; { a manifest that will not load keeps today's fallback }
  end;
end;

{ E-PLATLIB-PRIVATE-OUTDIR: the central defaults belong to the USER, not to this engine. A
  private engine that names its own outDir must not reach through them to the real library,
  so a defaults library outside that outDir is dropped, and stderr says so. A deployed engine
  keeps every entry. Pinned by tests\autotest\run_lsp_library_private_outdir.ps1. }
function LibrariesVisibleToThisEngine(const ALibraries: TArray<TLibraryDefault>): TArray<TLibraryDefault>;
begin
  Result:= ALibraries;
  var OutDir: string:= PrivateEngineOutDir;
  if OutDir = '' then Exit;
  Result:= nil;
  for var L: TLibraryDefault in ALibraries do
    if (L.LibraryDb = '') or StartsText(OutDir, TPath.GetFullPath(L.LibraryDb)) then Result:= Result + [L]
    else Writeln(ErrOutput, 'drag-lint LSP: private engine: defaults library ', L.LibraryDb, ' ignored, it is outside the outDir of this engine''s drag-lint.json (', OutDir, ')');
end;

function TLSPServer.Defaults: TContextDefaults;
begin
  if not FDefaultsRead then
  begin
    FDefaultsRead:= True;
    if TryLoadContextDefaults(FDefaults) then FDefaults.Libraries:= LibrariesVisibleToThisEngine(FDefaults.Libraries)
    else FDefaults:= Default(TContextDefaults);
  end;
  Result:= FDefaults;
end;

function TLSPServer.DprojStamp(const AFile: string): string;
begin
  Result:= '';
  try
    if (AFile <> '') and TFile.Exists(AFile) then
      Result:= FormatDateTime('yyyymmddhhnnsszzz', TFile.GetLastWriteTime(AFile));
  except
    on E: Exception do Result:= ''; // an unreadable stamp only costs a re-resolve
  end;
end;

function ProjectSearchStamp(const APath: string): string; forward;

function TLSPServer.FileContext(const APath: string): TLspFileContext;
var
  Key  : string;
  Entry: TCtxEntry;
begin
  Key:= LowerCase(APath);
  var Had: Boolean:= FCtxCache.TryGetValue(Key, Entry);
  if Had and (Entry.Ctx.Project <> '') and (Entry.Stamp = DprojStamp(Entry.Ctx.Project)) then Exit(Entry.Ctx);
  { 148 LS: a file with no project re-checks the folders the project search reads (at most
    every LSP_CTX_RECHECK_MS), so a project file created mid-session is seen without a restart. }
  if Had and (Entry.Ctx.Project = '') then
  begin
    var NowTick: UInt64:= GetTickCount64;
    if NowTick - Entry.Checked < LSP_CTX_RECHECK_MS then Exit(Entry.Ctx);
    Entry.Checked:= NowTick;
    if Entry.Stamp = ProjectSearchStamp(APath) then
    begin
      FCtxCache.AddOrSetValue(Key, Entry);
      Exit(Entry.Ctx);
    end;
  end;
  if Had then TProjectProfileCache.Forget(APath); { its file -> .dproj memo may hold the answer of before }
  Entry.Ctx    := ComputeFileContext(APath);
  Entry.Stamp  := if Entry.Ctx.Project <> '' then DprojStamp(Entry.Ctx.Project) else ProjectSearchStamp(APath);
  Entry.Checked:= GetTickCount64;
  FCtxCache.AddOrSetValue(Key, Entry);
  Result:= Entry.Ctx;
end;

{ Wave 149 LX (a3 display, aligned to EffectiveIndexPlatform since b76a5e20): the platform of a
  .dproj that carries no active selection (no $(Platform) marker, no delphilsp.json): the
  manifest's defaultPlatform, else Win32 (owner ruling a3). It used to be the platform the
  project DECLARES (Win64 if targeted): neither the index nor the per-file lint reads that set,
  so the status said Win64 over a parse that was Win32. Never raises. }
function MarkerlessDprojPlatform: string;
const
  NO_PLATFORM_DEFAULT = 'Win32'; // ruling a3: no platform named anywhere -> Win32
begin
  Result:= '';
  try
    Result:= TManifestIO.Load(ExtractFilePath(ParamStr(0)), GetCurrentDir).Settings.DefaultPlatform;
  except
    on E: Exception do Result:= ''; // fail-open: an unreadable manifest names no default
  end;
  if Result = '' then Result:= NO_PLATFORM_DEFAULT;
end;

{ A folder FindListingProject never looks inside: index, build and VCS output. }
function IsProjectSearchSkipped(const AName: string): Boolean;
begin
  Result:= MatchText(AName, ['_D-RAG', '__history', '__recovery', 'Win32', 'Win64', '.git', '.hg', 'node_modules']);
end;

{ The checkout's top: a .git folder, a .git FILE (a worktree) or an .hg folder. }
function IsRepositoryRoot(const ADir: string): Boolean;
var
  Git: string;
begin
  Git:= TPath.Combine(ADir, '.git');
  Result:= TDirectory.Exists(Git) or TFile.Exists(Git) or TDirectory.Exists(TPath.Combine(ADir, '.hg'));
end;

{ Project files directly in ADir, sorted; a .dpr only when no .dproj of its name exists. }
function ProjectFilesIn(const ADir: string): TArray<string>;
begin
  Result:= nil;
  try
    Result:= TDirectory.GetFiles(ADir, '*.dproj');
    { *.dpr also matches .dproj through the 8.3 name: test the real extension. }
    for var F: string in TDirectory.GetFiles(ADir, '*.dpr') do
      if SameText(ExtractFileExt(F), '.dpr') and not TFile.Exists(ChangeFileExt(F, '.dproj')) then
        Result:= Result + [F];
    TArray.Sort<string>(Result);
  except
    on E: Exception do Result:= nil; // an unreadable folder holds no candidate
  end;
end;

{ 148 LS: what a project search of ADir reads -- the write time of ADir and of each folder
  just under it that NearProjects lists. Creating or deleting a file changes its folder's
  write time, so a project file created mid-session changes the stamp. '' = unreadable. }
function NearStamp(const ADir: string): string;
begin
  Result:= '';
  try
    var Sb: TStringBuilder:= TStringBuilder.Create;
    try
      Sb.Append(FormatDateTime(LSP_DIR_STAMP_FMT, TDirectory.GetLastWriteTime(ADir)));
      var Subs: TArray<string>:= TDirectory.GetDirectories(ADir);
      TArray.Sort<string>(Subs);
      if Length(Subs) > LSP_PROJECT_SEARCH_DIRS then SetLength(Subs, LSP_PROJECT_SEARCH_DIRS);
      for var D: string in Subs do
        if not IsProjectSearchSkipped(ExtractFileName(D)) then
          Sb.Append('|').Append(FormatDateTime(LSP_DIR_STAMP_FMT, TDirectory.GetLastWriteTime(D)));
      Result:= Sb.ToString;
    finally
      Sb.Free;
    end;
  except
    on E: Exception do Result:= ''; // an unreadable folder keeps its last listing
  end;
end;

{ 148 LS: the NearStamp of every folder FindListingProject climbs for APath, in its order
  and with its stops (LSP_PROJECT_SEARCH_LEVELS, the repository root, the drive root). }
function ProjectSearchStamp(const APath: string): string;
begin
  Result:= '';
  var Dir: string:= ExcludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(APath)));
  for var Level:= 0 to LSP_PROJECT_SEARCH_LEVELS do
  begin
    if (Dir = '') or not TDirectory.Exists(Dir) then Exit;
    Result:= Result + '/' + NearStamp(Dir);
    if IsRepositoryRoot(Dir) then Exit;
    var Parent: string:= ExcludeTrailingPathDelimiter(ExtractFilePath(Dir));
    if SameText(Parent, Dir) then Exit;
    Dir:= Parent;
  end;
end;

function TLSPServer.NearProjects(const ADir: string): TArray<string>;
var
  Key: string;
begin
  Key:= LowerCase(ADir);
  var Stamp: string:= NearStamp(ADir); { 148 LS: was session-long; a changed folder is re-listed }
  var Seen: string;
  if FNearProjects.TryGetValue(Key, Result) and FNearStamps.TryGetValue(Key, Seen) and (Seen = Stamp) then Exit;
  Result:= ProjectFilesIn(ADir);
  try
    var Subs: TArray<string>:= TDirectory.GetDirectories(ADir);
    TArray.Sort<string>(Subs);
    if Length(Subs) > LSP_PROJECT_SEARCH_DIRS then SetLength(Subs, LSP_PROJECT_SEARCH_DIRS);
    for var D: string in Subs do
      if not IsProjectSearchSkipped(ExtractFileName(D)) then Result:= Result + ProjectFilesIn(D);
  except
    on E: Exception do Writeln(ErrOutput, 'drag-lint LSP: project search skipped ', ADir, ': ', E.Message);
  end;
  FNearProjects.AddOrSetValue(Key, Result);
  FNearStamps.AddOrSetValue(Key, Stamp);
end;

{ Does the project file LIST this exact unit path? A .dproj's DCCReference, a .dpr's
  `in '...'`, each resolved from the project's own folder -- so a relocated checkout
  still matches, and a same-named unit elsewhere never does. Memoised per project +
  stamp: the files of one folder share one read. }
function TLSPServer.ProjectListsUnit(const AProject, AUnitLower: string): Boolean;
var
  Key  : string;
  Units: TDictionary<string, Byte>;
begin
  Result:= False;
  try
    Key:= LowerCase(AProject) + '|' + DprojStamp(AProject);
    if not FProjectUnits.TryGetValue(Key, Units) then
    begin
      Units:= TDictionary<string, Byte>.Create;
      FProjectUnits.Add(Key, Units);
      var Text: string:= TFile.ReadAllText(AProject);
      var Pattern: string:= if SameText(ExtractFileExt(AProject), '.dproj') then '<DCCReference\s+Include="([^"]+)"'
        else '\bin\s+''([^'']+)''';
      for var M: TMatch in TRegEx.Matches(Text, Pattern, [roIgnoreCase]) do
        Units.AddOrSetValue(LowerCase(ExpandFileName(TPath.Combine(ExtractFilePath(AProject), M.Groups[1].Value))), 1);
    end;
    Result:= Units.ContainsKey(AUnitLower);
  except
    on E: Exception do Writeln(ErrOutput, 'drag-lint LSP: cannot read project ', AProject, ': ', E.Message);
  end;
end;

{ 1.44 lspctx: the project of a unit no index holds -- a worktree, a copy, a unit not
  indexed yet, an index mid-rebuild. Climbs from the unit's folder to the repository
  root (at most LSP_PROJECT_SEARCH_LEVELS without one), looking at each level in the
  folder and its immediate sub-folders, because a project is often a SIBLING of the
  unit's folder (src\cli\drag-lint.dproj, src\report\X.pas), not an ancestor. The
  nearest level with a project LISTING the unit wins, then path order; AOthers names
  the rest. Only ever a project that lists this exact path: never a guess. }
function TLSPServer.FindListingProject(const APath: string; out AOthers: string): string;
begin
  Result := '';
  AOthers:= '';
  var Full: string:= ExpandFileName(APath);
  var UnitLower: string:= LowerCase(Full);
  var Dir: string:= ExcludeTrailingPathDelimiter(ExtractFilePath(Full));
  for var Level:= 0 to LSP_PROJECT_SEARCH_LEVELS do
  begin
    if (Dir = '') or not TDirectory.Exists(Dir) then Exit;
    for var P: string in NearProjects(Dir) do
      if ProjectListsUnit(P, UnitLower) then
        if Result = '' then Result:= P
        else AOthers:= if AOthers = '' then ExtractFileName(P) else AOthers + ', ' + ExtractFileName(P);
    if (Result <> '') or IsRepositoryRoot(Dir) then Exit;
    var Parent: string:= ExcludeTrailingPathDelimiter(ExtractFilePath(Dir));
    if SameText(Parent, Dir) then Exit;
    Dir:= Parent;
  end;
end;

{ The startup project stores holding APath other than AProject's own, by DB file name,
  or ''. Already-open stores, one indexed lookup each, once per file (FCtxCache). }
function TLSPServer.OtherOwningStores(const APath, AProject: string): string;
begin
  Result:= '';
  var Own: string:= ChangeFileExt(ExtractFileName(AProject), '.sqlite');
  for var I:= 0 to High(FStores) do
    if (I <= High(FStorePaths)) and not IsLibraryPath(FStorePaths[I])
       and not SameText(ExtractFileName(FStorePaths[I]), Own) and (FStores[I].FindFileIdByPath(APath) > 0) then
      Result:= if Result = '' then ExtractFileName(FStorePaths[I]) else Result + ', ' + ExtractFileName(FStorePaths[I]);
end;

{ The platform of the startup library store holding APath, or '': a library unit's
  platform is known even though it has no project. }
function TLSPServer.StartupLibraryPlatformOf(const APath: string): string;
const
  LIBRARY_PREFIX = 'library-';
begin
  Result:= '';
  for var I:= 0 to High(FStores) do
    if (I <= High(FStorePaths)) and IsLibraryPath(FStorePaths[I]) and (FStores[I].FindFileIdByPath(APath) > 0) then
      Exit(Copy(ChangeFileExt(ExtractFileName(FStorePaths[I]), ''), Length(LIBRARY_PREFIX) + 1, MaxInt));
end;

function TLSPServer.ComputeFileContext(const APath: string): TLspFileContext;
var
  Ctx    : TProjectContext;
  HaveCtx: Boolean;
  P, C   : string;
  PlatSrc: string;
  LspDefs: TArray<string>;
  LspNum : TArray<TPair<string, Integer>>;
  LspSw  : TArray<TPair<string, Boolean>>;
begin
  Result       := Default(TLspFileContext);
  Result.Source:= lcsPlaceholder;
  Ctx          := Default(TProjectContext);
  HaveCtx      := False;
  P:= '';
  C:= '';
  { Project: startup > client/IDE > owning .dproj > .dlcontext.json (only when no
    .dproj owns the file; a stale one falls back to the .dproj it names). }
  if FStartProject <> '' then
  begin
    Result.Project:= ExpandFileName(FStartProject);
    Result.Source := lcsStartup;
  end
  else if FClientProject <> '' then
  begin
    Result.Project:= FClientProject;
    Result.Source := lcsClient;
    HaveCtx:= FHaveClientCtx;
    if HaveCtx then Ctx:= FClientCtx;
  end
  else
  begin
    Result.Project:= TProjectProfileCache.BuildForFile(APath).Dproj;
    if Result.Project <> '' then Result.Source:= lcsDproj
    else if FindProjectContextForUnit(APath, Ctx) then
    begin
      if Ctx.Stale then
      begin
        Result.StaleContextFile:= ContextFileFor(Ctx.SourceFile);
        Result.Project:= Ctx.SourceFile;
        Result.Source := lcsDproj;
      end
      else
      begin
        HaveCtx       := True;
        Result.Source := lcsContextFile;
        Result.Project:= if Ctx.Project <> '' then Ctx.Project else Ctx.SourceFile;
      end;
    end;
    { 1.44 lspctx: no index holds the path and no context file names a project: the
      project file that LISTS it. }
    if Result.Project = '' then
    begin
      Result.Project:= FindListingProject(APath, Result.AlsoHeldBy);
      if Result.Project <> '' then Result.Source:= lcsDproj;
    end
    else if (Result.Source = lcsDproj) and (Result.StaleContextFile = '') then
      Result.AlsoHeldBy:= OtherOwningStores(APath, Result.Project);
  end;
  { 1.44 lspctx: a project known as a bare .dpr / .dpk (a manifest section names one
    that way) still has a platform: the .dproj of its name > its own .dlcontext.json >
    a .dproj that lists the unit, which then IS the project. }
  PlatSrc:= Result.Project;
  if (Result.Source = lcsDproj) and (Result.Project <> '') and not SameText(ExtractFileExt(Result.Project), '.dproj') then
  begin
    if TFile.Exists(ChangeFileExt(Result.Project, '.dproj')) then PlatSrc:= ChangeFileExt(Result.Project, '.dproj')
    else if FindProjectContextForUnit(Result.Project, Ctx) and not Ctx.Stale
      and SameText(if Ctx.Project <> '' then Ctx.Project else Ctx.SourceFile, Result.Project) then HaveCtx:= True
    else
    begin
      var Others: string;
      var Listing: string:= FindListingProject(APath, Others);
      if SameText(ExtractFileExt(Listing), '.dproj') then
      begin
        Result.Project:= Listing;
        PlatSrc       := Listing;
      end;
    end;
  end;
  if SameText(ExtractFileExt(PlatSrc), '.dproj') and not ReadDprojActiveSelection(PlatSrc, P, C) then
  begin
    P:= '';
    C:= '';
  end;
  if (P = '') and SameText(ExtractFileExt(PlatSrc), '.dproj') and not ReadDelphiLspDefines(PlatSrc, P, LspDefs, LspNum, LspSw) then P:= '';
  if (P = '') and SameText(ExtractFileExt(PlatSrc), '.dproj') then P:= MarkerlessDprojPlatform; { 149 LX: = EffectiveIndexPlatform order (manifest default, else a3 Win32) }
  if (P = '') and (Result.Project = '') then P:= StartupLibraryPlatformOf(APath);

  { Platform: startup > client > context file > the project's active platform > (a .dproj with
    none) the manifest default, else Win32 -- EffectiveIndexPlatform's order > central defaults >
    placeholder. }
  if FStartPlatform <> '' then Result.Platform:= FStartPlatform
  else if FClientPlatform <> '' then Result.Platform:= FClientPlatform
  else if HaveCtx and (Ctx.PlatformName <> '') then Result.Platform:= Ctx.PlatformName
  else Result.Platform:= P;
  if Result.Platform = '' then
  begin
    Result.PlatformDefaulted:= True;
    Result.Platform:= if Defaults.PlatformName <> '' then Defaults.PlatformName else LSP_PLACEHOLDER_PLATFORM;
    if (Result.Project = '') and (Defaults.PlatformName <> '') then Result.Source:= lcsDefaults;
  end;

  if FClientConfig <> '' then Result.Config:= FClientConfig
  else if HaveCtx and (Ctx.Config <> '') then Result.Config:= Ctx.Config
  else if C <> '' then Result.Config:= C
  else Result.Config:= Defaults.Config;

  { Target compiler (the context value of ResolveTargetCompiler): client > context file > central defaults. }
  Result.TargetCompiler:= if FClientTarget <> '' then FClientTarget
    else if HaveCtx and (Ctx.TargetCompiler <> '') then Ctx.TargetCompiler else Defaults.TargetCompiler;
  if HaveCtx then
  begin
    Result.ProjectDbOverride:= Ctx.ProjectDb;
    Result.LibraryDbOverride:= Ctx.LibraryDb;
  end;
end;

function TLSPServer.IsLibraryPath(const APath: string): Boolean;
begin
  { The convention the caller-scoping rule in HandleHoverBundle has always used. }
  Result:= LowerCase(ExtractFileName(APath)).StartsWith('library-');
end;

function TLSPServer.OwningStartupProjectDb(const APath: string): string;
begin
  Result:= '';
  if APath = '' then Exit;
  for var I:= 0 to High(FStores) do
    if (I <= High(FStorePaths)) and not IsLibraryPath(FStorePaths[I]) and (FStores[I].FindFileIdByPath(APath) > 0) then
      Exit(FStorePaths[I]);
end;

function TLSPServer.StartupLibraryFor(const APlatform: string): string;
begin
  Result:= '';
  for var P: string in FStorePaths do
    if SameText(ChangeFileExt(ExtractFileName(P), ''), 'library-' + APlatform) then Exit(P);
end;

function TLSPServer.DbSetFor(const APath: string; const ACtx: TLspFileContext): TLspDbSet;
var
  UseResolver: Boolean;
  Resolved   : TLspDbSet;
  Key        : string;
begin
  Result     := Default(TLspDbSet);
  Resolved   := Default(TLspDbSet);
  UseResolver:= Assigned(FDbResolver) and not FExplicitDbs;
  if UseResolver then
  begin
    Key:= LowerCase(ACtx.Project + '|' + ACtx.Platform);
    if not FResolved.TryGetValue(Key, Resolved) then
    begin
      try
        Resolved:= FDbResolver(ACtx.Project, ACtx.Platform);
      except
        on E: Exception do
        begin
          Writeln(ErrOutput, 'drag-lint LSP: context DB resolve failed for ', ACtx.Project, ' / ', ACtx.Platform, ': ', E.Message);
          Resolved:= Default(TLspDbSet);
        end;
      end;
      FResolved.Add(Key, Resolved);
    end;
  end;

  { Project DB: the context file's override > the resolved owner of the project >
    the startup store that owns the file. Never another project's store. }
  if ACtx.ProjectDbOverride <> '' then Result.ProjectDb:= ACtx.ProjectDbOverride
  else if UseResolver and (ACtx.Project <> '') then Result.ProjectDb:= Resolved.ProjectDb;
  if (Result.ProjectDb = '') or not TFile.Exists(Result.ProjectDb) then Result.ProjectDb:= OwningStartupProjectDb(APath);

  { Library DB for the context's platform: an explicit --db library-<platform> >
    the context file's libraryDb > central libraries.<platform>.libraryDb >
    resolve-dbs. None -> '' and the caller refuses library answers. }
  if FExplicitDbs or not UseResolver then Result.LibraryDb:= StartupLibraryFor(ACtx.Platform);
  { battery-138: explicit --db flags are the whole universe (see ExplicitDbs) --
    a context file or the central defaults never add a library nobody named. }
  { 1.39 (lsp-libfb): no listed library-<platform> -> fall back to the central defaults'
    library for the ACTIVE platform only (ContextNotice says so). }
  if FExplicitDbs then
  begin
    if Result.LibraryDb = '' then Result.LibraryDb:= DefaultsLibraryDbFor(Defaults, ACtx.Platform);
    if (Result.LibraryDb <> '') and not TFile.Exists(Result.LibraryDb) then Result.LibraryDb:= '';
    Exit;
  end;
  if Result.LibraryDb = '' then Result.LibraryDb:= ACtx.LibraryDbOverride;
  if Result.LibraryDb = '' then Result.LibraryDb:= DefaultsLibraryDbFor(Defaults, ACtx.Platform);
  if (Result.LibraryDb = '') and UseResolver then Result.LibraryDb:= Resolved.LibraryDb;
  if (Result.LibraryDb <> '') and not TFile.Exists(Result.LibraryDb) then Result.LibraryDb:= '';
end;

function TLSPServer.StoreSet(const ADbs: TLspDbSet): TArray<ISymbolStore>;
var
  E: TStoreSet;
  S: ISymbolStore;
begin
  E.Key:= LowerCase(ADbs.ProjectDb + '|' + ADbs.LibraryDb);
  for var I:= 0 to FSets.Count - 1 do
    if FSets[I].Key = E.Key then
    begin
      E:= FSets[I];
      if I > 0 then
      begin
        FSets.Delete(I);
        FSets.Insert(0, E);
      end;
      Exit(E.Stores);
    end;
  E.Stores:= nil;
  E.Paths := nil;
  for var D: string in [ADbs.ProjectDb, ADbs.LibraryDb] do
  begin
    if (D = '') or ((Length(E.Paths) > 0) and SameText(E.Paths[0], D)) then Continue;
    { Reuse an already open connection: the startup stores, then the cached sets. }
    S:= nil;
    for var I:= 0 to High(FStorePaths) do
      if SameText(FStorePaths[I], D) then S:= FStores[I];
    if S = nil then
      for var Cached: TStoreSet in FSets do
        for var J:= 0 to High(Cached.Paths) do
          if SameText(Cached.Paths[J], D) then S:= Cached.Stores[J];
    if S = nil then S:= OpenReaderStore(D);
    if S = nil then Continue;
    E.Stores:= E.Stores + [S];
    E.Paths := E.Paths + [D];
  end;
  FSets.Insert(0, E);
  while FSets.Count > LSP_STORE_SET_LRU do FSets.Delete(FSets.Count - 1);
  Result:= E.Stores;
end;

function TLSPServer.StorePathOf(const AStore: ISymbolStore): string;
begin
  Result:= '';
  for var I:= 0 to High(FStores) do
    if (FStores[I] = AStore) and (I <= High(FStorePaths)) then Exit(FStorePaths[I]);
  for var Cached: TStoreSet in FSets do
    for var J:= 0 to High(Cached.Stores) do
      if Cached.Stores[J] = AStore then Exit(Cached.Paths[J]);
end;

function TLSPServer.CallerSearchStores(const APath: string): TArray<ISymbolStore>;
var
  All: TArray<ISymbolStore>;
begin
  All   := StoresForFile(APath);
  Result:= nil;
  for var St: ISymbolStore in All do
    if not IsLibraryPath(StorePathOf(St)) then Result:= Result + [St];
  if Length(Result) = 0 then Result:= All;
end;

function TLSPServer.ProjectDbIncompleteReason(const AProjectDb: string): string;
begin
  { lf-lsp (docs\superpowers\plans\2026-10-28-library-first-resolve-plan.md 2.5):
    STUB until ENGINE's lf-ready / lf-marker lanes name the marker meta key and
    the readiness API. TEST-ONLY seam: run_lsp_context_reindex_guard names a
    FIXTURE db in DRAGLINT_LSP_TEST_MARK_INCOMPLETE; never set in production. }
  Result:= '';
  if AProjectDb = '' then Exit;
  var Marked: string:= GetEnvironmentVariable('DRAGLINT_LSP_TEST_MARK_INCOMPLETE');
  { The test marker behaves like the real one: a successful writer run clears it. }
  var Done: TReindexRun;
  if (Marked <> '') and SameText(ExpandFileName(Marked), ExpandFileName(AProjectDb)) then
    if FReindex.TryGetValue(LowerCase(AProjectDb), Done) and (Done.State = risDone) then Exit('')
    else Exit('needs re-resolve (test marker)');
  { lf-marker (gaps/lf-marker cb98fe76): schema_meta.library_resolve_state =
    JSON (state: pending|bound, platform, library, reason, ...); missing or
    empty = no marker. Only `pending` is incomplete. Key: Core.Versions.LIBRARY_RESOLVE_STATE_META_KEY. }
  var St: ISymbolStore:= nil;
  for var I:= 0 to High(FStorePaths) do
    if SameText(FStorePaths[I], AProjectDb) then St:= FStores[I];
  if St = nil then
    for var Cached: TStoreSet in FSets do
      for var J:= 0 to High(Cached.Paths) do
        if SameText(Cached.Paths[J], AProjectDb) then St:= Cached.Stores[J];
  if St = nil then Exit;
  var Raw: string:= '';
  try
    Raw:= St.GetMetaValue(LIBRARY_RESOLVE_STATE_META_KEY);
  except
    on E: Exception do Raw:= ''; { an unreadable marker is no marker; the answers stand }
  end;
  if Trim(Raw) = '' then Exit;
  var V: TJSONValue:= nil;
  try
    V:= TJSONObject.ParseJSONValue(Raw);
    if (V is TJSONObject) and SameText(JsonStrOf(TJSONObject(V), 'state'), 'pending') then
    begin
      Result:= 'is resolved without the ' + JsonStrOf(TJSONObject(V), 'platform') + ' library';
      if JsonStrOf(TJSONObject(V), 'reason') <> '' then Result:= Result + ' (' + JsonStrOf(TJSONObject(V), 'reason') + ')';
    end;
  finally
    V.Free;
  end;
end;

function LastLogLine(const ALog: string): string;
begin
  Result:= '';
  try
    if not TFile.Exists(ALog) then Exit;
    var Lines: TArray<string>:= TFile.ReadAllLines(ALog);
    for var I:= High(Lines) downto 0 do
      if Trim(Lines[I]) <> '' then Exit(Copy(Trim(Lines[I]), 1, LSP_REINDEX_REASON_MAX));
  except
    on E: Exception do Result:= ''; { the exit code alone still names the failure }
  end;
end;

procedure TLSPServer.StartReindex(const ADb, ADproj: string);
var
  Run : TReindexRun;
  Sa  : TSecurityAttributes;
  HLog: THandle;
  HNul: THandle;
  Si  : TStartupInfo;
  Pi  : TProcessInformation;
  Exe : string;
  Cmd : string;
begin
  Run        := Default(TReindexRun);
  Run.Db     := ADb;
  Run.Dproj  := ADproj;
  Run.State  := risFailed;
  Run.LogPath:= TPath.Combine(TPath.GetTempPath,
    Format('drag-lint-lsp-reindex-%d-%d.log', [GetCurrentProcessId, FReindex.Count + 1]));
  FillChar(Sa, SizeOf(Sa), 0);
  Sa.nLength       := SizeOf(Sa);
  Sa.bInheritHandle:= True;
  HLog:= CreateFile(PChar(Run.LogPath), GENERIC_WRITE, FILE_SHARE_READ, @Sa, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  HNul:= CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, @Sa, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  try
    if (HLog = INVALID_HANDLE_VALUE) or (HNul = INVALID_HANDLE_VALUE) then
      Run.Reason:= 'cannot create ' + Run.LogPath
    else
    begin
      FillChar(Si, SizeOf(Si), 0);
      Si.cb         := SizeOf(Si);
      Si.dwFlags    := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
      Si.wShowWindow:= SW_HIDE;
      Si.hStdInput  := HNul;
      Si.hStdOutput := HLog;
      Si.hStdError  := HLog;
      { TEST-ONLY override, like DRAGLINT_FULLRULES_CHILD_EXE: the guard points
        this at a stub so no run ever touches a real project DB. The writer slot
        is the engine's own (busy timeout / two-writers rule), not ours. }
      Exe:= GetEnvironmentVariable('DRAGLINT_LSP_REINDEX_EXE');
      if Exe = '' then Exe:= ParamStr(0);
      Cmd:= Format('"%s" index --project "%s" --db "%s"', [Exe, ADproj, ADb]);
      { A batch stub runs through cmd /s /c, which keeps the inner quoting. }
      if MatchText(ExtractFileExt(Exe), ['.cmd', '.bat']) then
      begin
        Cmd:= Format('"%s" /s /c "%s"', [GetEnvironmentVariable('ComSpec'), Cmd]);
        Exe:= GetEnvironmentVariable('ComSpec');
      end;
      UniqueString(Cmd);
      if CreateProcess(PChar(Exe), PChar(Cmd), nil, nil, True, CREATE_NO_WINDOW, nil, nil, Si, Pi) then
      begin
        CloseHandle(Pi.hThread);
        Run.Process:= Pi.hProcess;
        Run.State  := risRunning;
        Writeln(ErrOutput, 'drag-lint LSP: re-index started (log ', Run.LogPath, '): ', Cmd);
      end
      else
        Run.Reason:= 'cannot start ' + Exe + ': ' + SysErrorMessage(GetLastError);
    end;
  finally
    if HLog <> INVALID_HANDLE_VALUE then CloseHandle(HLog);
    if HNul <> INVALID_HANDLE_VALUE then CloseHandle(HNul);
  end;
  var Key: string:= LowerCase(ADb);
  FReindex.AddOrSetValue(Key, Run);
  if Run.State <> risRunning then
  begin
    Writeln(ErrOutput, 'drag-lint LSP: re-index NOT started for ', ADb, ': ', Run.Reason);
    Exit;
  end;
  var H: THandle:= Run.Process;
  var Watcher: TThread:= TThread.CreateAnonymousThread(
    procedure
    var
      Handles: array[0..1] of THandle;
    begin
      Handles[0]:= H;
      Handles[1]:= FStopEvent.Handle;
      if WaitForMultipleObjects(Length(Handles), @Handles[0], False, INFINITE) <> WAIT_OBJECT_0 then Exit;
      FWorkLock.Enter;
      try
        ReindexFinished(Key);
      finally
        FWorkLock.Leave;
      end;
    end);
  Watcher.FreeOnTerminate:= False;
  FReindexThreads.Add(Watcher);
  Watcher.Start;
end;

procedure TLSPServer.ReindexFinished(const AKey: string);
var
  Run : TReindexRun;
  Code: DWORD;
begin
  if not FReindex.TryGetValue(AKey, Run) or (Run.Process = 0) then Exit;
  try
    Code:= 1;
    GetExitCodeProcess(Run.Process, Code);
    CloseHandle(Run.Process);
    Run.Process:= 0;
    if Code = 0 then
    begin
      Run.State:= risDone;
      try
        TFile.Delete(Run.LogPath);
      except
        on E: Exception do Run.LogPath:= ''; { a leftover log is harmless }
      end;
    end
    else
    begin
      Run.State := risFailed;
      Run.Reason:= Format('exit %d: %s; log %s', [Code, LastLogLine(Run.LogPath), Run.LogPath]);
    end;
    FReindex.AddOrSetValue(AKey, Run);
    Writeln(ErrOutput, 'drag-lint LSP: re-index of ', Run.Db, ' finished, exit ', Code);
    { The declared-type session cache is keyed by store INSTANCE; the reopened
      store may reuse a freed address over changed rows. }
    ClearPropertyDeclaredTypeCache;
    { 151 CF: the Raises: line's open index is re-opened on next use, like the stores. }
    if SameText(FExcIndexPath, Run.Db) then
    begin
      FreeAndNil(FExcIndex);
      FExcIndexPath:= '';
    end;
    { Re-open that DB: drop every cached set holding it (reopened lazily) and
      swap a startup store in place. }
    for var I:= FSets.Count - 1 downto 0 do
      for var P: string in FSets[I].Paths do
        if SameText(P, Run.Db) then
        begin
          FSets.Delete(I);
          Break;
        end;
    for var I:= 0 to High(FStorePaths) do
      if SameText(FStorePaths[I], Run.Db) then
      begin
        var S: ISymbolStore:= OpenReaderStore(Run.Db);
        if S <> nil then FStores[I]:= S;
      end;
    if Length(FStores) > 0 then FStore:= FStores[0];
    FCtxCache.Clear;
    { Proxy mode: no open-document map (the IDE's DelphiLSP owns diagnostics); re-announce the announced files so the notice clears. }
    for var ProxyPath: string in FProxyPaths.ToArray do
    begin
      StoresForFile(ProxyPath);
      QueueContextNotification(ProxyPath);
    end;
    { Clear (or state) the notice and republish every open document. }
    for var Doc: TPair<string, string> in FOpenDocs.ToArray do
    begin
      var DocPath: string:= FileFromUri(Doc.Value);
      PublishDiagnostics(Doc.Value, DocPath);
      StoresForFile(DocPath);
      QueueContextNotification(DocPath);
    end;
    FlushPending;
  except
    on E: Exception do Writeln(ErrOutput, 'drag-lint LSP: re-index completion failed: ', E.ClassName, ': ', E.Message);
  end;
end;

function TLSPServer.ContextNotice(const APath: string; const ACtx: TLspFileContext; const ADbs: TLspDbSet;
  AQueue: Boolean): string;
var
  Acc: string;

  procedure Add(const AReason, AText: string);
  begin
    FNoticeWarns:= True;
    Acc:= if Acc = '' then AText else Acc + ' ' + AText;
    if not AQueue then Exit;
    var Key: string:= LowerCase(APath) + '|' + AReason;
    if FNoticed.ContainsKey(Key) then Exit;
    FNoticed.Add(Key, 1);
    var Params: TJSONObject:= TJSONObject.Create;
    Params.AddPair('type'   , TJSONNumber.Create(LSP_MSG_TYPE_WARNING));
    Params.AddPair('message', AText);
    QueueNotification('window/showMessage', Params);
  end;

  { 1.44 lspctx: advice, not a fault: info level, once per FOLDER. AInText = False keeps
    it out of the per-file text (status bar, hover footer) for what is normal for a file. }
  procedure AddAdvice(const AReason, AText: string; AInText: Boolean = True);
  begin
    if AInText then Acc:= if Acc = '' then AText else Acc + ' ' + AText;
    if not AQueue then Exit;
    var Key: string:= LowerCase(ExtractFileDir(APath)) + '|' + AReason;
    if FNoticed.ContainsKey(Key) then Exit;
    FNoticed.Add(Key, 1);
    var Params: TJSONObject:= TJSONObject.Create;
    Params.AddPair('type'   , TJSONNumber.Create(LSP_MSG_TYPE_INFO));
    Params.AddPair('message', AText);
    QueueNotification('window/showMessage', Params);
  end;

begin
  Result:= '';
  Acc   := '';
  FNoticeWarns:= False;
  if APath = '' then Exit;
  if ACtx.Project = '' then
    AddAdvice('unknown-project', Format('drag-lint: no project is known for %s -- answering from the %s library only. '
      + 'Pick one with dragLint.selectProject (draglint.setContext outside VS Code) or name it in a .dlcontext.json.',
      [ExtractFileName(APath), ACtx.Platform]));
  if ACtx.PlatformDefaulted then
    AddAdvice('default-platform', Format('drag-lint: no platform is known for %s -- using the default %s. '
      + 'Pick one with dragLint.selectPlatform (draglint.setContext outside VS Code) or name it in a .dlcontext.json.',
      [ExtractFileName(APath), ACtx.Platform]));
  if ACtx.AlsoHeldBy <> '' then
    AddAdvice('several-projects', Format('drag-lint: %s belongs to several projects -- using %s, also in %s. '
      + 'Pick another with dragLint.selectProject.',
      [ExtractFileName(APath), ExtractFileName(ACtx.Project), ACtx.AlsoHeldBy]), False);
  if (ACtx.Project <> '') and (ADbs.ProjectDb = '') and not FExplicitDbs and (ACtx.Source = lcsDproj) then
    AddAdvice('no-project-index', Format('drag-lint: %s has no index here -- answering from the %s library only. '
      + 'Build it with: drag-lint index --project "%s"', [ExtractFileName(ACtx.Project), ACtx.Platform, ACtx.Project]));
  if ACtx.StaleContextFile <> '' then
    Add('stale-context', Format('drag-lint: %s is stale (its .dproj changed) -- reading the .dproj instead.',
      [ExtractFileName(ACtx.StaleContextFile)]));
  { 1.38: an invalid target compiler is named, never guessed; the file is linted at the default. }
  var TargetErr: string;
  TargetGateFor(APath, ACtx, TargetErr);
  if TargetErr <> '' then
    Add('bad-target', Format('drag-lint: %s -- linting %s at the default target %s.',
      [TargetErr, ExtractFileName(APath), CompilerDisplayName(DEFAULT_TARGET_COMPILER)]));
  if FExplicitDbs and (ADbs.LibraryDb <> '') and (StartupLibraryFor(ACtx.Platform) = '') then
    Add('library-fallback', Format('drag-lint: using the %s library from context defaults (%s) -- no library-%s store was listed in dragLint.databases.',
      [ACtx.Platform, ExtractFileName(ADbs.LibraryDb), ACtx.Platform]));
  if ADbs.LibraryDb = '' then
    Add('no-library', Format('drag-lint: no library index for platform %s -- library answers are refused. '
      + 'Index that library, or set libraries.%s.libraryDb in %s.', [ACtx.Platform, ACtx.Platform, ContextDefaultsFile]));
  { Library-first resolve (lf-lsp) + owner ruling 2026-10-28: a project DB
    marked "needs re-resolve" is re-indexed in the background; meanwhile the
    answers continue, marked incomplete. }
  var Run: TReindexRun;
  if (ADbs.ProjectDb <> '') and FReindex.TryGetValue(LowerCase(ADbs.ProjectDb), Run) then
  begin
    if Run.State = risRunning then
      Add('reindex-running', Format('drag-lint: re-index in progress for %s -- answers may be incomplete.',
        [ExtractFileName(ADbs.ProjectDb)]))
    else if Run.State = risFailed then
      Add('reindex-failed', Format('drag-lint: re-index of %s failed (%s) -- answers may be incomplete; not retried.',
        [ExtractFileName(ADbs.ProjectDb), Run.Reason]))
    else
    begin
      { The run finished but the marker still says pending (e.g. the library
        was not ready): state it, never start another run. }
      var StillPending: string:= ProjectDbIncompleteReason(ADbs.ProjectDb);
      if StillPending <> '' then
        Add('incomplete', Format('drag-lint: %s %s -- answers may be incomplete.', [ExtractFileName(ADbs.ProjectDb), StillPending]));
    end;
  end
  else if ADbs.ProjectDb <> '' then
  begin
    var Incomplete: string:= ProjectDbIncompleteReason(ADbs.ProjectDb);
    if Incomplete <> '' then
      if AQueue and FQueueNotices and SameText(ExtractFileExt(ACtx.Project), '.dproj') then
      begin
        StartReindex(ADbs.ProjectDb, ACtx.Project);
        Acc:= ''; { restart the text: the run's state decides the wording now }
        Result:= ContextNotice(APath, ACtx, ADbs, AQueue);
        Exit;
      end
      else Add('incomplete', Format('drag-lint: %s %s -- answers may be incomplete.', [ExtractFileName(ADbs.ProjectDb), Incomplete]));
  end;
  Result:= Acc;
end;

function TLSPServer.TargetGateFor(const APath: string; const ACtx: TLspFileContext; out AError: string): TTargetRuleGate;
var
  V    : Integer;
  Dproj: string;
begin
  Dproj:= if SameText(ExtractFileExt(ACtx.Project), '.dproj') then ACtx.Project else '';
  if not ResolveTargetCompiler(FStartupTargetCompiler, TLspCompletion.LintConfigTargetCompiler(APath), ACtx.TargetCompiler,
           Dproj, V, AError) then
    V:= DEFAULT_TARGET_COMPILER; { refused: notice (ContextNotice) + the default, never a guess }
  SetActiveTargetCompiler(V);
  { One catalog walk per distinct target: the gate is rebuilt only when the target changes. }
  if FTargetGate.Target <> V then FTargetGate:= TLspCompletion.BuildTargetGate(V);
  Result:= FTargetGate;
end;

procedure TLSPServer.RepublishRetargeted;
var
  Err: string;
begin
  for var Doc in FOpenDocs.ToArray do
  begin
    var Was: Integer;
    if not FPublishedTarget.TryGetValue(Doc.Key, Was) then Continue;
    var Path: string:= FileFromUri(Doc.Value);
    if TargetGateFor(Path, FileContext(Path), Err).Target <> Was then PublishDiagnostics(Doc.Value, Path);
  end;
end;

procedure TLSPServer.QueueNotification(const AMethod: string; AParams: TJSONObject);
begin
  if not FQueueNotices then
  begin
    AParams.Free; { proxy mode: stdout belongs to the relay, nothing may be written }
    Exit;
  end;
  var Obj: TJSONObject:= TJSONObject.Create;
  Obj.AddPair('jsonrpc', '2.0');
  Obj.AddPair('method' , AMethod);
  Obj.AddPair('params' , AParams);
  FPending.Add(Obj);
end;

procedure TLSPServer.QueueContextNotification(const APath: string);
begin
  if (APath = '') or not FQueueNotices then Exit;
  var Ctx: TLspFileContext:= FileContext(APath);
  var Dbs: TLspDbSet      := DbSetFor(APath, Ctx);
  var Params: TJSONObject := TJSONObject.Create;
  Params.AddPair('uri'     , FileToUri(APath));
  Params.AddPair('project' , Ctx.Project);
  Params.AddPair('platform', Ctx.Platform);
  Params.AddPair('config'  , Ctx.Config);
  Params.AddPair('source'  , LSP_SOURCE_NAMES[Ctx.Source]);
  var Notice: string:= ContextNotice(APath, Ctx, Dbs, False);
  Params.AddPair('notice'  , Notice);
  { 1.44 lspctx: the status bar paints a warning only for a warning-level reason. }
  if (Notice <> '') and not FNoticeWarns then Params.AddPair('level', 'info');
  QueueNotification(LSP_NOTIFY_CONTEXT, Params);
end;

procedure TLSPServer.EnableProxyNotices(const ASink: TProc<string>);
begin
  FNoticeSink   := ASink;
  FQueueNotices := Assigned(ASink);
end;

procedure TLSPServer.AnnounceProxyOpen(const APath: string);
begin
  if not Assigned(FNoticeSink) or (APath = '') then Exit;
  FWorkLock.Enter;
  try
    if not FProxyPaths.Contains(APath) then FProxyPaths.Add(APath);
    FLastOpenPath:= APath;
    StoresForFile(APath);
    QueueContextNotification(APath);
    FlushPending;
  finally
    FWorkLock.Leave;
  end;
end;

procedure TLSPServer.FlushPending;
begin
  try
    for var Obj: TJSONObject in FPending do
      if Assigned(FNoticeSink) then FNoticeSink(Obj.ToJSON) else SendRawNotification(Obj);
  finally
    FPending.Clear;
  end;
end;

procedure TLSPServer.ApplyClientContext(const AObj: TJSONObject);
var
  Proj, Plat, Conf: string;
begin
  Proj:= JsonStrOf(AObj, 'project');
  Plat:= JsonStrOf(AObj, 'platform');
  Conf:= JsonStrOf(AObj, 'config');
  FHaveClientCtx:= False;
  FClientCtx    := Default(TProjectContext);
  { CLIENT contract: `project` may name a .dlcontext.json; its project /
    platform / config then apply (an explicit platform / config still wins). }
  if Proj.EndsWith(LSP_CONTEXT_FILE_EXT, True) then
  begin
    if TryLoadProjectContext(Proj, FClientCtx) then
    begin
      FHaveClientCtx:= True;
      if FClientCtx.Project <> '' then Proj:= FClientCtx.Project;
    end
    else
      Writeln(ErrOutput, 'drag-lint LSP: client context file not readable, ignored: ', Proj);
  end;
  FClientProject := if Proj <> '' then ExpandFileName(Proj) else '';
  FClientPlatform:= Plat;
  FClientConfig  := Conf;
  FClientTarget  := JsonStrOf(AObj, 'targetCompiler');
  FCtxCache.Clear;
  QueueContextNotification(FLastOpenPath);
  RepublishRetargeted;
end;

procedure TLSPServer.ApplyClientSettingsFile(const AFile: string);
var
  Base, Proj, Plat: string;
  LspDefs: TArray<string>;
  LspNum : TArray<TPair<string, Integer>>;
  LspSw  : TArray<TPair<string, Boolean>>;
begin
  if AFile = '' then Exit;
  Base:= ChangeFileExt(ChangeFileExt(AFile, ''), '');   { App.delphilsp.json -> App }
  Proj:= Base + '.dproj';
  if not TFile.Exists(Proj) then Proj:= Base + '.dpr';
  if not TFile.Exists(Proj) then
  begin
    Writeln(ErrOutput, 'drag-lint LSP: settingsFile names no project beside it, ignored: ', AFile);
    Exit;
  end;
  if not ReadDelphiLspDefines(Base + '.dproj', Plat, LspDefs, LspNum, LspSw) then Plat:= '';
  FHaveClientCtx := False;
  FClientCtx     := Default(TProjectContext);
  FClientProject := ExpandFileName(Proj);
  FClientPlatform:= Plat;
  FClientConfig  := '';
  FClientTarget  := '';
  FCtxCache.Clear;
  QueueContextNotification(FLastOpenPath);
  RepublishRetargeted;
end;

function TLSPServer.HandleSetContext(const AId: TJSONValue; const AParams: TJSONObject): Boolean;
var
  Args: TJSONValue;
  Obj : TJSONObject;
begin
  Result:= JsonStrOf(AParams, 'command') = LSP_CMD_SET_CONTEXT;
  if not Result then Exit;
  Obj := nil;
  Args:= AParams.GetValue('arguments');
  if (Args is TJSONArray) and (TJSONArray(Args).Count > 0) and (TJSONArray(Args).Items[0] is TJSONObject) then
    Obj:= TJSONObject(TJSONArray(Args).Items[0]);
  if Obj = nil then
  begin
    if AId <> nil then
      SendError(AId, LSP_ERR_INVALID_PARAMS, LSP_CMD_SET_CONTEXT + ' expects arguments [{project, platform, config}]');
    Exit;
  end;
  ApplyClientContext(Obj);
  if AId <> nil then SendResult(AId, nil);
end;

procedure TLSPServer.HandleDidChangeConfiguration(const AParams: TJSONObject);
var
  Settings: TJSONValue;
  Section : TJSONValue;
begin
  if AParams = nil then Exit;
  Settings:= AParams.GetValue('settings');
  if not (Settings is TJSONObject) then Exit;
  Section:= TJSONObject(Settings).GetValue(LSP_CONFIG_SECTION);
  if (Section is TJSONObject) and HasContextKeys(TJSONObject(Section)) then ApplyClientContext(TJSONObject(Section))
  else if JsonStrOf(TJSONObject(Settings), 'settingsFile') <> '' then
    ApplyClientSettingsFile(FileFromUri(JsonStrOf(TJSONObject(Settings), 'settingsFile')));
end;

function TLSPServer.ContextFooter(const APath: string): string;
var
  Ctx: TLspFileContext;
begin
  Ctx   := FileContext(APath);
  Result:= 'context: ' + (if Ctx.Project = '' then 'none' else ExtractFileName(Ctx.Project)) + ' -- ' + Ctx.Platform
    + (if Ctx.PlatformDefaulted then ' [default]' else '');
  var Dbs   : TLspDbSet:= DbSetFor(APath, Ctx);
  var Notice: string   := ContextNotice(APath, Ctx, Dbs, False);
  if Notice <> '' then Result:= Result + #10#10 + Notice;
  { LSP-UNOWNED (owner ruling D2, 2026-11-03): a file no index of its context owns still
    answers from the stores (hover, definition); the footer says whose answer it is. }
  var Owned: Boolean:= False;
  for var St: ISymbolStore in StoreSet(Dbs) + FStores do
    if St.FindFileIdByPath(APath) > 0 then Owned:= True;
  if (not Owned) and (APath <> '') then
    Result:= Result + #10#10 + Format('(from %s; file not in this project)', [(if Dbs.ProjectDb <> '' then ExtractFileName(Dbs.ProjectDb) else if Dbs.LibraryDb <> '' then ExtractFileName(Dbs.LibraryDb) else 'the open index')]);
end;

function TLSPServer.StoresForFile(const APath: string): TArray<ISymbolStore>;
var
  Stamp: TDateTime;
  Ctx  : TLspFileContext;
  Dbs  : TLspDbSet;
begin
  Result:= FStores;
  if APath = '' then Exit;
  { LSP-1 CORE: the file's context set -- its project's DB + its platform's
    library -- replaces the startup list; another project's store never answers. }
  Ctx:= FileContext(APath);
  Dbs:= DbSetFor(APath, Ctx);
  ContextNotice(APath, Ctx, Dbs, True);
  Result:= StoreSet(Dbs);
  { The overwhelmingly common case: a file the project index owns. Nothing
    below runs. }
  for var St: ISymbolStore in Result do
    if St.FindFileIdByPath(APath) > 0 then Exit;
  if not TFile.Exists(APath) then Exit;

  { Kept in step with TDelphi13Parser.FileExtensions, which is the authority.
    Duplicated rather than read from a parser instance because constructing one
    just to ask would be work on every unowned hover, including the ones that
    then decline to index. }
  var Ext: string:= LowerCase(ExtractFileExt(APath));
  if (Ext <> '.pas') and (Ext <> '.dpr') and (Ext <> '.dpk') and (Ext <> '.inc') then Exit;

  try
    Stamp:= TFile.GetLastWriteTime(APath);
  except
    Exit;
  end;

  { Cache hit: same file, same last-write time. Repeated hovers in one unit --
    which is what hovering actually looks like -- cost a single parse. }
  if (FEphemStore = nil) or (not SameText(FEphemFile, APath)) or (FEphemStamp <> Stamp) then
    if not BuildEphemeralStore(APath, Stamp) then Exit;

  { PREPENDED, not substituted. TTypeAtResolver.Resolve picks as its Primary the
    first store that owns the file, so this makes the anchor exist; the context
    set still answers, just behind it. }
  Result:= TArray<ISymbolStore>.Create(FEphemStore) + Result;
end; // function


function TLSPServer.ComputeHover(const AParams: TJSONObject; out AOut: THoverComputation): Boolean;
var
  Path: string ;
  Line: Integer;
  Col : Integer;
begin
  Result:= False;
  AOut  := Default(THoverComputation);
  if (Length(FStores) = 0) or not PositionParams(AParams, Path, Line, Col) then Exit;
  Result:= ComputeHoverAt(Path, Line, Col, AOut);
end; // function

function TLSPServer.OpenStores: TArray<ISymbolStore>;
begin
  Result:= Copy(FStores);
end;

function TLSPServer.SelectSymbolAt(const AStores: TArray<ISymbolStore>; const APath, AIdent: string; ALine0, ACol0: Integer; out ASel: TSymbolSelection): Boolean;
{ S0: moved out of ComputeHover unchanged, so hover and ResolveSymbolAt share
  ONE rule for which symbol a position means. Only the names changed:
  Stores/Path/Ident/Line/Col are now parameters, and the state the renderer
  needs comes back in ASel instead of locals. }
var
  Symbols: TArray<TSymbol>;
  Stores : TArray<ISymbolStore>;
  Path   : string ;
  Ident  : string ;
  Line   : Integer;
  Col    : Integer;
begin
  Result:= False;
  ASel  := Default(TSymbolSelection);
  Stores:= AStores;
  Path  := APath  ;
  Ident := AIdent ;
  Line  := ALine0 ;
  Col   := ACol0  ;
  { v0.40.3: hover returns the FIRST hit across stores in declared order
    (project DB before library DB, per CLI arg ordering). For multi-hit
    cases the user can use Find Usages to see all stores' results. }
  Symbols:= nil;
  var HitStore: ISymbolStore:= nil;
  for var StIdx:= 0 to High(Stores) do
  begin
    Symbols:= Stores[StIdx].FindSymbolsByExactName(Ident);
    if Length(Symbols) > 0 then
    begin
      HitStore:= Stores[StIdx];
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
  var CurLine1: Integer:= Line + 1;
  { C2.5: the cursor is on a FORWARD DECLARATION (`TFoo = class;`). The store
    already folded that row into the real declaration and stamped ForwardLine,
    so no candidate's own StartLine matches the cursor -- match ForwardLine
    instead, and remember to say so in the popup (OnForwardStub). Checked for
    ANY candidate count: a folded pair is ONE row, which the `> 1` guard below
    would skip. }
  var OnForwardStub: Boolean:= False;
  for var si:= 0 to High(Symbols) do
    if (Symbols[si].ForwardLine = CurLine1)
      and SameText(HitStore.GetFilePath(Symbols[si].FileId), Path) then
    begin
      Chosen:= si;
      FoundDeclImpl:= True;
      OnForwardStub:= True;
      Break;
    end;
  if (not FoundDeclImpl) and (Length(Symbols) > 1) then
  begin
    for var si:= 0 to High(Symbols) do
      if SameText(HitStore.GetFilePath(Symbols[si].FileId), Path)
        and ((Symbols[si].StartLine = CurLine1)
             or ((Symbols[si].ImplStartLine > 0) and (CurLine1 >= Symbols[si].ImplStartLine) and (CurLine1 <= Symbols[si].ImplEndLine))) then
      begin
        Chosen:= si; FoundDeclImpl:= True; Break;
      end;
  end;
  var Sel: TSymbol:= Symbols[Chosen];
  ASel.Narrowed:= FoundDeclImpl;

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
    var TAR:= TTypeAtResolver.Resolve(Stores, Path, Line + 1, Col + 1);
    ASel.HasTypeAt:= True;  { 151 CF: ComputeHoverAt's undocumented branch reuses it }
    ASel.TypeAt   := TAR ;
    if TAR.HasResolved and (TAR.Resolved.Id > 0) and SameText(TAR.Resolved.Name, Ident) then
    begin
      Sel:= TAR.Resolved;
      ASel.Narrowed:= True;
      if (TAR.ResolvedStoreIndex >= 0) and (TAR.ResolvedStoreIndex <= High(Stores)) then
      begin
        HitStore:= Stores[TAR.ResolvedStoreIndex];
        Symbols := HitStore.FindSymbolsByExactName(Ident);
      end;
    end
    else if TAR.HasResolved and TAR.OwnerTypeFallback and (TAR.Resolved.Id > 0) then
    begin
      ASel.OwnerFloorType:= TAR.Resolved;
      ASel.HaveOwnerFloor:= True;
    end;
  end;
  ASel.Symbols      := Symbols      ;
  ASel.HitStore     := HitStore     ;
  ASel.Sel          := Sel          ;
  ASel.OnForwardStub:= OnForwardStub;
  Result:= True;
end; // function

function TLSPServer.ComputeHoverAt(const APath: string; ALine, ACol: Integer; out AOut: THoverComputation): Boolean;  // dl:ok cyclomatic-complexity@b387, cognitive-complexity@7029, method-too-long@2d59, deep-nesting@5f57 -- REVIEWED S0: the hover RENDERING half of the former ComputeHover (54 before); the selection half moved to SelectSymbolAt, further splitting is out of S0 scope (re-reviewed A5 fix: now 35; still one rendering pass, a split stays out of scope here)
var
  Path    : string         ;
  Ident   : string         ;
  MdValue : string         ;
  Line    : Integer        ;
  Col     : Integer        ;
  Symbols : TArray<TSymbol>;
  Sym     : TSymbol        ;
  Doc     : TParsedDoc     ;
  Sb      : TStringBuilder ;
  Stores  : TArray<ISymbolStore>;  { FStores, or the ephemeral single-unit store prepended -- see StoresForFile }
  OwnerFloorType: TSymbol  ;   // when set, the resolver found the LHS type but not the member -> render an honest inherited-member note
  HaveOwnerFloor: Boolean  ;
  Selection     : TSymbolSelection;
begin
  Result:= False;
  AOut  := Default(THoverComputation);
  { OwnerFloorType / HaveOwnerFloor are assigned together from Selection below,
    which SelectSymbolAt zeroes with Default() first -- so an OwnerFloorType read
    on a path someone adds later can never carry a garbage Id into a store
    lookup. }
  if Length(FStores) = 0 then
  begin
    Exit;
  end;
  Path:= APath;
  Line:= ALine;
  Col := ACol ;
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
  { INBOX-lsp-hover-unindexed-file-resolves-library-symbol: EVERY store lookup
    from here on goes through Stores, not FStores. For a file some index owns
    the two are the same array; for a loose file Stores carries an ephemeral
    index of that one unit in front, which is what stops the loop below --
    first store that has the NAME -- from handing back a library symbol
    belonging to a different program. Built after the intrinsic check, so
    hovering `Length` never triggers a parse. }
  Stores:= StoresForFile(Path);
  if not SelectSymbolAt(Stores, Path, Ident, Line, Col, Selection) then
  begin
    Exit;
  end;
  Symbols       := Selection.Symbols       ;
  var HitStore: ISymbolStore:= Selection.HitStore;
  var Sel     : TSymbol     := Selection.Sel     ;
  var OnForwardStub: Boolean:= Selection.OnForwardStub;
  HaveOwnerFloor:= Selection.HaveOwnerFloor;
  OwnerFloorType:= Selection.OwnerFloorType;

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
    var HovFacts: TDocFacts:= TDocFactsBuilder.Build(HitStore, Sel, LoadDocHandlesOptions, False, False, '', HoverExtraStores(APath, HitStore)); { gap 3: the SAME 'Catches:' knob document writes with; 149 LX: + the file's other project stores }
    var HovFactLines: TArray<string>:= TDocRegions.FormatPhase2FactLines(HovFacts, LoadDocComplexityMin);
    { E-USE-EDGES-PHASE2: the property/field 'Used in:' line, same formatter as the doc block. }
    HovFactLines:= TDocRegions.FormatUsedInLines(HovFacts) + HovFactLines;
    { 150 LX2: the callers, first as in the doc block; '' when the /// block already shows them. }
    var HovCalledFrom: string:= FormatHoverCalledFromLine(HovFacts, Doc.RawBlock + Doc.Remarks);
    if HovCalledFrom <> '' then HovFactLines:= [HovCalledFrom] + HovFactLines;
    HovFactLines:= HovFactLines + ExceptionFactLines(HitStore, Sel); { D1: Raises:, after the doc-block facts }
    MdValue:= DRagLint.Hover.Renderer.RenderHoverMarkdown(Sel, Doc, HovRhs, HovFactLines,
      FormatDeclaredType(DescribeDeclaredType(Sel, HitStore)));
  end
  else
  begin
    Sb:= TStringBuilder.Create;
    try
      { v0.40.8f: try to resolve the actual type at cursor first. If we
        can, narrow the candidate list to symbols on THAT type (else a
        common member like DataBinding lists every class that has one). }
      { 151 CF (LX-5): SelectSymbolAt already asked this exact question when the cursor was
        not on a declaration; resolve again only when it did not. }
      var TAResult: TTypeAtResult;
      if Selection.HasTypeAt then TAResult:= Selection.TypeAt
      else                        TAResult:= TTypeAtResolver.Resolve( Stores, Path, Line + 1, Col + 1);

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
        Sb.AppendLine('    ' + DeclLineFor(Sym, HitStore));
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

      { C3: an undocumented symbol still has index facts (Directives:, Complexity:,
        ...). Append the SAME Phase-2 fact lines the doc branch renders, only when
        the popup describes exactly ONE symbol (several overloads would misattribute). }
      if Length(Filtered) = 1 then
      begin
        var NdFacts: TDocFacts:= TDocFactsBuilder.Build(HitStore, Filtered[0], LoadDocHandlesOptions, False, False, '', HoverExtraStores(APath, HitStore)); { 149 LX: cross-DB uses }
        var NdLines: TArray<string>:= TDocRegions.FormatPhase2FactLines(NdFacts, LoadDocComplexityMin);
        NdLines:= TDocRegions.FormatUsedInLines(NdFacts) + NdLines; { E-USE-EDGES-PHASE2 }
        var NdCalledFrom: string:= FormatHoverCalledFromLine(NdFacts, ''); { 150 LX2: no /// block here }
        if NdCalledFrom <> '' then NdLines:= [NdCalledFrom] + NdLines;
        NdLines:= NdLines + ExceptionFactLines(HitStore, Filtered[0]); { D1: Raises: }
        if Length(NdLines) > 0 then
        begin
          Sb.AppendLine('');
          Sb.AppendLine('**Analysis facts:**');
          for var NdLine in NdLines do Sb.AppendLine('- ' + NdLine);
        end;
      end;
      MdValue:= Sb.ToString;
    finally
      Sb.Free;
    end; // try
  end; // else Doc.HasContent
  end; // else HaveOwnerFloor
  { C2.5: the popup was built for the REAL declaration; say that the cursor is
    on its forward stub and where the real one is. Rendered as the first line so
    the plugin's one-line header shows it. }
  if OnForwardStub then
    MdValue:= Format('_forward declaration -> line %d_'#10#10, [Sel.StartLine]) + MdValue;
  AOut.MdValue:= MdValue;
  { On the owner-type floor the markdown deliberately names the OWNER TYPE,
    because the member was not found on it or any base. Report that same type
    as the bundle's subject; reporting Sel there would hand back an arbitrary
    same-named symbol -- the shape that put an FMX type in a VCL project. }
  if HaveOwnerFloor then AOut.Sel:= OwnerFloorType
  else                   AOut.Sel:= Sel;
  AOut.Store    := HitStore;
  AOut.Path     := APath   ;
  AOut.HasSymbol:= True    ;
  Result:= True;
end; // function

function TLSPServer.WithContextFooter(const AParams: TJSONObject; const AMd: string): string;
var
  FooterPath: string;
  FooterLine, FooterCol: Integer;
begin
  { LSP-1 CORE: the footer names the context the answer came from (SPEC 3). }
  Result:= AMd;
  if PositionParams(AParams, FooterPath, FooterLine, FooterCol) then
    Result:= Result + #10#10'---'#10#10 + ContextFooter(FooterPath);
end;

procedure TLSPServer.HandleHover(const AId: TJSONValue; const AParams: TJSONObject);
{ A thin envelope over ComputeHover. Every rule about WHICH symbol a position
  means now lives in one place, so `draglint/hoverBundle` cannot describe a
  different symbol than this reply does for the same cursor. }
var
  HoverObj: TJSONObject     ;
  Contents: TJSONObject     ;
  Comp    : THoverComputation;
begin
  if not ComputeHover(AParams, Comp) then
  begin
    SendResult(AId, nil); { result: null }
    Exit;
  end;
  Comp.MdValue:= WithContextFooter(AParams, Comp.MdValue);
  HoverObj:= TJSONObject.Create;
  Contents:= TJSONObject.Create;
  Contents.AddPair('kind'    , 'markdown' );
  Contents.AddPair('value'   , Comp.MdValue);
  HoverObj.AddPair('contents', Contents   );
  SendResult(AId, HoverObj);
end; // procedure

function TLSPServer.ComputeHoverMarkdown(const APath: string; ALine0, ACol0: Integer): string;
var
  Comp: THoverComputation;
begin
  if ComputeHoverAt(APath, ALine0, ACol0, Comp) then Result:= Comp.MdValue
  else                                                Result:= '';
end;

function TLSPServer.ResolveSymbolAt(const APath: string; ALine0, ACol0: Integer; out ASym: TSymbol; out AStore: ISymbolStore): Boolean;
var
  Selection: TSymbolSelection;
begin
  Result:= False;
  ASym  := Default(TSymbol);
  AStore:= nil;
  if Length(FStores) = 0 then Exit;
  var Ident: string:= IdentifierAtPosition(APath, ALine0, ACol0);
  { An intrinsic has no indexed symbol; hover renders it from a table. }
  if (Ident = '') or IsCompilerIntrinsic(Ident) then Exit;
  if not SelectSymbolAt(StoresForFile(APath), APath, Ident, ALine0, ACol0, Selection) then Exit;
  { The owner-type floor names a TYPE, not the symbol under the cursor. }
  if Selection.HaveOwnerFloor then Exit;
  ASym:= Selection.Sel;
  { Nothing narrowed: Sel is merely Symbols[0]. Prefer the source declaration
    over a generated DFM row, as the hover listing does. }
  if not Selection.Narrowed then
  begin
    var Deduped: TArray<TSymbol>:= DedupAndPreferSource(Selection.Symbols);
    if Length(Deduped) > 0 then ASym:= Deduped[0];
  end;
  AStore:= Selection.HitStore;
  Result:= True;
end;

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
  lines of a form class.

  S0: the body moved to ComputeCallerCounts (ILspServerContext.CallerCounts);
  this is its envelope. }
var
  Uri: string     ;
  Res: TJSONObject;
begin
  Uri:= '';
  if AParams <> nil then
  begin
    var TdObj: TJSONObject:= AParams.GetValue('textDocument') as TJSONObject;
    if TdObj <> nil then TdObj.TryGetValue<string>('uri', Uri);
  end;
  Res:= TJSONObject.Create;
  try
    Res.AddPair('counts', ComputeCallerCounts(FileFromUri(Uri)));
    { 1.40 ifrpt: the "N implementors" lens of interfaces and interface methods (0-based lines). }
    Res.AddPair('implementors', ImplementorCountsForFile(StoresForFile(FileFromUri(Uri)), FileFromUri(Uri)));
    { Wave 149 LX (D1P-149 i): the exception lens titles, one (line, title) object per routine, 0-based on the
      routine's declaration line -- the RAD Studio lens reads callerCounts, not codeLens. }
    Res.AddPair('exceptions', ComputeExceptionLenses(FileFromUri(Uri)));
  except  // dl:ok bare-except@56ea -- frees the not-yet-handed-over JSON value and re-raises; nothing is swallowed
    Res.Free;
    raise;
  end;
  SendResult(AId, Res);
end;

function TLSPServer.ExceptionFactLines(const AStore: ISymbolStore; const ASym: TSymbol): TArray<string>;
begin
  Result:= [];
  if (not FExceptionFacts) or (ASym.Kind not in [skProcedure, skFunction, skMethod, skConstructor, skDestructor]) then Exit;
  var DbPath: string:= StorePathOf(AStore);
  if DbPath = '' then Exit;
  { 151 CF (LX-5): one open index per DB path instead of TChartsIndex.Create per hover. }
  if (FExcIndex = nil) or not SameText(FExcIndexPath, DbPath) then
  begin
    FreeAndNil(FExcIndex);
    FExcIndex    := TChartsIndex.Create(DbPath);
    FExcIndexPath:= DbPath;
  end;
  var Line: string:= ExceptionRaisesLine(ExceptionFactsOfIndex(FExcIndex, ASym.QualifiedName, ''));
  if Line <> '' then Result:= [Line];
end;

function TLSPServer.ComputeExceptionLenses(const APath: string): TJSONArray;
begin
  Result:= TJSONArray.Create;
  if (not FExceptionFacts) or (APath = '') then Exit;
  var DbPath: string:= '';
  var FilePath: string:= '';
  for var St: ISymbolStore in StoresForFile(APath) do
  begin
    var Fid: Int64:= St.FindFileIdByPath(APath);
    if Fid <= 0 then Continue;
    DbPath:= StorePathOf(St);
    FilePath:= St.GetFilePath(Fid);
    if DbPath <> '' then Break;
  end;
  if (DbPath = '') or (FilePath = '') then Exit;
  var ByRoutine: TObjectDictionary<Integer, TList<TExceptionFact>>:= TObjectDictionary<Integer, TList<TExceptionFact>>.Create([doOwnsValues]);
  try
    for var F: TExceptionFact in ExceptionFactsOfFile(DbPath, FilePath) do
    begin
      if F.RoutineLine <= 0 then Continue;
      var L: TList<TExceptionFact>;
      if not ByRoutine.TryGetValue(F.RoutineLine, L) then
      begin
        L:= TList<TExceptionFact>.Create;
        ByRoutine.Add(F.RoutineLine, L);
      end;
      L.Add(F);
    end;
    var Lines: TArray<Integer>:= ByRoutine.Keys.ToArray;
    TArray.Sort<Integer>(Lines);
    for var Ln: Integer in Lines do
    begin
      var Title: string:= ExceptionLensTitle(ByRoutine[Ln].ToArray);
      if Title = '' then Continue;
      var O: TJSONObject:= TJSONObject.Create;
      Result.AddElement(O);
      O.AddPair('line' , TJSONNumber.Create(Ln - 1));
      O.AddPair('title', Title);
    end;
  finally
    ByRoutine.Free;
  end;
end;

function TLSPServer.HoverExtraStores(const APath: string; const AHit: ISymbolStore): TArray<ISymbolStore>;
begin
  Result:= nil;
  if APath = '' then Exit;
  { The file's context set, plus every startup project store that also owns the file (a
    shared unit: OtherOwningStores' set). LSP-1 CORE keeps those out of the ANSWER; here they
    only add inbound facts, exactly as document's extra stores do. }
  var Cands: TArray<ISymbolStore>:= StoresForFile(APath);
  for var I:= 0 to High(FStores) do
    if (I <= High(FStorePaths)) and not IsLibraryPath(FStorePaths[I]) then Cands:= Cands + [FStores[I]];
  for var St: ISymbolStore in Cands do
  begin
    if (St = nil) or (St = AHit) or (St = FEphemStore) or IsLibraryPath(StorePathOf(St)) then Continue;
    var Dup: Boolean:= False;
    for var Have: ISymbolStore in Result do
      if Have = St then Dup:= True;
    if (not Dup) and (St.FindFileIdByPath(APath) > 0) then Result:= Result + [St];
  end;
end;

function TLSPServer.ComputeExceptionFactsAt(const APath: string; ALine0: Integer): TJSONArray;
begin
  Result:= TJSONArray.Create;
  if (not FExceptionFacts) or (APath = '') or (ALine0 < 0) then Exit;  // dl:ok duplicate-code@fa81 -- 149 LX exception-site JSON mirrors the callerCounts title builder over the same facts; 150 row to share
  var DbPath: string:= '';
  var FilePath: string:= '';
  for var St: ISymbolStore in StoresForFile(APath) do
  begin
    var Fid: Int64:= St.FindFileIdByPath(APath);
    if Fid <= 0 then Continue;
    DbPath:= StorePathOf(St);
    FilePath:= St.GetFilePath(Fid);
    if DbPath <> '' then Break;
  end;
  if (DbPath = '') or (FilePath = '') then Exit;
  try
    for var F: TExceptionFact in ExceptionFactsOfFile(DbPath, FilePath) do
    begin
      if F.RoutineLine <> ALine0 + 1 then Continue;
      var O: TJSONObject:= TJSONObject.Create;
      Result.AddElement(O);
      O.AddPair('uri'      , FileToUri(if F.FilePath <> '' then F.FilePath else FilePath));
      O.AddPair('line'     , TJSONNumber.Create(if F.Line > 0 then F.Line - 1 else 0));
      O.AddPair('character', TJSONNumber.Create(if F.Col > 0 then F.Col - 1 else 0));
      O.AddPair('action'   , F.Action);
      O.AddPair('type'     , F.TypeName);
      O.AddPair('via'      , F.Via);
      O.AddPair('routine'  , F.Routine);
    end;
  except  // dl:ok bare-except@041e -- frees the not-yet-handed-over JSON value and re-raises; nothing is swallowed
    Result.Free;
    raise;
  end;
end;

function TLSPServer.ComputeCallerCounts(const APath: string): TJSONArray;
{ PERFORMANCE (INBOX-ide-hang-on-slow-engine section 2, 2026-10-29). The first
  version asked FindCallersByName ONCE PER ROUTINE and resolved GetFilePath ONCE
  PER RETURNED ROW. DevExpress dxBar.pas from the platform library: 4,256
  routines but 2,740 distinct names (84 `Create`s each re-fetched all 43,001
  `Create` refs), so 4.25 million rows and 4.25 million one-row path queries --
  13 minutes, during which the serial loop answered nothing. Now:

    * the work is keyed by (store, lowercased name), so a name is asked ONCE
      however many routines share it;
    * a line declared by ONE name in ONE store -- nearly every line -- gets its
      count from CountCallerSitesByNames, NAME_BATCH names per statement, no
      rows materialised (dxBar: 413 ms warm);
    * only a line with several keys (the same file in two stores, S1; or two
      routines on one line) still unions real sites, once per distinct key set,
      with each store's file paths cached;
    * between batches the loop serves waiting hovers (YieldToPendingRequests),
      so even a cold page cache cannot queue a tooltip behind this. }
const
  NAME_BATCH     = 64;   { names per CountCallerSitesByNames statement; a hover waits at most one batch }
  FILE_KEY_SHIFT = 40;   { Paths key: store index above bit 40, file id below (ids stay far under 2^40) }
var
  Arr     : TJSONArray;
  Path    : string    ;
  Decl    : TObjectDictionary<Integer, TStringList>;   { decl line -> distinct 'store:lowername' keys }
  KeyCount: TDictionary<string, Integer>;              { single-key lines: key -> distinct sites }
  SetCount: TDictionary<string, Integer>;              { multi-key lines: key set -> distinct sites }
  Batches : TObjectDictionary<Integer, TList<string>>; { store index -> names to count }
  Paths   : TDictionary<Int64, string>;                { store index shl 40 + file id -> lowercased path }
  Lines   : TList<Integer>;
  Stores  : TArray<ISymbolStore>;                   { LSP-1 CORE: the file's context set, not every startup store }

  function StoreOf(const AKey: string): Integer;
  begin
    Result:= StrToInt(Copy(AKey, 1, Pos(':', AKey) - 1));
  end;

  function NameOf(const AKey: string): string;
  begin
    Result:= Copy(AKey, Pos(':', AKey) + 1, MaxInt);
  end;

  { Distinct (path, line) sites over every key of one line -- the S1 dedup. }
  function UnionCount(const AKeys: TStringList): Integer;
  var
    Sites: TDictionary<string, Byte>;
  begin
    Sites:= TDictionary<string, Byte>.Create;
    try
      for var K: string in AKeys do
      begin
        var SI: Integer:= StoreOf(K);
        var St: ISymbolStore:= Stores[SI];
        for var R: TReference in St.FindCallersByName(NameOf(K)) do
        begin
          var PKey: Int64:= (Int64(SI) shl FILE_KEY_SHIFT) + R.FileId;
          var P: string;
          if not Paths.TryGetValue(PKey, P) then
          begin
            P:= LowerCase(St.GetFilePath(R.FileId));
            Paths.Add(PKey, P);
          end;
          Sites.AddOrSetValue(P + ':' + IntToStr(R.StartLine), 1);
        end;
      end;
      Result:= Sites.Count;
    finally
      Sites.Free;
    end;
  end;

begin
  Arr:= TJSONArray.Create;
  try
    Path:= APath;
    Stores:= StoresForFile(Path);

    { A file this index does not know is not an error -- it is a file with no
      lenses. An empty array says that unambiguously; an error would make the
      client retry something that will never succeed. }
    if Path <> '' then
    begin
      Decl    := TObjectDictionary<Integer, TStringList>.Create([doOwnsValues]);
      KeyCount:= TDictionary<string, Integer>.Create;
      SetCount:= TDictionary<string, Integer>.Create;
      Batches := TObjectDictionary<Integer, TList<string>>.Create([doOwnsValues]);
      Paths   := TDictionary<Int64, string>.Create;
      Lines   := TList<Integer>.Create;
      try
        { ROUTINES ONLY, keyed per DECLARATION LINE (S1), across the file's context set (LSP-1 CORE). }
        for var SI: Integer:= 0 to High(Stores) do
        begin
          if Stores[SI] = nil then Continue;
          for var Sym: TSymbol in Stores[SI].FindSymbolsByFile(Path) do
          begin
            if Sym.Kind not in [skProcedure, skFunction, skMethod, skConstructor, skDestructor] then Continue;
            if Sym.StartLine <= 0 then Continue;
            var Keys: TStringList;
            if not Decl.TryGetValue(Sym.StartLine, Keys) then
            begin
              Keys:= TStringList.Create;
              Keys.Sorted    := True;
              Keys.Duplicates:= dupIgnore;
              Decl.Add(Sym.StartLine, Keys);
            end;
            Keys.Add(IntToStr(SI) + ':' + LowerCase(Sym.Name));
          end;
        end;

        { The fast path: one key on the line, its count from the aggregate. }
        for var Keys: TStringList in Decl.Values do
          if (Keys.Count = 1) and not KeyCount.ContainsKey(Keys[0]) then
          begin
            KeyCount.Add(Keys[0], 0);
            var SI: Integer:= StoreOf(Keys[0]);
            var Names: TList<string>;
            if not Batches.TryGetValue(SI, Names) then
            begin
              Names:= TList<string>.Create;
              Batches.Add(SI, Names);
            end;
            Names.Add(NameOf(Keys[0]));
          end;
        for var SI: Integer in Batches.Keys do
        begin
          var Names: TArray<string>:= Batches[SI].ToArray;
          var B: Integer:= 0;
          while B < Length(Names) do
          begin
            YieldToPendingRequests;
            var Slice: TArray<string>:= Copy(Names, B, NAME_BATCH);
            var Got: TArray<Integer>:= Stores[SI].CountCallerSitesByNames(Slice);
            for var I: Integer:= 0 to High(Slice) do KeyCount[IntToStr(SI) + ':' + Slice[I]]:= Got[I];
            Inc(B, NAME_BATCH);
          end;
        end;

        { The exact path: several keys on the line, union their real sites. }
        for var Keys: TStringList in Decl.Values do
          if (Keys.Count > 1) and not SetCount.ContainsKey(Keys.CommaText) then
          begin
            YieldToPendingRequests;
            SetCount.Add(Keys.CommaText, UnionCount(Keys));
          end;

        { S2: SOURCE order, not dictionary enumeration order. }
        Lines.AddRange(Decl.Keys);
        Lines.Sort;
        for var Line: Integer in Lines do
        begin
          var Keys: TStringList:= Decl[Line];
          var Item: TJSONObject:= TJSONObject.Create;
          { 0-BASED, matching LSP convention. The store is 1-based and the
            plugin's cache is 0-based; converting HERE means exactly one place
            knows about the offset. }
          Item.AddPair('line' , TJSONNumber.Create(Line - 1));
          Item.AddPair('count', TJSONNumber.Create(if Keys.Count = 1 then KeyCount[Keys[0]] else SetCount[Keys.CommaText]));
          Arr.AddElement(Item);
        end;
      finally
        Lines.Free;
        Paths.Free;
        Batches.Free;
        SetCount.Free;
        KeyCount.Free;
        Decl.Free;
      end;
    end;
  except  // dl:ok bare-except@bb6b -- frees the not-yet-handed-over JSON value and re-raises; nothing is swallowed
    Arr.Free;
    raise;
  end;
  Result:= Arr;
end;

function TLSPServer.InputPending: Boolean;
var
  H    : THandle;
  Avail: DWORD  ;
begin
  Result:= False;
  if FInputEnded or (FStdIn = nil) then Exit;
  H:= FStdIn.Handle;
  case GetFileType(H) of
    FILE_TYPE_PIPE: Result:= PeekNamedPipe(H, nil, 0, nil, @Avail, nil) and (Avail > 0);
    { A redirected FILE (the battery's stdin): readable without blocking while
      the position is short of the end. }
    FILE_TYPE_DISK: Result:= FStdIn.Position < FStdIn.Size;
  end;
end;

procedure TLSPServer.YieldToPendingRequests;
{ WHY A YIELD AND NOT A WORKER THREAD. A worker would need its own connection to
  every store (FireDAC connections are not shared across threads), opening a
  3 GB library DB a second time, and every handler's state made thread-safe.
  The loop is single-threaded by design; the defect was only that ONE request
  could hold it for minutes. Serving waiting hovers at batch boundaries bounds
  hover latency by one batch with no new concurrency at all.

  WHICH METHODS. Read-only, cheap, latency-visible ones: hover, hoverBundle,
  definition, and $/cancelRequest (a notification with nothing to answer).
  Everything else -- didChange, shutdown, another callerCounts -- is deferred
  to Run, and once anything is deferred nothing later is served early. }
var
  Msg   : TJSONObject;
  Method: string     ;
begin
  if FYielding or (FDeferred.Count > 0) then Exit;
  FYielding:= True;
  try
    while (FDeferred.Count = 0) and InputPending do
    begin
      Msg:= ReadMessage;
      if Msg = nil then
      begin
        FInputEnded:= True;
        Break;
      end;
      Method:= if Msg.GetValue('method') <> nil then Msg.GetValue('method').Value else '';
      if (Method = 'textDocument/hover') or (Method = 'draglint/hoverBundle') or
         (Method = 'textDocument/definition') or (Method = '$/cancelRequest') then
      begin
        try
          try
            DispatchMessage(Msg);
          except
            { Isolated like a feature (S8): a hover raising here must not abort
              the long request it interrupted. stderr only -- stdout is the protocol. }
            on E: Exception do
            begin
              Writeln(ErrOutput, 'drag-lint LSP: ', Method, ' (served during a yield) raised ', E.ClassName, ': ', E.Message);
              if Msg.GetValue('id') <> nil then
                SendError(Msg.GetValue('id'), LSP_ERR_INTERNAL, 'internal error in ' + Method + ': ' + E.ClassName + ': ' + E.Message);
            end;
          end;
        finally
          Msg.Free;
        end;
      end
      else FDeferred.Enqueue(Msg);
    end;
  finally
    FYielding:= False;
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
  reads, writes, calls, types, attributes, events, raises, handles, impact. That is not tidiness
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
  JRaises: TJSONArray    ;
  JHandles: TJSONArray   ;
  JImpact: TJSONArray    ;
  Nm     : string        ;
  Width  : string        ;
  Depth  : Integer       ;
  St     : ISymbolStore  ;
  S      : TSymbol       ;
  R      : TReference    ;
  L      : TImpactLevel  ;
  DeclO  : TJSONObject   ;

  procedure AddRefRow(AArr: TJSONArray; const AFile: string; ALine, ACol: Integer; const AResolution: string);
  var
    O: TJSONObject;
  begin
    O:= TJSONObject.Create;
    O.AddPair('file', AFile);
    O.AddPair('line', TJSONNumber.Create(ALine));
    O.AddPair('col' , TJSONNumber.Create(ACol ));
    if AResolution <> '' then O.AddPair('resolution', AResolution); { XERJ item 3: LAST key, as the CLI }
    AArr.AddElement(O);
  end;

  { The ref-kind -> bucket mapping is the CLI verb's, including its catch-all:
    'call + anything else' lands in calls. Changing it here would make the two
    shapes disagree on a row's bucket while both still "work". }
  function GroupFor(const ARef: TReference; const ADecls: TArray<TSymbol>): TJSONArray;
  begin
    var Bucket: string:= UsageBucketIn(ARef, ADecls); { DRagLint.Query.Callers, shared with the CLI }
    if Bucket      = 'reads'      then Result:= JReads
    else if Bucket = 'writes'     then Result:= JWrites
    else if Bucket = 'types'      then Result:= JTypes
    else if Bucket = 'attributes' then Result:= JAttrs
    else if Bucket = 'events'     then Result:= JEvents
    else if Bucket = 'raises'     then Result:= JRaises
    else if Bucket = 'handles'    then Result:= JHandles
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
    JRaises:= TJSONArray.Create;
    JHandles:= TJSONArray.Create;
    JImpact:= TJSONArray.Create;

    for St in FStores do
    begin
      if St = nil then Continue;
      var Decls: TArray<TSymbol>:= St.FindSymbolsByExactName(Nm);
      for S in Decls do
      begin
        DeclO:= TJSONObject.Create;
        DeclO.AddPair('kind'     , S.Kind.ToText);
        DeclO.AddPair('qname'    , S.QualifiedName);
        DeclO.AddPair('file'     , St.GetFilePath(S.FileId));
        DeclO.AddPair('line'     , TJSONNumber.Create(S.StartLine));
        DeclO.AddPair('signature', S.Signature);
        JDecls.AddElement(DeclO);
      end;
      for R in UsageRefsForName(St, Nm, Decls) do
        AddRefRow(GroupFor(R, Decls), St.GetFilePath(R.FileId), R.StartLine, R.StartCol, R.Resolution);
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
    Res.AddPair('raises'      , JRaises);
    Res.AddPair('handles'     , JHandles);
    Res.AddPair('impact'      , JImpact);
    Reply.AddPair('result', Res);
    SendMessage(Reply);
  finally
    Reply.Free;
  end;
end;

function HoverResolvedCallers(const AStore: ISymbolStore; const ABareName: string; const ASel: TSymbol): TQueryCallerRows;
{ The hover bundle's resolved caller rows from one store: every resolved caller
  of ABareName, then -- RB-5 (1.38) -- the sites that reach the HOVERED method
  only through the interface it implements, as `find-callers --resolved` lists
  them (target_qname = the method, via = the interface method). Without them
  every such row named the interface as its target, the popup picked none, and
  a method called only through its interface read "0 callers".
  BOUNDED: the dispatch walk runs for the hovered QName's own symbols only,
  never for every same-named target the name query matched.
  Pinned by run_lsp_hover_via_callers_guard.ps1. }
var
  Acc: TList<TQueryCallerRow>;
begin
  Result:= ResolvedCallersForName(AStore, ABareName);
  if ASel.Kind not in [skProcedure, skFunction, skMethod] then Exit;
  Acc:= TList<TQueryCallerRow>.Create;
  try
    Acc.AddRange(Result);
    for var TS: TSymbol in AStore.FindSymbolsByQualifiedName(ASel.QualifiedName) do
      if TS.Kind in [skProcedure, skFunction, skMethod] then Acc.AddRange(DispatchCallersOf(AStore, TS.Id));
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

procedure AddViaKeys(const AObj: TJSONObject; const ARow: TQueryCallerRow);
{ RB-5: a via row names the interface method, with the keys and the rule that
  `find-callers --resolved --json` uses; a direct row gains no key. }
begin
  if ARow.Via = '' then Exit;
  AObj.AddPair('via'     , ARow.Via    );
  AObj.AddPair('via_kind', ARow.ViaKind);
  if ARow.ViaEdge = 'ambiguous' then AObj.AddPair('via_edge', ARow.ViaEdge);
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
    Res.AddPair('markdown', WithContextFooter(AParams, Comp.MdValue));

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
    var Asm_     : THoverAssembly:= AssembleHover(Comp.Store, Comp.Sel, True, HoverExtraStores(Comp.Path, Comp.Store)); { 149 LX: cross-DB uses }
    FactLines:= Asm_.FactLines + ExceptionFactLines(Comp.Store, Comp.Sel); { D1: the popup's Raises: line }
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
    { LSP-1 CORE: from the hovered file's context set, never another project's store. }
    var BundlePath: string;
    var BundleLine, BundleCol: Integer;
    var Search: TArray<ISymbolStore>;
    if PositionParams(AParams, BundlePath, BundleLine, BundleCol) then Search:= CallerSearchStores(BundlePath)
    else Search:= FStores;

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
        for var R in HoverResolvedCallers(Search[i], BareName, Comp.Sel) do
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
          AddViaKeys(O, R);

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
    { StoresForFile, not FStores: in a file no index owns, the receiver's type
      is declared in that file and nowhere else, so a member list built from the
      configured stores alone came back EMPTY -- measured 0 items after
      'LThing.' on the guard fixture. }
    Items:= TLspCompletion.BuildCompletionItems(StoresForFile(Path), Path, Line, Col);
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

{ True when the request's context.only names AKind or a parent of it ('source'
  covers 'source.removeUnusedImports'). No `only` = an ordinary light-bulb request. }
function CodeActionKindRequested(const AContext: TJSONObject; const AKind: string): Boolean;
begin
  Result:= False;
  if (AContext = nil) or (AContext.GetValue('only') is not TJSONArray) then Exit;
  for var V: TJSONValue in TJSONArray(AContext.GetValue('only')) do
    if SameText(V.Value, AKind) or StartsText(V.Value + '.', AKind) then Exit(True);
end;

function TLSPServer.BuildRemoveUnusedSourceAction(const APath, ABufferText: string): TJSONObject;
begin
  Result:= nil;
  var Owner: ISymbolStore:= nil;
  for var St: ISymbolStore in FStores do
    if (St <> nil) and (St.FindFileIdByPath(APath) > 0) then
    begin
      Owner:= St;
      Break;
    end;
  var Gate: TDropGate:= TUsesOnSave.ComputeDropGate(Owner, APath, ABufferText);
  Writeln(ErrOutput, Format('drag-lint LSP: uses-on-save: drop gate buffer=%s fresh=%s directive=%s (%s)',
    [BoolToStr(Gate.BufferMatchesIndex, True), BoolToStr(Gate.IndexFresh, True), BoolToStr(Gate.UsesClauseHasDirective, True), APath]));
  if not (Gate.BufferMatchesIndex and Gate.IndexFresh) then Exit;
  var LintJson: string;
  if not RunFullRulesLint(APath, LintJson, UNUSED_UNIT_RULE) then Exit;
  { D3: an entry of a clause holding a {$ directive is never removed silently }
  var Keep: TArray<TLintFinding>:= nil;
  for var F: TLintFinding in TUsesOnSave.UnusedFindingsFromLintJson(LintJson, APath) do
    if TUsesOnSave.UsesClauseHasDirectiveAt(ABufferText, F.StartLine) then
      Writeln(ErrOutput, Format('drag-lint LSP: uses-on-save: drop gate buffer=True fresh=True directive=True (%s:%d)', [APath, F.StartLine]))
    else if not SameText(F.Severity, 'warning') then
      Continue { info = the unit HAS an initialization section: linked for its side effect, never removed silently }
    else if TUsesOnSave.RemoveUnusedEntries(APath, ABufferText, [F]) = ABufferText then
      Continue { the fixer declines it (initialization-section tier, a layout it does not edit) }
    else
      Keep:= Keep + [F];
  if Length(Keep) = 0 then Exit;
  var FileUri: string:= FileToUri(APath);
  var Edit: TJSONObject:= TUsesOnSave.TextChangeEdit(FileUri, ABufferText, TUsesOnSave.RemoveUnusedEntries(APath, ABufferText, Keep));
  if Edit = nil then Exit;
  var Diags: TJSONArray:= TJSONArray.Create;
  try
    for var F: TLintFinding in Keep do Diags.AddElement(TUsesOnSave.DiagnosticOfFinding(F));
    Result:= TUsesOnSave.RemoveUnusedImportAction(Diags, Edit, Gate);
  finally
    Diags.Free;
    Edit.Free;
  end;
end;

procedure TLSPServer.HandleCodeAction(const AId: TJSONValue; const AParams: TJSONObject);
var
  Reply    : TJSONObject;
  TextDoc  : TJSONObject;
  RangeObj : TJSONObject;
  StartPos : TJSONObject;
  EndPos   : TJSONObject;
  Uri      : string     ;
  Path     : string     ;
  StartLine: Integer    ;
  StartCol : Integer    ;
  EndLine  : Integer    ;
  EndCol   : Integer    ;
  Context  : TJSONObject;
  Diags    : TJSONArray ;
  Actions  : TJSONArray ;
begin
  Reply:= TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    if AId <> nil then Reply.AddPair('id', AId.Clone as TJSONValue);

    if (AParams = nil) then
    begin
      Reply.AddPair('result', TJSONNull.Create);
      SendMessage(Reply);
      Exit;
    end;

    TextDoc := AParams.GetValue('textDocument') as TJSONObject;
    RangeObj:= AParams.GetValue('range'        ) as TJSONObject;
    Context := AParams.GetValue('context'      ) as TJSONObject;

    if (TextDoc = nil) or (RangeObj = nil) then
    begin
      Reply.AddPair('result', TJSONNull.Create);
      SendMessage(Reply);
      Exit;
    end;

    Uri:= TextDoc.GetValue('uri').Value;
    Path:= FileFromUri(Uri);

    { Extract range: LSP uses 0-based lines and characters; our builder uses 1-based. }
    StartPos:= RangeObj.GetValue('start') as TJSONObject;
    EndPos  := RangeObj.GetValue('end'  ) as TJSONObject;

    if (StartPos = nil) or (EndPos = nil) then
    begin
      Reply.AddPair('result', TJSONNull.Create);
      SendMessage(Reply);
      Exit;
    end;

    StartLine:= StrToIntDef(StartPos.GetValue('line'     ).Value, 0) + 1;
    StartCol := StrToIntDef(StartPos.GetValue('character').Value, 0) + 1;
    EndLine  := StrToIntDef(EndPos  .GetValue('line'     ).Value, 0) + 1;
    EndCol   := StrToIntDef(EndPos  .GetValue('character').Value, 0) + 1;

    { Get diagnostics from context if provided; otherwise build them. }
    if (Context <> nil) and (Context.GetValue('diagnostics') is TJSONArray) then
      Diags:= Context.GetValue('diagnostics') as TJSONArray
    else
      Diags:= TLspCompletion.BuildDiagnostics(EnsureLinter, Path, FStore);

    try
      { Build code actions for the given range and diagnostics. }
      Actions:= TLspCompletion.BuildCodeActions(Path, StartLine, StartCol, EndLine, EndCol, Diags);
      { unit-missing-from-uses quick-fixes, recomputed from the stores rather than read
        from the client's copy (a client may drop diagnostic data), placed first. }
      var MuDiags: TJSONArray:= TLspCompletion.BuildMissingUsesDiagnostics(Path, StoresForFile(Path));
      try
        var MuActs: TJSONArray:= TLspCompletion.BuildMissingUsesActions(Path, StartLine, EndLine, MuDiags);
        try
          for var J:= 0 to Actions.Count - 1 do MuActs.AddElement(Actions.Items[J].Clone as TJSONValue);
          Actions.Free;
          Actions:= MuActs;
          MuActs := nil;
        finally
          MuActs.Free;
        end;
      finally
        MuDiags.Free;
      end;
      { Auto uses on save: the removal quickfix edits the buffer the user is
        looking at; the silent source.removeUnusedImports action is built only
        when the client asks for that kind (context.only) -- it spawns a child
        lint, which a light-bulb request must not pay for. }
      var FromOverlay: Boolean;
      var BufText: string:= TEncoding.ANSI.GetString(TLiveDocuments.ReadBytes(Path, FromOverlay));
      var FileUri: string:= FileToUri(Path);
      var RmQuick: TJSONArray:= TUsesOnSave.RemoveUnusedQuickfixes(Path, FileUri, BufText, Diags, StartLine, EndLine);
      try
        for var J:= 0 to RmQuick.Count - 1 do Actions.AddElement(RmQuick.Items[J].Clone as TJSONValue);
      finally
        RmQuick.Free;
      end;
      if CodeActionKindRequested(Context, KINDS_ON_SAVE[1]) then
      begin
        var RmSrc: TJSONObject:= BuildRemoveUnusedSourceAction(Path, BufText);
        if RmSrc <> nil then Actions.AddElement(RmSrc);
      end;
      var FixActs: TJSONArray:= TLspCompletion.BuildFixActions(Path, StartLine, EndLine, Diags);
      try
        for var J:= 0 to FixActs.Count - 1 do Actions.AddElement(FixActs.Items[J].Clone as TJSONValue);
      finally
        FixActs.Free;
      end;
      Reply.AddPair('result', Actions);
    finally
      if Context = nil then Diags.Free; { only free if we built it; context owns it }
    end;

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
begin
  if AParams = nil then Exit;
  TextDoc:= AParams.GetValue('textDocument') as TJSONObject;
  if TextDoc = nil then Exit;
  Uri:= TextDoc.GetValue('uri').Value;
  Path:= FileFromUri(Uri);
  { LSP-1 CORE: announce the file's context (status bar) and its notices once. }
  FLastOpenPath:= Path;
  StoresForFile(Path);
  QueueContextNotification(Path);
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
  FOpenDocs.AddOrSetValue(LowerCase(Path), Uri);
  PublishDiagnostics(Uri, Path);
end; // procedure

procedure TLSPServer.PublishDiagnostics(const AUri, APath: string);
var
  Uri      : string     ;
  Path     : string     ;
  Diags    : TJSONArray ;
  Notif    : TJSONObject;
  ParamsObj: TJSONObject;
begin
  Uri := AUri;
  Path:= APath;
  { 1.38: the file's target compiler gates its lint findings (startup > config > context). }
  var TargetErr: string;
  var Gate: TTargetRuleGate:= TargetGateFor(Path, FileContext(Path), TargetErr);
  FPublishedTarget.AddOrSetValue(LowerCase(Path), Gate.Target);
  // v0.26: pass FStore so compiler_findings are merged into publishDiagnostics.
  Diags:= TLspCompletion.BuildDiagnostics(EnsureLinter, Path, FStore, Gate);
  if FFullRules then
  begin
    { C1: replace the lint subset (every source='drag-lint' entry) by the full
      `lint --json` set; the store's compiler findings (source='dcc') stay. }
    var Started: UInt64:= GetTickCount64;
    var LintJson: string;
    var Full: TJSONArray:= nil;
    if RunFullRulesLint(Path, LintJson) then Full:= TLspCompletion.DiagnosticsFromLintJson(LintJson);
    if Full <> nil then
    begin
      for var K:= Diags.Count - 1 downto 0 do
        if SameText((Diags.Items[K] as TJSONObject).GetValue<string>('source', ''), 'drag-lint') then
          Diags.Remove(K).Free;
      for var J:= 0 to Full.Count - 1 do
        if not Gate.Drops((Full.Items[J] as TJSONObject).GetValue<string>('code', '')) then { 1.38 }
          Diags.AddElement(Full.Items[J].Clone as TJSONValue);
      Full.Free;
    end
    else if FFullRulesSuperseded then
      Writeln(ErrOutput, 'drag-lint lsp: full-rules superseded by a newer save, result discarded: ', Path)
    else
      Writeln(ErrOutput, 'drag-lint lsp: full-rules fallback to the subset (stalled, failed run or invalid JSON): ', Path);
    Writeln(ErrOutput, Format('drag-lint lsp: full-rules %s %d ms %d findings', [Path, GetTickCount64 - Started, Diags.Count]));
  end;
  { unit-missing-from-uses needs the file's project store AND the platform library
    (StoresForFile), which BuildDiagnostics' single store cannot give it; built here,
    with the uses edits as data for the codeAction. Replaces any copy the --full-rules
    child produced (that one carries no data). }
  var MissingUses: TJSONArray:= TLspCompletion.BuildMissingUsesDiagnostics(Path, StoresForFile(Path));
  try
    for var K:= Diags.Count - 1 downto 0 do
      if SameText((Diags.Items[K] as TJSONObject).GetValue<string>('code', ''), MISSING_USES_RULE) then
        Diags.Remove(K).Free;
    for var J:= 0 to MissingUses.Count - 1 do
      Diags.AddElement(MissingUses.Items[J].Clone as TJSONValue);
  finally
    MissingUses.Free;
  end;
  { No store owns the file (e.g. another worktree's copy): its findings are not backed by
    a project index, so say so in the source tag. Owned files keep 'drag-lint'. }
  if not AnyStoreOwns(Path) then
    for var K:= 0 to Diags.Count - 1 do
      if SameText((Diags.Items[K] as TJSONObject).GetValue<string>('source', ''), 'drag-lint') then
      begin
        (Diags.Items[K] as TJSONObject).RemovePair('source').Free;
        (Diags.Items[K] as TJSONObject).AddPair('source', 'drag-lint (unowned)');
      end;
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

function TLSPServer.NewerSavePending(const AFile: string): Boolean;
begin
  for var Msg: TJSONObject in FDeferred do
  begin
    var Method: string:= if Msg.GetValue('method') <> nil then Msg.GetValue('method').Value else '';
    if (Method <> 'textDocument/didSave') and (Method <> 'textDocument/didOpen') then Continue;
    var Params: TJSONObject:= Msg.GetValue('params') as TJSONObject;
    var Doc: TJSONObject:= if Params <> nil then Params.GetValue('textDocument') as TJSONObject else nil;
    if (Doc <> nil) and (Doc.GetValue('uri') <> nil) and SameText(FileFromUri(Doc.GetValue('uri').Value), AFile) then Exit(True);
  end;
  Result:= False;
end; // function

function TLSPServer.WaitFullRulesChild(AProcess, AOut: THandle; ABudget: Cardinal; const AFile: string; ASupersedable: Boolean): Boolean;
var
  Deadline: UInt64    ;
  LastSize: DWORD     ;
  Size    : DWORD     ;
  CpuMark : Int64     ;
  Cpu     : Int64     ;
  CreateT, ExitT, KernelT, UserT: TFileTime;
begin
  FFullRulesSuperseded:= False;
  LastSize:= 0;
  CpuMark := 0;
  Deadline:= GetTickCount64 + ABudget;
  while WaitForSingleObject(AProcess, LSP_FULL_RULES_POLL_MS) <> WAIT_OBJECT_0 do
  begin
    YieldToPendingRequests;
    if ASupersedable and NewerSavePending(AFile) then
    begin
      FFullRulesSuperseded:= True;
      Exit(False);
    end;
    Size:= GetFileSize(AOut, nil);
    if (Size <> INVALID_FILE_SIZE) and (Size > LastSize) then
    begin
      LastSize:= Size;
      Deadline:= GetTickCount64 + ABudget;
    end;
    if GetProcessTimes(AProcess, CreateT, ExitT, KernelT, UserT) then
    begin
      { a FILETIME is the little-endian 64-bit count of 100 ns units }
      Cpu:= PInt64(@UserT)^ + PInt64(@KernelT)^;
      if Cpu - CpuMark >= LSP_FULL_RULES_CPU_PROGRESS_100NS then
      begin
        CpuMark:= Cpu;
        Deadline:= GetTickCount64 + ABudget;
      end;
    end;
    if GetTickCount64 >= Deadline then Exit(False);
  end;
  Result:= True;
end; // function
function TLSPServer.RunFullRulesLint(const AFile: string; out AJson: string; const ARule: string): Boolean;
var
  Sa      : TSecurityAttributes;
  TmpPath : string;
  HOut    : THandle;
  HNul    : THandle;
  Si      : TStartupInfo;
  Pi      : TProcessInformation;
  Cmd     : string;
  ChildExe: string;
  ExitCode: DWORD;
begin
  Result:= False;
  AJson:= '';
  if AFile = '' then Exit;
  { LSP C12: the FIRST store that owns the file is the one the child lint picks
    (it walks the same --db list in this order), so it alone decides the budget. }
  var OwningDb: string:= '';
  for var I:= 0 to High(FStores) do
    if FStores[I].FindFileIdByPath(AFile) > 0 then
    begin
      if I <= High(FStorePaths) then OwningDb:= FStorePaths[I];
      Break;
    end;
  { Owner ruling D1 (like the IDE): the child lints against the ACTIVE context's
    DB set -- its project DB + its platform's library -- exactly the set hover
    uses (DbSetFor), never every store opened at startup. No active project DB
    (a loose or unowned file) keeps the startup list. }
  var ChildDbs: TArray<string>;
  var CtxDbs: TLspDbSet:= DbSetFor(AFile, FileContext(AFile));
  if CtxDbs.ProjectDb <> '' then
  begin
    ChildDbs:= [CtxDbs.ProjectDb, CtxDbs.LibraryDb];
    OwningDb:= CtxDbs.ProjectDb;
  end
  else ChildDbs:= FStorePaths;
  var Budget: Cardinal:= LintChildTimeoutMs(OwningDb);
  TmpPath:= TPath.GetTempFileName;
  FillChar(Sa, SizeOf(Sa), 0);
  Sa.nLength       := SizeOf(Sa);
  Sa.bInheritHandle:= True;
  HOut:= CreateFile(PChar(TmpPath), GENERIC_WRITE, FILE_SHARE_READ, @Sa, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  HNul:= CreateFile('NUL', GENERIC_READ or GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, @Sa, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  try
    if (HOut = INVALID_HANDLE_VALUE) or (HNul = INVALID_HANDLE_VALUE) then Exit;
    FillChar(Si, SizeOf(Si), 0);
    Si.cb         := SizeOf(Si);
    Si.dwFlags    := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    Si.wShowWindow:= SW_HIDE;
    Si.hStdInput  := HNul;
    Si.hStdOutput := HOut;
    Si.hStdError  := HNul;
    { I1: hand the child the server's OWN index list so it resolves the same stores
      (used-unit-not-resolvable and friends need them). }
    { TEST-ONLY override: run_lsp_full_rules_guard substitutes a stub child
      (timeout, bad JSON) through this variable; it is never set in production. }
    ChildExe:= GetEnvironmentVariable('DRAGLINT_FULLRULES_CHILD_EXE');
    if ChildExe = '' then ChildExe:= ParamStr(0);
    Cmd:= '"' + ChildExe + '" lint "' + AFile + '" --json --output-encoding utf8'; { the engine writes 7-bit ASCII by default; the read below is UTF-8 }
    if ARule <> '' then Cmd:= Cmd + ' --rule "' + StringReplace(ARule, '"', '', [rfReplaceAll]) + '"';
    for var DbP in ChildDbs do
      if DbP <> '' then Cmd:= Cmd + ' --db "' + DbP + '"';
    { C15: the in-process lint's profile, not a different one; values quoted, a double quote dropped. }
    if FStartProject <> '' then Cmd:= Cmd + ' --project "' + StringReplace(FStartProject, '"', '', [rfReplaceAll]) + '"';
    if FStartPlatform <> '' then Cmd:= Cmd + ' --platform "' + StringReplace(FStartPlatform, '"', '', [rfReplaceAll]) + '"';
    UniqueString(Cmd);
    if not CreateProcess(PChar(ChildExe), PChar(Cmd), nil, nil, True, CREATE_NO_WINDOW, nil, nil, Si, Pi) then Exit;
    try
      if not WaitFullRulesChild(Pi.hProcess, HOut, Budget, AFile, ARule = '') then
      begin
        TerminateProcess(Pi.hProcess, 1);
        WaitForSingleObject(Pi.hProcess, LSP_FULL_RULES_REAP_MS);
        Exit;
      end;
      ExitCode:= 1;
      GetExitCodeProcess(Pi.hProcess, ExitCode);
      { lint exits 1 when it REPORTS findings (stdout is the complete array) and
        2+ on an error such as a missing path, so exit 0 or 1 with a JSON array is
        a good run; anything else falls back to the subset. }
      CloseHandle(HOut);
      HOut:= INVALID_HANDLE_VALUE;
      try
        AJson:= TFile.ReadAllText(TmpPath, TEncoding.UTF8);
      except
        on Exception do AJson:= ''; { never raise out of didSave: the caller falls back to the subset }
      end;
      Result:= (ExitCode <= 1) and AJson.TrimLeft.StartsWith('[');
    finally
      CloseHandle(Pi.hThread);
      CloseHandle(Pi.hProcess);
    end;
  finally
    if HOut <> INVALID_HANDLE_VALUE then CloseHandle(HOut);
    if HNul <> INVALID_HANDLE_VALUE then CloseHandle(HNul);
    try
      TFile.Delete(TmpPath);
    except
      on Exception do TmpPath:= ''; { a leftover temp file is harmless; raising out of didSave is not }
    end;
  end;
end; // function

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
  var ClosedUri: string:= TextDoc.GetValue('uri').Value;
  var ClosedPath: string:= FileFromUri(ClosedUri);
  TLiveDocuments.Remove(ClosedPath);
  TProjectProfileCache.Forget(ClosedPath); // LSP C10: keep the file -> .dproj memo bounded to open files
  FCtxCache.Remove(LowerCase(ClosedPath)); // LSP-1 CORE: same bound for the context memo
  FOpenDocs.Remove(LowerCase(ClosedPath));
  { INBOX-lsp-hover-unindexed-file: the ephemeral index exists only to answer
    hovers in ONE file. Once that buffer is gone it is dead weight holding a
    temp database open, so it is evicted with the overlay and for the same
    reason. }
  if (ClosedPath <> '') and SameText(ClosedPath, FEphemFile) then DropEphemeralStore;
  PublishEmptyDiagnostics(ClosedUri); // stale Problems entries: the client keeps the last publish until told otherwise
end; // procedure

procedure TLSPServer.PublishEmptyDiagnostics(const AUri: string);
var
  Notif, ParamsObj: TJSONObject;
begin
  Notif:= TJSONObject.Create;
  try
    Notif.AddPair('jsonrpc', '2.0');
    Notif.AddPair('method', 'textDocument/publishDiagnostics');
    ParamsObj:= TJSONObject.Create;
    ParamsObj.AddPair('uri', AUri);
    ParamsObj.AddPair('diagnostics', TJSONArray.Create);
    Notif.AddPair('params', ParamsObj);
    SendRawNotification(Notif);
  finally
    Notif.Free;
  end;
end; // procedure

function IsLintableSource(const APathLower: string): Boolean;
begin
  Result:= APathLower.EndsWith('.pas') or APathLower.EndsWith('.dpr') or APathLower.EndsWith('.dpk');
end; // function

procedure TLSPServer.HandleDidChangeWatchedFiles(const AParams: TJSONObject);
{ A deleted file (e.g. a removed git worktree) is never didClose'd, so without this its
  last diagnostics stay in the client's Problems panel forever. }
const
  FILE_CHANGE_DELETED = 3; // LSP FileChangeType.Deleted
var
  Changes: TJSONArray;
  Item: TJSONValue;
  Entry: TJSONObject;
  DelUri, DelPath, ChgPath: string;
  Seen: TDictionary<string, Boolean>;
begin
  if AParams = nil then Exit;
  Changes:= AParams.GetValue('changes') as TJSONArray;
  if Changes = nil then Exit;
  { A file edited on disk by another tool (an agent) never reaches didChange/didSave, so
    its Problems entries went stale. Created/Changed on a lintable source that the client
    does NOT have open is re-linted from disk; an open file is left alone (the editor
    buffer is authoritative and the client sends didChange when it reloads). The batch is
    de-duplicated and capped, so a burst of writes stays bounded. }
  Seen:= TDictionary<string, Boolean>.Create;
  try
    for Item in Changes do
    begin
      Entry:= Item as TJSONObject;
      if Entry = nil then Continue;
      DelUri:= Entry.GetValue<string>('uri', '');
      if DelUri = '' then Continue;
      DelPath:= FileFromUri(DelUri);
      if Entry.GetValue<Integer>('type', 0) = FILE_CHANGE_DELETED then
      begin
        TLiveDocuments.Remove(DelPath);
        TProjectProfileCache.Forget(DelPath);
        if (DelPath <> '') and SameText(DelPath, FEphemFile) then DropEphemeralStore;
        PublishEmptyDiagnostics(DelUri);
        Continue;
      end;
      ChgPath:= LowerCase(DelPath);
      if not IsLintableSource(ChgPath) or FOpenDocs.ContainsKey(ChgPath) or Seen.ContainsKey(ChgPath) then Continue;
      if Seen.Count >= WATCH_REFRESH_MAX then Break;
      Seen.Add(ChgPath, True);
      RefreshFileFromDisk(DelUri);
    end;
  finally
    Seen.Free;
  end;
end; // procedure

procedure TLSPServer.RefreshFileFromDisk(const AUri: string);
var
  Path: string;
begin
  Path:= FileFromUri(AUri);
  if (Path = '') or not TFile.Exists(Path) then
  begin
    PublishEmptyDiagnostics(AUri);
    Exit;
  end;
  TProjectProfileCache.Forget(Path);
  if not FOpenDocs.ContainsKey(LowerCase(Path)) then TLiveDocuments.Remove(Path);
  PublishDiagnostics(AUri, Path);
end; // procedure

procedure TLSPServer.HandleRefreshDiagnostics(const AParams: TJSONObject);
var
  Uris: TJSONArray;
  I, Last: Integer;
begin
  if AParams = nil then Exit;
  Uris:= AParams.GetValue('uris') as TJSONArray;
  if Uris = nil then Exit;
  Last:= Uris.Count;
  if Last > WATCH_REFRESH_MAX then Last:= WATCH_REFRESH_MAX;
  for I:= 0 to Last - 1 do
    RefreshFileFromDisk(Uris.Items[I].Value);
end; // procedure

function TLSPServer.StandDownTaken: Boolean;
begin
  Result:= (FControl <> nil) and FControl.StandDownRequested;
end;

function TLSPServer.ReadMessageGuarded: TJSONObject;
begin
  { The bracket is what tells the control listener that cancelling the main
    thread's synchronous I/O is safe: inside it the pending read is stdin's. }
  if FControl <> nil then FControl.EnterRead;
  try
    Result:= ReadMessage;
  finally
    if FControl <> nil then FControl.LeaveRead;
  end;
end;

function TLSPServer.DispatchMessage(const AMsg: TJSONObject): Boolean;
var
  Method   : string     ;
  Id       : TJSONValue ;
  Params   : TJSONObject;
  ParamsVal: TJSONValue ;
  Feature  : TLspFeature;
begin
  Result:= True;
  Method:= if AMsg.GetValue('method') <> nil then AMsg.GetValue('method').Value else '';
  Id       := AMsg.GetValue('id'    );
  ParamsVal:= AMsg.GetValue('params');
  Params:= if ParamsVal is TJSONObject then TJSONObject(ParamsVal) else nil;

  if Method      = 'initialize' then HandleInitialize(Id, Params)
  else if Method = 'initialized' then
    // notification, no response
  else if Method = 'shutdown' then HandleShutdown(Id)
  else if Method = 'exit' then Result:= False
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
  else if Method = 'textDocument/codeAction' then HandleCodeAction(Id, Params)
  else if Method = 'textDocument/didOpen' then HandleDidOpenOrSave(Params)
  else if Method = 'textDocument/didSave' then HandleDidOpenOrSave(Params)
  else if Method = 'textDocument/didChange' then HandleDidChange(Params)
  else if Method = 'textDocument/didClose' then HandleDidClose(Params)
  else if Method = 'workspace/didChangeWatchedFiles' then HandleDidChangeWatchedFiles(Params)
  else if Method = 'draglint/refreshDiagnostics' then HandleRefreshDiagnostics(Params)
  else if Method = 'workspace/didChangeConfiguration' then HandleDidChangeConfiguration(Params)
  else if (Method = 'workspace/executeCommand') and HandleSetContext(Id, Params) then
    // LSP-1 CORE: draglint.setContext answered; other commands fall through to the feature
  { S0: registered features, tried after every built-in and before the
    catch-all, so an unknown method still answers -32601. }
  else if FFeatureByMethod.TryGetValue(Method, Feature) then
  begin
    { S8: exception isolation. One feature raising answers THIS request with
      -32603 (internal error) and leaves the server alive for the next. }
    try
      Feature.Handle(FContext, Method, Id, Params);
    except
      on E: Exception do
      begin
        { stderr only -- stdout is the protocol channel. A notification (Id = nil) has no reply, so this is its only trace. }
        Writeln(ErrOutput, 'drag-lint LSP: feature ', Method, ' raised ', E.ClassName, ': ', E.Message);
        if Id <> nil then SendError(Id, LSP_ERR_INTERNAL, 'internal error in ' + Method + ': ' + E.ClassName + ': ' + E.Message);
      end;
    end;
  end
  else if (Id <> nil) and (Method <> '') then SendError(Id, LSP_ERR_METHOD_NOT_FOUND, 'method not found: ' + Method);
end;

procedure TLSPServer.Run;
var
  Msg   : TJSONObject;
  Method: string     ;
begin
  FQueueNotices:= True; { LSP-1 CORE: stdout is ours here (never in proxy mode) }
  while not FShuttingDown do
  begin
    { W3 control channel: a stand-down taken here (after a handler ran while
      the request arrived) ends the loop without another read; one that
      arrives DURING the read is delivered by CancelSynchronousIo, which makes
      ReadMessage return nil -- the EnterRead/LeaveRead bracket is what tells
      the listener that cancelling is safe, i.e. the pending I/O is stdin's and
      not a SQLite page read inside a handler. }
    if StandDownTaken then Break;
    { Yield: what a long request read but did not serve comes first, in
      arrival order; an EOF met during a yield ends the loop once it is drained. }
    Msg:= nil;
    if FDeferred.Count > 0 then Msg:= FDeferred.Dequeue
    else if not FInputEnded then Msg:= ReadMessageGuarded;
    if Msg = nil then Break;
    FWorkLock.Enter; { LSP-1 CORE: a finishing re-index waits for this request }
    try
      Method:= if Msg.GetValue('method') <> nil then Msg.GetValue('method').Value else '';
      if FControl <> nil then FControl.BeginWork(Method);
      BeatBegin(Method); { 1.40 heartbeat: every request is an action; the engine code it runs reports its steps }
      if not DispatchMessage(Msg) then Break;
    finally
      if FControl <> nil then FControl.EndWork;
      BeatBegin(''); { idle }
      try
        FlushPending; { LSP-1 CORE: notices + draglint/context queued by this message }
      finally
        FWorkLock.Leave;
      end;
      Msg.Free;
    end; // try
  end; // while
end; // procedure

end.
