---
id: v151-thrb-rules
title: Thread race and blocking rules
summary: "Four lint rules: racing writes in parallel bodies, non-atomic global increments in threads, unbounded waits in forms, lost task exceptions"
product: DL
group: linting
order: 30058
since: 1.51.0-alpha
status: shipped
updated: 1.51.1-alpha
---

# Thread race and blocking rules

Four lint rules: racing writes in parallel bodies, non-atomic global increments in threads, unbounded waits in forms, lost task exceptions.

Read this when you want lint to catch data races between threads, a frozen window, or an exception lost inside a TTask. Run `drag-lint lint <unit.pas>` or `lint-all`; each rule is selectable with --rule. With an index the rules also recognise thread, form and frame classes whose ancestor lives in another unit.

## How to run it

```text
drag-lint lint <path> [--profile <name>] [--target-compiler <ver|auto>] [--rule <id>|help] [--disable id1,id2] [--rules-dir <dir>] [--json] [--labels] [--no-preprocess] [--library-db <lib.sqlite>] [--build-config <name>]
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Four rules look for code that shares data between threads without protection, blocks the
user interface, or loses an exception raised in a task. All four read one unit's parse
tree; with an index (`lint --db` or `lint-all`) the index also decides which classes
descend from TThread, TCustomForm or TCustomFrame when the ancestor is declared in another
unit. Each rule can be selected with `--rule <id>` or switched with `--enable` /
`--disable`.

### The rules
* **parallel-for-shared-write** -- the body of `TParallel.For`, or of a `TTask.Run` /
  `TTask.Create` / `TTask.Future` / `TThread.CreateAnonymousThread` started inside a loop,
  assigns a plain variable that is declared outside the body (a captured local, a field, a
  global), or passes it to Inc / Dec / Include / Exclude / SetLength / Delete, and the body
  takes no lock. Element stores (`Results[I] := ...`), member stores, variables the body
  declares itself (parameters, `var` sections, inline `var`, `for var`), stores under a
  `with`, and nested anonymous methods (a `Synchronize` body runs serialised) are not
  reported. A body that calls Enter / Acquire / BeginWrite / Lock / TMonitor.Enter /
  EnterCriticalSection anywhere counts as locked.
* **thread-unsafe-increment** -- Inc, Dec, `X := X + e` or `X := X - e` on a unit-level
  variable or a class var of the same unit, inside Execute of a thread class or inside the
  body of a task / anonymous thread started once. A threadvar, a local or parameter of the
  same name, a field of the thread class, TInterlocked calls, Synchronize / Queue bodies and
  routines that take a lock are not reported. A TParallel.For body or a task started in a
  loop is left to parallel-for-shared-write, so one line never gets both findings.
* **blocking-call-in-main-thread** -- a method of a form or frame class, in a unit with
  `{$R *.dfm}` or `{$R *.fmx}`, waits with no time limit: `WaitFor` / `Wait` with no
  argument or `INFINITE`, `WaitForSingleObject(h, INFINITE)`,
  `WaitForMultipleObjects(..., INFINITE)`, `TTask.WaitForAll` / `WaitForAny` without a
  timeout, or `TThread.Sleep`. A wait on an object the same method also stops or frees (the
  usual shutdown), destructors, anonymous-method bodies, data modules and thread classes
  are not reported. A plain `Sleep` call is reported by sleep-in-vcl, not here.
* **task-exception-unobserved** -- `TTask.Run` / `TTask.Create` / `TTask.Future` whose body
  has no top-level try..except, and whose task is never observed: the result is thrown away
  (also after `.Start`), or kept in a local that the routine never uses again except to
  start it. The body is an anonymous method, or a routine of the same unit passed by name.
  A task that is waited, read (`.Value`), passed on, returned or kept in a field counts as
  observed; a body the rule cannot see (a parameter, a routine of another unit) is not
  reported. `TTask.Run` with an anonymous method is reported by exception-escapes-thread
  already and is skipped here.

### Defaults
All four are ON by default and report as warnings. On the four project indexes and the
97 threading units of the RAD Studio sources they were measured on, none reported a false
positive. The blocking rule exempts teardown: a wait on an object the same method also
stops or frees (Terminate, Stop, Shutdown, Cancel, Free, FreeAndNil), because a form's
FormDestroy legitimately waits for its worker to end.

### Fixes
None of the four has an autofix: the right repair (a lock, TInterlocked, a per-iteration
slot, a worker thread, a Wait) depends on the design, so the message names the options.

### Examples
```pascal
TParallel.For(0, High(Values),
  procedure(I: Integer)
  begin
    Total:= Total + Values[I];      // parallel-for-shared-write
  end);

procedure TWorker.Execute;
begin
  while not Terminated do
    Inc(GProcessed);                // thread-unsafe-increment
end;

procedure TMainForm.LoadClick(Sender: TObject);
begin
  FLoader.WaitFor;                  // blocking-call-in-main-thread
end;

TTask.Create(DoWork).Start;         // task-exception-unobserved (DoWork has no try..except)
```

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
