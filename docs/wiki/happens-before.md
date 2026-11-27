# happens-before

Answers "has event A happened before event B, on every execution?" for two events you name.

It reads the index (nothing is written), lists every site of both events and gives one of three
answers:

| Answer | Meaning |
|---|---|
| `YES` | proven: every site of B runs after a site of A, on every path |
| `NO` | proven: there is a run of B with no A before it |
| `MAY` | everything else. "Not proven" -- never a proof that the order is wrong |

Every doubt answers `MAY`. A wrong `YES` or `NO` would be worse than an honest `MAY`, so the verb
proves or it does not answer.

## Running it

```
drag-lint happens-before --a <event> --b <event> --db <db> [--json] [--max-routines N] [--max-seconds S]
drag-lint happens-before --preset <name> [--a <event>] --db <db> [--json]
```

Exit 0: `YES`. Exit 1: `NO` or `MAY`. Exit 2: usage or other error (unknown event kind, unknown or
ambiguous target, no `--db`, missing or stale DB); the message goes to stderr and stdout stays
empty. Exit 3: unknown flag.

## Events

An event is a set of sites in the index.

| Event | Its sites |
|---|---|
| `write:<QName>` | the writers of a unit variable, class var or instance field |
| `read:<QName>` | its reads |
| `call:<QName>` | the call sites the index resolves to that routine |
| `extcall:<Name>[,<Name>...]` | the calls of routines the index does NOT hold (RTL, a library), matched by name; a comma list is one event |
| `extwrite:<Name>[,<Name>...]` | the assignments to (or through) a variable the index does NOT hold, e.g. `FormatSettings.DecimalSeparator :=  ` |
| `app-run:<program>\|*` | the top-level `Application.Run` of that program block (`*` = every program) |
| `site:<file>:<line>[:<col>]` | one source position |

`<QName>` may be a unique trailing part (`GFlag`, `TConn.Open`); an ambiguous one is refused with
the candidates.

Two properties of an event decide what can be proven:

* A site is **definite** when the event certainly happens there. A `var` / `out` argument, a call
  the index cannot resolve and a write inside a `with` are **uncertain** sites: the write may or may
  not happen. They are listed as `A?` lines with the source line.
* An event is **complete** when the index holds every place it can happen. It is **incomplete** when
  the target's address is taken, the target is published, the routine takes part in virtual or
  interface dispatch, or something outside the code can run it (a DFM event, a message handler, an
  exported routine, a thread). The answer says why.

`YES` needs a complete B. `NO` needs a complete A.

## What is proven, and how

`YES` -- every site of B is judged against A, by the first method that holds:

| Method | Proof |
|---|---|
| `same-routine` | a definite site of A runs before B on every path of B's routine |
| `callee` | the same, counting a certain call of a routine that performs A on every normal return |
| `callers` | B's routine runs only through resolved, certain calls, and A is proven before every one of them (up to 6 levels up) |
| `check-init` | for `write:T` before `read:T` only: the [check-init](check-init) solver answers SET for every use (it knows the order of initialization sections and the program block) |
| `program-order` | what the methods above could not prove goes to the ordered-root solve (`HbOrderSolve`): the initialization chain, the program block, handler order and call chains, with the definite sites of A as marks. A is first from every root that reaches B. Works for every event kind, not only `write:` / `read:` |

`NO` -- one of two proofs:

| Reason | Proof |
|---|---|
| `a-never-happens` | A is complete and has no site, B has at least one |
| `b-first` | A is complete and every site of A (uncertain ones too) runs after a site of B in its own routine, or (`program-order`, the same solve with B as marks) after a B from every root: the first A of any run is preceded by a B that no A preceded |

A `program-order` `YES` that leaned on a heuristic says so in `limits[]` (see Limits). A `NO` never
leans on the handler-order heuristic or on indirect-call edges.

`MAY` -- each unproven site of B carries one reason:

