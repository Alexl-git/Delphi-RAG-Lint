unit DRagLint.Core.ControlChannel;

{ ---------------------------------------------------------------------------
  THE MAINTENANCE CONTROL CHANNEL -- a documented, local, user-scoped way to
  ask a long-lived engine to stand down.  docs\PLAN-maintenance-shutdown-channel.md

  WHY IT EXISTS
    Staging a new engine, or re-parsing an index, needs the engines that hold
    the file or the database to let go. Every mechanism that existed keyed on
    the OWNER going away: LSP shutdown/exit rides the editor's own stdio and
    only the editor can send it; --parent-pid fires when the spawning IDE
    dies; the Job Object when the parent dies. The maintenance case is the
    owner STAYING while a third process needs the file released. Until this
    unit the only answer was TerminateProcess, which leaves -wal/-shm sidecars
    and in-flight work behind. (`ide-release` is the plugin-side sibling: it
    asks the Delphi IDE plugin not to RESPAWN; it cannot reach an engine VS
    Code spawned, and it frees nothing itself.)

  WHAT IT IS, AND IS NOT
    * A Windows NAMED PIPE, never a TCP port. A loopback listener is reachable
      by every local user and by a browser page (DNS rebinding defeats naive
      Origin checks), and it needs a port that can collide. A pipe is not
      reachable from a browser, needs no port, and carries an ACL.
    * Per user and per session: the name carries the creating user's SID and
      the logon session id, and the pipe is created with an EXPLICIT DACL that
      grants the creating user only. A NULL DACL would grant Everyone. Remote
      clients are rejected at the pipe as well (PIPE_REJECT_REMOTE_CLIENTS).
    * It does ONE thing. Two messages exist -- `status` (describe yourself)
      and `shutdown` (stand down) -- and `status` is there only so a
      maintenance tool can learn which engine holds which database before it
      asks. Nothing here runs a query, reindexes, or takes an argument that
      names work. A control channel that can do arbitrary work is the
      "backdoor" the owner's wording reached for, and is exactly what this is
      not.
    * Every honoured or refused request is audited -- who asked (pid + exe),
      when -- on the engine's stderr (the editor's engine log captures it) and
      in %LOCALAPPDATA%\drag-lint\control-channel-audit.log, beside the
      engine-hold sentinel and for the same reason (TEMP is per-process).

  WHO LISTENS -- ONE gate, ControlChannelEnabledFor, and it is PROVISIONAL.
    See that function.

  WIRE -- one message per connection, UTF-8, TAB-separated, LF-terminated:
    status                   -> status<TAB>pid<TAB>version<TAB>extractor<TAB>db...
    status<TAB>role<TAB>beat -> ... extractor<TAB>role=<verb><TAB>beat=<seq|action|step|n|total|age-ms><TAB>db...
                                (each extra field only when its argument is asked; 1.39.1 role, 1.40 beat)
    The 1.40 HEARTBEAT pipe (BEAT_PIPE_PREFIX, see "ENGINE HEARTBEAT" below) speaks the same
    `status` and answers everything else `unknown` -- it is never a stand-down channel.
    shutdown[<TAB>wait-ms]   -> exiting<TAB>pid<TAB>db...   (stores closed; exit 0 follows)
                             -> busy<TAB>pid<TAB>what       (still running; nothing changed)
    anything else            -> unknown<TAB>pid             (still running; nothing changed)

  HOW THE HOST STANDS DOWN
    The LSP main thread blocks in a synchronous ReadFile on stdin, which only
    the editor writes to. So the listener (1) flags the request, (2) cancels
    the main thread's pending stdin read with CancelSynchronousIo -- ONLY
    while the host says it is inside that read, so an unrelated synchronous
    I/O (a SQLite page read inside a handler) is never the one cancelled --
    and (3) waits, up to the requested deadline, for the host to report that
    it has left its loop AND CLOSED EVERY STORE. Only then is `exiting`
    written, so a tool that reads the reply may proceed at once. If the
    deadline passes first, and no cancel has landed, the request is WITHDRAWN
    atomically, `busy` names the in-flight method, and the host carries on
    untouched. State moves through ONE interlocked word, so the host taking
    the request and the listener withdrawing it cannot both happen.
  --------------------------------------------------------------------------- }

interface

uses
  Winapi.Windows
  , System.SysUtils
  , System.Classes
  , System.SyncObjs
  ;

const
  /// <summary>Leaf prefix of every control pipe: <c>\\.\pipe\drag-lint-ctl-&lt;sid&gt;-s&lt;session&gt;-p&lt;pid&gt;</c>.</summary>
  CONTROL_PIPE_PREFIX     = 'drag-lint-ctl-';
  CONTROL_MSG_STATUS      = 'status';
  CONTROL_MSG_SHUTDOWN    = 'shutdown';
  CONTROL_REPLY_STATUS    = 'status';
  CONTROL_REPLY_EXITING   = 'exiting';
  CONTROL_REPLY_BUSY      = 'busy';
  CONTROL_REPLY_UNKNOWN   = 'unknown';
  /// <summary>1.39.1: the argument of a <c>status</c> request that asks for the engine's ROLE. An engine
  /// that knows it answers with a <c>role=&lt;verb&gt;</c> field right after the extractor version; a plain
  /// <c>status</c> (every older client) gets the old reply unchanged, and an older engine ignores the argument.</summary>
  CONTROL_STATUS_ARG_ROLE = 'role';
  /// <summary>Prefix of the role field of a status reply (a database path never starts with it).</summary>
  CONTROL_ROLE_FIELD_PREFIX = 'role=';
  /// <summary>Graceful deadline when the request names none, in ms.</summary>
  CONTROL_DEFAULT_WAIT_MS = 5000;
  /// <summary>Upper clamp on any requested deadline, in ms (10 minutes).</summary>
  CONTROL_MAX_WAIT_MS     = 600000;
  /// <summary>PROCESS_QUERY_LIMITED_INFORMATION -- not declared by Winapi.Windows;
  /// the access GetExitCodeProcess / QueryFullProcessImageName need.</summary>
  PROCESS_QUERY_LIMITED_INFORMATION_ACCESS = $1000;

/// <summary>THE ONE GATE: does an engine running <paramref name="ACommand"/>
/// open a control channel?</summary>
/// <param name="ACommand">The CLI verb the engine was started with.</param>
/// <returns>True for <c>lsp</c>, <c>cycles</c>, <c>index</c>, <c>lint-all</c> and <c>warm-rule-cache</c>.</returns>
/// <remarks>
/// PROVISIONAL ANSWER to the plan's open owner question (Q1, session
/// 93): honoured by every running engine, or only by one in <c>lsp</c> mode?
/// Taken as <c>lsp</c> only, in the owner's absence, for two reasons: an
/// engine in the middle of an index is the one process a stray message must
/// never stop, and the LSP servers are the processes that actually linger
/// (four were live during session 92-93, one five days old). Narrow is the
/// REVERSIBLE direction -- widening later is additive, narrowing after
/// something shipped is a breaking change. To widen: add the verb here AND
/// start the channel in that verb's dispatch branch the way the <c>lsp</c>
/// branch in DRagLint.CLI does (Create after the stores are open, Run,
/// StandDownComplete after they are closed). Nothing else consults the mode.
/// <para>WIDENED 2026-10-26 (lane X-BT, owner ruling: an IDE cycle-fix run has
/// no time limit, so its Cancel must reach the engine): <c>cycles</c> listens,
/// started by DRagLint.CLI.CycleFix.RunCycleFix -- which only a
/// <c>cycles --fix</c> run reaches -- not by the dispatch. Standing down there
/// means: kill the build it waits on, roll every written file back and exit 1
/// with "cancelled -- rolled back" (not 0: the run did not finish).</para>
/// <para>WIDENED 2026-10-28 (DEC-13 reopened, owner): <c>index</c> (single root, `--project`, `--all`) and `lint-all` listen too, started by the Do* verb through BatchChannelOpen. A stand-down is taken BETWEEN FILES (index: the storage layer's file-transaction gate, so no file row is ever half written) or between files of the lint scan (lint-all stops and prints the findings so far). Exit code CONTROL_EXIT_STOOD_DOWN.</para>
/// <para>WIDENED 2026-10-30 (1.39.1, known issue of 1.39.0): <c>warm-rule-cache</c> listens, started by DRagLint.CLI.DoWarmRuleCache. A warm only reads and its result is disposable, so a stand-down is taken AT ONCE by a watcher thread (no safe point to wait for) and the process exits CONTROL_EXIT_STOOD_DOWN; shutdown and an index of the same database stop it, and the engine image is free again.</para>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.StartStandDownChannel (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.DoWarmRuleCache (DRagLint.CLI.pas), DRagLint.CLI.Run (DRagLint.CLI.pas), DRagLint.Core.ControlChannel.BatchChannelOpen (DRagLint.Core.ControlChannel.pas)</para>
/// <para>Pure</para>
/// <para>Calls: SameText</para>
/// <para>Returns: SameText(ACommand, 'lsp') or SameText(ACommand, 'cycles') or SameText(ACommand, 'index')</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ControlChannelEnabledFor(const ACommand: string): Boolean;

/// <summary>The current user's SID as a string (<c>S-1-5-21-...</c>).</summary>
/// <returns>The SID string, or '' when the token cannot be read.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoShutdown (DRagLint.CLI.pas), [dclDragLintWizard]DRagLint.Core.ControlChannel.BeatPipeNameFor (DRagLint.Core.ControlChannel.pas), [dclDragLintWizard]DRagLint.Core.ControlChannel.ControlPipeLeafFor (DRagLint.Core.ControlChannel.pas), [dclDragLintWizard]DRagLint.Core.ControlChannel.ListControlPipesForThisUser (DRagLint.Core.ControlChannel.pas), [dclDragLintWizard]DRagLint.Core.ControlChannel.SnapshotWritingBeats (DRagLint.Core.ControlChannel.pas), [dclDragLintWizard]DRagLint.Core.ControlChannel.TControlChannel.Create (DRagLint.Core.ControlChannel.pas)</para>
/// <para>Calls: CloseHandle, ConvertSidToStringSidW, GetTokenInformation, HLOCAL, LocalFree, OpenProcessToken, PTokenUser</para>
/// <para>Pure</para>
/// <para>Returns: ''; SidStr</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CurrentUserSidString: string;

/// <summary>The logon session id of the current process.</summary>
/// <returns>The session id (0 when it cannot be read).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoShutdown (DRagLint.CLI.pas), DRagLint.Core.ControlChannel.BeatPipeNameFor (DRagLint.Core.ControlChannel.pas), DRagLint.Core.ControlChannel.ControlPipeLeafFor (DRagLint.Core.ControlChannel.pas), DRagLint.Core.ControlChannel.ListControlPipesForThisUser (DRagLint.Core.ControlChannel.pas), DRagLint.Core.ControlChannel.SnapshotWritingBeats (DRagLint.Core.ControlChannel.pas)</para>
/// <para>Calls: ProcessIdToSessionId</para>
/// <para>Returns: S</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CurrentSessionId: Cardinal;

