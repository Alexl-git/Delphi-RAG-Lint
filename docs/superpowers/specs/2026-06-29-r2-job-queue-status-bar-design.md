# R2 IDE job queue + dock status bar -- design (v0.65.1 / v0.66 branch)

> **Status:** design for the `feature/r2-dock-statusbar` branch. Implemented autonomously
> (open questions decided below, user away). Build-verified only; **manual RAD Studio test
> is the merge gate** -- there is no OTAPI test harness. Ships as v0.65.1 or v0.66 after the
> user confirms it in the IDE.

## Goal
Serialize the heavy, DB-touching one-shot IDE jobs (reindex / lint-all / forms-csv) through a
single background worker so they never collide on the project SQLite DB ("database is locked"),
and surface their state in a **status strip along the bottom of the drag-lint dock window**.
The LSP server stays a separate live process; the queue governs only the heavy jobs.

## Why now (problems in today's code)
- `forms-csv` runs **synchronously on the UI thread** (`RunAndCaptureStdout`, 120 s) -- freezes
  the IDE.
- `reindex`, `lint-all`, `forms-csv` each spawn their own `TThread.CreateAnonymousThread`; two
  can run at once and collide on the DB. The only existing guard (`GProjectBuildBusy`) covers
  compile/ghost-check, not these.
- Live progress (`lint-all: [i/N] NN%`) only goes to the Messages view; there is no in-place bar.

## Components

### 1. `DragLint.Plugin.JobQueue` (new unit -- the model)
A lazily-created singleton `TDragLintJobQueue` with ONE worker thread.
- **Job descriptor** `TDragLintJob`: `Kind`, `Title`, `CoalesceKey`, `CmdLine`, `TimeoutMs`,
  `Streaming`, and three optional callbacks: `OnPreRun: TProc` (UI thread, before the process
  starts -- e.g. stop the LSP for reindex), `OnLine: TProc<string>` (worker thread, per output
  line), `OnDone: TProc<Integer,string>` (UI thread: exit code + full output -- the existing
  post-run logic: open report, post Messages summary).
- **FIFO** `TObjectList<TDragLintJob>` guarded by a `TCriticalSection`; an auto-reset `TEvent`
  wakes the worker. The worker drains all pending jobs, runs each via the existing
  `DragLint.Plugin.ProcRun` helpers (`RunCaptureStreaming` for streaming, `RunCaptureStdout`
  otherwise), then blocks until the next enqueue.
- **Coalescing:** `Enqueue` drops any *pending* (not running) job with the same non-empty
  `CoalesceKey` before adding the new one -- a reindex-on-save supersedes a queued reindex.
- **Published state** `TQueueState` (`Running`, `CurrentTitle`, `Percent` [-1 = indeterminate],
  `QueueDepth`, `LastResult`), snapshotted under the lock. The queue exposes
  `OnChange: reference to procedure(const AState)`; every transition is marshalled to the main
  thread via `TThread.Queue`, and the closure reads `FOnChange` **at execution time on the main
  thread** (never captures it) so a dock closing mid-job cannot dangle.
- **Progress parse:** the same digit-before-`%` scan lint-all uses today, moved into the queue's
  internal streaming callback, drives `Percent`.
- **Clean teardown:** `ShutdownJobQueue` (unit finalization) sets a shutdown flag, signals the
  event, **joins** the worker (`WaitFor`), then frees -- no orphan thread, matching the plugin's
  anti-unload-AV discipline.

### 2. `DragLint.Plugin.StatusBar` (new unit -- the view)
`TDragLintStatusBar = class(TPanel)` docked `alBottom`, ~26 px, with:
- a state `TLabel` ("Idle" / "Reindex Micronite2027 ..." / "lint-all 45%"),
- a `TProgressBar` (visible while `Running`; `pbstMarquee` when `Percent < 0`, else `Percent`),
- a queue-depth `TLabel` ("2 queued", hidden when 0),
- a `TLabel` for the last result ("lint-all: 78/78, 0 errors"),
- a **Cancel** `TButton`, enabled only when `QueueDepth > 0`.
Exposes `ApplyState(const AState: TQueueState)`; all control mutation on the main thread.

### 3. Dock-frame integration (`DragLint.Plugin.DockForm`)
The frame constructor creates a `TDragLintStatusBar` (`alBottom`) so the `TPageControl`
(`alClient`) fills the rest, then subscribes: `JobQueue.OnChange := <update bar>` and seeds it
with `JobQueue.GetState`. The destructor nils `JobQueue.OnChange`. The bar shows across all tabs
(Structure / Search / Find Usages). The queue runs even when the dock is closed (no subscriber);
the Messages-view posts remain so closed-dock users still get feedback.

### 4. Launcher conversion (`DragLint.Plugin.Editor`)
`InvokeReindexProject`, `InvokeLintAll`, `InvokeGenerateFormsCsv` stop spawning their own threads
and instead build a `TDragLintJob` and `Enqueue` it; their current post-run code becomes `OnDone`
(and the LSP-stop becomes reindex's `OnPreRun`). `forms-csv` thus stops blocking the UI. Compile /
ghost-check keep their existing `GProjectBuildBusy` single-flight path (edit-triggered, frequent,
bespoke result handling) -- out of scope for v1.

## Decisions (open questions from the v0.65 plan, resolved)
- **Cancel:** clears *pending* jobs only; the running job is allowed to finish. Hard-killing a
  mid-flight reindex risks a corrupt/locked index, and `ProcRun` does not expose the child handle.
  Hard-cancel of the running job is a v0.66 follow-up (needs a `ProcRun` handle hook).
- **Click-to-expand queue list:** no (YAGNI); the depth count + Messages log suffice for v1.
- **Persist across IDE restart:** no; the queue is in-memory, idle on restart.
- **Idle state:** shown ("Idle" + last result).
- **Throttle:** progress `OnChange` only fires on an actual `Percent` change (already coalesced);
  the bar updates in place.
- **Messages vs bar (double-reporting):** keep the existing Messages begin/end + summary posts
  (feedback when the dock is closed) and add the bar as the live in-place indicator. Trimming the
  per-percent Messages spam is left as a post-test tweak the user can request.

## Testing
- **Build:** Win32 BPL (`dclDragLintWizard.dproj`) compiles clean; both new units added to the
  `.dpr` uses + `.dproj` DCCReferences.
- **Manual (merge gate):** RAD Studio, project open -> open the drag-lint dock -> run Reindex,
  Run Lint All, Generate Forms CSV; confirm the bottom strip shows the running job + live %,
  "N queued" when stacking two, Cancel clears the pending one, the report/CSV still opens, no
  freeze, no unload AV on closing the IDE.