| Reason | Meaning |
|---|---|
| `a-not-on-every-path` | A is in the routine, but a path reaches B without it (an `if`, a loop, an exception handler) |
| `a-site-uncertain` | the only A in the routine is an uncertain site |
| `a-in-other-routine` | A has no site in B's routine, in a callee that always performs it, or before every call of B's routine; also what the pre-check answers (see below) |
| `a-sites-incomplete` | A can also happen where the index holds no site |
| `b-sites-incomplete` | every known site of B is proven, but B can also happen where the index holds no site |
| `no-b-site` | B has no site in the index: nothing to judge (a `YES` over nothing would be vacuous) |
| `no-routine-body` | the site is in a program block, an initialization section, at unit level, in an anonymous method, or in a body with `goto` / `asm`, and `program-order` could not order it either |
| `budget` | `--max-routines` or `--max-seconds` ran out |

## Pre-check

Before any routine body is solved, the call graph alone says which sites of B a proof can reach at
all: the routines that hold a site of A, everything that reaches one backwards (calls of every
confidence, dispatch, indirect edges), and everything those reach forwards. A site of B outside
that set cannot be proven, so it answers `MAY` / `a-in-other-routine` at once with the limit
`pre-check` and no routine body is solved for it. When the pre-check refutes every site of B the
`b-first` proof is skipped too. The pre-check stands down (proves nothing, refutes nothing) when A
is in an initialization section or a program block, when a walk passes its node cap, and for
`write:T` / `read:T` (the constructor model of check-init orders sites the call graph does not).

## Examples

Write then read, one routine:

```
> drag-lint happens-before --a write:uHb4.GFwd --b read:uHb4.GFwd --db App.sqlite
happens-before  A = write:uHb4.GFwd (1 site)   B = read:uHb4.GFwd (1 site)
verdict  YES   (proven: every site of B runs after A)
  B  uHb4.pas:49:8  in uHb4.Forward   proven   A runs first on every path (same-routine)
```

The same two statements swapped:

```
> drag-lint happens-before --a write:uHb4.GRev --b read:uHb4.GRev --db App.sqlite
happens-before  A = write:uHb4.GRev (1 site)   B = read:uHb4.GRev (1 site)
verdict  NO   (proven: every site of A runs after a site of B, so the first B runs with no A before it)
  A  uHb4.pas:56:3  in uHb4.Reversed   proven   B runs first on every path (same-routine)
```

The only writer is a call the index cannot resolve:

```
> drag-lint happens-before --a write:uHb4.GUnk --b read:uHb4.GUnk --db App.sqlite
happens-before  A = write:uHb4.GUnk (1 site)   B = read:uHb4.GUnk (2 sites)
verdict  MAY   (not proven either way)
  B  uHb4.pas:62:11  in uHb4.AcrossUnknown   a-site-uncertain   A may happen at uHb4.pas:62:11  ExtFill(GUnk); -- passed to a callee the index cannot resolve: whether it writes is not known
  B  uHb4.pas:63:8  in uHb4.AcrossUnknown   a-site-uncertain   A may happen at uHb4.pas:62:11  ExtFill(GUnk); -- passed to a callee the index cannot resolve: whether it writes is not known
  A  uHb4.pas:62:11  in uHb4.AcrossUnknown   open   not proven to run after B
  A? uHb4.pas:62:11  in uHb4.AcrossUnknown   ExtFill(GUnk); -- passed to a callee the index cannot resolve: whether it writes is not known
limits: check-init: UNKNOWN-CALLEE
```

## Presets

| Preset | Events |
|---|---|
| `randomize` | A = `extcall:Randomize`, B = `extcall:Random` |
| `format-settings` | A = `extwrite:FormatSettings`, B = `extcall:` of the RTL routines that format or parse with the global FormatSettings |
| `before-app-run --a <event>` | B = `app-run:*`: does A happen before `Application.Run`? |