/// <summary>Full pipe name an engine with pid <paramref name="APid"/> of THIS
/// user and session would listen on.</summary>
/// <param name="APid">Process id of the engine.</param>
/// <returns><c>\\.\pipe\drag-lint-ctl-&lt;sid&gt;-s&lt;session&gt;-p&lt;pid&gt;</c>.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.StandDownChild (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.ForwardStandDownToChildren (DRagLint.CLI.pas), DRagLint.CLI.StopStaleWarm (DRagLint.CLI.pas), [dclDragLintWizard]DRagLint.Core.ControlChannel.TControlChannel.Create (DRagLint.Core.ControlChannel.pas), [dclDragLintWizard]DragLint.Plugin.ProcRun.StartStandDown (DragLint.Plugin.ProcRun.pas)</para>
/// <para>Calls: DRagLint.Core.ControlChannel.ControlPipeLeafFor</para>
/// <para>Pure</para>
/// <para>Returns: PIPE_PREFIX_FULL + ControlPipeLeafFor(APid)</para>
/// <seealso cref="DRagLint.Core.ControlChannel.ControlPipeLeafFor"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ControlPipeNameFor(APid: Cardinal): string;

/// <summary>Pid encoded in a control pipe name, or 0 when the name is not one.</summary>
/// <param name="APipeLeaf">The name without the <c>\\.\pipe\</c> prefix.</param>
/// <returns>The pid, or 0.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Core.ControlChannel.ListControlPipesForThisUser (DRagLint.Core.ControlChannel.pas)</para>
/// <para>Calls: StrToIntDef</para>
/// <para>Pure</para>
/// <para>Returns: 0; StrToIntDef(APipeLeaf.Substring(P + 2), 0)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function PidFromControlPipeLeaf(const APipeLeaf: string): Cardinal;

/// <summary>Every control pipe currently in the pipe namespace that belongs
/// to THIS user and session.</summary>
/// <returns>Full pipe names. A pipe disappears with its process, so this is
/// also the live instance list -- no registry file to go stale.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoShutdown (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Core.ControlChannel.CurrentSessionId, DRagLint.Core.ControlChannel.CurrentUserSidString, DRagLint.Core.ControlChannel.PidFromControlPipeLeaf, FindFirstFileW, FindNextFileW, IntToStr</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Core.ControlChannel.CurrentSessionId"/>
/// <seealso cref="DRagLint.Core.ControlChannel.CurrentUserSidString"/>
/// <seealso cref="DRagLint.Core.ControlChannel.PidFromControlPipeLeaf"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ListControlPipesForThisUser: TArray<string>;

/// <summary>Sends ONE message to a control pipe and reads its one-line reply.</summary>
/// <param name="APipeName">Full pipe name.</param>
/// <param name="AMessage">The message without its LF terminator.</param>
/// <param name="AConnectTimeoutMs">How long to wait for a free pipe instance.</param>
/// <param name="AReply">The reply with its terminator stripped; '' on failure.</param>
/// <param name="AError">Why it failed; '' on success.</param>
/// <returns>True when a reply was read.</returns>
/// <remarks>
/// The read blocks until the engine replies; for <c>shutdown</c>
/// that is bounded by the wait-ms the message itself carries.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.StandDownChild (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.DoShutdown (DRagLint.CLI.pas), DRagLint.CLI.ForwardStandDownToChildren (DRagLint.CLI.pas), DRagLint.CLI.StopStaleWarm (DRagLint.CLI.pas), [dclDragLintWizard]DRagLint.Core.ControlChannel.RequestEngineBeat (DRagLint.Core.ControlChannel.pas), [dclDragLintWizard]DRagLint.Core.ControlChannel.SnapshotWritingBeats (DRagLint.Core.ControlChannel.pas), [dclDragLintWizard]DragLint.Plugin.ProcRun.StartStandDown (DragLint.Plugin.ProcRun.pas)</para>
/// <para>Calls: Cardinal, CloseHandle, CreateFileW, DRagLint.Core.ControlChannel.ReadLineFromPipe, IntToStr, PChar, SysErrorMessage, WaitNamedPipeW, WriteFile</para>
/// <para>Returns: False; True</para>
/// <para>Mutates: AReply (out), AError (out)</para>
/// <seealso cref="DRagLint.Core.ControlChannel.ReadLineFromPipe"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ControlRequest(const APipeName, AMessage: string; AConnectTimeoutMs: Integer; out AReply, AError: string): Boolean;

/// <summary>Where honoured and refused requests are appended.</summary>
/// <returns><c>%LOCALAPPDATA%\drag-lint\control-channel-audit.log</c>.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Core.ControlChannel.Audit (DRagLint.Core.ControlChannel.pas)</para>
/// <para>Calls: GetEnvironmentVariable</para>
/// <para>Returns: TPath.Combine(TPath.Combine(Base, AUDIT_DIR_NAME), AUDIT_FILE_NAME)</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ControlAuditLogPath: string;

{ ---- ENGINE HEARTBEAT (1.40, owner design 2026-11-01) ----------------------
  Every engine action writes (action, step, n/total, timestamp) into ONE
  process-wide status record; a status-only listener thread -- the heartbeat
  pipe, BEAT_PIPE_PREFIX -- hands it to whoever asks (the IDE plugin, every few
  seconds). The plugin's rule: the status CHANGING = slow, keep waiting; the
  status frozen (or no answer) for N minutes = stuck, only then kill. CPU and
  output silence no longer decide anything once a beat was seen.
  WIRE: `status<TAB>beat` -> the usual status reply with one more field,
  `beat=<seq>|<action>|<step>|<n>|<total>|<age-ms>`, after the role field (if
  asked) and before the databases. The ctl pipe answers the same request.
  Design note: C:\TEMP\claude\lanes\140\agent-beat\DESIGN-heartbeat.md;
  guards tests\autotest\run_engine_heartbeat_guard.ps1 (engine) and
  tests\plugin\run_procrun_heartbeat.ps1 (plugin). ------------------------- }

const
  /// <summary>Leaf prefix of a heartbeat (status-only) pipe:
  /// <c>\\.\pipe\drag-lint-beat-&lt;sid&gt;-s&lt;session&gt;-p&lt;pid&gt;</c>. A DIFFERENT family from
  /// CONTROL_PIPE_PREFIX on purpose: `shutdown --all` and the staging tools enumerate control pipes only, so a
  /// verb that merely reports progress never becomes a stand-down target.</summary>
  BEAT_PIPE_PREFIX = 'drag-lint-beat-';
  /// <summary>Argument of a <c>status</c> request that asks for the heartbeat field.</summary>
  CONTROL_STATUS_ARG_BEAT = 'beat';
  /// <summary>Prefix of the heartbeat field of a status reply (a database path never starts with it).</summary>
  CONTROL_BEAT_FIELD_PREFIX = 'beat=';

type
  /// <summary>One snapshot of the engine's status record.</summary>
  /// <remarks>
  /// Seq is the ONLY change test a client may use: it grows by one on every report, so two snapshots
  /// with the same Seq mean no progress in between, whatever the other fields say.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: [dclDragLintWizard]declaration (DRagLint.Core.ControlChannel.pas) ?, [dclDragLintWizard]DRagLint.Core.ControlChannel.BeatDisplayText (DRagLint.Core.ControlChannel.pas) ?, [dclDragLintWizard]DRagLint.Core.ControlChannel.BeatFieldText (DRagLint.Core.ControlChannel.pas) ?, [dclDragLintWizard]DRagLint.Core.ControlChannel.BeatSnapshot (DRagLint.Core.ControlChannel.pas) ?, [dclDragLintWizard]DRagLint.Core.ControlChannel.ParseBeatReply (DRagLint.Core.ControlChannel.pas), [dclDragLintWizard]DRagLint.Core.ControlChannel.RequestEngineBeat (DRagLint.Core.ControlChannel.pas), [dclDragLintWizard]DragLint.Plugin.LspClient.TDragLintLspClient.SampleEngineBeat (DragLint.Plugin.LspClient.pas) ?, [dclDragLintWizard]DragLint.Plugin.ProcRun.RunCore.CheckBeat (DragLint.Plugin.ProcRun.pas) ?</para>
  /// <para>Used in units: DRagLint.CLI, [dclDragLintWizard]DRagLint.Core.ControlChannel, [dclDragLintWizard]DragLint.Plugin.LspClient, [dclDragLintWizard]DragLint.Plugin.ProcRun</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TEngineBeat = record
    /// <summary>Report counter; 0 = nothing reported yet.</summary>
    Seq   : Int64 ;
    /// <summary>The verb or LSP method in progress ('' = idle).</summary>
    Action: string;
    /// <summary>Phase inside the action ('' = none).</summary>
    Step  : string;
    /// <summary>Counter inside the step.</summary>
    N     : Int64 ;
    /// <summary>Denominator of N; 0 = unknown.</summary>
    Total : Int64 ;
    /// <summary>Milliseconds since the last report, at snapshot time.</summary>
    AgeMs : Int64 ;
  end;

/// <summary>Starts a new action in the status record: action AAction, no step, n = total = 0.</summary>
/// <param name="AAction">The verb or LSP method ('' = idle).</param>
/// <remarks>
/// Thread-safe; cheap (one critical section). Every Beat* call advances Seq.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Core.ControlChannel.BeatChannelOpen (DRagLint.Core.ControlChannel.pas), DRagLint.LSP.Server.TLSPServer.Run (DRagLint.LSP.Server.pas)</para>
/// <para>Calls: DRagLint.Core.ControlChannel.BeatMarkLocked</para>
/// <seealso cref="DRagLint.Core.ControlChannel.BeatMarkLocked"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure BeatBegin(const AAction: string);

/// <summary>Starts a new step inside the current action: n = 0, total = ATotal.</summary>
/// <param name="AStep">The phase name.</param>
/// <param name="ATotal">Denominator of the step's counter; 0 = unknown.</param>
/// <remarks>
/// Thread-safe.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Analysis.PurityStage.TPurityRun.Execute (DRagLint.Analysis.PurityStage.pas), DRagLint.CLI.CycleFix.ReportWaitProgress (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.Stage (DRagLint.CLI.pas), DRagLint.CLI.TLintPhaseProfiler.Phase (DRagLint.CLI.pas), DRagLint.Storage.SQLite.BeatStreamOpen (DRagLint.Storage.SQLite.pas)</para>
/// <para>Calls: DRagLint.Core.ControlChannel.BeatMarkLocked</para>
/// <seealso cref="DRagLint.Core.ControlChannel.BeatMarkLocked"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure BeatStep(const AStep: string; ATotal: Int64 = 0);

/// <summary>Reports progress inside the current step.</summary>
/// <param name="AN">The new counter; negative = one more than before.</param>
/// <param name="ATotal">New denominator; negative = unchanged.</param>
/// <remarks>
/// Thread-safe; safe to call from hot loops (one critical section, no allocation).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Analysis.PurityStage.TPurityRun.ScanFiles (DRagLint.Analysis.PurityStage.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), [dclDragLintWizard]DRagLint.Core.ControlChannel.BeatTestHold (DRagLint.Core.ControlChannel.pas), DRagLint.Core.Indexer.TIndexer.ReportProgress (DRagLint.Core.Indexer.pas), DRagLint.Storage.SQLite.ResolveLog (DRagLint.Storage.SQLite.pas)</para>
/// <para>Calls: DRagLint.Core.ControlChannel.BeatMarkLocked</para>
/// <seealso cref="DRagLint.Core.ControlChannel.BeatMarkLocked"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure BeatProgress(AN: Int64 = -1; ATotal: Int64 = -1);

