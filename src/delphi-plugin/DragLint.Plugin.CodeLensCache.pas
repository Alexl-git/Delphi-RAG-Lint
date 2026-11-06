unit DragLint.Plugin.CodeLensCache;

{ Singleton cache for per-file code-lens data (caller counts).

  PopulateOnce shells out to drag-lint surface to discover method
  declarations, then for each method shells drag-lint query find-callers
  to get the caller count.  Results are stored as a map:
    lowercase(filepath) -> (0-based line number -> "[N callers]" label)
  1.40 (ifrpt): an interface or interface method also gets "[N implementors]",
  from the 'implementors' array of the same draglint/callerCounts reply.

  PaintLine reads from the cache only -- no subprocess calls during paint.
  Cache is invalidated (file entry dropped) on BufferSaved via
  InvalidateFile so it repopulates on the next EditorViewActivated.

  BOUNDED (2026-08-16). The cache retains at most CODELENS_MAX_FILES files and
  evicts least-recently-used first. Before that it only ever shrank via Clear or
  InvalidateFile, so an IDE session that visited many files grew it without any
  limit. "Used" means painted (GetForLine) or activated (PopulateOnce), which is
  why both touch -- an LRU that only ordered by INSERTION would evict the file
  the user has been staring at all afternoon. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , System.SyncObjs
  ;

const
  { Default ceiling on how many FILES the cache retains. Chosen to comfortably
    cover an ordinary editing session's open tabs and recent navigation while
    keeping the worst case bounded: each entry is one line->label map for one
    file, so a few dozen is kilobytes, not megabytes. Before this bound existed
    the cache only ever shrank via Clear or InvalidateFile, so a long IDE session
    that visited many files grew it without limit. }
  CODELENS_MAX_FILES = 32;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.CodeLensCache.pas) ?, DragLint.Plugin.CodeLensCache.CodeLensCache (DragLint.Plugin.CodeLensCache.pas)</para>
  /// <para>Used in units: DragLint.Plugin.CodeLensCache</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDragLintCodeLensCache = class
    strict private
      { outer key: lowercase filepath; inner key: 0-based line number }
      FByFile  : TDictionary<string, TDictionary<Integer, string>>;
      { Most-recently-used FIRST. Kept in step with FByFile under FLock; its
        length is therefore always FByFile.Count. This is a plain TList rather
        than anything cleverer because it is bounded by FMaxFiles, so the O(n)
        Remove on touch is a few dozen string compares -- and GetForLine sits on
        the IDE paint path, where predictability matters more than asymptotics. }
      FOrder   : TList<string>                                    ;
      FMaxFiles: Integer                                          ;
      FLock    : TCriticalSection                                 ;
      { Keys whose fallback spawn pass is running on a worker. Under FLock. }
      FInFlight: TDictionary<string, Boolean>                     ;

      { Both assume FLock is already held. }
      /// <summary><!-- drag-lint:auto sum -->Both assume FLock is already held.</summary>
      /// <param name="AKey"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.GetForLine (DragLint.Plugin.CodeLensCache.pas), DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.PopulateOnce (DragLint.Plugin.CodeLensCache.pas), DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.StoreForFile (DragLint.Plugin.CodeLensCache.pas)</para>
      /// <para>Reads: FOrder</para>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Clear"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Create"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Destroy"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.EvictLocked"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.FileCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure TouchLocked(const AKey: string);
      /// <summary><!-- drag-lint:auto sum -->Drop least-recently-used entries until the
      /// cap is met, freeing each inner map as it goes -- the cache owns them. FLock must
      /// already be held.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.StoreForFile (DragLint.Plugin.CodeLensCache.pas)</para>
      /// <para>Reads: FOrder, FMaxFiles, FByFile</para>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Clear"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Create"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Destroy"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.FileCount"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.FinishFallback"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure EvictLocked;
    private
      { Main thread: clears AKey's in-flight mark and stores AInner (nil = store nothing). }
      /// <summary><!-- drag-lint:auto sum -->Main thread: clears AKey's in-flight mark
      /// and stores AInner (nil = store nothing).</summary>
      /// <param name="AKey"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AInner"><!-- drag-lint:auto type -->TDictionary&lt;Integer, string&gt;</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.PopulateOnce (DragLint.Plugin.CodeLensCache.pas)</para>
      /// <para>Calls: DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.StoreForFile</para>
      /// <para>Reads: FLock, FInFlight</para>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.StoreForFile"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Clear"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Create"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Destroy"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.EvictLocked"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure FinishFallback(const AKey: string; AInner: TDictionary<Integer, string>);
    public
      /// <summary>Creates the cache with a bound on how many files it retains.</summary>
      /// <param name="AMaxFiles">File ceiling; values below 1 are clamped to 1.
      /// Defaults to CODELENS_MAX_FILES.</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.CodeLensCache.CodeLensCache (DragLint.Plugin.CodeLensCache.pas)</para>
      /// <para>constructor</para>
      /// <para>Writes: FByFile, FOrder, FMaxFiles, FLock, FInFlight</para>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Clear"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Destroy"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.EvictLocked"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.FileCount"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.FinishFallback"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(AMaxFiles: Integer = CODELENS_MAX_FILES);
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Reads: FLock, FByFile, FOrder, FInFlight</para>
      /// <para>Directives: override</para>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Clear"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Create"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.EvictLocked"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.FileCount"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.FinishFallback"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      destructor Destroy; override;

      { Returns "[N callers]" string for the given file + 0-based line,
      or "" if nothing is cached for that line.

      A HIT ALSO TOUCHES the entry, which is what makes this an LRU rather than
      a FIFO: the file currently being painted is exactly the one that must not
      be evicted, and it may have been populated long ago. }
      /// <summary><!-- drag-lint:auto sum -->A HIT ALSO TOUCHES the entry, which is what
      /// makes this an LRU rather than a FIFO: the file currently being painted is
      /// exactly the one that must not be evicted, and it may have been populated long
      /// ago.</summary>
      /// <param name="AFilePath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ALine"><!-- drag-lint:auto type -->Integer</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: ''.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.EditViewNotifier.TDragLintEditViewNotifier.PaintLine (DragLint.Plugin.EditViewNotifier.pas)</para>
      /// <para>Calls: DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.TouchLocked, LowerCase</para>
      /// <para>Reads: FLock, FByFile</para>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.TouchLocked"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Clear"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Create"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Destroy"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.EvictLocked"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function GetForLine(const AFilePath: string; ALine: Integer): string;

      /// <summary>Stores (and takes ownership of) the line->label map for one
      /// file, evicting the least recently used entries past the cap.</summary>
      /// <param name="AFilePath">File the map belongs to; keyed case-insensitively.</param>
      /// <param name="AInner">Line->label map. The cache OWNS it from this call
      /// on and frees it on eviction, invalidation or destruction. Passing nil
      /// is a no-op.</param>
      /// <remarks>
      /// PopulateOnce's own store path; also the seam a console test
      /// uses to fill the cache without shelling out to the exe.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.FinishFallback (DragLint.Plugin.CodeLensCache.pas), DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.PopulateOnce (DragLint.Plugin.CodeLensCache.pas)</para>
      /// <para>Calls: DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.EvictLocked, DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.TouchLocked, LowerCase</para>
      /// <para>Reads: FLock, FByFile</para>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.EvictLocked"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.TouchLocked"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Clear"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Create"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure StoreForFile(const AFilePath: string; AInner: TDictionary<Integer, string>);

      /// <summary>Number of FILES currently retained (never exceeds MaxFiles).</summary>
      /// <returns><!-- drag-lint:auto -->Integer -- Observed: FByFile.Count.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Reads: FLock, FByFile</para>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Clear"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Create"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Destroy"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.EvictLocked"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.FinishFallback"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function FileCount: Integer;

      /// <summary>The configured file ceiling.</summary>
      property MaxFiles: Integer read FMaxFiles;

      { Drop the cached entry for AFilePath so the next Populate re-runs. }
      /// <summary><!-- drag-lint:auto sum -->Drop the cached entry for AFilePath so the
      /// next Populate re-runs.</summary>
      /// <param name="AFilePath"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: LowerCase</para>
      /// <para>Reads: FLock, FByFile, FOrder</para>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Clear"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Create"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Destroy"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.EvictLocked"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.FileCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure InvalidateFile(const AFilePath: string);

      /// <summary>Fills the caller-count labels of one file, once: through the
      /// LSP hook when one can answer, else by spawning "drag-lint surface" and
      /// one "query find-callers" per method.</summary>
      /// <param name="AFilePath">The source file; empty = no-op.</param>
      /// <param name="AExePath">Path to drag-lint.exe; empty = no-op.</param>
      /// <param name="ADbPath">The project database; empty = no-op.</param>
      /// <param name="AOnStored">Optional; called on the MAIN thread once a
      /// fallback pass has stored its labels (the caller repaints the gutter).</param>
      /// <remarks>
      /// Never waits on the engine (2026-11-01, IDE-HANG): it runs on view
      /// activation in the IDE main thread. The spawn fallback runs on a worker
      /// thread -- one per file at a time -- and stores its answer on the main
      /// thread when the last child finishes, however late. Each child is
      /// bounded by a STALL budget (ProcRun.RunCaptureStdout), not a wall clock.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.EditViewNotifier.TDragLintEditServicesNotifier.EditorViewActivated (DragLint.Plugin.EditViewNotifier.pas)</para>
      /// <para>Calls: AOnStored, DragLint.Plugin.CodeLensCache.SpawnCallerCounts, DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.FinishFallback, DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.StoreForFile, DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.TouchLocked, DragLint.Plugin.Telemetry.DLT, Format, GCallerCountsHook, LowerCase</para>
      /// <para>Complexity: 21 (cyclomatic, outer body), 95 lines (full implementation)</para>
      /// <para>Reads: FLock, FByFile, FInFlight</para>
      /// <para>Catches: Exception (swallowed)</para>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.SpawnCallerCounts"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.FinishFallback"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.StoreForFile"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.TouchLocked"/>
      /// <seealso cref="DragLint.Plugin.Telemetry.DLT"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure PopulateOnce(const AFilePath, AExePath, ADbPath: string; const AOnStored: TProc = nil);

      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Reads: FLock, FByFile, FOrder</para>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Create"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Destroy"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.EvictLocked"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.FileCount"/>
      /// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.FinishFallback"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure Clear;
  end;

{ v(2026-08-24): the LSP-backed fast path.

  PopulateOnce shells `query find-callers` ONCE PER METHOD. Measured on
  DataCopy's uMainZeissCopy.pas: 136 routines at ~165 ms per process start is
  over twenty seconds of serial spawning to label ONE file, repeated every time
  the cache repopulates. `draglint/callerCounts` answers the whole file in one
  round trip against the already-open stores -- 2.10 s including a COLD process
  start and index open, and a fraction of that against the warm server.

  WHY A HOOK RATHER THAN A DIRECT CALL. This unit cannot use
  DragLint.Plugin.Editor, which owns the LSP client: Editor already uses
  DragLint.Plugin.EditViewNotifier, which uses this unit, so the reverse edge
  would close a cycle. Editor installs the hook at startup instead, and nothing
  here needs to know the LSP exists.

  Returns False when the LSP cannot answer -- not started, down, or the file is
  in no index -- and PopulateOnce then does exactly what it did before. The slow
  path is the FALLBACK, not the norm, and it is deliberately still there: a code
  lens that stops appearing while the server restarts is worse than a slow one. }
type
  /// <summary>Receives one file's caller counts on the MAIN thread.</summary>
  /// <param name="AOk">False when the engine timed out or answered nothing usable.</param>
  /// <param name="ALines">0-based lines; -1 entries are skipped.</param>
  /// <param name="ACounts">Caller count per entry of ALines; -1 = no caller label (an
  /// interface line that only carries implementors).</param>
  /// <param name="AImpls">Implementor count per entry of ALines (1.40): 0 = none.</param>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.CodeLensCache.pas), DragLint.Plugin.Editor.LspCallerCounts (DragLint.Plugin.Editor.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCallerCountsDone = reference to procedure(AOk: Boolean; const ALines, ACounts, AImpls: TArray<Integer>);

  /// <summary>Asynchronous caller-count source (2026-10-29).</summary>
  /// <param name="AFilePath"><!-- drag-lint:auto type -->const string</param>
  /// <param name="ADone"><!-- drag-lint:auto type -->const TCallerCountsDone</param>
  /// <returns>True when the hook TOOK the file -- it sent a request whose answer
  /// arrives through ADone, or it declined for now (busy, one in flight, engine
  /// starting) and the next activation asks again. False only when no LSP can
  /// answer, and the cache falls back to its per-method spawns.</returns>
  /// <remarks>
  /// The hook must never wait on the engine: it runs on view activation
  /// in the IDE main thread.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.CodeLensCache.pas), DragLint.Plugin.CodeLensCache.SetCallerCountsHook (DragLint.Plugin.CodeLensCache.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCallerCountsHook = reference to function(const AFilePath: string;
    const ADone: TCallerCountsDone): Boolean;