```
drag-lint happens-before --preset randomize --db App.sqlite
drag-lint happens-before --preset format-settings --db App.sqlite
drag-lint happens-before --preset before-app-run --a write:uConfig.GConfig --db App.sqlite
```

`--preset randomize` answers `NO` (`a-never-happens`) when the project calls `Random` and never
`Randomize`, `YES` when every `Random` call is proven to run after a `Randomize`, else `MAY`.
`format-settings` asks whether the settings are assigned before the first format / parse call;
`before-app-run` takes A from `--a` and is refused without it.

## The in-force question (use-after-free, finalization, lock-held-when)

Some events are a STATE, not a moment: an object stays freed until the variable is assigned again, a
lock stays held until it is left. With such an event as A the verb answers a different question,
"is A in force when B runs?" (`"question": "in-force"` in the JSON, `question:` on the verdict line).

| Event | Sites | Undone by |
|---|---|---|
| `free:<QName>` | `X.Free`, `X.Destroy`, `X.DisposeOf`, `FreeAndNil(X)`, `X := nil` | an assignment to X |
| `final-free:<QName>` | the same, only inside a finalization section (unit variable or class var) | -- |
| `held:<QName>` | `L.Enter` / `Acquire` / `BeginRead` / `BeginWrite`, `TMonitor.Enter(L)`, `EnterCriticalSection(L)` | any other mention of L |
| `use:<QName>` (for B) | the dereferencing reads `X.`, `X[`, `X^` | |

| Preset | Events | Wanted |
|---|---|---|
| `use-after-free --a <QName>` | A = `free:X`, B = `use:X` | `NO` |
| `finalization --a <QName>` | A = `final-free:X`, B = `use:X` | `NO` |
| `lock-held-when --a <QName> --b <event>` | A = `held:L`, B = your event | `YES` |

`--a` takes the variable itself (a unit variable, class var or instance field), not an event. Local
variables are not events of this verb; the lint rule `use-after-free` covers them.

```
drag-lint happens-before --preset use-after-free --a uCache.TCache.FItems --db App.sqlite
drag-lint happens-before --preset finalization --a uLog.GLog --db App.sqlite
drag-lint happens-before --preset lock-held-when --a uAcct.TAcct.FLock --b write:uAcct.TAcct.FBalance --db App.sqlite
```

Verdicts:

* `free:` / `final-free:` ask "does B EVER run with A in force?". `YES` = a site of B is in force on
  every path that reaches it (whenever that site runs). `NO` = no site of B can run with A in force
  (`b-never-after-a`), or A never happens (`a-never-happens`). `MAY` = everything else
  (`b-may-run-after-a`).
* `held:` asks "is A in force at EVERY site of B?". `YES` = all of them; `NO` only when the lock is
  never entered anywhere; else `MAY`.

Proofs (the `methods[]` codes; each judged row carries one):

* `in-force` -- in B's own routine a certain site of A lies on every path to the site and nothing
  can have undone it since. A call that can reach a routine which writes (or, for a lock, mentions)
  the variable counts as an undo: calls of every confidence, dispatch, indirect edges.
* `reassigned-first` -- the mirror: a certain assignment on every path and no possible free since.
* `finalization-order` -- nothing that can run after the free reaches the site: no caller chain from
  a finalization section (other than statements before the free in its own section, when that
  section has no loop), from a destructor, or from a routine that can run without a visible call
  (event handlers, published methods, thread Execute, address taken).

```
> drag-lint happens-before --preset finalization --a uFinRes.GCache --db App.sqlite
happens-before  A = final-free:uFinRes.GCache (1 site)   B = use:uFinRes.GCache (1 site)   preset finalization
verdict  MAY   (not proven either way)   question: is A in force when B runs?
  B  uFinUser.pas:23:3  in uFinUser.TNode.Destroy   b-may-run-after-a   uFinUser.TNode.Destroy is a destructor: an object can be destroyed during or after the unit finalizations
limits: aliases-not-followed
```