/// <summary>A copy of the status record, with AgeMs computed now.</summary>
/// <returns>The snapshot; Seq = 0 when nothing was reported yet.</returns>
/// <remarks>
/// Thread-safe; one critical section.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.TStageHeartbeat.CheckStall (DRagLint.CLI.pas), DRagLint.CLI.TStageHeartbeat.ProgressSuffix (DRagLint.CLI.pas), DRagLint.Core.ControlChannel.TControlListener.Serve (DRagLint.Core.ControlChannel.pas)</para>
/// <para>Calls: Int64</para>
/// <para>Returns: GBeat</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BeatSnapshot: TEngineBeat;

/// <summary>TEST SEAM: holds the caller for DRAGLINT_TEST_RESOLVE_DELAY_MS, as a stalled stage would.</summary>
/// <remarks>
/// Unset / 0 = returns at once. With DRAGLINT_TEST_BEAT_MOVES set the hold reports progress as it
/// waits, which is a genuinely slow stage with a moving counter. Lives here, not in the resolve pass, so the
/// guards that use it can change without touching resolver surface.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Storage.SQLite.TSQLiteSymbolStore.ResolveCallTargets (DRagLint.Storage.SQLite.pas)</para>
/// <para>Calls: DRagLint.Core.ControlChannel.BeatProgress, GetEnvironmentVariable, Sleep, StrToIntDef, UInt64</para>
/// <seealso cref="DRagLint.Core.ControlChannel.BeatProgress"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure BeatTestHold;

/// <summary>One-line human text for a snapshot, e.g. <c>index: resolve 120/400</c>.</summary>
/// <param name="ABeat">The snapshot.</param>
/// <returns>The text; 'idle' for an empty action.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoShutdown (DRagLint.CLI.pas), [dclDragLintWizard]DragLint.Plugin.LspClient.TDragLintLspClient.SampleEngineBeat (DragLint.Plugin.LspClient.pas), [dclDragLintWizard]DragLint.Plugin.ProcRun.RunCore.CheckBeat (DragLint.Plugin.ProcRun.pas), DRagLint.Storage.FileMembership.BeatAwareBusy (DRagLint.Storage.FileMembership.pas)</para>
/// <para>Calls: IntToStr</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BeatDisplayText(const ABeat: TEngineBeat): string;

/// <summary>Asks the engine with process id APid for its heartbeat.</summary>
/// <param name="APid">Engine process id.</param>
/// <param name="AConnectTimeoutMs">How long to wait for a free pipe instance.</param>
/// <param name="ABeat">The snapshot on success.</param>
/// <returns>True when the engine answered with a beat field. False = no heartbeat (no pipe -- an older engine,
/// a wrapper process, a verb that does not report -- or no answer).</returns>
/// <remarks>
/// Blocks at most about AConnectTimeoutMs plus the listener's reply (immediate: a status-only
/// listener does no work). Any thread.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoShutdown (DRagLint.CLI.pas), [dclDragLintWizard]DragLint.Plugin.LspClient.TDragLintLspClient.SampleEngineBeat (DragLint.Plugin.LspClient.pas), [dclDragLintWizard]DragLint.Plugin.ProcRun.RunCore.CheckBeat (DragLint.Plugin.ProcRun.pas)</para>
/// <para>Calls: Default, DRagLint.Core.ControlChannel.BeatPipeNameFor, DRagLint.Core.ControlChannel.ControlRequest, DRagLint.Core.ControlChannel.ParseBeatReply</para>
/// <para>Returns: ControlRequest(BeatPipeNameFor(APid), CONTROL_MSG_STATUS + #9 + CONTROL_STATUS_ARG_BEAT, AConnectTimeoutMs, Reply, Err)</para>
/// <para>Mutates: ABeat (out)</para>
/// <seealso cref="DRagLint.Core.ControlChannel.BeatPipeNameFor"/>
/// <seealso cref="DRagLint.Core.ControlChannel.ControlRequest"/>
/// <seealso cref="DRagLint.Core.ControlChannel.ParseBeatReply"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RequestEngineBeat(APid: Cardinal; AConnectTimeoutMs: Integer; out ABeat: TEngineBeat): Boolean;

/// <summary>Opens the process-wide heartbeat pipe for verb ACommand and starts the status record's action as
/// ACommand -- for lsp, index, lint-all, lint, context and 'cycles --fix' (the CLI's name for `cycles` run
/// with --fix), the verbs the IDE plugin waits on.</summary>
/// <param name="ACommand">The CLI verb.</param>
/// <param name="AVersion">DRAGLINT_VERSION.</param>
/// <param name="AExtractor">DRAGLINT_EXTRACTOR_VERSION.</param>
/// <returns>True when listening. False when the verb does not report, a beat pipe is already open, or the pipe
/// could not be created (the run proceeds without one; nothing is printed -- the heartbeat is advisory).</returns>
/// <exception cref="EInvalidOperation"><!-- drag-lint:auto exc -->via DRagLint.Core.ControlChannel.TControlChannel.Create: TControlChannel must be created on the main thread -- the one the listener has to wake</exception>
/// <remarks>
/// Main thread only. The pipe closes at unit finalization. Its name: <c>\\.\pipe\drag-lint-beat-&lt;sid&gt;-s&lt;session&gt;-p&lt;pid&gt;</c>.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Run (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Core.ControlChannel.BeatBegin, DRagLint.Core.ControlChannel.BeatChannelEnabledFor, DRagLint.Core.ControlChannel.TControlChannel.Create, DRagLint.Core.ControlChannel.TControlChannel.Start, FreeAndNil</para>
/// <para>Returns: False</para>
/// <seealso cref="DRagLint.Core.ControlChannel.BeatBegin"/>
/// <seealso cref="DRagLint.Core.ControlChannel.BeatChannelEnabledFor"/>
/// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Create"/>
/// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Start"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BeatChannelOpen(const ACommand, AVersion, AExtractor: string): Boolean;

{ ---- WRITER PUBLICATION (1.41 SQLITE-BUSY-BEAT, owner ruling 2026-11-01) ----
  A second writer that meets SQLITE_BUSY waits as long as the HOLDER's beat seq
  advances. To find the holder it asks every other engine's heartbeat pipe
  `status<TAB>beat<TAB>writing`; an engine answers `writing=<db>|<db>...` with
  the databases it has a writer store open on. Asked only with `writing`, so
  every older parser keeps its reply shape. Spec:
  docs\superpowers\specs\2026-11-03-store-busybeat-halfread-design.md. ------ }

const
  /// <summary>Argument of a <c>status</c> request that asks for the writer field.</summary>
  CONTROL_STATUS_ARG_WRITING = 'writing';
  /// <summary>Prefix of the writer field of a status reply; the paths follow, separated by '|'.</summary>
  CONTROL_WRITING_FIELD_PREFIX = 'writing=';

type
  /// <summary>One other engine that has a writer store open on a database, and its heartbeat.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: [dclDragLintWizard]declaration (DRagLint.Core.ControlChannel.pas) ?, [dclDragLintWizard]DRagLint.Core.ControlChannel.SnapshotWritingBeats (DRagLint.Core.ControlChannel.pas), DRagLint.Storage.FileMembership.BeatAwareBusy (DRagLint.Storage.FileMembership.pas)</para>
  /// <para>Used in units: DRagLint.Core.ControlChannel, DRagLint.Storage.FileMembership</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TWritingBeat = record
    /// <summary>The engine's process id.</summary>
    Pid : Cardinal   ;
    /// <summary>Its heartbeat at snapshot time; Beat.Seq is the progress test.</summary>
    Beat: TEngineBeat;
  end;

/// <summary>Records that this process opened a writer store on ADbPath (refcounted).</summary>
/// <param name="ADbPath">The database path; compared as a lower-cased full path.</param>
/// <remarks>
/// Thread-safe. Pair every call with BeatWriterClosed.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Storage.FileMembership.ArmBeatAwareWait (DRagLint.Storage.FileMembership.pas)</para>
/// <para>Calls: DRagLint.Core.ControlChannel.WriterKey</para>
/// <seealso cref="DRagLint.Core.ControlChannel.WriterKey"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure BeatWriterOpened(const ADbPath: string);

/// <summary>Undoes one BeatWriterOpened for ADbPath; the path leaves the writer field at refcount 0.</summary>
/// <param name="ADbPath">The database path given to BeatWriterOpened.</param>
/// <remarks>
/// Thread-safe; a path that was never opened is ignored.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Storage.FileMembership.DisarmBeatAwareWait (DRagLint.Storage.FileMembership.pas)</para>
/// <para>Calls: DRagLint.Core.ControlChannel.WriterKey</para>
/// <seealso cref="DRagLint.Core.ControlChannel.WriterKey"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure BeatWriterClosed(const ADbPath: string);

/// <summary>Asks every OTHER engine of this user and session, on its heartbeat pipe, which databases it
/// writes, and returns those that write ADbPath with their heartbeat.</summary>
/// <param name="ADbPath">The database a writer waits on.</param>
/// <param name="AConnectTimeoutMs">Per-pipe wait for a free instance.</param>
/// <returns>One entry per engine whose writer field names ADbPath; empty when none answers so -- an engine
/// older than 1.41, a verb without a heartbeat pipe, or a writer that is not drag-lint.</returns>
/// <remarks>
/// Any thread. Blocks at most about AConnectTimeoutMs per listed pipe. Never raises.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Storage.FileMembership.BeatAwareBusy (DRagLint.Storage.FileMembership.pas)</para>
/// <para>Calls: Default, DRagLint.Core.ControlChannel.ControlRequest, DRagLint.Core.ControlChannel.CurrentSessionId, DRagLint.Core.ControlChannel.CurrentUserSidString, DRagLint.Core.ControlChannel.ParseBeatReply, DRagLint.Core.ControlChannel.ReplyWrites, DRagLint.Core.ControlChannel.WriterKey, FindFirstFileW, FindNextFileW, IntToStr, SameText, StrToIntDef</para>
/// <para>Catches: Exception (swallowed)</para>
/// <seealso cref="DRagLint.Core.ControlChannel.ControlRequest"/>
/// <seealso cref="DRagLint.Core.ControlChannel.CurrentSessionId"/>
/// <seealso cref="DRagLint.Core.ControlChannel.CurrentUserSidString"/>
/// <seealso cref="DRagLint.Core.ControlChannel.ParseBeatReply"/>
/// <seealso cref="DRagLint.Core.ControlChannel.ReplyWrites"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SnapshotWritingBeats(const ADbPath: string; AConnectTimeoutMs: Integer): TArray<TWritingBeat>;