/// <summary>Installs the LSP-backed caller-count source. Pass nil to remove it
/// and force the per-method spawn path.</summary>
/// <param name="AHook"><!-- drag-lint:auto type -->const TCallerCountsHook</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: initialization/finalization (DragLint.Plugin.Editor.pas)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure SetCallerCountsHook(const AHook: TCallerCountsHook);

/// <returns><!-- drag-lint:auto -->TDragLintCodeLensCache -- Observed: GCodeLensCache.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.EditViewNotifier.TDragLintEditServicesNotifier.EditorViewActivated (DragLint.Plugin.EditViewNotifier.pas), DragLint.Plugin.EditViewNotifier.TDragLintEditViewNotifier.PaintLine (DragLint.Plugin.EditViewNotifier.pas)</para>
/// <para>Calls: DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Create</para>
/// <seealso cref="DragLint.Plugin.CodeLensCache.TDragLintCodeLensCache.Create"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CodeLensCache: TDragLintCodeLensCache;

implementation

uses
  Winapi.Windows
  , System.Classes
  , System.IOUtils
  , DragLint.Plugin.ProcRun   { RunCaptureStdout -- stall-bounded spawn }
  , DragLint.Plugin.Telemetry { DLT }
  ;

const
  { STALL budget per spawned child (ProcRun semantics): killed only after this
    long with neither output nor CPU. The old 15 s wall clock came AFTER an
    unbounded ReadFile, so a hung child blocked forever. }
  CODELENS_SPAWN_STALL_MS = 15000;

