# Thread lifetime rules (anonymous threads, destructors, Terminated, threadvar, Queue)

Six lint rules and one widening of an existing rule, all about the lifetime of a `TThread`. They are plain
per-file checks (`lint <file>` and `lint-all` both run them); none of them needs the parse tree beyond the
unit's own text, so they also work on a unit that is not in a project index. The thread-class test uses the
project index for ancestors declared in other units when one is available, and falls back to the unit's own
class declarations and to the `...Thread` naming convention.

```
drag-lint lint <unit.pas> --rule anonymous-thread-not-started
drag-lint lint-all --db <project.sqlite> --rule thread-loop-without-terminated
```

## Rules

| id | fires when |
|---|---|
| `anonymous-thread-not-started` | `TThread.CreateAnonymousThread(...)` is a statement of its own, or is assigned to a local variable that is never started (`Start` / `Resume`) and never leaves the routine. |
| `synchronize-in-destructor` | The destructor of a `TThread` descendant calls `Synchronize`, directly or through methods of the same class (three levels). The main thread usually frees the thread and waits for it, so the call can deadlock. |
| `thread-loop-without-terminated` | A `while` / `repeat` loop in `Execute` (or in a private / protected method only `Execute` reaches) never reads `Terminated` and either is endless (`while True`, `until False`) with no `Break` / `Exit` / `raise`, or polls with `Sleep` / `WaitFor`. |
| `thread-use-after-free-on-terminate` | A routine sets `X.FreeOnTerminate := True`, starts `X`, and then reaches into `X` (`X.Member`) before reassigning it. |
| `threadvar-managed` | A `threadvar` has a managed type (string, variant, dynamic array, interface, anonymous method, or a record holding one). Delphi does not finalize threadvar storage when a thread ends. |
| `queue-nil-in-package` | `TThread.Queue(nil, ...)` / `TThread.ForceQueue(nil, ...)` in a unit that belongs to a package: it uses `ToolsAPI` / `DesignIntf` / `DesignEditors`, or a `.dpk` in the unit's folder, a parent (up to three levels) or a neighbouring folder lists it under `contains`. |
| `freeonterminate-then-wait` (widened) | Also reports `FreeAndNil(X)` and `X.DisposeOf` on a thread that frees itself: `FreeOnTerminate` was set to `True` earlier in the routine, or `X` is a local of a class whose constructor sets it. The existing `X.Free` / `X.WaitFor` forms are unchanged. |

## What does not fire

* A thread that is started by chaining (`...CreateAnonymousThread(...).Start`), returned, stored or passed on.
* `Queue` instead of `Synchronize` in a destructor; `Synchronize` in a class that is not a thread.
* Loops that read `Terminated`, call `Terminate`, or contain `Break` / `Exit` / `raise`; finite counting loops.
* Public helpers of a thread class (they may be called from elsewhere).
* `string[N]` (a short string), classes, plain records and `Int64` in a `threadvar`.

## Autofix

None. Each fix changes behaviour (starting a thread, restructuring a loop, replacing a threadvar), so the
message carries the suggestion instead.

Guards: `tests\lint\<rule-id>.pas` (one fixture per rule, HIT / OK markers),
`tests\autotest\run_v151_THR-A_queue_nil_dpk.ps1` (`.dpk` membership).