type
  /// <summary>The engine side of the channel: one listener thread on the
  /// per-user pipe, and the hooks the host loop uses to cooperate.</summary>
  /// <remarks>
  /// <para>Create and Start on the MAIN thread (the one that blocks in the
  /// stdin read) -- Start duplicates the calling thread's handle so the
  /// listener can cancel that read. Create raises otherwise.</para>
  /// <para>Host contract: bracket the blocking read with EnterRead/LeaveRead,
  /// bracket each request with BeginWork/EndWork, test StandDownRequested at
  /// the top of the loop, and call StandDownComplete AFTER every store is
  /// closed -- the `exiting` reply is withheld until then. Then Free.</para>
  /// <para>Thread-safety: the host hooks are interlocked; the listener owns
  /// the pipe handles exclusively.</para>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: [dclDragLintWizard]declaration (DRagLint.Core.ControlChannel.pas) ?, DRagLint.CLI.CycleFix.StartStandDownChannel (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.DoWarmRuleCache (DRagLint.CLI.pas), DRagLint.CLI.Run (DRagLint.CLI.pas), [dclDragLintWizard]DRagLint.Core.ControlChannel.BatchChannelOpen (DRagLint.Core.ControlChannel.pas), [dclDragLintWizard]DRagLint.Core.ControlChannel.BeatChannelOpen (DRagLint.Core.ControlChannel.pas), [dclDragLintWizard]DRagLint.Core.ControlChannel.TControlListener.Create (DRagLint.Core.ControlChannel.pas) ?, [dclDragLintWizard]DRagLint.Core.ControlChannel.TControlListener.ServeStandDown (DRagLint.Core.ControlChannel.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.CLI.CycleFix, DRagLint.Core.ControlChannel, DRagLint.LSP.Server</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TControlChannel = class
    private
      const
        ST_IDLE      = 0;
        ST_REQUESTED = 1;
        ST_TAKEN     = 2;
      var
        FDbs        : TArray<string>;
        FVersion    : string        ;
        FExtractor  : string        ;
        FRole       : string        ; { the verb hosting the channel: lsp, index, lint-all, cycles, warm-rule-cache }
        FPipeName   : string        ;
        FOwnerSid   : string        ;
        FSD         : Pointer       ; { self-relative SECURITY_DESCRIPTOR from SDDL; LocalFree'd }
        FSA         : TSecurityAttributes;
        FMainThread : THandle       ;
        FListener   : TThread       ;
        FFirstPipe  : THandle       ;
        FState      : Integer       ; { ST_* -- one interlocked word }
        FInRead     : Integer       ; { 1 while the host is inside its stdin read }
        FWorkLock   : TCriticalSection;
        FWork       : string        ;
        FDone       : TEvent        ; { StandDownComplete }
        FReplied    : TEvent        ; { the listener wrote its final reply }
        FRequested  : TEvent        ; { set while a stand-down request is pending or taken }
        FStatusOnly : Boolean       ; { 1.40 heartbeat pipe: answers status only; shutdown is `unknown` }
      /// <param name="AError"><!-- drag-lint:auto type -->out string</param>
      /// <returns><!-- drag-lint:auto type -->THandle</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Core.ControlChannel.TControlChannel.Start (DRagLint.Core.ControlChannel.pas), DRagLint.Core.ControlChannel.TControlListener.Execute (DRagLint.Core.ControlChannel.pas)</para>
      /// <para>Calls: CreateNamedPipeW, PChar, SysErrorMessage</para>
      /// <para>Mutates: AError (out)</para>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.BeginWork"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Create"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.CurrentWork"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Destroy"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.EndWork"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function CreatePipeInstance(out AError: string): THandle;
      /// <returns><!-- drag-lint:auto -->string -- Observed: FWork.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Core.ControlChannel.TControlListener.ServeStandDown (DRagLint.Core.ControlChannel.pas)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.BeginWork"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Create"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.CreatePipeInstance"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Destroy"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.EndWork"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function CurrentWork: string;
    public
      /// <summary>Prepares a channel describing the stores <paramref name="ADbs"/>.
      /// Nothing listens until Start.</summary>
      /// <param name="ADbs">Databases the engine holds -- what `status` reports.</param>
      /// <param name="AVersion">DRAGLINT_VERSION.</param>
      /// <param name="AExtractor">DRAGLINT_EXTRACTOR_VERSION.</param>
      /// <param name="ARole">The verb hosting the channel (lsp, index, lint-all, cycles,
      /// warm-rule-cache); a `status role` request reports it. '' = not reported (the
      /// reply keeps its pre-1.39.1 shape).</param>
      /// <param name="AStatusOnly">1.40: True = the HEARTBEAT pipe (BeatPipeNameFor, not ControlPipeNameFor):
      /// it answers `status` (with the beat field when asked) and nothing else -- a `shutdown` gets `unknown`
      /// and changes nothing.</param>
      /// <exception cref="EInvalidOperation">Not called on the main thread.</exception>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.CycleFix.StartStandDownChannel (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.DoWarmRuleCache (DRagLint.CLI.pas), DRagLint.CLI.Run (DRagLint.CLI.pas), DRagLint.Core.ControlChannel.BatchChannelOpen (DRagLint.Core.ControlChannel.pas), DRagLint.Core.ControlChannel.BeatChannelOpen (DRagLint.Core.ControlChannel.pas)</para>
      /// <para>Calls: Copy, DRagLint.Core.ControlChannel.BeatPipeNameFor, DRagLint.Core.ControlChannel.ControlPipeNameFor, DRagLint.Core.ControlChannel.CurrentUserSidString</para>
      /// <para>Pure</para>
      /// <para>constructor</para>
      /// <seealso cref="DRagLint.Core.ControlChannel.BeatPipeNameFor"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.ControlPipeNameFor"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.CurrentUserSidString"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.BeginWork"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.CreatePipeInstance"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(const ADbs: TArray<string>; const AVersion, AExtractor: string; const ARole: string = '';
        AStatusOnly: Boolean = False);
      /// <summary>Stops the listener (bounded wait) and releases the pipe.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: CloseHandle, CreateFileW, FreeAndNil, HLOCAL, InterlockedCompareExchange, LocalFree, PChar, WaitForSingleObject, WaitNamedPipeW</para>
      /// <para>Complexity: 13 (cyclomatic, outer body), 42 lines (full implementation)</para>
      /// <para>Pure</para>
      /// <para>Directives: override</para>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.BeginWork"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Create"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.CreatePipeInstance"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.CurrentWork"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.EndWork"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      destructor Destroy; override;
      /// <summary>Builds the DACL, creates the first pipe instance and starts
      /// the listener. Synchronous, so the pipe exists before this returns.</summary>
      /// <param name="AError">Why it could not listen; '' on success.</param>
      /// <returns>True when listening.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.CycleFix.StartStandDownChannel (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.DoWarmRuleCache (DRagLint.CLI.pas), [dclDragLintWizard]DRagLint.Core.ControlChannel.BatchChannelOpen (DRagLint.Core.ControlChannel.pas), [dclDragLintWizard]DRagLint.Core.ControlChannel.BeatChannelOpen (DRagLint.Core.ControlChannel.pas), [dclDragLintWizard]DragLint.Plugin.About.StartBackgroundSelfInfoFetch (DragLint.Plugin.About.pas) ?, [dclDragLintWizard]DragLint.Plugin.Editor.InvokeReverseCallTreeMessages (DragLint.Plugin.Editor.pas) ?, [dclDragLintWizard]DragLint.Plugin.Editor.RunCompileDiagnoseAsync (DragLint.Plugin.Editor.pas) ?, [dclDragLintWizard]DragLint.Plugin.Editor.RunFullCompileSweepAsync (DragLint.Plugin.Editor.pas) ?, [dclDragLintWizard]DragLint.Plugin.Editor.RunGhostCheckAsync (DragLint.Plugin.Editor.pas) ?, [dclDragLintWizard]DragLint.Plugin.Editor.RunGhostRecoverFor (DragLint.Plugin.Editor.pas) ?,
      /// [dclDragLintWizard]DragLint.Plugin.LiveDiagnostics.TLiveRunner.OnTick (DragLint.Plugin.LiveDiagnostics.pas) ?</para>
      /// <para>Calls: DRagLint.Core.ControlChannel.ConvertStringSecurityDescriptorToSecurityDescriptorW, DRagLint.Core.ControlChannel.TControlChannel.CreatePipeInstance, DRagLint.Core.ControlChannel.TControlListener.Create, DuplicateHandle, PChar, SysErrorMessage</para>
      /// <para>Returns: False; True</para>
      /// <para>Mutates: AError (out)</para>
      /// <seealso cref="DRagLint.Core.ControlChannel.ConvertStringSecurityDescriptorToSecurityDescriptorW"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.CreatePipeInstance"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlListener.Create"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.BeginWork"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function Start(out AError: string): Boolean;
      /// <summary>Full name of the pipe this engine listens on.</summary>
      property PipeName: string read FPipeName;
      /// <summary>SID string the DACL grants -- the only trustee.</summary>
      property OwnerSid: string read FOwnerSid;
      /// <summary>A manual-reset event, signalled the instant a stand-down
      /// request arrives and reset if the listener withdraws it.</summary>
      /// <returns>The event's handle; owned by the channel, valid until Free.</returns>
      /// <remarks>
      /// For a host that blocks in something other than the stdin read
      /// (`cycles --fix` waiting on a build): it waits on this beside its child,
      /// then takes the request with StandDownRequested. Taking it commits the
      /// host to exiting; the event stays set from then on.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.CycleFix.RunBounded (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.DoWarmRuleCache (DRagLint.CLI.pas)</para>
      /// <para>Returns: FRequested.Handle</para>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.BeginWork"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Create"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.CreatePipeInstance"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.CurrentWork"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function RequestEvent: THandle;
      /// <summary>Host hook: True exactly once, when a stand-down request is
      /// pending; taking it commits the host to exiting.</summary>
      /// <returns>True when the host must leave its loop.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.CycleFix.TakeStandDown (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.DoWarmRuleCache (DRagLint.CLI.pas), DRagLint.Core.ControlChannel.BatchStandDownTaken (DRagLint.Core.ControlChannel.pas), DRagLint.LSP.Server.TLSPServer.StandDownTaken (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: InterlockedCompareExchange</para>
      /// <para>Returns: InterlockedCompareExchange(FState, ST_TAKEN, ST_REQUESTED) = ST_REQUESTED</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.BeginWork"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Create"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.CreatePipeInstance"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.CurrentWork"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function StandDownRequested: Boolean;
      /// <summary>Host hook: the host is about to block in its stdin read.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ReadMessageGuarded (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: InterlockedExchange</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.BeginWork"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Create"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.CreatePipeInstance"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.CurrentWork"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure EnterRead;
      /// <summary>Host hook: the stdin read returned.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.ReadMessageGuarded (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: InterlockedExchange</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.BeginWork"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Create"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.CreatePipeInstance"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.CurrentWork"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure LeaveRead;
      /// <summary>Host hook: a request is being handled (named in a `busy` reply).</summary>
      /// <param name="AWhat">The method name.</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Core.ControlChannel.TControlChannel.EndWork (DRagLint.Core.ControlChannel.pas), DRagLint.LSP.Server.TLSPServer.Run (DRagLint.LSP.Server.pas)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Create"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.CreatePipeInstance"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.CurrentWork"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Destroy"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.EndWork"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure BeginWork(const AWhat: string);
      /// <summary>Host hook: the request is done.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.LSP.Server.TLSPServer.Run (DRagLint.LSP.Server.pas)</para>
      /// <para>Calls: DRagLint.Core.ControlChannel.TControlChannel.BeginWork</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.BeginWork"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Create"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.CreatePipeInstance"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.CurrentWork"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure EndWork;
      /// <summary>Host hook: every store is closed; the `exiting` reply may go.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.CycleFix.RunCycleFix (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.DoWarmRuleCache (DRagLint.CLI.pas), [dclDragLintWizard]DRagLint.Core.ControlChannel.BatchChannelClose (DRagLint.Core.ControlChannel.pas)</para>
      /// <para>Calls: DRagLint.Core.ControlChannel.HangStoreCloseForTests, InterlockedCompareExchange</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.ControlChannel.HangStoreCloseForTests"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.BeginWork"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Create"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.CreatePipeInstance"/>
      /// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.CurrentWork"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure StandDownComplete;
  end;


