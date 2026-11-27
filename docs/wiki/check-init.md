# check-init

Answers "is this variable or field set before it is used, on every execution?" for ONE
unit variable, class var or instance field.

It reads the index (no new data is persisted) and names the writers, the use, and -- when it
cannot prove the value is set -- the first reason why not. The answer is one of four verdicts:

| Verdict | Meaning |
|---|---|
| `SET` | proven: every judged use runs after a writer that counts as initialization, on every path |
| `NEVER-SET` | proven absence: no resolved writer, no soft writer, not published (streamed), no `absolute` overlay |
| `MAY-BE-UNSET` | everything else. "Not proven safe" -- never a proof that a run is bad |
| `UNKNOWN-CALLEE` | not SET, and a call on the path has no source in the index (it may set the target by reference); the headline names the callee, the judged uses stay `MAY-BE-UNSET` and carry reason `unknown-callee`. Record the answer once (see "Calls with no source" below) |

`:= nil` (and `FreeAndNil`) is NOT an initialization of a class, interface, pointer or procedural
target: such a writer is listed as `assign-nil  (does not count)`.

## Running it

```
drag-lint check-init <QName> [--at <file>:<line>[:<col>]] --db <db> [--json] [--explain] [--max-routines N] [--max-seconds S]
```

* `<QName>` is `Unit.GVar`, `Unit.TClass.ClassVar` or `Unit.TClass.FField`. With only `--at`, the
  variable under that position is the target; a line-only `--at file:line` judges the use at its
  real column.
* Exit 0: every judged use is SET. Exit 1: the verdict is MAY-BE-UNSET, NEVER-SET or UNKNOWN-CALLEE. Exit 2: usage or
  other error (unknown or ambiguous target, bad `--at`, no `--db`, unreadable DB); the message goes
  to stderr and stdout stays empty, so a `--json` consumer never parses half a document.
* `--explain` adds the root chain and the `reasons:` line under every use.
* `--max-routines N` caps the routines analysed (default 2000). When the cap is hit the answer is
  MAY-BE-UNSET with reason `budget` and `budget.exhausted` is true.
* `--max-seconds S` caps the wall clock of one query (default 60; decimals allowed; `0` = no cap).
  A query the cap stops is never SET: it answers MAY-BE-UNSET with reason `budget`, the limit
  `stopped-after <S>s`, a summary starting `(stopped after S s`, and `budget.timed_out` and
  `budget.exhausted` true. A large project's widely used global can take minutes uncapped
  (measured: up to 11 min on a 2600-unit client), so the cap is on by default.
* `--json` prints one object: `target`, `verdict`, `proven`, `scope`, `summary`, `reasons`,
  `uses[]` (`file`, `line`, `col`, `routine`, `verdict`, `reasons`, `why`, `witness[]`),
  `writers[]` (`how`, `resolved`, `counts`, `fired_by`, `callers`), `roots`, `limits`, `budget` (`routines`, `ms`, `exhausted`, `max_s`, `timed_out`).
* MCP: the tool `check_init` takes `target` or `at`, `explain`, `max_routines`, `max_seconds`, `db` and returns the
  same JSON.
* IDE: Analyze > Check Initialization of Identifier at Cursor... (also in the editor context menu) runs the same engine on the identifier under the caret.
* Hover: the `Set by:` section of a variable or field hover runs the same engine with a smaller budget -- 200 routines and 5 s wall clock (environment variables `DRAGLINT_HOVER_SETBY_MAX_ROUTINES` / `DRAGLINT_HOVER_SETBY_MAX_SECONDS`); a capped solve shows `budget exceeded`.

## An answer: a read that runs before its writer

`SolveInitOrder`: unit `siSecond` is listed first in the `.dpr` and reads `siFirst.GCfg`, which only
`siFirst` writes in its `initialization` section. `siFirst` initializes second, so the read sees 0.

