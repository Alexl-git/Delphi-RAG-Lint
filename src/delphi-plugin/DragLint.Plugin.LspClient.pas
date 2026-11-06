unit DragLint.Plugin.LspClient;

interface

uses
  System.SysUtils
  , System.Classes
  , System.JSON
  , System.IOUtils
  , System.Generics.Collections
  , System.SyncObjs
  , Winapi.Windows
  , DRagLint.Core.JobObject
  , DragLint.Plugin.LspWriteQueue
  ;

/// <param name="AMsg"><!-- drag-lint:auto type -->const string</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Diagnose.DiagConnections (DragLint.Plugin.Diagnose.pas), DragLint.Plugin.Diagnose.DiagIndexes (DragLint.Plugin.Diagnose.pas), DragLint.Plugin.Diagnose.EngineInfoJson (DragLint.Plugin.Diagnose.pas), DragLint.Plugin.Diagnose.IndexVerdicts (DragLint.Plugin.Diagnose.pas), DragLint.Plugin.Diagnose.RefreshEngineInfo (DragLint.Plugin.Diagnose.pas) (+25 more)</para>
/// <para>Calls: AnsiString, DragLint.Plugin.LspClient.GetPluginLogPath, FileExists, Format, FormatDateTime</para>
/// <para>Catches: Exception (empty)</para>
/// <seealso cref="DragLint.Plugin.LspClient.GetPluginLogPath"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure DebugLog(const AMsg: string); // appends to GetPluginLogPath
/// <returns><!-- drag-lint:auto -->string -- Observed: PluginLogPath(PLUGIN_LOG_NAME).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.About.FormatErrorBlock (DragLint.Plugin.About.pas), DragLint.Plugin.About.FormatLiveBlock (DragLint.Plugin.About.pas), DragLint.Plugin.Diagnose.BuildDiagnoseReport (DragLint.Plugin.Diagnose.pas), DragLint.Plugin.Diagnose.TailOfPluginLog (DragLint.Plugin.Diagnose.pas), DragLint.Plugin.Editor.EnsureLspClient (DragLint.Plugin.Editor.pas) (+2 more)</para>
/// <para>Calls: DragLint.Plugin.LogPaths.PluginLogPath</para>
/// <seealso cref="DragLint.Plugin.LogPaths.PluginLogPath"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function GetPluginLogPath: string; // single source of truth (v0.40.1)