const
  /// <summary>Exit code of a batch verb (index, lint-all) that stopped on a maintenance stand-down: it did NOT finish, it left no half-written state, and re-running the same command resumes.</summary>
  CONTROL_EXIT_STOOD_DOWN = 4;

/// <summary>Opens the process-wide control channel of a long one-shot verb, when ControlChannelEnabledFor(ACommand).</summary>
/// <param name="ACommand">The CLI verb.</param>
/// <param name="ADbs">Databases the run writes or reads -- what status reports.</param>
/// <param name="AVersion">DRAGLINT_VERSION.</param>
/// <param name="AExtractor">DRAGLINT_EXTRACTOR_VERSION.</param>
/// <param name="ASilent">True under a machine-readable output format: the 'listening' line is not written (stderr stays empty on the success path); the channel still opens. A failure to open is still said.</param>
/// <returns>True when listening. False when the verb does not listen, a channel is already open, or the pipe could not be created (said on stderr; the run proceeds without it).</returns>
/// <exception cref="EInvalidOperation"><!-- drag-lint:auto exc -->via DRagLint.Core.ControlChannel.TControlChannel.Create: TControlChannel must be created on the main thread -- the one the listener has to wake</exception>
/// <remarks>
/// Main thread only. Pair with BatchChannelClose in a finally.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoIndexAll (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Core.ControlChannel.ControlChannelEnabledFor, DRagLint.Core.ControlChannel.TControlChannel.Create, DRagLint.Core.ControlChannel.TControlChannel.Start, FreeAndNil, Writeln</para>
/// <para>Returns: False; True</para>
/// <seealso cref="DRagLint.Core.ControlChannel.ControlChannelEnabledFor"/>
/// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Create"/>
/// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Start"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BatchChannelOpen(const ACommand: string; const ADbs: TArray<string>; const AVersion, AExtractor: string; ASilent: Boolean = False): Boolean;

/// <summary>True once a maintenance stand-down request has been taken by this batch run.</summary>
/// <returns>True when the run must stop at its next safe point; sticky once true.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoIndexAll (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.CLI.InstallIndexStandDownGate (DRagLint.CLI.pas), DRagLint.CLI.WatchIdle (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Core.ControlChannel.TControlChannel.StandDownRequested</para>
/// <para>Returns: GBatchTaken</para>
/// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.StandDownRequested"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BatchStandDownTaken: Boolean;

/// <summary>Releases the batch channel; when a request was taken, answers `exiting` first.</summary>
/// <remarks>
/// Call AFTER every store is closed. Safe when no channel is open.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.InstallIndexStandDownGate (DRagLint.CLI.pas), DRagLint.CLI.Run (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Core.ControlChannel.TControlChannel.StandDownComplete, FreeAndNil</para>
/// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.StandDownComplete"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure BatchChannelClose;

/// <summary>Pipe name of the open batch channel, '' when none.</summary>
/// <returns><!-- drag-lint:auto -->string -- Observed: ''.</returns>
function BatchChannelPipeName: string;
implementation

uses
  System.IOUtils
  , System.DateUtils
  , System.StrUtils { MatchText: BeatChannelEnabledFor }
  , System.Generics.Collections { TDictionary: GWriterDbs }
  , DRagLint.Core.OutputEncoding { EncodeForOutput: these lines bypass ErrOutput }
  ;

type
  TControlListener = class(TThread)
    private
      FOwner: TControlChannel;
      procedure AcceptAndServe(APipe: THandle);
      procedure Serve(APipe: THandle);
      procedure ServeStandDown(APipe: THandle; AWaitMs: Integer);
      procedure Reply(APipe: THandle; const ALine: string);
      function RequesterText(APipe: THandle): string;
    protected
      procedure Execute; override;
    public
      constructor Create(AOwner: TControlChannel);
  end;