{ ---- module-level singleton ---- }

var
  GCodeLensCache: TDragLintCodeLensCache = nil;
  { Every live cache instance; main thread only. A late fallback answer is
    stored only into an instance still listed here. }
  GLiveLensCaches: TList<TDragLintCodeLensCache> = nil;

function CodeLensCache: TDragLintCodeLensCache;
begin
  if GCodeLensCache = nil then GCodeLensCache:= TDragLintCodeLensCache.Create;
  Result:= GCodeLensCache;
end;

{ ---- helper: spawn and capture stdout+stderr ---- }

{ 2026-11-01 (PLUG-INFWAIT): delegates to ProcRun. The copy that lived here read
  the pipe with an unbounded ReadFile BEFORE its 15 s wait, so a child that hung
  without closing its output blocked the caller for good. True when the child
  started (its output, however partial, is in AOutput). }
function RunCapture(const ACmdLine: string; out AOutput: string): Boolean;
begin
  Result:= RunCaptureStdout(ACmdLine, AOutput, CODELENS_SPAWN_STALL_MS) <> -1;
end; // function

{ ---- parse "drag-lint surface" output to extract method names + lines ----

  Typical surface line:
    function  MyUnit.TMyClass.MyMethod  path/to/file.pas:42
  We only want impl-side methods (procedure/function) and their line. }