```
> drag-lint check-init siFirst.GCfg --explain --db <db>
siFirst.GCfg : Integer (unit-variable, siFirst.pas:10) -- zero value until set: 0
verdict  MAY-BE-UNSET   (not proven)
writers (1)
  siFirst.pas:25:3  siFirst.initialization  assign
use  siSecond.pas:17:20  MAY-BE-UNSET
witness
  1  siSecond.initialization  siSecond.pas:16:0  initialization of siSecond, link 1 of 3 (SolveInitOrder.dpr)
  2    siSecond.initialization  siSecond.pas:17:20  reads GCfg
why not SET: root "initialization of siSecond" (link 1 of 3) runs before "initialization of siFirst" (link 2), which writes it
  reasons: writer-later-unit
uses judged (2): 0 SET, 0 NEVER-SET, 2 MAY-BE-UNSET
roots: ordered 3 (initialization of siSecond -> initialization of siFirst -> program block of SolveInitOrder.dpr), unordered 0
limits: none
[exit 1]
```

(The real output lists the first use, `siFirst.pas:21:12`, as well; shortened here.) The witness is
printed root-first: each hop is one step from the root to the read.

A proven answer is short:

```
> drag-lint check-init scData.GData --db <db>
scData.GData : Integer (unit-variable, scData.pas:6) -- zero value until set: 0
use  scWork.pas:14:6  in scWork.Level3
verdict  SET   (proven: every judged use runs after a counting writer)
writers (1)
  scData.pas:16:3  scData.SetData  assign  called from 1 routines: SolveCallChain
limits: none
[exit 0]
```

and so is a proven absence:

```
> drag-lint check-init evgData.GNever --db <db>
evgData.GNever : Integer (unit-variable, evgData.pas:31) -- zero value until set: 0
use  evgData.pas:78:19  in evgData.UseIt
verdict  NEVER-SET   no resolved writer, no soft writer, not published, no absolute overlay
why not SET: nothing ever writes it
limits: none
[exit 1]
```

## Instance fields: the constructor model

For a field, the question is per object: does every constructor that can build the object set the
field before the use runs? The engine checks the declared constructors (including a chained
`inherited Create`), the subclasses, and what the constructor does with `Self`.

```
> drag-lint check-init fcData.TBoth.FHalf --explain --db <db>
fcData.TBoth.FHalf : TObject (instance-field, fcData.pas:9) -- zero value until set: nil
use  fcData.pas:81:3  in fcData.TBoth.Run
verdict  MAY-BE-UNSET   (not proven: fcData.TBoth.CreateFor does not set FHalf on every path) writer routines: fcData.TBoth.Create (constructor)
writers (1)
  fcData.pas:62:3  fcData.TBoth.Create  create-into  called from 1 routines: fcData.TBoth.CreateChained
witness
  1  fcData.TBoth.CreateFor  fcData.pas:66:0  does not set FHalf on every path
  2    fcData.TBoth.Run  fcData.pas:81:3  reads FHalf
why not SET: fcData.TBoth.CreateFor does not set FHalf on every path
  reasons: ctor-misses-field
roots: ordered 0, unordered 0
limits: instance-by-constructors
[exit 1]
```

Writers of a field include a write through a property whose write accessor IS the field
(`property Number: Integer read FNumber write FNumber`; `Item.Number:= 5`), listed at the property
write; a read of such a property (`read FNumber`) is a use of the field. A write through a setter
method counts through the call to the setter. `X.Number:= ..` whose receiver type the index could
not resolve is a soft writer (the field is then never NEVER-SET).

A component field streamed from the form file is set by the inherited form constructor: its uses
outside a constructor are judged as if a constructor set it (not when a constructor calls
`CreateNew`). A read through ANOTHER object (`Other.FField`) is proven only by the constructor
model; a write of Self earlier in the same routine does not count for it (`receiver-unproven`).

A MAY answer for a field also lists the writer routines in the verdict line, each marked
`(constructor)` or `(not called by every constructor)`, so you can see where the value comes from
even when it is not proven.

## Reason codes

Each use carries the codes that stop it from being SET (`--explain` prints them; `--json` always
has them in `reasons`). The list is closed and appended to only; tools branch on the literals.