const
  MAX_MSG                          = 4096;
  CC_IO_BUF_BYTES                  = 512;   { one ReadFile chunk; a message is a few hundred bytes }
  CC_POLL_MS                       = 25;    { listener's wait slice between cancel attempts }
  CC_STORE_CLOSE_GRACE_MS          = 60000; { after the read is cancelled, how long the host may take to close stores }
  CC_RETRY_MS                      = 200;   { back-off when CreateNamedPipe transiently fails }
  CC_WAKE_PIPE_MS                  = 100;   { teardown: WaitNamedPipe for the throwaway wake-up client }
  CC_WAKE_POLL_MS                  = 150;   { teardown: per-attempt wait for the listener to notice Terminated }
  CC_REPLY_JOIN_MS                 = 5000;  { teardown while a reply is being written: let it finish }
  CC_LISTENER_JOIN_MS              = 3000;  { teardown: bounded final join, then detach (never freeze exit) }
  CC_WAKE_ATTEMPTS                 = 10;
  CC_LF                            = 10;    { the one-line wire terminator }
  CC_NO_WAIT_MS                    = 0;     { TEvent.WaitFor poll: is it signalled right now }
  PIPE_PREFIX_FULL                 = '\\.\pipe\';
  CC_FILE_FLAG_FIRST_PIPE_INSTANCE = $00080000;
  CC_PIPE_REJECT_REMOTE_CLIENTS    = $00000008;
  CC_SDDL_REVISION_1               = 1;
  CC_THREAD_TERMINATE              = $0001; { the access CancelSynchronousIo needs on the thread handle }
  AUDIT_DIR_NAME                   = 'drag-lint';
  AUDIT_FILE_NAME                  = 'control-channel-audit.log';
  TEST_HANG_STORE_CLOSE_VAR        = 'DRAGLINT_TEST_HANG_STORE_CLOSE_MS';
  TEST_STORE_CLOSE_GRACE_VAR       = 'DRAGLINT_TEST_STORE_CLOSE_GRACE_MS';

{ TEST SEAM, inert unless the environment variable names a positive number of
  milliseconds: DRAGLINT_TEST_STORE_CLOSE_GRACE_MS replaces CC_STORE_CLOSE_GRACE_MS so
  run_control_channel_guard.ps1 (section H) can reach the 'stand-down started but
  not finished' reply in seconds instead of a minute. }
function StoreCloseGraceMs: Cardinal;
var
  V: Integer;
begin
  V:= StrToIntDef(GetEnvironmentVariable(TEST_STORE_CLOSE_GRACE_VAR), 0);
  Result:= if V > 0 then Cardinal(V) else CC_STORE_CLOSE_GRACE_MS;
end;

{ TEST SEAM, inert unless set: DRAGLINT_TEST_HANG_STORE_CLOSE_MS=N makes
  StandDownComplete sleep N ms before signalling FDone -- a host whose store
  close hangs (run_control_channel_guard.ps1 section H). }
procedure HangStoreCloseForTests;
var
  V: Integer;
begin
  V:= StrToIntDef(GetEnvironmentVariable(TEST_HANG_STORE_CLOSE_VAR), 0);
  if V > 0 then Sleep(V);
end;

{ Not in Winapi.Windows (checked against the RTL source, not assumed). }
function ConvertStringSecurityDescriptorToSecurityDescriptorW(StringSecurityDescriptor: LPCWSTR; StringSDRevision: DWORD;
  var SecurityDescriptor: Pointer; SecurityDescriptorSize: PULONG): BOOL; stdcall; external advapi32;
function QueryFullProcessImageNameW(hProcess: THandle; dwFlags: DWORD; lpExeName: LPWSTR; var lpdwSize: DWORD): BOOL; stdcall; external kernel32;

{ ---- gate ---------------------------------------------------------------- }

function ControlChannelEnabledFor(const ACommand: string): Boolean;
begin
  { PROVISIONAL -- see the interface remarks. `lsp`, `cycles` (its --fix run), and (DEC-13, 2026-10-28)
    the long one-shot runs `index` and `lint-all`. }
  Result:= SameText(ACommand, 'lsp') or SameText(ACommand, 'cycles') or SameText(ACommand, 'index')
    or SameText(ACommand, 'lint-all') or SameText(ACommand, 'warm-rule-cache');
end;

{ ---- batch channel (DEC-13) ---------------------------------------------- }

var
  GBatchChannel: TControlChannel;
  GBatchTaken  : Boolean;

function BatchChannelOpen(const ACommand: string; const ADbs: TArray<string>; const AVersion, AExtractor: string; ASilent: Boolean): Boolean;
var
  Err: string;
begin
  Result:= False;
  if (GBatchChannel <> nil) or not ControlChannelEnabledFor(ACommand) then Exit;
  GBatchTaken:= False;
  GBatchChannel:= TControlChannel.Create(ADbs, AVersion, AExtractor, ACommand);
  if GBatchChannel.Start(Err) then
  begin
    if not ASilent then
      Writeln(ErrOutput, 'drag-lint ', ACommand, ': control channel listening on ', GBatchChannel.PipeName, ' (accepts status and shutdown)');
    Exit(True);
  end;
  Writeln(ErrOutput, 'drag-lint ', ACommand, ': control channel NOT started: ', Err);
  FreeAndNil(GBatchChannel);
end;

function BatchStandDownTaken: Boolean;
begin
  if GBatchChannel = nil then Exit(False);
  if not GBatchTaken then GBatchTaken:= GBatchChannel.StandDownRequested;
  Result:= GBatchTaken;
end;

procedure BatchChannelClose;
begin
  if GBatchChannel = nil then Exit;
  if GBatchTaken then GBatchChannel.StandDownComplete;
  FreeAndNil(GBatchChannel);
end;

function BatchChannelPipeName: string;
begin
  if GBatchChannel = nil then Result:= '' else Result:= GBatchChannel.PipeName;
end;

{ ---- heartbeat (1.40) ------------------------------------------------------ }

const
  BEAT_SEP = '|';

var
  GBeatLock   : TCriticalSection; { guards GBeat and GBeatTick; lives for the unit's lifetime }
  GBeat       : TEngineBeat;      { AgeMs is not kept here: BeatSnapshot computes it from GBeatTick }
  GBeatTick   : UInt64;           { GetTickCount64 of the last report }
  GBeatChannel: TControlChannel;  { the status-only listener, nil when this verb does not report }

{ Under GBeatLock: one more report. }
procedure BeatMarkLocked;
begin
  Inc(GBeat.Seq);
  GBeatTick:= GetTickCount64;
end;

procedure BeatBegin(const AAction: string);
begin
  GBeatLock.Enter;
  try
    GBeat.Action:= AAction;
    GBeat.Step  := '';
    GBeat.N     := 0;
    GBeat.Total := 0;
    BeatMarkLocked;
  finally
    GBeatLock.Leave;
  end;
end;

procedure BeatStep(const AStep: string; ATotal: Int64 = 0);
begin
  GBeatLock.Enter;
  try
    GBeat.Step := AStep;
    GBeat.N    := 0;
    GBeat.Total:= ATotal;
    BeatMarkLocked;
  finally
    GBeatLock.Leave;
  end;
end;

procedure BeatProgress(AN: Int64 = -1; ATotal: Int64 = -1);
begin
  GBeatLock.Enter;
  try
    GBeat.N:= if AN < 0 then GBeat.N + 1 else AN;
    if ATotal >= 0 then GBeat.Total:= ATotal;
    BeatMarkLocked;
  finally
    GBeatLock.Leave;
  end;
end;

procedure BeatTestHold;
const
  HOLD_SLICE_MS = 20;
var
  T0   : UInt64;
  Hold : Integer;
  Moves: Boolean;
begin
  Hold:= StrToIntDef(GetEnvironmentVariable('DRAGLINT_TEST_RESOLVE_DELAY_MS'), 0);
  if Hold <= 0 then Exit;
  Moves:= GetEnvironmentVariable('DRAGLINT_TEST_BEAT_MOVES') <> '';
  T0:= GetTickCount64;
  while GetTickCount64 - T0 < UInt64(Hold) do
  begin
    Sleep(HOLD_SLICE_MS);
    if Moves then BeatProgress;
  end;
end;

function BeatSnapshot: TEngineBeat;
begin
  GBeatLock.Enter;
  try
    Result:= GBeat;
    Result.AgeMs:= if GBeat.Seq = 0 then 0 else Int64(GetTickCount64 - GBeatTick);
  finally
    GBeatLock.Leave;
  end;
end;

{ A name on the wire: the field separator, TAB and control characters become '_'. }
function BeatClean(const S: string): string;
var
  I: Integer;
begin
  Result:= S;
  for I:= 1 to Length(Result) do
    if (Result[I] < ' ') or (Result[I] = BEAT_SEP) then Result[I]:= '_';
end;

function BeatFieldText(const ABeat: TEngineBeat): string;
begin
  Result:= CONTROL_BEAT_FIELD_PREFIX + IntToStr(ABeat.Seq) + BEAT_SEP + BeatClean(ABeat.Action) + BEAT_SEP +
           BeatClean(ABeat.Step) + BEAT_SEP + IntToStr(ABeat.N) + BEAT_SEP + IntToStr(ABeat.Total) + BEAT_SEP +
           IntToStr(ABeat.AgeMs);
end;

function ParseBeatReply(const AReply: string; out ABeat: TEngineBeat): Boolean;
const
  BEAT_PARTS = 6; { seq, action, step, n, total, age -- in that order }
  I_SEQ    = 0;
  I_ACTION = 1;
  I_STEP   = 2;
  I_N      = 3;
  I_TOTAL  = 4;
  I_AGE    = 5;
var
  Field: string;
  Parts: TArray<string>;
begin
  ABeat:= Default(TEngineBeat);
  for Field in AReply.TrimRight([#13, #10]).Split([#9]) do
  begin
    if not Field.StartsWith(CONTROL_BEAT_FIELD_PREFIX, True) then Continue;
    Parts:= Field.Substring(Length(CONTROL_BEAT_FIELD_PREFIX)).Split([BEAT_SEP]);
    if Length(Parts) <> BEAT_PARTS then Exit(False);
    ABeat.Seq   := StrToInt64Def(Parts[I_SEQ], -1);
    ABeat.Action:= Parts[I_ACTION];
    ABeat.Step  := Parts[I_STEP];
    ABeat.N     := StrToInt64Def(Parts[I_N], 0);
    ABeat.Total := StrToInt64Def(Parts[I_TOTAL], 0);
    ABeat.AgeMs := StrToInt64Def(Parts[I_AGE], 0);
    Exit(ABeat.Seq >= 0);
  end;
  Result:= False;
end;

function BeatDisplayText(const ABeat: TEngineBeat): string;
begin
  if ABeat.Action = '' then Exit('idle');
  Result:= ABeat.Action;
  if ABeat.Step <> '' then Result:= Result + ': ' + ABeat.Step;
  if ABeat.Total > 0 then Result:= Result + ' ' + IntToStr(ABeat.N) + '/' + IntToStr(ABeat.Total)
  else if ABeat.N > 0 then Result:= Result + ' ' + IntToStr(ABeat.N);
end;

function BeatPipeNameFor(APid: Cardinal): string;
begin
  Result:= PIPE_PREFIX_FULL + BEAT_PIPE_PREFIX + CurrentUserSidString + '-s' + IntToStr(CurrentSessionId) + '-p' + IntToStr(APid);
end;

function RequestEngineBeat(APid: Cardinal; AConnectTimeoutMs: Integer; out ABeat: TEngineBeat): Boolean;
var
  Reply, Err: string;
begin
  ABeat:= Default(TEngineBeat);
  Result:= ControlRequest(BeatPipeNameFor(APid), CONTROL_MSG_STATUS + #9 + CONTROL_STATUS_ARG_BEAT, AConnectTimeoutMs, Reply, Err)
           and ParseBeatReply(Reply, ABeat);
end;

function BeatChannelEnabledFor(const ACommand: string): Boolean;
begin
  { 'cycles --fix' (lane 142-cyc, owner ruling D4): the CLI passes it for `cycles --fix` only, so a plain
    `cycles` list query keeps being judged by its CPU (no heartbeat that would stand still while it works) }
  Result:= MatchText(ACommand, ['lsp', 'index', 'lint-all', 'lint', 'context', 'cycles --fix']);
end;

function BeatChannelOpen(const ACommand, AVersion, AExtractor: string): Boolean;
var
  Err: string;
begin
  Result:= False;
  if (GBeatChannel <> nil) or not BeatChannelEnabledFor(ACommand) then Exit;
  BeatBegin(ACommand);
  GBeatChannel:= TControlChannel.Create([], AVersion, AExtractor, ACommand, {AStatusOnly=}True);
  if GBeatChannel.Start(Err) then Exit(True);
  FreeAndNil(GBeatChannel); { advisory: a run without a heartbeat is judged the old way by the plugin }
end;

procedure BeatChannelClose;
begin
  FreeAndNil(GBeatChannel);
end;

{ ---- writer publication (1.41) -------------------------------------------- }

const
  WRITING_SEP = '|'; { a Windows path cannot contain it }

var
  GWriterDbs: TDictionary<string, Integer>; { lower-cased full path -> open writer stores; under GBeatLock }

function WriterKey(const ADbPath: string): string;
begin
  Result:= LowerCase(ExpandFileName(ADbPath));
end;

procedure BeatWriterOpened(const ADbPath: string);
var
  N: Integer;
begin
  GBeatLock.Enter;
  try
    if not GWriterDbs.TryGetValue(WriterKey(ADbPath), N) then N:= 0;
    GWriterDbs.AddOrSetValue(WriterKey(ADbPath), N + 1);
  finally
    GBeatLock.Leave;
  end;
end;

procedure BeatWriterClosed(const ADbPath: string);
var
  N: Integer;
begin
  GBeatLock.Enter;
  try
    if not GWriterDbs.TryGetValue(WriterKey(ADbPath), N) then Exit;
    if N <= 1 then GWriterDbs.Remove(WriterKey(ADbPath))
    else GWriterDbs[WriterKey(ADbPath)]:= N - 1;
  finally
    GBeatLock.Leave;
  end;
end;

function WritingFieldText: string;
var
  Keys: TArray<string>;
  I   : Integer       ;
begin
  GBeatLock.Enter;
  try
    Keys:= GWriterDbs.Keys.ToArray;
  finally
    GBeatLock.Leave;
  end;
  for I:= 0 to High(Keys) do Keys[I]:= BeatClean(Keys[I]);
  Result:= CONTROL_WRITING_FIELD_PREFIX + string.Join(WRITING_SEP, Keys);
end;

{ True when AReply carries a writer field that names AKey (a WriterKey). }
function ReplyWrites(const AReply, AKey: string): Boolean;
var
  Field, P: string;
begin
  for Field in AReply.Split([#9]) do
  begin
    if not Field.StartsWith(CONTROL_WRITING_FIELD_PREFIX, True) then Continue;
    for P in Field.Substring(Length(CONTROL_WRITING_FIELD_PREFIX)).Split([WRITING_SEP]) do
      if SameText(P, AKey) then Exit(True);
  end;
  Result:= False;
end;

function SnapshotWritingBeats(const ADbPath: string; AConnectTimeoutMs: Integer): TArray<TWritingBeat>;
var
  Mine : string         ;
  OwnLeaf: string         ;
  Key  : string         ;
  H    : THandle        ;
  Found: TWin32FindDataW;
  Leafs: TArray<string> ;
  Leaf : string         ;
  Reply: string         ;
  Err  : string         ;
  W    : TWritingBeat   ;
  P    : Integer        ;
begin
  SetLength(Result, 0);
  try
    Key  := WriterKey(ADbPath);
    Mine := BEAT_PIPE_PREFIX + CurrentUserSidString + '-s' + IntToStr(CurrentSessionId) + '-p';
    OwnLeaf:= Mine + IntToStr(GetCurrentProcessId);
    SetLength(Leafs, 0);
    H:= FindFirstFileW(PIPE_PREFIX_FULL + '*', Found);
    if H = INVALID_HANDLE_VALUE then Exit;
    try
      repeat
        Leaf:= Found.cFileName;
        if Leaf.StartsWith(Mine, True) and not SameText(Leaf, OwnLeaf) then Leafs:= Leafs + [Leaf];
      until not FindNextFileW(H, Found);
    finally
      Winapi.Windows.FindClose(H);
    end;
    for Leaf in Leafs do
    begin
      if not ControlRequest(PIPE_PREFIX_FULL + Leaf, CONTROL_MSG_STATUS + #9 + CONTROL_STATUS_ARG_BEAT + #9 +
        CONTROL_STATUS_ARG_WRITING, AConnectTimeoutMs, Reply, Err) then Continue;
      if not ReplyWrites(Reply, Key) then Continue;
      W:= Default(TWritingBeat);
      if not ParseBeatReply(Reply, W.Beat) then Continue;
      P:= Leaf.LastIndexOf('-p');
      W.Pid:= StrToIntDef(Leaf.Substring(P + 2), 0);
      Result:= Result + [W];
    end;
  except  // dl:ok try-except-swallowed@a8f7 -- REVIEWED 2026-11-03: a failed probe means no holder with a beat, which the waiter treats as the fixed timeout
    on E: Exception do SetLength(Result, 0); { no answer = no holder with a beat }
  end;
end;
{ ---- identity ------------------------------------------------------------ }

function CurrentUserSidString: string;
var
  Token  : THandle    ;
  Needed : DWORD      ;
  Buf    : TBytes     ;
  SidStr : LPWSTR     ;
begin
  Result:= '';
  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, Token) then Exit;
  try
    Needed:= 0;
    GetTokenInformation(Token, TokenUser, nil, 0, Needed);
    if Needed = 0 then Exit;
    SetLength(Buf, Needed);
    if not GetTokenInformation(Token, TokenUser, @Buf[0], Needed, Needed) then Exit;
    if ConvertSidToStringSidW(PTokenUser(@Buf[0])^.User.Sid, SidStr) then
    begin
      try
        Result:= SidStr;
      finally
        LocalFree(HLOCAL(SidStr));
      end;
    end;
  finally
    CloseHandle(Token);
  end;
end;

function CurrentSessionId: Cardinal;
var
  S: DWORD;
begin
  S:= 0;
  if not ProcessIdToSessionId(GetCurrentProcessId, S) then S:= 0;
  Result:= S;
end;

function ControlPipeLeafFor(APid: Cardinal): string;
begin
  Result:= CONTROL_PIPE_PREFIX + CurrentUserSidString + '-s' + IntToStr(CurrentSessionId) + '-p' + IntToStr(APid);
end;

function ControlPipeNameFor(APid: Cardinal): string;
begin
  Result:= PIPE_PREFIX_FULL + ControlPipeLeafFor(APid);
end;

function PidFromControlPipeLeaf(const APipeLeaf: string): Cardinal;
var
  P: Integer;
begin
  Result:= 0;
  if not APipeLeaf.StartsWith(CONTROL_PIPE_PREFIX, True) then Exit;
  P:= APipeLeaf.LastIndexOf('-p');
  if P < 0 then Exit;
  Result:= StrToIntDef(APipeLeaf.Substring(P + 2), 0);
end;

function ListControlPipesForThisUser: TArray<string>;
var
  Mine  : string          ;
  H     : THandle         ;
  Found : TWin32FindDataW ;
  Leaf  : string          ;
begin
  SetLength(Result, 0);
  { Everything up to the pid: the SID and the session are ours by construction,
    so another user's or another session's engines are never even listed. }
  Mine:= CONTROL_PIPE_PREFIX + CurrentUserSidString + '-s' + IntToStr(CurrentSessionId) + '-p';
  H:= FindFirstFileW(PIPE_PREFIX_FULL + '*', Found);
  if H = INVALID_HANDLE_VALUE then Exit;
  try
    repeat
      Leaf:= Found.cFileName;
      if Leaf.StartsWith(Mine, True) and (PidFromControlPipeLeaf(Leaf) > 0) then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)]:= PIPE_PREFIX_FULL + Leaf;
      end;
    until not FindNextFileW(H, Found);
  finally
    Winapi.Windows.FindClose(H);
  end;
end;

function ControlAuditLogPath: string;
var
  Base: string;
begin
  { Mirrors DRagLint.Core.EngineHold: LOCALAPPDATA is the one per-user place a
    shell, an editor and the IDE agree on; TEMP is per-process. }
  Base:= GetEnvironmentVariable('LOCALAPPDATA');
  if Base = '' then Base:= TPath.GetCachePath;
  if Base = '' then Base:= TPath.GetTempPath;
  Result:= TPath.Combine(TPath.Combine(Base, AUDIT_DIR_NAME), AUDIT_FILE_NAME);
end;

{ ---- wire ---------------------------------------------------------------- }

{ Reads ONE LF-terminated line from a pipe handle (either end uses it). Stops
  at the terminator, at EOF / a broken pipe, or at MAX_MSG bytes. }
function ReadLineFromPipe(AHandle: THandle): TBytes;
var
  Buf : array[0..CC_IO_BUF_BYTES - 1] of Byte;
  Got : DWORD  ;
  I   : Integer;
  Term: Boolean;
begin
  SetLength(Result, 0);
  Term:= False;
  while (not Term) and (Length(Result) < MAX_MSG) do
  begin
    Got:= 0;
    if not ReadFile(AHandle, Buf[0], Length(Buf), Got, nil) then Break;  // dl:ok used-before-assignment@c7b1
    if Got = 0 then Break;
    I:= Length(Result);
    SetLength(Result, I + Integer(Got));
    Move(Buf[0], Result[I], Got);
    Term:= Buf[Got - 1] = CC_LF;
  end;
end;

{ ---- client -------------------------------------------------------------- }

function ControlRequest(const APipeName, AMessage: string; AConnectTimeoutMs: Integer; out AReply, AError: string): Boolean;
var
  H      : THandle;
  Bytes  : TBytes ;
  Written: DWORD  ;
  Acc    : TBytes ;
begin
  Result:= False;
  AReply:= '';
  AError:= '';
  if not WaitNamedPipeW(PChar(APipeName), Cardinal(AConnectTimeoutMs)) then
  begin
    AError:= 'no free pipe instance within ' + IntToStr(AConnectTimeoutMs) + ' ms (' + SysErrorMessage(GetLastError) + ')';
    Exit;
  end;
  H:= CreateFileW(PChar(APipeName), GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0);
  if H = INVALID_HANDLE_VALUE then
  begin
    AError:= 'could not open the pipe: ' + SysErrorMessage(GetLastError);
    Exit;
  end;
  try
    Bytes:= TEncoding.UTF8.GetBytes(AMessage + #10);
    if not WriteFile(H, Bytes[0], Length(Bytes), Written, nil) then
    begin
      AError:= 'write failed: ' + SysErrorMessage(GetLastError);
      Exit;
    end;
    Acc:= ReadLineFromPipe(H);
    if Length(Acc) = 0 then
    begin
      AError:= 'no reply (the engine closed the pipe)';
      Exit;
    end;
    AReply:= TEncoding.UTF8.GetString(Acc).TrimRight([#13, #10]);
    Result:= True;
  finally
    CloseHandle(H);
  end;
end;

{ ---- audit --------------------------------------------------------------- }

function NowIso: string;
var
  ST: TSystemTime;
begin
  { The OS's UTC clock, not TTimeZone.ToUniversalTime(Now): the RTL conversion is an hour off for the
    whole of a DST-transition day (lane 140-cli DST). }
  GetSystemTime(ST);
  Result:= FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', SystemTimeToDateTime(ST));
end;

{ ONE WriteFile per line, straight to the stderr handle: the listener runs on
  its own thread and Delphi's ErrOutput text file is not thread-safe. Encoded
  like ErrOutput (default ascii), not always UTF-8 as it was. }
procedure StderrLine(const S: string);
var
  B      : TBytes;
  Written: DWORD ;
  H      : THandle;
begin
  H:= GetStdHandle(STD_ERROR_HANDLE);
  if (H = 0) or (H = INVALID_HANDLE_VALUE) then Exit;
  B:= EncodeForOutput(S + sLineBreak); { the --output-encoding bytes ErrOutput writes (2026-10-26) }
  WriteFile(H, B[0], Length(B), Written, nil);
end;

procedure Audit(const ALine: string);
var
  P: string;
begin
  StderrLine('drag-lint LSP: control channel: ' + ALine);
  try
    P:= ControlAuditLogPath;
    TDirectory.CreateDirectory(ExtractFileDir(P));
    { The file is shared by every engine of this user: each line names its writer. }
    TFile.AppendAllText(P, 'engine pid ' + IntToStr(GetCurrentProcessId) + ': ' + ALine + sLineBreak, TEncoding.ASCII);
  except
    { best effort: the stderr line above is the record that always exists }
  end;
end;

{ ---- TControlChannel ----------------------------------------------------- }

constructor TControlChannel.Create(const ADbs: TArray<string>; const AVersion, AExtractor: string; const ARole: string = '';
  AStatusOnly: Boolean = False);
begin
  inherited Create;
  if GetCurrentThreadId <> MainThreadID then
    raise EInvalidOperation.Create('TControlChannel must be created on the main thread -- the one the listener has to wake');
  FDbs      := Copy(ADbs);
  FVersion  := AVersion;
  FExtractor:= AExtractor;
  FRole     := ARole;
  FState    := ST_IDLE;
  FInRead   := 0;
  FFirstPipe:= INVALID_HANDLE_VALUE;
  FWorkLock := TCriticalSection.Create;
  FDone     := TEvent.Create(nil, {ManualReset=}True, False, '');
  FReplied  := TEvent.Create(nil, {ManualReset=}True, False, '');
  FRequested:= TEvent.Create(nil, {ManualReset=}True, False, '');
  FOwnerSid := CurrentUserSidString;
  FStatusOnly:= AStatusOnly;
  FPipeName := if AStatusOnly then BeatPipeNameFor(GetCurrentProcessId) else ControlPipeNameFor(GetCurrentProcessId);
end;

destructor TControlChannel.Destroy;
var
  H: THandle;
  I: Integer;
begin
  if FListener <> nil then
  begin
    FListener.Terminate;
    if InterlockedCompareExchange(FState, ST_TAKEN, ST_TAKEN) = ST_TAKEN then
      { a request is being honoured: the listener is writing `exiting`; let it }
      FReplied.WaitFor(CC_REPLY_JOIN_MS)
    else
    begin
      { Wake it out of ConnectNamedPipe with a throwaway client (the
        OpenSourceServer teardown, which is the one that does not freeze). }
      for I:= 1 to CC_WAKE_ATTEMPTS do
      begin
        if WaitForSingleObject(FListener.Handle, 0) = WAIT_OBJECT_0 then Break;
        if WaitNamedPipeW(PChar(FPipeName), CC_WAKE_PIPE_MS) then
        begin
          H:= CreateFileW(PChar(FPipeName), GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0);
          if H <> INVALID_HANDLE_VALUE then CloseHandle(H);
        end;
        if WaitForSingleObject(FListener.Handle, CC_WAKE_POLL_MS) = WAIT_OBJECT_0 then Break;
      end;
    end;
    if WaitForSingleObject(FListener.Handle, CC_LISTENER_JOIN_MS) = WAIT_OBJECT_0 then FreeAndNil(FListener)
    else
    begin
      { never block process exit on a stuck listener -- detach, as the IDE server does }
      FListener.FreeOnTerminate:= True;
      FListener:= nil;
    end;
  end;
  if FFirstPipe <> INVALID_HANDLE_VALUE then CloseHandle(FFirstPipe);
  if FMainThread <> 0 then CloseHandle(FMainThread);
  if FSD <> nil then LocalFree(HLOCAL(FSD));
  FReplied.Free;
  FRequested.Free;
  FDone.Free;
  FWorkLock.Free;
  inherited Destroy;
end;

function TControlChannel.CreatePipeInstance(out AError: string): THandle;
begin
  AError:= '';
  { ONE instance, first-instance-only: a second creator of this name -- which
    carries our own pid, so it could only be deliberate -- makes OUR create
    fail rather than silently sharing the name with a squatter. }
  Result:= CreateNamedPipeW(PChar(FPipeName),
    PIPE_ACCESS_DUPLEX or CC_FILE_FLAG_FIRST_PIPE_INSTANCE,
    PIPE_TYPE_BYTE or PIPE_READMODE_BYTE or PIPE_WAIT or CC_PIPE_REJECT_REMOTE_CLIENTS,
    1, MAX_MSG, MAX_MSG, 0, @FSA);
  if Result = INVALID_HANDLE_VALUE then AError:= SysErrorMessage(GetLastError);
end;

function TControlChannel.Start(out AError: string): Boolean;
var
  Sddl: string;
begin
  Result:= False;
  AError:= '';
  if FOwnerSid = '' then
  begin
    AError:= 'cannot read the current user''s SID; refusing to listen with a weaker DACL';
    Exit;
  end;
  { EXPLICIT DACL, creating user only. P = protected (no inherited ACEs),
    A = allow, GA = generic all. Never nil (NULL DACL = Everyone). }
  Sddl:= 'D:P(A;;GA;;;' + FOwnerSid + ')';
  if not ConvertStringSecurityDescriptorToSecurityDescriptorW(PChar(Sddl), CC_SDDL_REVISION_1, FSD, nil) then
  begin
    AError:= 'security descriptor: ' + SysErrorMessage(GetLastError);
    Exit;
  end;
  FSA.nLength             := SizeOf(FSA);
  FSA.lpSecurityDescriptor:= FSD;
  FSA.bInheritHandle      := False;
  if not DuplicateHandle(GetCurrentProcess, GetCurrentThread, GetCurrentProcess, @FMainThread, CC_THREAD_TERMINATE, False, 0) then
  begin
    AError:= 'main thread handle: ' + SysErrorMessage(GetLastError);
    Exit;
  end;
  FFirstPipe:= CreatePipeInstance(AError);
  if FFirstPipe = INVALID_HANDLE_VALUE then
  begin
    AError:= 'CreateNamedPipe ' + FPipeName + ': ' + AError;
    Exit;
  end;
  FListener:= TControlListener.Create(Self);
  Result:= True;
end;

function TControlChannel.RequestEvent: THandle;
begin
  Result:= FRequested.Handle;
end;

function TControlChannel.StandDownRequested: Boolean;
begin
  Result:= InterlockedCompareExchange(FState, ST_TAKEN, ST_REQUESTED) = ST_REQUESTED;
end;

procedure TControlChannel.EnterRead;
begin
  InterlockedExchange(FInRead, 1);
end;

procedure TControlChannel.LeaveRead;
begin
  InterlockedExchange(FInRead, 0);
end;

procedure TControlChannel.BeginWork(const AWhat: string);
begin
  FWorkLock.Enter;
  try
    FWork:= AWhat;
  finally
    FWorkLock.Leave;
  end;
end;

procedure TControlChannel.EndWork;
begin
  BeginWork('');
end;

function TControlChannel.CurrentWork: string;
begin
  FWorkLock.Enter;
  try
    Result:= FWork;
  finally
    FWorkLock.Leave;
  end;
end;

procedure TControlChannel.StandDownComplete;
begin
  { The host left its loop because the cancelled read returned nil, or because
    it took the request explicitly; either way the request is now TAKEN. }
  InterlockedCompareExchange(FState, ST_TAKEN, ST_REQUESTED);
  HangStoreCloseForTests;
  FDone.SetEvent;
end;

{ ---- TControlListener ---------------------------------------------------- }

constructor TControlListener.Create(AOwner: TControlChannel);
begin
  FOwner:= AOwner;
  FreeOnTerminate:= False;
  inherited Create(False);
end;

procedure TControlListener.Reply(APipe: THandle; const ALine: string);
var
  B      : TBytes;
  Written: DWORD ;
begin
  B:= TEncoding.UTF8.GetBytes(ALine + #10);
  if WriteFile(APipe, B[0], Length(B), Written, nil) then FlushFileBuffers(APipe);
end;

function TControlListener.RequesterText(APipe: THandle): string;
var
  Pid : ULONG                     ;
  H   : THandle                   ;
  Name: array[0..MAX_PATH] of Char;
  Len : DWORD                     ;
begin
  Result:= 'pid ? (unknown)';
  Pid:= 0;
  if not GetNamedPipeClientProcessId(APipe, Pid) then Exit;
  Result:= 'pid ' + IntToStr(Pid) + ' (unknown exe)';
  H:= OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION_ACCESS, False, Pid);
  if H = 0 then Exit;
  try
    Len:= Length(Name);
    if QueryFullProcessImageNameW(H, 0, @Name[0], Len) then Result:= 'pid ' + IntToStr(Pid) + ' (' + string(PChar(@Name[0])) + ')';
  finally
    CloseHandle(H);
  end;
end;

{ True when a status request's arguments (fields 1..) include AArg. Before 1.40
  only field 1 was read, so `status<TAB>role` is answered exactly as before. }
function StatusArgAsked(const AFields: TArray<string>; const AArg: string): Boolean;
var
  I: Integer;
begin
  for I:= 1 to High(AFields) do
    if SameText(Trim(AFields[I]), AArg) then Exit(True);
  Result:= False;
end;

procedure TControlListener.Serve(APipe: THandle);
var
  Acc     : TBytes               ;
  Fields  : TArray<string>       ;
  Verb    : string               ;
  Pid     : string               ;
  Line    : string               ;
  WaitMs  : Integer              ;
  D       : string               ;
begin
  Acc:= ReadLineFromPipe(APipe);
  if Length(Acc) = 0 then Exit; { the teardown wake-up, or a client that said nothing }
  Fields:= TEncoding.UTF8.GetString(Acc).TrimRight([#13, #10]).Split([#9]);
  Verb:= '';
  if Length(Fields) > 0 then Verb:= Trim(Fields[0]);
  Pid:= IntToStr(GetCurrentProcessId);

  if SameText(Verb, CONTROL_MSG_STATUS) then
  begin
    Line:= CONTROL_REPLY_STATUS + #9 + Pid + #9 + FOwner.FVersion + #9 + FOwner.FExtractor;
    { 1.39.1: the role only when asked, so every older parser of the reply (dbs from field 4 on) is unaffected. }
    if StatusArgAsked(Fields, CONTROL_STATUS_ARG_ROLE) and (FOwner.FRole <> '') then
      Line:= Line + #9 + CONTROL_ROLE_FIELD_PREFIX + FOwner.FRole;
    { 1.40: the heartbeat, likewise only when asked. }
    if StatusArgAsked(Fields, CONTROL_STATUS_ARG_BEAT) then Line:= Line + #9 + BeatFieldText(BeatSnapshot);
    { 1.41: the writer field, likewise only when asked (SQLITE-BUSY-BEAT). }
    if StatusArgAsked(Fields, CONTROL_STATUS_ARG_WRITING) then Line:= Line + #9 + WritingFieldText;
    for D in FOwner.FDbs do Line:= Line + #9 + D;
    Reply(APipe, Line);
  end
  else if SameText(Verb, CONTROL_MSG_SHUTDOWN) and not FOwner.FStatusOnly then
  begin
    WaitMs:= CONTROL_DEFAULT_WAIT_MS;
    if Length(Fields) > 1 then WaitMs:= StrToIntDef(Trim(Fields[1]), CONTROL_DEFAULT_WAIT_MS);
    if WaitMs < 0 then WaitMs:= 0;
    if WaitMs > CONTROL_MAX_WAIT_MS then WaitMs:= CONTROL_MAX_WAIT_MS;
    ServeStandDown(APipe, WaitMs);
  end
  else
    { ONE thing. Anything else is answered and changes nothing. }
    Reply(APipe, CONTROL_REPLY_UNKNOWN + #9 + Pid);
end;

procedure TControlListener.ServeStandDown(APipe: THandle; AWaitMs: Integer);
var
  Pid      : string ;
  Line     : string ;
  Started  : UInt64 ;
  Cancelled: Boolean;
  Who      : string ;
  D        : string ;
begin
  Pid:= IntToStr(GetCurrentProcessId);
  Who:= RequesterText(APipe);

  if InterlockedCompareExchange(FOwner.FState, TControlChannel.ST_REQUESTED, TControlChannel.ST_IDLE) <> TControlChannel.ST_IDLE then
  begin
    { a stand-down is already in flight -- report the same answer it will get }
    if FOwner.FDone.WaitFor(AWaitMs) = wrSignaled then Reply(APipe, CONTROL_REPLY_EXITING + #9 + Pid)
    else Reply(APipe, CONTROL_REPLY_BUSY + #9 + Pid + #9 + 'a stand-down is already in progress');
    Exit;
  end;
  FOwner.FRequested.SetEvent;

  Started  := GetTickCount64;
  Cancelled:= False;
  repeat
    { Cancel the host's stdin read -- and ONLY that read: never while it is
      inside a handler, where the synchronous I/O in flight would be SQLite's. }
    if (not Cancelled) and (InterlockedCompareExchange(FOwner.FInRead, 1, 1) = 1) then
      if CancelSynchronousIo(FOwner.FMainThread) then Cancelled:= True;
    if FOwner.FDone.WaitFor(CC_POLL_MS) = wrSignaled then Break;
    { F5 (2026-10-25): leave as soon as the read is cancelled -- the host IS
      leaving, and the store-close grace below bounds the rest. The old exit
      `deadline and not Cancelled` could only end on FDone once Cancelled was
      set, so a host hanging in its store close pinned this thread and the
      'started but not finished' reply was unreachable. }
  until Cancelled or (GetTickCount64 - Started >= UInt64(AWaitMs));

  if FOwner.FDone.WaitFor(CC_NO_WAIT_MS) <> wrSignaled then
  begin
    if Cancelled then
    begin
      { the read is gone, so the host IS leaving: wait for the stores to close }
      if FOwner.FDone.WaitFor(StoreCloseGraceMs) <> wrSignaled then
      begin
        Audit('shutdown asked by ' + Who + ' at ' + NowIso + ' -- read cancelled but the host has not closed its stores after '
          + IntToStr(StoreCloseGraceMs) + ' ms');
        Reply(APipe, CONTROL_REPLY_BUSY + #9 + Pid + #9 + 'stand-down started but not finished');
        { the final reply IS written: without this the host's teardown, finding the state TAKEN,
          waited the whole CC_REPLY_JOIN_MS for a reply that had already gone (W5-C) }
        FOwner.FReplied.SetEvent;
        Exit;
      end;
    end
    else if InterlockedCompareExchange(FOwner.FState, TControlChannel.ST_IDLE, TControlChannel.ST_REQUESTED) = TControlChannel.ST_REQUESTED then
    begin
      { WITHDRAWN atomically: the host never took it, nothing changed }
      FOwner.FRequested.ResetEvent;
      Line:= FOwner.CurrentWork;
      if Line = '' then Line:= 'not idle';
      Audit('shutdown REFUSED at ' + NowIso + ' -- busy with ' + Line + '; asked by ' + Who + '; deadline ' + IntToStr(AWaitMs) + ' ms');
      Reply(APipe, CONTROL_REPLY_BUSY + #9 + Pid + #9 + Line);
      Exit;
    end
    else
      { the host took it in the same instant: it is exiting, wait for the stores }
      FOwner.FDone.WaitFor(StoreCloseGraceMs);
  end;

  Line:= CONTROL_REPLY_EXITING + #9 + Pid;
  for D in FOwner.FDbs do Line:= Line + #9 + D;
  Audit('shutdown honoured at ' + NowIso + ' -- asked by ' + Who + '; closed ' + IntToStr(Length(FOwner.FDbs)) + ' store(s), exiting 0');
  Reply(APipe, Line);
  FOwner.FReplied.SetEvent;
  Terminate;
end;

procedure TControlListener.AcceptAndServe(APipe: THandle);
var
  Connected: Boolean;
begin
  try
    { Blocks until a client connects -- a tool, or the teardown's throwaway
      wake-up, which Serve then reads as an empty message and ignores. }
    Connected:= ConnectNamedPipe(APipe, nil) or (GetLastError = ERROR_PIPE_CONNECTED);
    if Connected and not Terminated then Serve(APipe);
  finally
    DisconnectNamedPipe(APipe);
    CloseHandle(APipe);
  end;
end;

procedure TControlListener.Execute;
var
  Pipe: THandle;
  Err : string ;
begin
  NameThreadForDebugging('drag-lint control channel');
  { The first instance was created synchronously by Start, so the pipe already
    existed when the engine announced it. Every later instance is ours to make. }
  Pipe:= FOwner.FFirstPipe;
  FOwner.FFirstPipe:= INVALID_HANDLE_VALUE;
  if (Pipe <> INVALID_HANDLE_VALUE) and not Terminated then AcceptAndServe(Pipe);
  while not Terminated do
  begin
    Pipe:= FOwner.CreatePipeInstance(Err);
    if Pipe = INVALID_HANDLE_VALUE then Sleep(CC_RETRY_MS) { transient; the name is ours, retry }
    else AcceptAndServe(Pipe);
  end;
end;

initialization
  GBeatLock:= TCriticalSection.Create;
  GWriterDbs:= TDictionary<string, Integer>.Create;

finalization
  BeatChannelClose;
  FreeAndNil(GWriterDbs);
  FreeAndNil(GBeatLock);

end.