type
  /// <param name="AMethod"><!-- drag-lint:auto type -->const string</param>
  /// <param name="AParams"><!-- drag-lint:auto type -->TJSONValue</param>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.LspClient.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TLspNotificationHandler = reference to procedure(const AMethod: string; AParams: TJSONValue);

  /// <summary>How an asynchronous request ended.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DragLint.Plugin.Editor.DoCompletion (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeGoToDefinition (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeSignatureHelp (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.RequestHoverBundleAsync (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.RequestHoverTextAsync (DragLint.Plugin.Editor.pas) (+5 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDLLspReplyStatus = (
    lrsResult , { the engine answered with a 'result' member     }
    lrsError  , { the engine answered with an 'error' member     }
    lrsTimeout  { NOT FINAL: the request's budget passed and the  }
                { engine is still working; the answer follows    }
  );

  /// <summary>Receives the answer to RequestAsync, on the MAIN thread.</summary>
  /// <param name="AId">The id RequestAsync returned.</param>
  /// <param name="AStatus">How the request ended.</param>
  /// <param name="AReply">The FULL JSON-RPC envelope (jsonrpc, id, result |
  /// error) for lrsResult / lrsError; nil otherwise. Owned by the client and
  /// freed when the callback returns -- clone anything kept.</param>
  /// <remarks>
  /// Late results (owner ruling 2026-11-01): when the budget passes the
  /// callback runs ONCE with lrsTimeout -- a notice that the answer is late, so
  /// the caller can show it as pending -- and AGAIN with lrsResult / lrsError
  /// when the answer arrives. A caller that no longer wants it (superseded by a
  /// newer request) calls CancelRequest; nothing else drops a late answer.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.LspClient.pas), DragLint.Plugin.LspClient.DeliverReply (DragLint.Plugin.LspClient.pas), DragLint.Plugin.LspClient.TDragLintLspClient.RequestAsync (DragLint.Plugin.LspClient.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TLspReplyProc = reference to procedure(AId: Integer; AStatus: TDLLspReplyStatus; AReply: TJSONValue);

  /// <summary>Lifecycle state of the LSP child process, for status display.</summary>
  /// <remarks>
  /// Added 2026-08-17. The plugin previously had NO readable connection
  /// state at all, so the only way it could report trouble was a modal dialog at
  /// the moment of failure -- and that dialog said "handshake failed" for a
  /// handshake that had actually succeeded 56 s after the client stopped
  /// waiting. A readable state lets the UI show what is true continuously
  /// instead of asserting something false once.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.LspClient.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDragLintLspState = (
    dlsDown,      { never started, or stopped                     }
    dlsStarting,  { process spawned, initialize not yet answered  }
    dlsConnected, { initialize succeeded; server is usable        }
    dlsFailed     { spawn or initialize failed; see LastError     }
  );

  /// <summary>One request sent and not yet answered.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.LspClient.pas), DragLint.Plugin.LspClient.OutstandingNow (DragLint.Plugin.LspClient.pas), DragLint.Plugin.LspClient.TDragLintLspClient.Create (DragLint.Plugin.LspClient.pas), DragLint.Plugin.LspClient.TDragLintLspClient.IsBusy (DragLint.Plugin.LspClient.pas), DragLint.Plugin.LspClient.TDragLintLspClient.IsStuck (DragLint.Plugin.LspClient.pas)</para>
  /// <para>Used in units: DragLint.Plugin.LspClient</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDLOutstanding = record
    /// <summary>GetTickCount64 when it was sent.</summary>
    Sent      : UInt64 ;
    /// <summary>True for a background method (caller counts, code lens): IsBusy ignores it.</summary>
    Background: Boolean;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.Editor.pas) ?, DragLint.Plugin.Diagnose.DiagConnections (DragLint.Plugin.Diagnose.pas) ?, DragLint.Plugin.Editor.CurrentLspClient (DragLint.Plugin.Editor.pas) ?, DragLint.Plugin.Editor.EnsureLspClient (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.SyncLiveBufferToLsp (DragLint.Plugin.Editor.pas) ? (+14 more)</para>
  /// <para>Used in units: DragLint.Plugin.Diagnose, DragLint.Plugin.Editor, DragLint.Plugin.HoverTracker, DragLint.Plugin.LspClient</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDragLintLspClient = class
    strict private
      FProcessHandle  : THandle                         ;
      FProcessId      : DWORD                           ;
      FStdInWrite     : THandle                         ;
      FStdOutRead     : THandle                         ;
      FReaderThread   : TThread                         ;
      FPendingRequests: TDictionary<Integer, TEvent>    ;
      FResponses      : TDictionary<Integer, TJSONValue>;
      FLock           : TCriticalSection                ;
      FNextId         : Integer                         ;
      FOnNotification : TLspNotificationHandler         ;
      FState          : TDragLintLspState               ;
      FLastError      : string                          ;
      FStartedAt      : TDateTime                       ;
      { Set when a write to the server's stdin fails with a pipe error. The
        process handle can still report ALIVE while the pipe is gone, so this
        is a SECOND liveness fact, not a duplicate of FProcessHandle. }
      FPipeBroken     : Boolean                         ;
      { 2026-10-29 (IDE must never wait on the engine): the ONLY path to the
        engine's stdin. Callers enqueue; a private thread writes. }
      FWriter         : TDLLspWriteQueue                ;
      { Asynchronous requests still waiting for an answer, by id. }
      FAsync          : TDictionary<Integer, TObject>   ;
      { Cancel flags of async requests, kept past dispatch so a request
        cancelled while its answer is already queued is still dropped. }
      FFlags          : TDictionary<Integer, TObject>   ;
      { Every request sent and not yet answered (sync and async), with the tick
        it was sent at. A TIMED-OUT request stays here: the serial engine is
        still working on it, which is exactly what "busy" has to see. }
      FOutstanding    : TDictionary<Integer, TDLOutstanding>;
      FLastRxTick     : UInt64                          ;
      { Engine CPU (100 ns) at the last progress mark, and the tick of that mark:
        an engine burning CPU is working, however long it stays silent. }
      FLastCpu100ns   : Int64                           ;
      FLastCpuTick    : UInt64                          ;
      { 1.40 heartbeat: once the engine answered one, its status counter (seq) is THE progress signal and
        CPU no longer counts. FLastBeatTick = when seq last changed; FNextBeatTick = when the ticker asks
        again. Guarded by FLock, like the CPU mark. }
      FBeatSeen       : Boolean                         ;
      FBeatSeq        : Int64                           ;
      FLastBeatTick   : UInt64                          ;
      FNextBeatTick   : UInt64                          ;
      FBeatText       : string                          ;
      FTicker         : TThread                         ;
      FTickerStop     : TEvent                          ;
      FBusyAfterMs    : Cardinal                        ;
      FStuckAfterMs   : Cardinal                        ;
      /// <summary><!-- drag-lint:auto sum -->ERROR_NO_DATA (232) and ERROR_BROKEN_PIPE
      /// (109) both mean the server is no longer reading us. Anything else is a transient
      /// write problem and is left alone -- declaring the client dead on, say, a partial
      /// write would throw away a working server. Latched, so the log records the
      /// transition once instead of once per message: the 2026-08-21 log is 40 identical
      /// failure lines and the repetition is what made it look like noise rather than a
      /// state change.</summary>
      /// <param name="ALastError"><!-- drag-lint:auto type -->DWORD</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.LspClient.TDragLintLspClient.StartWorkers (DragLint.Plugin.LspClient.pas)</para>
      /// <para>Calls: DragLint.Plugin.LspClient.DebugLog, Format</para>
      /// <para>Reads: FPipeBroken   Writes: FPipeBroken, FLastError, FState</para>
      /// <seealso cref="DragLint.Plugin.LspClient.DebugLog"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure NotePipeError(ALastError: DWORD);
      /// <param name="AJson"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ACoalesceKey"><!-- drag-lint:auto type -->const string = ''</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.LspClient.TDragLintLspClient.Notify (DragLint.Plugin.LspClient.pas)</para>
      /// <para>Calls: Copy, DragLint.Plugin.LspClient.DebugLog, DragLint.Plugin.LspWriteQueue.TDLLspWriteQueue.Enqueue, Format</para>
      /// <para>Reads: FWriter</para>
      /// <seealso cref="DragLint.Plugin.LspClient.DebugLog"/>
      /// <seealso cref="DragLint.Plugin.LspWriteQueue.TDLLspWriteQueue.Enqueue"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure WriteFramedMessage(const AJson: string; const ACoalesceKey: string = '');
      /// <param name="AId"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="AMethod"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AParams"><!-- drag-lint:auto type -->TJSONValue</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: (FWriter &lt;&gt; nil) and
      /// FWriter.Enqueue(TEncoding.UTF8.GetBytes(Format('Content-Length: %d'#13#10#13#10,
      /// [Length(Body)])) + Body).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.LspClient.TDragLintLspClient.Request (DragLint.Plugin.LspClient.pas), DragLint.Plugin.LspClient.TDragLintLspClient.RequestAsync (DragLint.Plugin.LspClient.pas)</para>
      /// <para>Calls: BoolToStr, DragLint.Plugin.LspClient.DebugLog, DragLint.Plugin.LspWriteQueue.TDLLspWriteQueue.Enqueue, Format</para>
      /// <para>Reads: FWriter</para>
      /// <seealso cref="DragLint.Plugin.LspClient.DebugLog"/>
      /// <seealso cref="DragLint.Plugin.LspWriteQueue.TDLLspWriteQueue.Enqueue"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function SendRequestFrame(AId: Integer; const AMethod: string; AParams: TJSONValue): Boolean;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes (DragLint.Plugin.LspClient.pas)</para>
      /// <para>Calls: DragLint.Plugin.LspClient.DebugLog, DragLint.Plugin.LspClient.TDLLspTickerThread.Create, DragLint.Plugin.LspClient.TDragLintLspClient.NotePipeError, DragLint.Plugin.LspWriteQueue.TDLLspWriteQueue.Create, Format</para>
      /// <para>Reads: FStdInWrite, FTickerStop   Writes: FLastRxTick, FWriter, FTickerStop, FTicker</para>
      /// <seealso cref="DragLint.Plugin.LspClient.DebugLog"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDLLspTickerThread.Create"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.NotePipeError"/>
      /// <seealso cref="DragLint.Plugin.LspWriteQueue.TDLLspWriteQueue.Create"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure StartWorkers;
      /// <param name="ABudgetMs"><!-- drag-lint:auto type -->Cardinal</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.LspClient.TDragLintLspClient.Stop (DragLint.Plugin.LspClient.pas)</para>
      /// <para>Calls: Cardinal, DragLint.Plugin.LspClient.DebugLog, FreeAndNil, WaitForSingleObject</para>
      /// <para>Reads: FTicker, FTickerStop, FWriter   Writes: FTicker, FTickerStop</para>
      /// <seealso cref="DragLint.Plugin.LspClient.DebugLog"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure StopWorkers(ABudgetMs: Cardinal);
      /// <summary><!-- drag-lint:auto sum -->After Stop NO callback runs -- not for
      /// requests still waiting, and not for answers already queued to the main thread
      /// (their flags are still in FFlags, which is pruned only once a delivery has run).
      /// A callback may capture the client or state the caller is about to free with it,
      /// so "told lrsFailed later" would be a use-after-free; callers watching for an
      /// answer notice the client was replaced instead.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.LspClient.TDragLintLspClient.Stop (DragLint.Plugin.LspClient.pas)</para>
      /// <para>Calls: DragLint.Plugin.LspClient.IDLReplyFlag.SetCancelled, TDLFlagHolder</para>
      /// <para>Reads: FLock, FFlags, FAsync</para>
      /// <seealso cref="DragLint.Plugin.LspClient.IDLReplyFlag.SetCancelled"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Create"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure CancelAllAsync;
    private
      { Accessible to TLspReaderThread in same unit }
      /// <summary><!-- drag-lint:auto sum -->Accessible to TLspReaderThread in same unit</summary>
      /// <param name="AMsg"><!-- drag-lint:auto type -->TJSONValue</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.LspClient.TLspReaderThread.Execute (DragLint.Plugin.LspClient.pas)</para>
      /// <para>Calls: DragLint.Plugin.LspClient.DeliverReply, FOnNotification, TDLAsyncEntry</para>
      /// <para>Reads: FLock, FOutstanding, FPendingRequests, FResponses, FAsync, FOnNotification   Writes: FLastRxTick</para>
      /// <seealso cref="DragLint.Plugin.LspClient.DeliverReply"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DispatchMessage(AMsg: TJSONValue);
      { Accessible to the ticker thread in same unit }
      /// <summary><!-- drag-lint:auto sum -->Accessible to the ticker thread in same unit</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.LspClient.TDLLspTickerThread.Execute (DragLint.Plugin.LspClient.pas)</para>
      /// <para>Calls: DragLint.Plugin.LspClient.DebugLog, DragLint.Plugin.LspClient.DeliverReply, DragLint.Plugin.LspClient.TDragLintLspClient.SampleEngineBeat, DragLint.Plugin.LspClient.TDragLintLspClient.SampleEngineCpu, Format, TDLAsyncEntry</para>
      /// <para>Reads: FLock, FAsync</para>
      /// <seealso cref="DragLint.Plugin.LspClient.DebugLog"/>
      /// <seealso cref="DragLint.Plugin.LspClient.DeliverReply"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.SampleEngineBeat"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.SampleEngineCpu"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ExpireTimedOut;
      /// <summary><!-- drag-lint:auto sum -->Called by the ticker thread. An async
      /// request past its budget gets ONE lrsTimeout notice and STAYS in FAsync and
      /// FOutstanding (owner ruling 2026-11-01, fix/late-results): the engine is still
      /// working on it, its answer is delivered when it arrives, and the engine is not
      /// told to stop. A hung engine is the watchdog's business (IsStuck), not a
      /// per-request clock. Under FLock, from the ticker: moves the CPU progress mark
      /// when the server process has burnt CPU_PROGRESS_100NS since the last one. No
      /// process handle (pipes attached directly) = no sample.</summary>
      /// <param name="ANow"><!-- drag-lint:auto type -->UInt64</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.LspClient.TDragLintLspClient.ExpireTimedOut (DragLint.Plugin.LspClient.pas)</para>
      /// <para>Calls: GetProcessTimes, PInt64</para>
      /// <para>Reads: FProcessHandle, FLastCpu100ns   Writes: FLastCpu100ns, FLastCpuTick</para>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Create"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SampleEngineCpu(ANow: UInt64);
      /// <summary><!-- drag-lint:auto sum -->From the ticker, OUTSIDE FLock (the ask is
      /// pipe I/O, bounded by BEAT_CONNECT_MS): every BEAT_POLL_MS ask the engine's
      /// heartbeat pipe for its status. No process id (pipes attached directly) = no ask.</summary>
      /// <param name="ANow"><!-- drag-lint:auto type -->UInt64</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.LspClient.TDragLintLspClient.ExpireTimedOut (DragLint.Plugin.LspClient.pas)</para>
      /// <para>Calls: DRagLint.Core.ControlChannel.BeatDisplayText, DRagLint.Core.ControlChannel.RequestEngineBeat, DragLint.Plugin.LspClient.TDragLintLspClient.NoteEngineBeat</para>
      /// <para>Reads: FLock, FProcessId, FNextBeatTick   Writes: FNextBeatTick</para>
      /// <seealso cref="DRagLint.Core.ControlChannel.BeatDisplayText"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.RequestEngineBeat"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.NoteEngineBeat"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SampleEngineBeat(ANow: UInt64);
    public
      /// <summary><!-- drag-lint:auto sum -->TDragLintLspClient</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.Editor.EnsureLspClient (DragLint.Plugin.Editor.pas)</para>
      /// <para>constructor</para>
      /// <para>Writes: FLock, FPendingRequests, FResponses, FAsync, FFlags, FOutstanding, FNextId, FProcessHandle (+9 more)</para>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Destroy"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.DispatchMessage"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: DragLint.Plugin.LspClient.TDragLintLspClient.Stop</para>
      /// <para>Reads: FPendingRequests, FResponses, FAsync, FFlags, FOutstanding, FLock</para>
      /// <para>Directives: override</para>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Stop"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      destructor Destroy; override;
      /// <param name="AExePath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: Start(AExePath, nil).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: DragLint.Plugin.LspClient.TDragLintLspClient.Start/2</para>
      /// <para>Overload 1 of 2</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Start"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function Start(const AExePath: string): Boolean; overload;
      { v0.40.3: spawn with explicit --db paths. Each path becomes a
      separate "--db <quoted>" cmd-line flag the LSP server iterates. }
      /// <summary><!-- drag-lint:auto sum -->v0.40.3: spawn with explicit --db paths.
      /// Each path becomes a separate "--db &lt;quoted&gt;" cmd-line flag the LSP server
      /// iterates.</summary>
      /// <param name="AExePath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ADbPaths"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; True.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.About.StartBackgroundSelfInfoFetch (DragLint.Plugin.About.pas) ?, DragLint.Plugin.Editor.EnsureLspClient (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.RunCompileDiagnoseAsync (DragLint.Plugin.Editor.pas) ?, DragLint.Plugin.Editor.RunFullCompileSweepAsync (DragLint.Plugin.Editor.pas) ?, DragLint.Plugin.LspClient.TDragLintLspClient.Start/1 (DragLint.Plugin.LspClient.pas) (+4 more)</para>
      /// <para>Calls: BoolToStr, CloseHandle, CreatePipe, CreateProcessW, DRagLint.Core.JobObject.AssignToDragLintJob, DragLint.Plugin.LspClient.DebugLog, DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes, FileExists, Format, IntToStr, Move, PChar, SetHandleInformation, ZeroMemory</para>
      /// <para>Overload 2 of 2</para>
      /// <para>Reads: FLock, FProcessHandle   Writes: FState, FLastError, FStartedAt, FProcessHandle, FProcessId, FBeatSeen, FBeatSeq, FBeatText (+1 more)</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="DRagLint.Core.JobObject.AssignToDragLintJob"/>
      /// <seealso cref="DragLint.Plugin.LspClient.DebugLog"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function Start(const AExePath: string; const ADbPaths: TArray<string>): Boolean; overload;

      /// <summary>Runs the client over two pipe handles instead of a spawned
      /// process -- the seam the non-blocking tests drive.</summary>
      /// <param name="AStdInWrite">Write end the client sends frames to; owned
      /// (closed by Stop).</param>
      /// <param name="AStdOutRead">Read end the client reads frames from; owned
      /// (closed by Stop).</param>
      /// <remarks>
      /// Start uses the same path after CreateProcess. No process
      /// handle is set, so IsAlive stays False.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.LspClient.TDragLintLspClient.Start/2 (DragLint.Plugin.LspClient.pas)</para>
      /// <para>Calls: DragLint.Plugin.LspClient.TDragLintLspClient.StartWorkers, DragLint.Plugin.LspClient.TLspReaderThread.Create</para>
      /// <para>Reads: FStdOutRead   Writes: FStdInWrite, FStdOutRead, FReaderThread</para>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.StartWorkers"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TLspReaderThread.Create"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure AttachPipes(AStdInWrite, AStdOutRead: THandle);

      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.Editor.DLRunMaintenanceJob (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.EnsureLspClient (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeAutoDocumentProject (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeFormatProjectYadf (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeReindexProject (DragLint.Plugin.Editor.pas) (+2 more)</para>
      /// <para>Calls: BoolToStr, CancelSynchronousIo, Cardinal, CloseHandle, DebugLog, DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync, DragLint.Plugin.LspClient.TDragLintLspClient.Stop.Left, DragLint.Plugin.LspClient.TDragLintLspClient.Stop.Step, DragLint.Plugin.LspClient.TDragLintLspClient.StopWorkers, Format, TerminateProcess, WaitForSingleObject</para>
      /// <para>Reads: FProcessId, FPipeBroken, FProcessHandle, FLock, FOutstanding, FStdInWrite, FStdOutRead, FReaderThread   Writes: FState, FStdInWrite, FStdOutRead, FReaderThread, FProcessHandle, FProcessId</para>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Stop.Left"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Stop.Step"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.StopWorkers"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure Stop;

      /// <summary>Synchronous initialize handshake (45 s budget).</summary>
      /// <returns>True when the engine answered; State is then dlsConnected.</returns>
      /// <remarks>
      /// BLOCKS the calling thread. Kept for console tests; the IDE uses
      /// InitializeAsync.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: DragLint.Plugin.LspClient.DebugLog, DragLint.Plugin.LspClient.TDragLintLspClient.Request</para>
      /// <para>Returns: Resp &lt;&gt; nil</para>
      /// <para>Writes: FState, FLastError</para>
      /// <seealso cref="DragLint.Plugin.LspClient.DebugLog"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Request"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function Initialize: Boolean                                                                        ;

      /// <summary>Sends initialize without waiting; ADone(True) on the main
      /// thread once the engine answers, ADone(False) on timeout / failure.</summary>
      /// <param name="ADone">Completion callback; may be nil.</param>
      /// <remarks>
      /// State is dlsStarting until the answer, then dlsConnected or
      /// dlsFailed.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.Editor.EnsureLspClient (DragLint.Plugin.Editor.pas)</para>
      /// <para>Calls: ADone, DragLint.Plugin.LspClient.DebugLog, DragLint.Plugin.LspClient.TDragLintLspClient.RequestAsync, Format</para>
      /// <para>Writes: FState, FLastError</para>
      /// <seealso cref="DragLint.Plugin.LspClient.DebugLog"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.RequestAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure InitializeAsync(const ADone: TProc<Boolean>);

      /// <summary>Synchronous request: sends and WAITS up to ATimeoutMs.</summary>
      /// <param name="AMethod">JSON-RPC method.</param>
      /// <param name="AParams">Parameters; cloned. nil sends {}.</param>
      /// <param name="ATimeoutMs">How long to wait for the answer.</param>
      /// <returns>The full JSON-RPC envelope (caller frees), or nil on timeout.</returns>
      /// <remarks>
      /// BLOCKS the calling thread -- never call it from the IDE main
      /// thread (owner rule 2026-10-29); use RequestAsync there. The send itself
      /// never blocks.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.LspClient.TDragLintLspClient.Initialize (DragLint.Plugin.LspClient.pas)</para>
      /// <para>Calls: DragLint.Plugin.LspClient.OutstandingNow, DragLint.Plugin.LspClient.TDragLintLspClient.SendRequestFrame</para>
      /// <para>Returns: nil</para>
      /// <para>Reads: FLock, FNextId, FPendingRequests, FOutstanding, FResponses   Writes: FNextId</para>
      /// <seealso cref="DragLint.Plugin.LspClient.OutstandingNow"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.SendRequestFrame"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function Request(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Integer = 5000): TJSONValue;

      /// <summary>Sends a request and returns at once; the answer is delivered
      /// to AOnReply on the MAIN thread (TThread.ForceQueue).</summary>
      /// <param name="AMethod">JSON-RPC method.</param>
      /// <param name="AParams">Parameters; cloned, the caller keeps ownership. nil
      /// sends {}.</param>
      /// <param name="ATimeoutMs">After this, AOnReply gets an lrsTimeout NOTICE
      /// (the answer is late) and the request stays live: no $/cancelRequest is
      /// sent and the answer is still delivered when it arrives.</param>
      /// <param name="AOnReply">Callback; called once with the answer
      /// (lrsResult / lrsError), preceded by one lrsTimeout notice when the answer
      /// is late; never again after CancelRequest or Stop.</param>
      /// <returns>The request id (&gt; 0), or 0 when nothing was sent (queue full,
      /// pipe failed, not attached) -- AOnReply is then never called.</returns>
      /// <remarks>
      /// Never blocks and never waits on the engine.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.Editor.DoCompletion (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeGoToDefinition (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeSignatureHelp (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.LspCallerCounts (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.RequestHoverBundleAsync (DragLint.Plugin.Editor.pas) (+2 more)</para>
      /// <para>Calls: DragLint.Plugin.LspClient.IDLReplyFlag.GetDone, DragLint.Plugin.LspClient.OutstandingNow, DragLint.Plugin.LspClient.TDragLintLspClient.SendRequestFrame, TDLFlagHolder, UInt64</para>
      /// <para>Returns: 0; Id</para>
      /// <para>Reads: FWriter, FLock, FNextId, FFlags, FAsync, FOutstanding   Writes: FNextId</para>
      /// <seealso cref="DragLint.Plugin.LspClient.IDLReplyFlag.GetDone"/>
      /// <seealso cref="DragLint.Plugin.LspClient.OutstandingNow"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.SendRequestFrame"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function RequestAsync(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Integer; const AOnReply: TLspReplyProc): Integer;

      /// <summary>Drops an asynchronous request: its callback will not run, even
      /// when the answer is already on its way, and $/cancelRequest is sent.</summary>
      /// <param name="AId">An id from RequestAsync; 0 and unknown ids are ignored.</param>
      /// <remarks>
      /// Main thread. Never blocks.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.HoverTracker.TDragLintHoverHelper.CancelInflight (DragLint.Plugin.HoverTracker.pas)</para>
      /// <para>Calls: DragLint.Plugin.LspClient.IDLReplyFlag.SetCancelled, DragLint.Plugin.LspClient.TDragLintLspClient.Notify, TDLFlagHolder</para>
      /// <para>Reads: FLock, FFlags, FAsync</para>
      /// <seealso cref="DragLint.Plugin.LspClient.IDLReplyFlag.SetCancelled"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Notify"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure CancelRequest(AId: Integer);

      /// <summary>Queues a notification; never blocks.</summary>
      /// <param name="AMethod">JSON-RPC method.</param>
      /// <param name="AParams">Parameters; cloned. nil sends {}.</param>
      /// <param name="ACoalesceKey">When not empty, replaces a not-yet-written
      /// notification with the same key (didChange per document).</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.Editor.BroadcastDidSaveForAffectedFiles (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeDiagnostics (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeRunAstChecks (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.SyncLiveBufferToLsp (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.TriggerDiagnosticsOnSave (DragLint.Plugin.Editor.pas) (+1 more)</para>
      /// <para>Calls: DragLint.Plugin.LspClient.TDragLintLspClient.WriteFramedMessage</para>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.WriteFramedMessage"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure Notify(const AMethod: string; AParams: TJSONValue; const ACoalesceKey: string = '');

      /// <summary>True when the engine has kept a request unanswered, or its
      /// stdin unread, for longer than BusyAfterMs.</summary>
      /// <returns>True while the oldest outstanding FOREGROUND request, or the
      /// current stdin write, is older than BusyAfterMs. Background requests
      /// (draglint/callerCounts, textDocument/codeLens) never count; a request whose frame could
      /// not be sent is never outstanding.</returns>
      /// <remarks>
      /// Callers use it to stop queueing more work (hover, code lens)
      /// behind a request the serial engine is still chewing on.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.Editor.DoCompletion (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.LspCallerCounts (DragLint.Plugin.Editor.pas), DragLint.Plugin.HoverTracker.TDragLintHoverHelper.OnTick (DragLint.Plugin.HoverTracker.pas)</para>
      /// <para>Calls: DragLint.Plugin.LspWriteQueue.TDLLspWriteQueue.WriteStalledMs</para>
      /// <para>Reads: FLock, FOutstanding, FBusyAfterMs, FWriter</para>
      /// <seealso cref="DragLint.Plugin.LspWriteQueue.TDLLspWriteQueue.WriteStalledMs"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function IsBusy: Boolean;

      /// <summary>True when requests are outstanding and the engine has made NO
      /// PROGRESS for longer than StuckAfterMs -- the watchdog's restart signal for
      /// a HUNG engine. Progress = a message received, or (1.40) its heartbeat
      /// status CHANGING; for an engine without a heartbeat, CPU burnt.</summary>
      /// <returns>True when the time since max(last message, last progress mark,
      /// oldest outstanding request) exceeds StuckAfterMs, or the stdin write has
      /// been blocked that long. The progress mark is the last heartbeat seq change
      /// once a beat was seen (CPU is then ignored: an engine spinning with a frozen
      /// status IS stuck), else the last CPU progress.</returns>
      /// <remarks>
      /// fix/late-results (owner ruling 2026-11-01): a slow engine that is
      /// working must never be restarted -- that loses every late result. The
      /// ticker asks the engine's heartbeat pipe (DRagLint.Core.ControlChannel
      /// RequestEngineBeat) every few seconds and samples CPU from the process
      /// handle; a client attached to bare pipes (tests) has neither unless
      /// NoteEngineBeat is called, and falls back to silence alone.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.Editor.EnsureLspClient (DragLint.Plugin.Editor.pas), DragLint.Plugin.HoverTracker.TDragLintHoverHelper.OnTick (DragLint.Plugin.HoverTracker.pas)</para>
      /// <para>Calls: DragLint.Plugin.LspWriteQueue.TDLLspWriteQueue.WriteStalledMs</para>
      /// <para>Returns: False; GetTickCount64 - Since &gt; FStuckAfterMs; FWriter.WriteStalledMs &gt; FStuckAfterMs</para>
      /// <para>Reads: FLock, FOutstanding, FLastRxTick, FBeatSeen, FLastBeatTick, FLastCpuTick, FStuckAfterMs, FWriter</para>
      /// <seealso cref="DragLint.Plugin.LspWriteQueue.TDLLspWriteQueue.WriteStalledMs"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function IsStuck: Boolean;

      /// <summary>Records one heartbeat answer of the engine (the ticker calls it; tests call it directly).</summary>
      /// <param name="ASeq">The status counter the engine reported; a value different from the last one is progress.</param>
      /// <param name="AText">Display text of the status (BeatDisplayText) -- EngineBeatText.</param>
      /// <remarks>
      /// Thread-safe. The first call switches IsStuck from the CPU rule to the heartbeat rule for the
      /// rest of this client's life.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.LspClient.TDragLintLspClient.SampleEngineBeat (DragLint.Plugin.LspClient.pas)</para>
      /// <para>Reads: FLock, FBeatSeen, FBeatSeq   Writes: FLastBeatTick, FBeatSeen, FBeatSeq, FBeatText</para>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Create"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure NoteEngineBeat(ASeq: Int64; const AText: string);

      /// <summary>The engine's last reported status for display (e.g. <c>textDocument/hover</c>,
      /// <c>index: resolve calls 12</c>); '' before the first heartbeat.</summary>
      /// <returns>The text. Thread-safe.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Returns: FBeatText</para>
      /// <para>Reads: FLock, FBeatText</para>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Create"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function EngineBeatText: string;

      /// <summary>Requests sent and not yet answered (timed-out ones included).</summary>
      /// <returns>The count; 0 when idle.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.Editor.EnsureLspClient (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.LspCallerCounts (DragLint.Plugin.Editor.pas)</para>
      /// <para>Returns: FOutstanding.Count</para>
      /// <para>Reads: FLock, FOutstanding</para>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Create"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function OutstandingCount: Integer;

      /// <summary>True while the spawned server process is still running.</summary>
      /// <returns>False when never started, exited, or the handle is invalid.</returns>
      /// <remarks>
      /// Probes the process handle with a zero timeout -- cheap, and
      /// distinguishes "we think we are connected" from "the child actually
      /// died", which FState alone cannot.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.Diagnose.DiagConnections (DragLint.Plugin.Diagnose.pas), DragLint.Plugin.Editor.EnsureLspClient (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.UpdateLspStatusIndicator (DragLint.Plugin.Editor.pas), DragLint.Plugin.LspClient.TDragLintLspClient.StateText (DragLint.Plugin.LspClient.pas)</para>
      /// <para>Calls: WaitForSingleObject</para>
      /// <para>Returns: False; WaitForSingleObject(FProcessHandle, 0) = WAIT_TIMEOUT</para>
      /// <para>Reads: FPipeBroken, FProcessHandle</para>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Create"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function IsAlive: Boolean;

      /// <summary>Human-readable one-word status for the About / status UI.</summary>
      /// <returns><!-- drag-lint:auto -->string -- Observed: 'starting'; 'connected';
      /// 'DIED (process exited after a successful handshake)'; 'DOWN'; 'not started'.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: DragLint.Plugin.LspClient.TDragLintLspClient.IsAlive</para>
      /// <para>Reads: FState</para>
      /// <para>Effect-free (proven)</para>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.IsAlive"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.AttachPipes"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelAllAsync"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.CancelRequest"/>
      /// <seealso cref="DragLint.Plugin.LspClient.TDragLintLspClient.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function StateText: string;

      property OnNotification: TLspNotificationHandler read FOnNotification write FOnNotification;
      /// <summary>Current lifecycle state; never raises.</summary>
      property State    : TDragLintLspState read FState    ;
      /// <summary>Last spawn/initialize failure detail, or '' when healthy.</summary>
      property LastError: string            read FLastError;
      /// <summary>When the current server process was spawned (0 if never).</summary>
      property StartedAt: TDateTime         read FStartedAt;
      /// <summary>PID of the server process, or 0 when not running.</summary>
      property ProcessId: DWORD             read FProcessId;
      /// <summary>Age in ms of an unanswered request that makes IsBusy True
      /// (default 3000).</summary>
      property BusyAfterMs : Cardinal read FBusyAfterMs  write FBusyAfterMs ;
      /// <summary>Time in ms without progress (no message, no CPU), with requests
      /// outstanding, that makes IsStuck True (default 180000).</summary>
      property StuckAfterMs: Cardinal read FStuckAfterMs write FStuckAfterMs;
  end;

implementation

uses
  DragLint.Plugin.LogPaths
  , DRagLint.Core.ControlChannel { 1.40 heartbeat: RequestEngineBeat, BeatDisplayText }
  ;

{ ---- Debug log ---- }

var
  GLogLock: TCriticalSection = nil;

function GetPluginLogPath: string;
{ v0.40.1: resolve the same path DebugLog actually writes to. Previously
  EnsureLspClient / InvokeTestConnection printed GetEnvironmentVariable('TEMP')
  while DebugLog wrote to TPath.GetTempPath -- the two can disagree under
  Windows TMP/TEMP precedence, so users hunted for a log at the displayed
  path and couldn't find it.
  2026-10-13 (installer layout v2, owner ruling): ALWAYS
  %LOCALAPPDATA%\drag-lint\logs, dev box included -- no %TEMP% probe and no
  beside-the-BPL fallback. }
const
  PLUGIN_LOG_NAME = 'drag-lint-plugin.log';
begin
  Result:= PluginLogPath(PLUGIN_LOG_NAME);
end; // function

procedure DebugLog(const AMsg: string);
var
  LogPath: string     ;
  Stream : TFileStream;
  Line   : AnsiString ;
begin
  if GLogLock = nil then GLogLock:= TCriticalSection.Create;
  GLogLock.Enter;
  try
    try
      LogPath:= GetPluginLogPath;
      if LogPath = '' then Exit; { no local-app-data folder: nowhere sane to log }
      Line:= AnsiString(Format('[%s] %s'#13#10, [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now), AMsg]));
      if FileExists(LogPath) then Stream:= TFileStream.Create(LogPath, fmOpenWrite or fmShareDenyNone)
      else Stream:= TFileStream.Create(LogPath, fmCreate or fmShareDenyNone);
      try
        Stream.Seek(0, soEnd);
        Stream.WriteBuffer(Line[1], Length(Line));
      finally
        Stream.Free;
      end;
    except
      // swallow log errors silently
    end; // try
  finally
    GLogLock.Leave;
  end; // try
end; // procedure

{ Reader thread }

type
  TLspReaderThread = class(TThread)
    private
      FOwner : TDragLintLspClient                              ;
      FHandle: THandle                                         ;
      function ReadBytes(ABuf: PByte; ACount: Integer): Boolean;
    protected
      procedure Execute; override;
    public
      constructor Create(AOwner: TDragLintLspClient; AHandle: THandle);
  end;

constructor TLspReaderThread.Create(AOwner: TDragLintLspClient; AHandle: THandle);
begin
  inherited Create(False);
  FOwner         := AOwner;
  FHandle        := AHandle;
  FreeOnTerminate:= False;
end;

function TLspReaderThread.ReadBytes(ABuf: PByte; ACount: Integer): Boolean;
var
  Remaining: DWORD   ;
  read     : DWORD   ;
  Ok       : LongBool;
begin
  Remaining:= ACount;
  while Remaining > 0 do
  begin
    Ok:= ReadFile(FHandle, ABuf^, Remaining, read, nil);
    if (not Ok) or (read = 0) then Exit(False);
    Inc(ABuf     , read);
    Dec(Remaining, read);
  end;
  Result:= True;
end;

procedure TLspReaderThread.Execute;
var
  Ch           : Byte      ;
  read         : DWORD     ;
  Ok           : LongBool  ;
  HeaderBuf    : AnsiString;
  Seq          : Integer   ; { how many of the 4-char CRLF CRLF we matched }
  ContentLength: Integer   ;
  BodyBuf      : TBytes    ;
  JsonStr      : string    ;
  JsonVal      : TJSONValue;
  Pos          : Integer   ;
  S            : string    ;
begin
  DebugLog('ReaderThread: started');
  try
  while not Terminated do
  begin
    { Read header byte-by-byte until CRLFCRLF }
    HeaderBuf:= '';
    Seq      := 0;
    repeat
      Ok:= ReadFile(FHandle, Ch, 1, read, nil);
      if (not Ok) or (read = 0) then
      begin
        DebugLog(Format('ReaderThread: ReadFile failed/EOF, Ok=%s Read=%d GetLastError=%d', [BoolToStr(Ok, True), read, GetLastError]));
        Exit;
      end;
      HeaderBuf:= HeaderBuf + AnsiChar(Ch);
      { track the CRLFCRLF sequence }
      case Seq of
        0: if Ch = 13 then Seq:= 1 else Seq:= 0                             ;
        1: if Ch = 10 then Seq:= 2 else if Ch = 13 then Seq:= 1 else Seq:= 0;
        2: if Ch = 13 then Seq:= 3 else Seq:= 0                             ;
        3: if Ch = 10 then Seq:= 4 else if Ch = 13 then Seq:= 1 else Seq:= 0;
      end;
    until Seq = 4;

    { Parse Content-Length }
    ContentLength:= 0;
    S:= string(HeaderBuf);
    Pos:= System.Pos('Content-Length:', S);
    if Pos = 0 then Pos:= System.Pos('content-length:', LowerCase(S));
    if Pos > 0 then
    begin
      Inc(Pos, Length('Content-Length:'));
      while (Pos <= Length(S)) and (S[Pos] = ' ') do Inc(Pos);
      while (Pos <= Length(S)) and (S[Pos] >= '0') and (S[Pos] <= '9') do
      begin
        ContentLength:= ContentLength * 10 + Ord(S[Pos]) - Ord('0');
        Inc(Pos);
      end;
    end;

    if ContentLength <= 0 then Continue;

    { Read body }
    SetLength(BodyBuf, ContentLength);
    if not ReadBytes(@BodyBuf[0], ContentLength) then Exit;

    { Decode and parse }
    JsonStr:= TEncoding.UTF8.GetString(BodyBuf);
    DebugLog(Format('ReaderThread: rx %d bytes: %s', [ContentLength, Copy(JsonStr, 1, 200)]));
    JsonVal:= TJSONObject.ParseJSONValue(JsonStr);
    { Abandoned by a Stop that ran out of budget: the owner may be gone. }
    if Terminated then
    begin
      JsonVal.Free;
      Exit;
    end;
    if JsonVal <> nil then FOwner.DispatchMessage(JsonVal)
    else DebugLog('ReaderThread: JSON parse failed');
  end; // while
  except
    on E: Exception do DebugLog('ReaderThread: died: ' + E.ClassName + ': ' + E.Message);
  end;
  DebugLog('ReaderThread: terminated normally');
end; // procedure

{ ---- async plumbing ---- }

const
  { Frames that may wait for the writer. A dwell sends at most one hover and
    one (coalesced) didChange, so this is far above normal use; it exists so an
    engine that stopped reading cannot make the queue grow without bound. }
  WRITE_QUEUE_CAPACITY = 256;
  { How often the ticker looks for timed-out async requests. }
  TICK_MS              = 100;
  DEFAULT_BUSY_MS      = 3000;
  DEFAULT_STUCK_MS     = 180000;
  { Engine CPU (100 ns units) since the last mark that counts as progress: 50 ms,
    above the clock-tick noise an idle process is charged. }
  CPU_PROGRESS_100NS   = 50 * 10000;
  { 1.40 heartbeat: how often the ticker asks the engine for its status, and how long one ask may wait
    for the pipe (the listener answers at once; a missing pipe fails at once). }
  BEAT_POLL_MS         = 2000;
  BEAT_CONNECT_MS      = 200;
  INITIALIZE_TIMEOUT_MS = 45000;

type
  { Main-thread-only cancel mark shared by the client and the queued delivery
    closure. Reference-counted so the closure stays safe after the client is
    gone. }
  IDLReplyFlag = interface
    ['{6E0C4D8B-3F1A-4B9E-9C55-0B7E2A6F4D11}']
    function GetCancelled: Boolean;
    procedure SetCancelled(AValue: Boolean);
    function GetDone: Boolean;
    procedure SetDone(AValue: Boolean);
    property Cancelled: Boolean read GetCancelled write SetCancelled;
    property Done     : Boolean read GetDone      write SetDone     ;
  end;

  TDLReplyFlag = class(TInterfacedObject, IDLReplyFlag)
    strict private
      FCancelled: Boolean;
      FDone     : Boolean;
    public
      function GetCancelled: Boolean;
      procedure SetCancelled(AValue: Boolean);
      function GetDone: Boolean;
      procedure SetDone(AValue: Boolean);
  end;

  { Holder object so the dictionaries can carry an interface + closure. }
  TDLAsyncEntry = class
    public
      Callback: TLspReplyProc; // dl:ok public-field@873a -- implementation-only holder for a dictionary value; no behaviour to encapsulate
      Deadline: UInt64       ; // dl:ok public-field@320e -- implementation-only holder for a dictionary value; no behaviour to encapsulate
      Late    : Boolean      ; // dl:ok public-field@d74f -- implementation-only holder for a dictionary value; True once the lrsTimeout notice went out
      Flag    : IDLReplyFlag ; // dl:ok public-field@b0b0 -- implementation-only holder for a dictionary value; no behaviour to encapsulate
  end;

  TDLFlagHolder = class
    public
      Flag: IDLReplyFlag; // dl:ok public-field@b0b0 -- implementation-only holder for a dictionary value; no behaviour to encapsulate
  end;

  TDLLspTickerThread = class(TThread)
    strict private
      FOwner: TDragLintLspClient;
      FStop : TEvent            ;
    protected
      procedure Execute; override;
    public
      constructor Create(AOwner: TDragLintLspClient; AStop: TEvent);
  end;

function TDLReplyFlag.GetCancelled: Boolean;
begin
  Result:= FCancelled;
end;

procedure TDLReplyFlag.SetCancelled(AValue: Boolean);
begin
  FCancelled:= AValue;
end;

function TDLReplyFlag.GetDone: Boolean;
begin
  Result:= FDone;
end;

procedure TDLReplyFlag.SetDone(AValue: Boolean);
begin
  FDone:= AValue;
end;

constructor TDLLspTickerThread.Create(AOwner: TDragLintLspClient; AStop: TEvent);
begin
  FOwner:= AOwner;
  FStop := AStop;
  FreeOnTerminate:= False;
  inherited Create(False);
end;

procedure TDLLspTickerThread.Execute;
begin
  try
    while FStop.WaitFor(TICK_MS) = wrTimeout do FOwner.ExpireTimedOut;
  except
    on E: Exception do DebugLog('LSP ticker thread died: ' + E.ClassName + ': ' + E.Message);
  end;
end;

{ Hands one answer to the main thread. The closure captures only the callback,
  the flag and the message -- never the client -- so it is safe to run after the
  client has been freed. The message is freed here whether or not it ran. }
procedure DeliverReply(const ACallback: TLspReplyProc; const AFlag: IDLReplyFlag;
  AId: Integer; AStatus: TDLLspReplyStatus; AMsg: TJSONValue; AFinal: Boolean = True);
begin
  TThread.ForceQueue(nil,
    procedure
    begin
      try
        if (not AFlag.Cancelled) and Assigned(ACallback) then
        try
          ACallback(AId, AStatus, AMsg);
        except
          on E: Exception do DebugLog(Format('LSP reply callback for id %d raised %s: %s', [AId, E.ClassName, E.Message]));
        end;
      finally
        { a late notice is not the end: the flag must stay cancellable }
        if AFinal then AFlag.Done:= True;
        AMsg.Free; // dl:ok free-of-parameter@66b8 -- ownership of AMsg is handed to this routine by contract (see its header)
      end;
    end);
end;

{ TDragLintLspClient }

constructor TDragLintLspClient.Create;
begin
  inherited Create;
  FLock:= TCriticalSection.Create;
  FPendingRequests:= TDictionary<Integer, TEvent    >.Create;
  FResponses      := TDictionary<Integer, TJSONValue>.Create;
  FAsync          := TObjectDictionary<Integer, TObject>.Create([doOwnsValues]);
  FFlags          := TObjectDictionary<Integer, TObject>.Create([doOwnsValues]);
  FOutstanding    := TDictionary<Integer, TDLOutstanding>.Create;
  FNextId       := 1;
  FProcessHandle:= 0;
  FStdInWrite   := INVALID_HANDLE_VALUE;
  FStdOutRead   := INVALID_HANDLE_VALUE;
  FReaderThread:= nil;
  FState    := dlsDown;
  FLastError:= '';
  FStartedAt:= 0;
  FPipeBroken:= False;
  FBusyAfterMs := DEFAULT_BUSY_MS ;
  FStuckAfterMs:= DEFAULT_STUCK_MS;
end;

procedure TDragLintLspClient.StartWorkers;
begin
  FLastRxTick:= GetTickCount64;
  FWriter:= TDLLspWriteQueue.Create(FStdInWrite, WRITE_QUEUE_CAPACITY,
    procedure(ALastError: DWORD)
    begin
      DebugLog(Format('WriteFile FAILED on the writer thread, GetLastError=%d', [ALastError]));
      NotePipeError(ALastError);
    end);
  FTickerStop:= TEvent.Create(nil, True, False, '');
  FTicker:= TDLLspTickerThread.Create(Self, FTickerStop);
end;

procedure TDragLintLspClient.StopWorkers(ABudgetMs: Cardinal);
var
  T0: UInt64;
begin
  T0:= GetTickCount64;
  if FTicker <> nil then
  begin
    FTickerStop.SetEvent;
    { The ticker never blocks on the engine (it waits on FTickerStop only), but
      its join is bounded all the same: no infinite WaitFor in a stop. }
    if WaitForSingleObject(FTicker.Handle, ABudgetMs div 2) = WAIT_OBJECT_0 then
    begin
      FreeAndNil(FTicker);
      FreeAndNil(FTickerStop);
    end
    else
    begin
      DebugLog('StopWorkers: ticker did not exit in budget -- abandoned');
      FTicker:= nil;      { leaked with its stop event; it touches nothing once signalled }
      FTickerStop:= nil;
    end;
  end;
  if FWriter <> nil then
  begin
    { Cancels a WriteFile blocked on a full pipe; the join is bounded by what
      is left of the budget. }
    var Used: UInt64:= GetTickCount64 - T0;
    FWriter.JoinBudgetMs:= if Used >= ABudgetMs then 0 else Cardinal(ABudgetMs - Used);
    FreeAndNil(FWriter);
  end;
end;

procedure TDragLintLspClient.AttachPipes(AStdInWrite, AStdOutRead: THandle);
begin
  FStdInWrite:= AStdInWrite;
  FStdOutRead:= AStdOutRead;
  StartWorkers;
  FReaderThread:= TLspReaderThread.Create(Self, FStdOutRead);
end;

{ Called by the ticker thread. An async request past its budget gets ONE
  lrsTimeout notice and STAYS in FAsync and FOutstanding (owner ruling
  2026-11-01, fix/late-results): the engine is still working on it, its answer
  is delivered when it arrives, and the engine is not told to stop. A hung
  engine is the watchdog's business (IsStuck), not a per-request clock. }
{ Under FLock, from the ticker: moves the CPU progress mark when the server
  process has burnt CPU_PROGRESS_100NS since the last one. No process handle
  (pipes attached directly) = no sample. }
procedure TDragLintLspClient.SampleEngineCpu(ANow: UInt64);
var
  CreateT, ExitT, KernelT, UserT: TFileTime;
  Cpu                           : Int64    ;
begin
  if FProcessHandle = 0 then Exit;
  if not GetProcessTimes(FProcessHandle, CreateT, ExitT, KernelT, UserT) then Exit;
  Cpu:= PInt64(@UserT)^ + PInt64(@KernelT)^; { FILETIME = little-endian 64-bit 100 ns count }
  if Cpu - FLastCpu100ns < CPU_PROGRESS_100NS then Exit;
  FLastCpu100ns:= Cpu;
  FLastCpuTick := ANow;
end;

{ From the ticker, OUTSIDE FLock (the ask is pipe I/O, bounded by BEAT_CONNECT_MS): every BEAT_POLL_MS
  ask the engine's heartbeat pipe for its status. No process id (pipes attached directly) = no ask. }
procedure TDragLintLspClient.SampleEngineBeat(ANow: UInt64);
var
  Pid: DWORD      ;
  B  : TEngineBeat;
begin
  FLock.Enter;
  try
    if (FProcessId = 0) or (ANow < FNextBeatTick) then Exit;
    FNextBeatTick:= ANow + BEAT_POLL_MS;
    Pid:= FProcessId;
  finally
    FLock.Leave;
  end;
  if RequestEngineBeat(Pid, BEAT_CONNECT_MS, B) then NoteEngineBeat(B.Seq, BeatDisplayText(B));
end;

procedure TDragLintLspClient.NoteEngineBeat(ASeq: Int64; const AText: string);
begin
  FLock.Enter;
  try
    if (not FBeatSeen) or (ASeq <> FBeatSeq) then FLastBeatTick:= GetTickCount64;
    FBeatSeen:= True;
    FBeatSeq := ASeq;
    FBeatText:= AText;
  finally
    FLock.Leave;
  end;
end;

function TDragLintLspClient.EngineBeatText: string;
begin
  FLock.Enter;
  try
    Result:= FBeatText;
  finally
    FLock.Leave;
  end;
end;

procedure TDragLintLspClient.ExpireTimedOut;
var
  Now64  : UInt64              ;
  Expired: TList<Integer>      ;
  Id     : Integer             ;
  Entry  : TDLAsyncEntry       ;
  Pair   : TPair<Integer, TObject>;
begin
  Now64:= GetTickCount64;
  SampleEngineBeat(Now64);
  Expired:= TList<Integer>.Create;
  try
    FLock.Enter;
    try
      SampleEngineCpu(Now64);
      for Pair in FAsync do
        if (not TDLAsyncEntry(Pair.Value).Late) and (TDLAsyncEntry(Pair.Value).Deadline <= Now64) then Expired.Add(Pair.Key);
      for Id in Expired do
      begin
        Entry:= TDLAsyncEntry(FAsync[Id]);
        Entry.Late:= True;
        DeliverReply(Entry.Callback, Entry.Flag, Id, lrsTimeout, nil, False);
      end;
    finally
      FLock.Leave;
    end;
    for Id in Expired do DebugLog(Format('LSP request id %d past its budget -- late, still waiting for the answer', [Id]));
  finally
    Expired.Free;
  end;
end;

{ After Stop NO callback runs -- not for requests still waiting, and not for
  answers already queued to the main thread (their flags are still in FFlags,
  which is pruned only once a delivery has run). A callback may capture the
  client or state the caller is about to free with it, so "told lrsFailed
  later" would be a use-after-free; callers watching for an answer notice the
  client was replaced instead. }
procedure TDragLintLspClient.CancelAllAsync;
var
  Holder: TObject;
begin
  FLock.Enter;
  try
    for Holder in FFlags.Values do TDLFlagHolder(Holder).Flag.Cancelled:= True;
    FAsync.Clear;
    FFlags.Clear;
  finally
    FLock.Leave;
  end;
end;

function TDragLintLspClient.IsAlive: Boolean;
begin
  Result:= False;
  { A LIVE PROCESS BEHIND A DEAD PIPE IS NOT ALIVE for any purpose a caller
    has. Reported 2026-08-24 from a plugin log in which EVERY write on
    2026-08-21 failed with GetLastError=232 (ERROR_NO_DATA, 'the pipe is
    being closed') -- hovers, completions and didChange alike -- while the
    client went on sending and no caller was ever told. Checking only the
    process handle is what let that run for eighteen minutes. }
  if FPipeBroken then Exit;
  if FProcessHandle = 0 then Exit;
  { WAIT_TIMEOUT means "still running"; WAIT_OBJECT_0 means it has exited. }
  Result:= WaitForSingleObject(FProcessHandle, 0) = WAIT_TIMEOUT;
end;

function TDragLintLspClient.StateText: string;
begin
  case FState of
    dlsStarting : Result:= 'starting';
    dlsConnected: if IsAlive then Result:= 'connected'
                  else Result:= 'DIED (process exited after a successful handshake)';
    dlsFailed   : Result:= 'DOWN';
  else
    Result:= 'not started';
  end;
end;

destructor TDragLintLspClient.Destroy;
begin
  Stop;
  FPendingRequests.Free;
  FResponses.Free;
  FAsync.Free;
  FFlags.Free;
  FOutstanding.Free;
  FLock.Free;
  inherited Destroy;
end;

function TDragLintLspClient.Start(const AExePath: string): Boolean;
begin
  Result:= Start(AExePath, nil);
end;

function TDragLintLspClient.Start(const AExePath: string; const ADbPaths: TArray<string>): Boolean;
var
  SA       : TSecurityAttributes;
  hReadIn  : THandle            ;
  hWriteIn : THandle            ;
  hReadOut : THandle            ;
  hWriteOut: THandle            ;
  SI       : TStartupInfoW      ;
  PI       : TProcessInformation;
  CmdLine  : string             ;
  CmdLineW : array of WideChar  ;
  LastErr  : DWORD              ;
begin
  Result:= False;
  FState    := dlsStarting;
  FLastError:= '';
  FStartedAt:= Now;
  DebugLog('Start: ExePath=' + AExePath);
  DebugLog('Start: AExePath FileExists=' + BoolToStr(FileExists(AExePath), True));
  if not FileExists(AExePath) then
  begin
    FState    := dlsFailed;
    FLastError:= 'engine exe not found at ' + AExePath;
  end;

  SA.nLength:= SizeOf(SA);
  SA.bInheritHandle:= True;
  SA.lpSecurityDescriptor:= nil;

  { stdin pipe: child reads from hReadIn, parent writes to hWriteIn }
  if not CreatePipe(hReadIn, hWriteIn, @SA, 0) then
  begin
    DebugLog('Start: CreatePipe(stdin) FAILED, GetLastError=' + IntToStr(GetLastError));
    Exit;
  end;
  { don't let child inherit the write end }
  SetHandleInformation(hWriteIn, HANDLE_FLAG_INHERIT, 0);

  { stdout pipe: parent reads from hReadOut, child writes to hWriteOut }
  if not CreatePipe(hReadOut, hWriteOut, @SA, 0) then
  begin
    CloseHandle(hReadIn );
    CloseHandle(hWriteIn);
    Exit;
  end;
  { don't let child inherit the read end }
  SetHandleInformation(hReadOut, HANDLE_FLAG_INHERIT, 0);

  ZeroMemory(@SI, SizeOf(SI));
  SI.cb:= SizeOf(SI);
  SI.dwFlags   := STARTF_USESTDHANDLES;
  SI.hStdInput := hReadIn;
  SI.hStdOutput:= hWriteOut;
  SI.hStdError := hWriteOut;

  ZeroMemory(@PI, SizeOf(PI));

  { Quote the exe path to handle paths with spaces (e.g. Program Files). }
  CmdLine:= '"' + AExePath + '" lsp';
  { v0.40.3: append every --db path the caller specified. Empty paths are
    skipped; paths get quoted so spaces survive. }
  for var DbI:= 0 to High(ADbPaths) do
    if ADbPaths[DbI] <> '' then CmdLine:= CmdLine + Format(' --db "%s"', [ADbPaths[DbI]]);
  { v0.47: tell the engine to self-exit if THIS process (the IDE) dies --
    belt-and-suspenders to the kill-on-close job object below. }
  CmdLine:= CmdLine + Format(' --parent-pid %d', [GetCurrentProcessId]);
  DebugLog('Start: CmdLine=' + CmdLine);
  SetLength(CmdLineW, Length(CmdLine) + 1);
  Move(PChar(CmdLine)^, CmdLineW[0], (Length(CmdLine) + 1) * SizeOf(WideChar));

  if not CreateProcessW(nil, @CmdLineW[0], nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then
  begin
    LastErr:= GetLastError;
    DebugLog('Start: CreateProcessW FAILED, GetLastError=' + IntToStr(LastErr));
    FState    := dlsFailed;
    FLastError:= Format('CreateProcessW failed (error %d) for %s', [LastErr, AExePath]);
    CloseHandle(hReadIn  );
    CloseHandle(hWriteIn );
    CloseHandle(hReadOut );
    CloseHandle(hWriteOut);
    Exit;
  end;
  DebugLog('Start: CreateProcessW OK, ProcessId=' + IntToStr(PI.dwProcessId));

  { Close child-side handles in the parent }
  CloseHandle(hReadIn  );
  CloseHandle(hWriteOut);
  CloseHandle(PI.hThread);

  FProcessHandle:= PI.hProcess;
  FProcessId    := PI.dwProcessId;
  { 1.40: a new engine starts on the CPU rule until IT answers a heartbeat. }
  FLock.Enter;
  try
    FBeatSeen    := False;
    FBeatSeq     := 0;
    FBeatText    := '';
    FNextBeatTick:= 0;
  finally
    FLock.Leave;
  end;
  { v0.47: OS force-kills the engine when the IDE process dies (crash/kill too). }
  AssignToDragLintJob(FProcessHandle);
  AttachPipes(hWriteIn, hReadOut);
  Result:= True;
  DebugLog('Start: success, reader thread launched');
end; // function

procedure TDragLintLspClient.Stop;
{ v0.40.2: previous order was: Terminate -> CloseHandle(FStdOutRead) ->
  WaitFor. On Windows, CloseHandle of a pipe read end does NOT reliably
  unblock another thread's ReadFile when the child still holds the write
  end open -- the reader thread blocks indefinitely in ReadFile and
  WaitFor hangs forever, freezing the IDE. (Confirmed root cause of the
  IDE freeze user reported after Test Connection in v0.40.1.)

  Correct sequence is to kill the child FIRST so its write end of stdout
  closes, which unblocks our ReadFile with ERROR_BROKEN_PIPE, then
  WaitFor returns immediately. Final WaitFor still gets a 2s upper bound
  so even a pathological reader thread can't lock the UI. }
const
  { 2026-10-29: ONE budget for the whole stop, shared by every wait in it. The
    old code had three independent 2 s waits plus an unbounded writer; after an
    engine death RAD Studio took minutes to exit and logged nothing. }
  STOP_BUDGET_MS = 2000;
var
  T0      : UInt64;
  Deadline: UInt64;

  function Left: Cardinal;
  var
    N: UInt64;
  begin
    N:= GetTickCount64;
    Result:= if N >= Deadline then 0 else Cardinal(Deadline - N);
  end;

  procedure Step(const AWhat: string);
  begin
    DebugLog(Format('Stop: %s (+%d ms)', [AWhat, GetTickCount64 - T0]));
  end;

begin
  T0:= GetTickCount64;
  Deadline:= T0 + STOP_BUDGET_MS;
  FState:= dlsDown;
  Step(Format('begin (pid=%d pipeBroken=%s)', [FProcessId, BoolToStr(FPipeBroken, True)]));
  { Step 1: kill the child unconditionally first. Forces the write end of
    stdout closed, which makes the reader thread's ReadFile return. Nothing is
    WRITTEN to the engine during a stop -- no closing handshake -- so a dead or
    deaf engine costs nothing here. }
  if FProcessHandle <> 0 then TerminateProcess(FProcessHandle, 0);
  Step('engine terminated');

  { Step 1b: stop the writer and the ticker BEFORE the stdin handle closes --
    the writer is the only user of it. A WriteFile blocked on a full pipe is
    cancelled (CancelSynchronousIo), never waited for; every async request
    still waiting is dropped -- see CancelAllAsync. }
  StopWorkers(Left);
  CancelAllAsync;
  FLock.Enter;
  try
    FOutstanding.Clear;
  finally
    FLock.Leave;
  end;
  Step('writer + ticker stopped');

  { Step 2: close stdin and stdout. A reader blocked in ReadFile on a pipe whose
    writer is still open (an engine alive but silent) is cancelled first. }
  if FStdInWrite <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(FStdInWrite);
    FStdInWrite:= INVALID_HANDLE_VALUE;
  end;
  if FStdOutRead <> INVALID_HANDLE_VALUE then
  begin
    if FReaderThread <> nil then CancelSynchronousIo(FReaderThread.Handle);
    CloseHandle(FStdOutRead);
    FStdOutRead:= INVALID_HANDLE_VALUE;
  end;
  Step('pipes closed');

  { Step 3: join the reader within what is left of the budget. WaitForSingleObject
    directly -- TThread.WaitFor has no timeout and pumping messages would
    re-enter the IDE. A reader still running is abandoned (it checks Terminated
    before dispatching, so it never touches this object again). }
  if FReaderThread <> nil then
  begin
    FReaderThread.Terminate;
    if WaitForSingleObject(FReaderThread.Handle, Left) = WAIT_OBJECT_0 then
    begin
      FReaderThread.Free;
      Step('reader joined');
    end
    else Step('reader did NOT exit in budget -- abandoned to keep the IDE responsive');
    FReaderThread:= nil;
  end;

  { Step 4: reap the child. v0.40.8h: the exe image lock is released only once
    the process has fully exited (the BPL reinstall's AutoPullStagedExe races
    it), so wait -- but only for what is left of the budget. }
  if FProcessHandle <> 0 then
  begin
    if WaitForSingleObject(FProcessHandle, Left) = WAIT_OBJECT_0 then Step('engine process reaped')
    else Step('engine process still exiting -- handle closed anyway');
    CloseHandle(FProcessHandle);
    FProcessHandle:= 0;
  end;
  { Keep ProcessId honest -- a stale PID on a stopped client would send anyone
    reading the diagnose report to a process that is no longer there. }
  FProcessId:= 0;
  Step('done');
end; // procedure

function TDragLintLspClient.Initialize: Boolean;
var
  Params: TJSONObject;
  Resp  : TJSONValue ;
begin
  DebugLog('Initialize: sending initialize request');
  Params:= TJSONObject.Create;
  Params.AddPair('processId', TJSONNumber.Create(GetCurrentProcessId));
  Params.AddPair('capabilities', TJSONObject.Create);
  try
    { v0.42: bumped 10s -> 45s. The server opens + migrates every resolved DB
      during initialize; a large DB (1.3 GB library) that predates the v0.42
      index additions builds them on first open. That one-time cost (plus
      several project DBs) can exceed 10s and fail the handshake. 45s covers it;
      subsequent opens are instant (CREATE INDEX IF NOT EXISTS no-ops). }
    Resp:= Request('initialize', Params, 45000);
    Result:= Resp <> nil;
    if Result then
    begin
      DebugLog('Initialize: response received OK');
      Resp.Free;
      FState    := dlsConnected;
      FLastError:= '';
    end
    else
    begin
      DebugLog('Initialize: TIMEOUT or no response within 45s');
      FState    := dlsFailed;
      { Deliberately NOT phrased as "handshake failed". On 2026-08-17 the server
        answered this exact request correctly at 101 s -- the client had simply
        stopped waiting at 45 s, and the dialog that said "failed" sent a day of
        debugging at the server. State the fact we actually have. }
      FLastError:= 'no initialize response within 45s (the server may still be starting -- check CPU load)';
    end;
  finally
    Params.Free;
  end;
end; // function

procedure TDragLintLspClient.InitializeAsync(const ADone: TProc<Boolean>);
var
  Params: TJSONObject;
  Id    : Integer    ;
begin
  DebugLog('InitializeAsync: sending initialize request');
  FState:= dlsStarting;
  Params:= TJSONObject.Create;
  try
    Params.AddPair('processId', TJSONNumber.Create(GetCurrentProcessId));
    Params.AddPair('capabilities', TJSONObject.Create);
    { Same 45 s budget as the blocking Initialize (see its v0.42 note), but the
      IDE no longer waits through it: the answer arrives on the main thread. }
    Id:= RequestAsync('initialize', Params, INITIALIZE_TIMEOUT_MS,
      procedure(AId: Integer; AStatus: TDLLspReplyStatus; AReply: TJSONValue)
      begin
        { LATE, not failed (fix/late-results): on 2026-08-17 the engine answered
          at 101 s. The handshake keeps waiting; ADone runs on the answer. A
          hung engine is the watchdog's (IsStuck covers dlsStarting). }
        if AStatus = lrsTimeout then
        begin
          DebugLog('InitializeAsync: no answer within 45 s -- late, still waiting');
          FLastError:= 'initialize is late (the server is still starting -- check CPU load); still waiting';
          Exit;
        end;
        if AStatus = lrsResult then
        begin
          DebugLog('InitializeAsync: response received OK');
          FState    := dlsConnected;
          FLastError:= '';
        end
        else
        begin
          DebugLog(Format('InitializeAsync: no usable answer (status %d)', [Ord(AStatus)]));
          FState    := dlsFailed;
          FLastError:= 'initialize answered with an error';
        end;
        if Assigned(ADone) then ADone(AStatus = lrsResult);
      end);
  finally
    Params.Free;
  end;
  if Id = 0 then
  begin
    FState    := dlsFailed;
    FLastError:= 'initialize could not be sent (pipe not writable)';
    if Assigned(ADone) then TThread.ForceQueue(nil, procedure begin ADone(False); end);
  end;
end;

{ True for a request the IDE sends in the BACKGROUND (draglint/callerCounts,
  textDocument/codeLens). It still counts for OutstandingCount and IsStuck; only
  IsBusy -- the "do not ask a hover now" signal -- ignores it, so a slow
  caller-count pass never starves the hover the engine yields to. }
function DLIsBackgroundLspMethod(const AMethod: string): Boolean;
begin
  Result:= (AMethod = 'draglint/callerCounts') or (AMethod = 'textDocument/codeLens');
end;

function OutstandingNow(const AMethod: string): TDLOutstanding;
begin
  Result.Sent      := GetTickCount64;
  Result.Background:= DLIsBackgroundLspMethod(AMethod);
end;

function TDragLintLspClient.SendRequestFrame(AId: Integer; const AMethod: string; AParams: TJSONValue): Boolean;
var
  Msg: TJSONObject;
begin
  Msg:= TJSONObject.Create;
  try
    Msg.AddPair('jsonrpc', '2.0');
    Msg.AddPair('id', TJSONNumber.Create(AId));
    Msg.AddPair('method', AMethod);
    if AParams <> nil then Msg.AddPair('params', AParams.Clone as TJSONValue)
    else Msg.AddPair('params', TJSONObject.Create);
    var Body: TBytes:= TEncoding.UTF8.GetBytes(Msg.ToString);
    Result:= (FWriter <> nil) and FWriter.Enqueue(TEncoding.UTF8.GetBytes(Format('Content-Length: %d'#13#10#13#10, [Length(Body)])) + Body);
    DebugLog(Format('Tx id=%d %s queued=%s', [AId, AMethod, BoolToStr(Result, True)]));
  finally
    Msg.Free;
  end;
end;

function TDragLintLspClient.Request(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Integer): TJSONValue;
var
  Id : Integer;
  Evt: TEvent ;
begin
  Result:= nil;
  Id    := 0;
  Evt:= TEvent.Create(nil, True, False, '');
  try
    FLock.Enter;
    try
      Id:= FNextId;
      Inc(FNextId);
      FPendingRequests.Add(Id, Evt);
      FOutstanding.AddOrSetValue(Id, OutstandingNow(AMethod));
    finally
      FLock.Leave;
    end;

    if not SendRequestFrame(Id, AMethod, AParams) then
    begin
      { Never sent: nothing for the engine to owe. Left in FOutstanding, it
        latched IsBusy / IsStuck and the watchdog restarted a healthy engine. }
      FLock.Enter;
      try
        FOutstanding.Remove(Id);
      finally
        FLock.Leave;
      end;
    end
    else if Evt.WaitFor(ATimeoutMs) = wrSignaled then
    begin
      FLock.Enter;
      try
        if FResponses.TryGetValue(Id, Result) then FResponses.Remove(Id);
      finally
        FLock.Leave;
      end;
    end;
  finally
    FLock.Enter;
    try
      FPendingRequests.Remove(Id);
      { A response that raced the timeout must not leak. }
      var Late: TJSONValue;
      if (Result = nil) and FResponses.TryGetValue(Id, Late) then
      begin
        FResponses.Remove(Id);
        Late.Free;
      end;
    finally
      FLock.Leave;
    end;
    Evt.Free;
  end;
end; // function

function TDragLintLspClient.RequestAsync(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Integer; const AOnReply: TLspReplyProc): Integer;
var
  Id    : Integer      ;
  Entry : TDLAsyncEntry;
  Holder: TDLFlagHolder;
begin
  Result:= 0;
  if FWriter = nil then Exit;
  Entry:= TDLAsyncEntry.Create;
  Entry.Callback:= AOnReply;
  Entry.Deadline:= GetTickCount64 + UInt64(if ATimeoutMs > 0 then ATimeoutMs else 0);
  Entry.Flag    := TDLReplyFlag.Create;
  Holder:= TDLFlagHolder.Create;
  Holder.Flag:= Entry.Flag;
  FLock.Enter;
  try
    Id:= FNextId;
    Inc(FNextId);
    { Prune flags whose delivery already ran -- they can no longer be cancelled. }
    var Gone: TList<Integer>:= TList<Integer>.Create;
    try
      for var Pair in FFlags do
        if TDLFlagHolder(Pair.Value).Flag.Done then Gone.Add(Pair.Key);
      for var G in Gone do FFlags.Remove(G);
    finally
      Gone.Free;
    end;
    FAsync.Add(Id, Entry);
    FFlags.Add(Id, Holder);
    FOutstanding.AddOrSetValue(Id, OutstandingNow(AMethod));
  finally
    FLock.Leave;
  end;

  if not SendRequestFrame(Id, AMethod, AParams) then
  begin
    FLock.Enter;
    try
      FAsync.Remove(Id);
      FFlags.Remove(Id);
      FOutstanding.Remove(Id);
    finally
      FLock.Leave;
    end;
    Exit;
  end;
  Result:= Id;
end;

procedure TDragLintLspClient.CancelRequest(AId: Integer);
var
  Holder: TObject;
  WasLive: Boolean;
begin
  if AId <= 0 then Exit;
  FLock.Enter;
  try
    if FFlags.TryGetValue(AId, Holder) then TDLFlagHolder(Holder).Flag.Cancelled:= True;
    WasLive:= FAsync.ContainsKey(AId);
    FAsync.Remove(AId);
    FFlags.Remove(AId);
  finally
    FLock.Leave;
  end;
  if not WasLive then Exit;
  var P: TJSONObject:= TJSONObject.Create;
  try
    P.AddPair('id', TJSONNumber.Create(AId));
    Notify('$/cancelRequest', P);
  finally
    P.Free;
  end;
end;

procedure TDragLintLspClient.Notify(const AMethod: string; AParams: TJSONValue; const ACoalesceKey: string);
var
  Msg: TJSONObject;
begin
  Msg:= TJSONObject.Create;
  try
    Msg.AddPair('jsonrpc', '2.0'  );
    Msg.AddPair('method' , AMethod);
    if AParams <> nil then Msg.AddPair('params', AParams.Clone as TJSONValue)
    else Msg.AddPair('params', TJSONObject.Create);
    WriteFramedMessage(Msg.ToString, ACoalesceKey);
  finally
    Msg.Free;
  end;
end;

function TDragLintLspClient.IsBusy: Boolean;
var
  Now64 : UInt64;
  Oldest: UInt64;
  Sent  : TDLOutstanding;
begin
  Now64:= GetTickCount64;
  Oldest:= Now64;
  FLock.Enter;
  try
    { A BACKGROUND request (caller counts, code lens) never makes the client
      busy: the engine yields to a hover, so refusing one would starve it. }
    for Sent in FOutstanding.Values do
      if (not Sent.Background) and (Sent.Sent < Oldest) then Oldest:= Sent.Sent;
  finally
    FLock.Leave;
  end;
  Result:= (Now64 - Oldest > FBusyAfterMs) or
           ((FWriter <> nil) and (FWriter.WriteStalledMs > FBusyAfterMs));
end;

function TDragLintLspClient.IsStuck: Boolean;
var
  Oldest: UInt64;
  Since : UInt64;
  Sent  : TDLOutstanding;
begin
  { Silence is measured from the LATER of "last thing the engine said" and
    "oldest request still unanswered": an engine idle for ten minutes and then
    asked something is not stuck the moment it is asked. }
  Result:= False;
  FLock.Enter;
  try
    if FOutstanding.Count > 0 then
    begin
      Oldest:= High(UInt64);
      for Sent in FOutstanding.Values do
        if Sent.Sent < Oldest then Oldest:= Sent.Sent;
      Since:= if FLastRxTick > Oldest then FLastRxTick else Oldest;
      { 1.40: with a heartbeat the status change is the progress mark and CPU is ignored. }
      if FBeatSeen then
      begin
        if FLastBeatTick > Since then Since:= FLastBeatTick;
      end
      else if FLastCpuTick > Since then Since:= FLastCpuTick;
      Result:= GetTickCount64 - Since > FStuckAfterMs;
    end;
  finally
    FLock.Leave;
  end;
  { An engine that stopped READING stdin is stuck whether or not anything was
    a request. }
  if (not Result) and (FWriter <> nil) then Result:= FWriter.WriteStalledMs > FStuckAfterMs;
end;

function TDragLintLspClient.OutstandingCount: Integer;
begin
  FLock.Enter;
  try
    Result:= FOutstanding.Count;
  finally
    FLock.Leave;
  end;
end;


{ ERROR_NO_DATA (232) and ERROR_BROKEN_PIPE (109) both mean the server is no
  longer reading us. Anything else is a transient write problem and is left
  alone -- declaring the client dead on, say, a partial write would throw away
  a working server. Latched, so the log records the transition once instead of
  once per message: the 2026-08-21 log is 40 identical failure lines and the
  repetition is what made it look like noise rather than a state change. }
procedure TDragLintLspClient.NotePipeError(ALastError: DWORD);
begin
  if FPipeBroken then Exit;
  if (ALastError <> ERROR_NO_DATA) and (ALastError <> ERROR_BROKEN_PIPE) then Exit;
  FPipeBroken:= True;
  FLastError := Format('the server stopped reading (GetLastError=%d)', [ALastError]);
  FState     := dlsFailed;
  DebugLog('LSP pipe is BROKEN -- client marked not alive; EnsureLspClient will restart it');
end;

procedure TDragLintLspClient.WriteFramedMessage(const AJson: string; const ACoalesceKey: string);
{ 2026-10-29: ENQUEUES, never writes. The blocking WriteFile under FLock that
  used to live here froze the IDE whenever the engine stopped reading stdin
  (docs\INBOX-ide-hang-on-slow-engine.md section 1). The writer thread in
  DragLint.Plugin.LspWriteQueue now owns the pipe; a full queue drops the frame
  and says so in the log instead of waiting. }
const
  LOG_PREVIEW_CHARS = 200; { how much of a frame the debug log quotes }
var
  Bytes: TBytes;
begin
  Bytes:= TEncoding.UTF8.GetBytes(AJson);
  DebugLog(Format('Tx: %d bytes: %s', [Length(Bytes), Copy(AJson, 1, LOG_PREVIEW_CHARS)]));
  if FWriter = nil then Exit;
  if not FWriter.Enqueue(TEncoding.UTF8.GetBytes(Format('Content-Length: %d'#13#10#13#10, [Length(Bytes)])) + Bytes, ACoalesceKey) then
    DebugLog('Tx DROPPED -- write queue full or pipe failed (engine not reading stdin?)');
end; // procedure

procedure TDragLintLspClient.DispatchMessage(AMsg: TJSONValue);
var
  IdVal    : TJSONValue;
  Id       : Integer   ;
  Evt      : TEvent    ;
  MethodVal: TJSONValue;
  ParamsVal: TJSONValue;
  MethodStr: string    ;
  Entry    : TObject   ;
  Status   : TDLLspReplyStatus;
begin
  FLock.Enter;
  try
    FLastRxTick:= GetTickCount64;
  finally
    FLock.Leave;
  end;

  IdVal:= (AMsg as TJSONObject).GetValue('id');
  if IdVal <> nil then
  begin
    { It's a response if it has 'result' or 'error' }
    if ((AMsg as TJSONObject).GetValue('result') <> nil) or ((AMsg as TJSONObject).GetValue('error') <> nil) then
    begin
      Id:= (IdVal as TJSONNumber).AsInt;
      Status:= if (AMsg as TJSONObject).GetValue('error') <> nil then lrsError else lrsResult;
      FLock.Enter;
      try
        FOutstanding.Remove(Id);
        if FPendingRequests.TryGetValue(Id, Evt) then
        begin
          FResponses.AddOrSetValue(Id, AMsg);
          Evt.SetEvent;
        end
        else if FAsync.TryGetValue(Id, Entry) then
        begin
          { Ownership of AMsg passes to the delivery closure. }
          DeliverReply(TDLAsyncEntry(Entry).Callback, TDLAsyncEntry(Entry).Flag, Id, Status, AMsg);
          FAsync.Remove(Id);
        end
        else AMsg.Free; // dl:ok free-of-parameter@2db8 -- the reader thread hands ownership of every parsed message to this routine
      finally
        FLock.Leave;
      end;
      Exit;
    end; // if
  end; // if

  { Notification or server-to-client request }
  MethodVal:= (AMsg as TJSONObject).GetValue('method');
  if (MethodVal <> nil) and Assigned(FOnNotification) then
  begin
    MethodStr:= MethodVal.Value;
    ParamsVal:= (AMsg as TJSONObject).GetValue('params');
    FOnNotification(MethodStr, ParamsVal);
  end;
  { We do NOT free AMsg here when it's a notification and we called the handler,
    because the caller may hold references. For safety, free it now since the
    handler is synchronous and done by the time we return. }
  AMsg.Free; // dl:ok free-of-parameter@66b8 -- the reader thread hands ownership of every parsed message to this routine
end; // procedure


initialization

finalization
if GLogLock <> nil then
begin
  GLogLock.Free;
  GLogLock:= nil;
end;

end.
