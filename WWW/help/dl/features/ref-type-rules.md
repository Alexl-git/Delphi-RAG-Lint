---
id: ref-type-rules
title: Lint rules on the static type of a reference
summary: "Lint rules on ref_types: is-always-true, is-never-true, argument-narrows, UI access from a thread, quit from a thread; sharper redundant-cast and unsafe casts"
product: DL
group: linting
order: 30033
since: 1.44.1-alpha
status: shipped
updated: 1.48.0-alpha
---

# Lint rules on the static type of a reference

Lint rules on ref_types: is-always-true, is-never-true, argument-narrows, UI access from a thread, quit from a thread; sharper redundant-cast and unsafe casts.

Read this to see which rules stand on ref_types, what each reports and what keeps it silent. They run in lint-all and lint-project over a 1.44 index.

## How to run it

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>] [--disable id,...] [--output <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none]
```

Example:

```text
drag-lint lint-all --db <project.sqlite> --rule argument-narrows
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Rules that read index fact F1, the `ref_types` table: the static type of a reference, written by the
resolve pass. They run in `lint-all` and `lint-project`, and for one file in `lint <file> --db` when
the rule ships ON. An index older than 1.44 has no such table and these rules answer nothing there.

```text
drag-lint lint-all --db <project.sqlite> --rule is-always-true
drag-lint lint-all --db <project.sqlite> --rule argument-narrows
```

| Rule | Default | Reports |
|---|---|---|
| `is-always-true` | ON | `x is T` where the static type of `x` already descends from `T`: the test only asks whether `x` is nil |
| `is-never-true` | OFF | `x is T` that no object can answer yes to: two classes where neither descends from the other, or a sealed class against an interface it does not implement, either way round. Proof only: both ancestries followed to the end and no homonym; a class that is not sealed against an interface stays silent, a descendant may implement it. The sealed half needs a 1.46 parse (`symbols.directives`) |
| `upcast-then-downcast` | ON | `TLeaf(TBase(x))` or `(x as TBase) as TLeaf` where `x` already is a `TBase` |
| `with-on-temporary` | ON | `with TFoo.Create do` with no free in the body and no owner taking the object |
| `interface-holder-of-non-refcounted` | ON | An interface variable assigned a `TComponent` / `TNoRefCountObject` / `TSingletonImplementation` descendant (a variable, `as`, a constructor, `Self`) |
| `argument-narrows` | ON | A variable, field or function result passed to a narrower by-value numeric parameter of a project routine |
| `redundant-cast` | ON | Also `T(a.b)`, `T(F(x))` and `x as T`; the index overrules the per-file type map for `T(x)` |
| `unsafe-typecast-without-is` | OFF | Also `T(a.b)` and `T(F(x))`; with a row in `ref_types` the rule fires only when both ends are classes and the cast narrows |

| `ui-access-in-thread-typed` | ON (1.47) | Thread code reads, writes or calls a member of a receiver whose static type is a UI class, directly or over resolved calls; see below |
| `quit-from-thread` | OFF (1.47) | Thread code calls `PostQuitMessage`, `Application.Terminate`, `Halt` or `ExitProcess`: it ends the process, or posts WM_QUIT to the worker's own queue, from the wrong thread; see below |

### `ui-access-in-thread-typed`

The typed answer to "does a thread touch the VCL". `ui-access-in-thread` (lexical, no index) and
`ui-access-in-thread-transitive` (`ui_affinity`) keep their ids, so their `dl:ok` markers stay valid.