type
  TMethodEntry = record
    Name: string ; { short leaf name, e.g. "MyMethod" }
    Line: Integer; { 1-based declaration line }
  end;

function ParseSurfaceForMethods(const AOutput: string): TArray<TMethodEntry>;
var
  Lines  : TStringList        ;
  List   : TList<TMethodEntry>;
  i      : Integer            ;
  L      : string             ;
  Parts  : TArray<string>     ;
  KindStr: string             ;
  QName  : string             ;
  LocPart: string             ;
  ColPos : Integer            ;
  Entry  : TMethodEntry       ;
  LK     : string             ;
begin
  List:= TList<TMethodEntry>.Create;
  try
    Lines:= TStringList.Create;
    try
      Lines.Text:= AOutput;
      for i:= 0 to Lines.Count - 1 do
      begin
        L:= Trim(Lines[i]);
        if L = '' then Continue;
        if (L[1] = '-') or (L[1] = '[') then Continue;

        Parts:= L.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
        if Length(Parts) < 2 then Continue;

        KindStr:= Parts[0];
        LK:= LowerCase(KindStr);
        if (LK <> 'procedure') and (LK <> 'function') and (LK <> 'proc') and (LK <> 'func') then Continue;

        QName:= Parts[1];
        Entry.Name:= QName;
        ColPos:= LastDelimiter('.', QName);
        if ColPos > 0 then Entry.Name:= Copy(QName, ColPos + 1, MaxInt);

        Entry.Line:= 0;
        if Length(Parts) >= 3 then
        begin
          LocPart:= Parts[2];
          ColPos:= LastDelimiter(':', LocPart);
          if ColPos > 1 then Entry.Line:= StrToIntDef( Copy(LocPart, ColPos + 1, MaxInt), 0);
        end;

        if Entry.Name <> '' then List.Add(Entry);
      end; // for
    finally
      Lines.Free;
    end; // try
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

