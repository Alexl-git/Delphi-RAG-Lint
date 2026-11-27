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
drag-lint happens-before --preset <name> --db <db> [--json]
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
| `extcall:<Name>` | the calls of a routine the index does NOT hold (RTL, a library), matched by name |
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

`NO` -- one of two proofs:

| Reason | Proof |
|---|---|
| `a-never-happens` | A is complete and has no site, B has at least one |
| `b-first` | A is complete and every site of A (uncertain ones too) runs after a site of B in its own routine: the first A of any run is preceded by a B that no A preceded |

`MAY` -- each unproven site of B carries one reason:

| Reason | Meaning |
|---|---|
| `a-not-on-every-path` | A is in the routine, but a path reaches B without it (an `if`, a loop, an exception handler) |
| `a-site-uncertain` | the only A in the routine is an uncertain site |
| `a-in-other-routine` | A has no site in B's routine, in a callee that always performs it, or before every call of B's routine |
| `a-sites-incomplete` | A can also happen where the index holds no site |
| `b-sites-incomplete` | every known site of B is proven, but B can also happen where the index holds no site |
| `no-b-site` | B has no site in the index: nothing to judge (a `YES` over nothing would be vacuous) |
| `no-routine-body` | the site is in a program block, an initialization section, at unit level, in an anonymous method, or in a body with `goto` / `asm` |
| `budget` | `--max-routines` or `--max-seconds` ran out |

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

`--preset randomize` answers `NO` (`a-never-happens`) when the project calls `Random` and never
`Randomize`, `YES` when every `Random` call is proven to run after a `Randomize`, else `MAY`.

Not built (they are not "A before every B" over sites, or need the order of initialization
sections for call events): `use-after-free`, `lock-held-when`, `format-settings`,
`before-app-run`, `finalization`.

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
* **Order across routines** is proven through certain calls only (`callee`, `callers`). The order of
  initialization sections and the program block is known to the check-init solver, so it is proven
  for `write:T` / `read:T` pairs only; a `call:` or `site:` event there answers `MAY`
  (`no-routine-body`).
* The `check-init` method inherits check-init's reading of a `var` / `out` argument as a write; its
  own limits travel with the answer as `check-init: <code>`.
* `--max-routines N` (default 2000) caps the routine bodies solved, `--max-seconds S` (default 60,
  0 = none) the wall clock; an answer stopped by either carries the limit `budget` and is never
  `YES` or `NO` because of it.
* On demand only: the verb is not part of `lint-all`.

Guard: `tests\autotest\run_v156_HB4.ps1`.