| Question | Answer |
|---|---|
| Thread code | `Execute` of any `TThread` descendant through the indexed ancestry; a lambda or named routine passed to `TThread.CreateAnonymousThread`, `TTask.Run`, `TTask.Create`, `TTask.Future` or `TParallel.For` |
| UI classes | Descendants of `TControl`, `TCustomForm`, `TFmxObject`; `TApplication` and `TScreen`. `Application` and `Screen` count as globals when unbound and the unit names a Forms unit but not `SvcMgr` or `WebBroker` |
| What fires | `Label1.Caption := x`, `if Label1.Visible`, `Label1.Hide`, `TLabel(x).Hide`, `TLabel.Create(nil)`, `Memo1.Lines.Add` (because of `Memo1`), and a bare `Caption` or `Close` in a form's own lambda or method when the library declares it on a UI class |
| Over calls | Up to 5 certain call edges; the finding sits on the call in the thread code and prints the path and the first access |
| Safe | The arguments of `Synchronize`, `Queue`, `ForceQueue`; a body naming `MainThreadID` or `CurrentThread`; a called routine naming `Synchronize` or `Queue` (taken to marshal itself) |
| Silent | An untyped receiver, a subscript, a `with` body, a stored lambda; a member the project declares (a plain field of a form; its methods are followed as calls); `Tag`, `Name`, `ClassName` and the other `TObject` / `TComponent` data; `Application.Terminated`, `ExeName`, `Handle` |
| Never constructed | An `Execute` whose class nothing in the project names outside its own method headers (no `TExit.Create`, no variable, no descendant, no `class of`) still fires, as a `hint` with ` (class never constructed)` appended: the code is wrong but does not run today (1.47) |
| Not UI here | `TStrings`, `TBitmap`, `TCanvas`, menus: `Lst.Add`, `Bmp.Canvas` stay silent. A `TStrings` held apart from its control has no type that names the control |

It needs the library index for the ancestry: without it only `Application` and `Screen` answer.
A project class named `TControl`, `TTask` or the like silences that name for the whole index.

### `quit-from-thread`

Same thread code as `ui-access-in-thread-typed` (`Execute` of a `TThread` descendant, a lambda or routine passed to
`TThread.CreateAnonymousThread`, `TTask.Run` / `Create` / `Future`, `TParallel.For`), so the two share one walk. Ships OFF; opt in with `--enable quit-from-thread`.

| Question | Answer |
|---|---|
| What fires | `PostQuitMessage(0)`, `Winapi.Windows.PostQuitMessage`, `Application.Terminate`, `Halt`, `Halt(n)`, `ExitProcess(n)` written in the thread body itself |
| Safe | The arguments of `Synchronize`, `Queue`, `ForceQueue` (they run on the main thread); a nested routine or a lambda nobody starts on a thread |
| Not followed | A quit reached over a called routine (`ui-access-in-thread-typed` follows call edges; this rule does not, yet) |
| Silent | `Self.Terminate` / `Terminate` of the thread itself; the same calls outside thread code; a project that declares its own `TThread` |
| Never constructed | As above: a hint with ` (class never constructed)` appended |

Real finding it was written for: `TExit.Execute` in ORM3 CLIENT `uMain.pas` calls `PostQuitMessage(0)` from a worker.
It needs the library index for the ancestry.
### What keeps a rule silent

An expression has a static type only as a single name, a member chain, a call, a hard cast or an `as`.
A subscript has none: the row of `List` in `List[i]` types the list, not the element. Neither has a
bare name inside a `with` body, because it may bind to a member of the with-expression.

A class's ancestry is `type_ancestors` in the project, continued by name in the library index. A
homonym keeps only the ancestors every class of that name shares, so it can silence a rule but never
make one fire. Without a library index a class on a library base has an incomplete ancestry.

`argument-narrows` skips overloaded callees (the resolver's overload choice is not proof of a
width), `var` and `out` parameters, constants and expressions other than a single name, chain or call.
Library callees are not checked.

`with-on-temporary` reports constructors only: a function's result may be owned elsewhere.

### Not a rule: `is-never-true`

`x is T` with unrelated classes does not compile (E2010), so in compiling code every finding of that
shape would be an index error. `Intf is TSealed` compiles and can be proved, but the index does not
record `sealed`, and that shape needs an extractor change for a test almost nobody writes.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