var
  GCallerCountsHook: TCallerCountsHook = nil;

procedure SetCallerCountsHook(const AHook: TCallerCountsHook);
begin
  GCallerCountsHook:= AHook;
end;

{ ---- parse caller count from "drag-lint query find-callers" output ---- }

function ParseCallerCount(const AOutput: string): Integer;
var
  Lines: TStringList;
  i    : Integer    ;
  L    : string     ;
  P    : Integer    ;
begin
  { Last line often has "N result(s)" or similar.
    We count non-blank, non-header lines that look like caller entries. }
  Result:= 0;
  Lines:= TStringList.Create;
  try
    Lines.Text:= AOutput;
    for i:= 0 to Lines.Count - 1 do
    begin
      L:= Trim(Lines[i]);
      if L = '' then Continue;
      { Skip leading header lines that contain "---" or start with known
        prefixes. Any other non-blank line is a caller entry. }
      if (L = '---') or (Pos('---', L) = 1) then Continue;
      if (L[1] = '[') then Continue;
      { Lines ending with "result(s)" are summary -- extract number }
      P:= Pos('result(s)', L);
      if P > 0 then
      begin
        { e.g. "3 result(s)" }
        Result:= StrToIntDef(Trim(Copy(L, 1, P - 1)), Result);
        Break;
      end;
      Inc(Result);
    end; // for
  finally
    Lines.Free;
  end; // try
end; // function

{ ---- TDragLintCodeLensCache ---- }

constructor TDragLintCodeLensCache.Create(AMaxFiles: Integer);
begin
  inherited Create;
  FByFile:= TDictionary<string, TDictionary<Integer, string>>.Create;
  FOrder := TList<string>.Create;
  { Clamped rather than asserted: a zero or negative cap would make every store
    immediately evict what it just stored, which reads as "the cache is broken"
    rather than "the cap was misconfigured". }
  if AMaxFiles < 1 then FMaxFiles:= 1 else FMaxFiles:= AMaxFiles;
  FLock    := TCriticalSection.Create;
  FInFlight:= TDictionary<string, Boolean>.Create;
  if GLiveLensCaches <> nil then GLiveLensCaches.Add(Self);
end;

destructor TDragLintCodeLensCache.Destroy;
var
  Inner: TDictionary<Integer, string>;
begin
  { A fallback pass still running stores nothing once this instance is gone:
    its main-thread completion checks GLiveLensCaches first. }
  if GLiveLensCaches <> nil then GLiveLensCaches.Remove(Self);
  FLock.Enter;
  try
    for Inner in FByFile.Values do Inner.Free;
    FByFile.Free;
    FOrder.Free;
    FInFlight.Free;
  finally
    FLock.Leave;
  end;
  FLock.Free;
  inherited;
end;

{ Move AKey to the front of the MRU order. FLock must already be held. }
procedure TDragLintCodeLensCache.TouchLocked(const AKey: string);
var
  Idx: Integer;
begin
  Idx:= FOrder.IndexOf(AKey);
  if Idx = 0 then Exit;              { already newest -- nothing to do }
  if Idx > 0 then FOrder.Delete(Idx);
  FOrder.Insert(0, AKey);
end;

{ Drop least-recently-used entries until the cap is met, freeing each inner map
  as it goes -- the cache owns them. FLock must already be held. }
procedure TDragLintCodeLensCache.EvictLocked;
var
  Victim: string                      ;
  Inner : TDictionary<Integer, string>;
begin
  while FOrder.Count > FMaxFiles do
  begin
    Victim:= FOrder[FOrder.Count - 1];
    FOrder.Delete(FOrder.Count - 1);
    if FByFile.TryGetValue(Victim, Inner) then
    begin
      Inner.Free;
      FByFile.Remove(Victim);
    end;
  end;