| Code | Meaning |
|---|---|
| `unordered-root` | the use is reached from a root that is in no program's initialization order and can run at any time |
| `escaped-routine` | the routine is exported, an interface method, has no callers, or its address is taken |
| `indirect-call` | the routine is reached through a procedural value or address (with `escaped-routine`); since 1.56 a call through a procedural value is also a hop of the witness, and it never proves a write |
| `relied-on-indirect-edges` | on a SET: the proof took a routine that is named as a value (callback, procedural variable, event) for one that runs only through the calls of its slot that the index lists (table `indirect_edges`). The why-text names the routine, the slot and the call site. Conditions: every naming of the routine is the binding of an edge; every edge has a call site in the index and is resolved; the slot is a parameter / local / field / unit variable that is only assigned, called and tested with `Assigned()`; a property over a field slot is only written; every call through the slot has an edge. Any doubt keeps the routine an escaped root (MAY-BE-UNSET) and the why-text says which condition failed |
| `writer-later-unit` | a unit that initializes later than the reading root writes it |
| `writer-conditional` | a writer before the use does not run on every path (also: a use in a destructor) |
| `writer-after-use-same-routine` | the only writer in the routine runs after the use (also: the use is reached from a constructor before the write) |
| `callee-not-must` | a routine called before the use does not write the value on every path |
| `virtual-fanout` | a virtual call before the use can dispatch to an override that does not write it |
| `soft-writer` | a write the index cannot resolve (unresolved name, `with`, address-of): it never helps prove SET and forbids NEVER-SET |
| `nil-write-only` | the only writers are `:= nil` / `FreeAndNil` on a reference type |
| `ctor-misses-field` | a constructor does not set the field on every path (also: a declared overload leaves an inherited constructor callable) |
| `no-declared-ctor` | the class declares no constructor, so nothing is guaranteed to set the field |
| `subclass-ctor-skips` | a subclass constructor does not chain to a constructor that sets the field |
| `virtual-call-in-ancestor-ctor` | an ancestor constructor makes a virtual call that can reach the use before the descendant sets the field |
| `self-escapes-in-ctor` | the constructor hands `Self` out before it sets the field |
| `unreliable-order` | the initialization order depends on a conditional or include-borne `uses` entry |
| `multi-program` | the target is judged in more than one program and not every one proves SET |
| `cfg-skipped` | a routine on the path holds `goto`, a label or `asm` and was not analysed |
| `budget` | the `--max-routines` cap or the `--max-seconds` wall-clock cap ran out before the use was proven |
| `guarded-test` | the use is the operand of an `Assigned` / `<> nil` test (it is a guard, not a dereference) |
| `relied-on-handler-order` | see below |
| `unknown-callee` | a call on the path has no source in the index and nobody recorded whether it reads or sets the target (headline `UNKNOWN-CALLEE`) |
| `receiver-unproven` | an instance-field use the constructor model left MAY: the call that sets the field (Init) and the use (Run) could not be proven to run on the same object; the `why` names the first call site that broke the proof |

Reserved in the contract but not produced by the engine yet: `interface-call`, `writer-on-thread`,
`index-incomplete`.

### Receiver proof: `SET by receiver`

When the constructor model leaves a field use MAY (`ctor-misses-field`, `no-declared-ctor`,
`subclass-ctor-skips`), the engine checks whether the method that sets the field runs on the SAME
object before the method that uses it. Proven receivers: a local variable, a value or const
parameter, `Self` (up to 4 call levels), and a field of `Self` that every constructor of its owner
creates and initializes. A proven use turns SET and says

```
SET by receiver: <writer> runs on <receiver> before <caller> calls on it at <file>:<line>
```

and the answer summary adds `(receiver-proven: ...)`. Anything else -- a unit or program variable,
a var / out / constref parameter, a chain, a function result, `with`, a receiver handed out
between the two calls, a use inside an anonymous method -- keeps the use MAY-BE-UNSET and adds
`receiver-unproven`. A field receiver freed in the destructor (`FreeAndNil(FW)`) is unproven too.

### Calls with no source: `checkInit.callees`

A call whose callee has no source in the index (a DLL import, a library without source) may set
the target through a var parameter. The engine cannot tell, so the answer is `UNKNOWN-CALLEE`.
Record the answer once per project in `<anchor>\_D-RAG\drag-lint-project.json` (beside the DB):

```json
{ "checkInit": { "callees": { "ReadExternal": "reads", "LoadExternal": "sets" } } }
```

`reads` = the callee only reads the argument (no writer, no warning); `sets` = it writes it (a
writer at the call). A dotless key matches the last part of the call; a dotted key matches only the
exact call text. Any other value, a malformed file or no anchor = no answer. A line marker
`// dl:callee-reads` or `// dl:callee-sets` on the call line wins over the project file.