What it refuses (always `MAY`, never a guess):

* a variable whose address is taken or that another variable overlays (`absolute`);
* a field site on another object than `Self` (`pBox.FItems.Free` is no proof about `Self.FItems`);
* an undo inside the body of a `try..except`, inside an anonymous method, or in the same statement as
  the judged site; a site inside a `with`;
* `final-free:` of a variable that is also freed (or may be) outside a finalization section --
  ask `use-after-free` for that;
* every OTHER unit's finalization section counts as "can run after the free": the unit order is not
  used. A lock held by the CALLER is not seen (`MAY`).

Limits on every in-force answer: `aliases-not-followed` (another reference to the same object, or an
owner that frees it, is not a site) and, on a proven one, `callbacks-not-modelled` (code the index
does not hold calling back into the project between the two sites).

## Handler order: what a program-order YES assumes

A `YES` with the limit `program-order: relied-on-handler-order` counts a DFM-bound event handler as
running after the WHOLE program-block prefix, up to `Application.Run` -- also after statements that
follow `Application.CreateForm`. That holds because such a handler fires from the message loop; the
OnCreate family, handlers the code references and forms created at run time are never ordered, and a
top-level `ShowModal` / `ProcessMessages` / dialog call in the prefix switches the ordering off.
Not seen: a message pump inside a ROUTINE the prefix calls, or in a unit initialization. If your
prefix calls such a routine before the write, read that `YES` as `MAY`. A `NO` never leans on it.

## --json

One line:

```
{ "verb": "happens-before", "preset": "randomize",
  "a": { "event", "kind", "name", "complete", "incomplete": [..],
         "sites": [ { "file", "line", "col", "routine", "definite", "note" } ] },
  "b": { .. },
  "verdict": "YES" | "NO" | "MAY", "proven": true | false, "summary": "..",
  "reasons": [ code ], "methods": [ code ],
  "judged": [ { "side": "a" | "b", "file", "line", "col", "routine", "proven", "method", "reason", "why" } ],
  "limits": [ code ], "budget": { "routines", "ms", "exhausted" } }
```

`preset` is present only for a preset question. `judged` holds the sites of B judged against A
(`side` = `b`) and, when the `b-first` proof was tried, the sites of A judged against B (`side` =
`a`). The reason and method codes are closed lists; tools may branch on them.

## Limits

* **Sites are not instances.** `write:TFoo.FBar` is a write of `FBar` on ANY object; the answer
  carries the limit `instance-insensitive`. For "is this field set on the same object before it is
  used" ask [check-init](check-init).
* **`extcall:` matches by name** (limit `matched-by-name`): a same-named routine of another unit the
  index does not hold matches too.
* **Order across routines** is proven through certain calls (`callee`, `callers`) and, for the
  initialization chain, the program block, handler order and call chains, by `program-order` for
  every event kind. A `program-order` `YES` that depended on a heuristic carries the limit
  `program-order: relied-on-handler-order` (the order handlers run in was assumed) or
  `program-order: relied-on-indirect-edges` (an indirect call edge was followed); a `NO` never
  does. What neither proves answers `MAY` (`no-routine-body`).
* **`pre-check`**: the call graph alone showed that no routine performing A reaches a site of B;
  that site answers `MAY` without a routine body being solved.
* The `check-init` method inherits check-init's reading of a `var` / `out` argument as a write; its
  own limits travel with the answer as `check-init: <code>`.
* `--max-routines N` (default 2000) caps the routine bodies solved, `--max-seconds S` (default 60,
  0 = none) the wall clock; an answer stopped by either carries the limit `budget` and is never
  `YES` or `NO` because of it.
* On demand only: the verb is not part of `lint-all`.

Guards: `tests\autotest\run_v156_HB4.ps1`, `tests\autotest\run_v156_HB5.ps1`.