end;

function TDragLintCodeLensCache.GetForLine(const AFilePath: string; ALine: Integer): string;
var
  Key  : string                      ;
  Inner: TDictionary<Integer, string>;
begin
  Result:= '';
  Key:= LowerCase(AFilePath);
  FLock.Enter;
  try
    if FByFile.TryGetValue(Key, Inner) then
    begin
      Inner.TryGetValue(ALine, Result);
      { Touch on a FILE hit, not on a label hit: a painted line with no lens
        label is still evidence the file is in active use. }
      TouchLocked(Key);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TDragLintCodeLensCache.StoreForFile(const AFilePath: string;
  AInner: TDictionary<Integer, string>);
var
  Key : string                      ;
  Prev: TDictionary<Integer, string>;
begin
  if AInner = nil then Exit;
  Key:= LowerCase(AFilePath);
  FLock.Enter;
  try
    { Replacing an existing entry must free the old map, or the overwrite leaks
      exactly what the cap was added to bound. }
    if FByFile.TryGetValue(Key, Prev) and (Prev <> AInner) then Prev.Free;
    FByFile.AddOrSetValue(Key, AInner);
    TouchLocked(Key);
    EvictLocked;
  finally
    FLock.Leave;
  end;
end;

function TDragLintCodeLensCache.FileCount: Integer;
begin
  FLock.Enter;
  try
    Result:= FByFile.Count;
  finally
    FLock.Leave;
  end;
end;

procedure TDragLintCodeLensCache.InvalidateFile(const AFilePath: string);
var
  Key  : string                      ;
  Inner: TDictionary<Integer, string>;
begin
  Key:= LowerCase(AFilePath);
  FLock.Enter;
  try
    if FByFile.TryGetValue(Key, Inner) then
    begin
      Inner.Free;
      FByFile.Remove(Key);
    end;
    { Unconditional: FOrder must never outlive its entry, or a later evict would
      pick a victim that is no longer in FByFile and silently under-evict. }
    var OIdx: Integer:= FOrder.IndexOf(Key);
    if OIdx >= 0 then FOrder.Delete(OIdx);
  finally
    FLock.Leave;
  end;
end;

{ The per-method spawn pass of the fallback. Runs on a WORKER thread and
  touches nothing shared. Returns the line->label map (the caller owns it), or
  nil when "surface" could not even start (nothing is stored then, so the next
  activation tries again -- as before). }
function SpawnCallerCounts(const AFilePath, AExePath, ADbPath: string): TDictionary<Integer, string>;
var
  UnitName : string              ;
  SurfCmd  : string              ;
  SurfOut  : string              ;
  Methods  : TArray<TMethodEntry>;
  M        : TMethodEntry        ;
  CallerCmd: string              ;
  CallerOut: string              ;
  Count    : Integer             ;
begin
  Result:= nil;
  UnitName:= TPath.GetFileNameWithoutExtension(AFilePath);
  SurfCmd:= Format('"%s" surface --qname "%s" --db "%s"', [AExePath, UnitName, ADbPath]);
  if not RunCapture(SurfCmd, SurfOut) then Exit;
  Methods:= ParseSurfaceForMethods(SurfOut);
  { An empty map is stored too, so a file with no methods is not re-shelled. }
  Result:= TDictionary<Integer, string>.Create;
  try
    for M in Methods do
    begin
      CallerCmd:= Format('"%s" query find-callers --name "%s" --db "%s"', [AExePath, M.Name, ADbPath]);
      CallerOut:= '';
      RunCapture(CallerCmd, CallerOut);
      Count:= ParseCallerCount(CallerOut);
      { Store on 0-based line (surface returns 1-based) }
      if M.Line > 0 then
        Result.AddOrSetValue(M.Line - 1, if Count = 1 then '[1 caller]' else Format('[%d callers]', [Count]));
    end;
  except
    on Exception do
    begin
      FreeAndNil(Result);
      raise;
    end;
  end;
end; // function

procedure TDragLintCodeLensCache.PopulateOnce( const AFilePath, AExePath, ADbPath: string; const AOnStored: TProc);
var
  Key   : string                ;
  HaveIt: Boolean               ;
  Inst  : TDragLintCodeLensCache;