### `relied-on-handler-order`

A DFM-bound event handler of a form that the program block creates with `Application.CreateForm`
runs after every statement before `Application.Run` (and after every unit initialization). The
engine uses that to prove a handler's use SET. This is a name heuristic, so every answer that used
it says so: the reason code, and the line

```
use  hoMain.pas:44:9  SET
relies on handler order: hoMain.TMainForm.btnGoClick (fired by MainForm.btnGo.OnClick) runs only after the program-block prefix of HandlersOrder (Application.Run at HandlersOrder.dpr:17) -- name heuristic, OnCreate family excluded
  reasons: relied-on-handler-order
```

A SET with this reason is only as good as the heuristic. The handler is NOT treated as ordered
(it stays an unordered root) when any of these holds:

* the event is of the OnCreate family: OnCreate, OnShow, OnActivate, OnResize, OnPaint, OnDestroy,
  OnTimer; a data-set Before* / After* event; a FormCreate-family method name;
* the code refers to the handler (a call, an address, an `OnX := Method` assignment): it can run
  outside the message loop;
* the form is created at run time or conditionally, not by an unconditional top-level
  `Application.CreateForm` before `Application.Run`;
* the program block has no unconditional `Application.Run`, or a statement before it pumps messages
  or fires events directly (`ShowModal`, `ProcessMessages`, ...).

Then the use is `MAY-BE-UNSET` with `unordered-root`, and the `why` text names which rule applied.
A pump hidden inside a routine the prefix calls, or inside a unit initialization, is not seen.

## Limits

`limits[]` names what the engine did not model. Every code means "the verdict above may be less
sharp than it looks", never "wrong":

| Limit | Meaning |
|---|---|
| `instance-by-constructors` | a field answer rests on the constructor model, not on tracking each object |
| `use-after-free-not-judged <file>:<line>` | names a `:= nil` / free writer of the field; a use after it is not judged |
| `unknown-callee` | a call on the path has no source in the index; the summary starts `UNKNOWN-CALLEE:` and names it (does it set the target by reference?) |
| `stopped-after <S>s` | the `--max-seconds` cap stopped the query; the verdict is never SET |
| `no-judged-use` | the answer is SET over ZERO judged uses: nothing reads the target, so the SET says nothing about a read (the summary says so too) |

Not modelled (a verdict stays MAY, it is never wrongly SET in the test fixtures): `Self` handed
out by a method called before the write; a use reached from a destructor's callees; an ancestor
constructor that writes the field before `inherited` is always flagged; a conditional `inherited`
in a descendant constructor counts as not chaining.

Calls through procedural values: since 1.56 the index pairs every binding of a slot with every call
through it (`indirect_edges`). check-init uses these edges as callers, never as writers. Not covered,
and therefore still an escaped root: a handler bound to a library event (`Button.OnClick`) or in a
`.dfm`, a slot that is copied or passed on, a binding the indexer declines (anonymous method,
setter behind an event property, `with`, a binding over two lines), a function named without `@`.
When the edges are not enough the answer says why (for example "pCb is read as a value (it can be
copied or passed on)", "no indirect-call edge binds it", "bound to Button1.OnClick, which this index
never calls"). A SET that relied on the edges says so in its summary line: "uses with
relied-on-indirect-edges rely on the index's indirect-call edges (1.56)". An index written before
1.56 gives the 1.55 answers (no `indirect_edges` table, no `must_writes` fact).

Other 1.56 changes: on an instance field, methods whose stored must-write fact lists the field, and
methods that hold no writer of it, no longer cost a flow graph, so a class with many methods no
longer ends in `budget` at the default `--max-routines`. On a numeric / Boolean / date-time
variable the argument events are the 1.55 ones (the new value rows of `data_flows` are not read as
argument rows).

## What to do with the answer

* `SET`: an `Assigned` guard on the use is dead weight; the initialization order covers it.
* `MAY-BE-UNSET`: read the `why not SET` line and the witness. `writer-later-unit` is the classic
  initialization-order bug: move the writer or the `uses` entry.
* `NEVER-SET`: delete the variable or add the missing write.
* Do not treat MAY as a bug report: it is "not proven".

See also: `find-callers` and `usages`.