begin
  if (AExePath = '') or (ADbPath = '') or (AFilePath = '') then Exit;

  Key:= LowerCase(AFilePath);

  { Skip if already populated. Activating a view is a USE, so touch it too --
    otherwise a file the user keeps returning to but never repaints could age
    out from under them. }
  FLock.Enter;
  try
    HaveIt:= FByFile.ContainsKey(Key);
    if HaveIt then TouchLocked(Key);
  finally
    FLock.Leave;
  end;
  if HaveIt then Exit;

  { THE FAST PATH. One round trip to the warm LSP for the whole file, instead
    of one process start per method. Falls through to the loop below whenever
    the hook is absent or says no -- see SetCallerCountsHook for why the slow
    path is kept rather than removed. }
  if Assigned(GCallerCountsHook) then
  begin
    { 2026-10-29: ASYNC. The answer is stored when it arrives (main thread). A
      failed or timed-out answer stores an EMPTY entry, so a file whose counts
      the engine could not produce in time is not asked again on every
      activation -- the 13-minute callerCounts of the report would otherwise
      be re-sent each time the user returned to that tab. }
    if GCallerCountsHook(AFilePath,
      procedure(AOk: Boolean; const HLines, HCounts, HImpls: TArray<Integer>)
      var
        Inn: TDictionary<Integer, string>;
      begin
        Inn:= TDictionary<Integer, string>.Create;
        if AOk and (Length(HLines) = Length(HCounts)) then
          for var K: Integer:= 0 to High(HLines) do
          begin
            { The server already reports 0-BASED lines, which is what this
              cache stores -- the conversion lives on the server so exactly one
              place knows about the offset. }
            if HLines[K] < 0 then Continue;
            var Lbl:= '';
            if HCounts[K] = 1 then Lbl:= '[1 caller]'
            else if HCounts[K] >= 0 then Lbl:= Format('[%d callers]', [HCounts[K]]);
            var NImpl:= if K <= High(HImpls) then HImpls[K] else 0;
            if NImpl > 0 then
              Lbl:= Lbl + (if Lbl = '' then '' else ' ') + (if NImpl = 1 then '[1 implementor]' else Format('[%d implementors]', [NImpl]));
            if Lbl <> '' then Inn.AddOrSetValue(HLines[K], Lbl);
          end;
        StoreForFile(Key, Inn);
      end) then Exit;
  end;

  { THE FALLBACK, off the main thread (2026-11-01, IDE-HANG). It used to run
    here synchronously: one process per method, each awaited, on view
    activation -- 136 routines at ~165 ms is 20+ s of frozen IDE, and a child
    that hung froze it for good. One pass per file at a time. }
  FLock.Enter;
  try
    if FInFlight.ContainsKey(Key) then Exit;
    FInFlight.Add(Key, True);
  finally
    FLock.Leave;
  end;
  Inst:= Self;
  TThread.CreateAnonymousThread(
    procedure
    var
      Res: TDictionary<Integer, string>;
    begin
      Res:= nil;
      try
        Res:= SpawnCallerCounts(AFilePath, AExePath, ADbPath);
      except
        { A raise mid-pass stores nothing (the next activation retries); the
          completion below must still run, or the in-flight mark stays set. }
        on E: Exception do DLT('codelens', 'fallback pass raised: ' + E.Message);
      end;
      TThread.Queue(nil,
        procedure
        begin
          if (GLiveLensCaches = nil) or not GLiveLensCaches.Contains(Inst) then
          begin
            Res.Free;
            Exit;
          end;
          Inst.FinishFallback(Key, Res);
          if (Res <> nil) and Assigned(AOnStored) then AOnStored();
        end);
    end).Start;
end; // procedure

procedure TDragLintCodeLensCache.FinishFallback(const AKey: string; AInner: TDictionary<Integer, string>);
begin
  FLock.Enter;
  try
    FInFlight.Remove(AKey);
  finally
    FLock.Leave;
  end;
  if AInner <> nil then StoreForFile(AKey, AInner);
end;

procedure TDragLintCodeLensCache.Clear;
var
  Inner: TDictionary<Integer, string>;
begin
  FLock.Enter;
  try
    for Inner in FByFile.Values do Inner.Free;
    FByFile.Clear;
    FOrder.Clear;
  finally
    FLock.Leave;
  end;
end;

initialization
GLiveLensCaches:= TList<TDragLintCodeLensCache>.Create;

finalization
FreeAndNil(GCodeLensCache);
FreeAndNil(GLiveLensCaches);

end.
