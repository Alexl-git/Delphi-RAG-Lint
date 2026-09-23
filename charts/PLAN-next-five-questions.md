<!-- dl:backlog status=open last-measured=2026-09-23 -->
# PLAN: the next five diagram questions

For a COLD session. Work ONLY under `charts\`. Five questions already ship
(`butterfly`, `deps`, `who-calls`, `event-wiring`, `touches-tables`) and are the
reference implementations; `charts\src\Test-Emitters.ps1` is the gate.

**Every number below was MEASURED on 2026-09-23 against the named indexes. Do
not re-derive them -- compare against them.** A number that does not match is a
FINDING: investigate before "fixing" the number.

```
$E   = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\third_party\dll-win64\drag-lint.exe'
$DOT = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe'
$CLI = 'C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite'
$SRV = 'C:\Projects\DB\ORM3\SERVER\_D-RAG\MicroniteMW1Service.sqlite'
$SRC = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\charts\src'
```

## Why these five

The batch adds the **two selection kinds the tool cannot yet answer for at
all** -- field/property and type -- and one item that is nearly free by reuse.
Selection-kind coverage today: method, unit, form-class. After this batch:
method, unit, form-class, field, property, type.

| # | question | selects | new? | effort |
|---|---|---|---|---|
| 1 | `what-it-calls` | method | reuse | **S** |
| 2 | `who-writes` | field / property | NEW KIND | **L** |
| 3 | `who-reads` | field / property | same emitter as 2 | **S** |
| 4 | `hierarchy` | type | NEW KIND | **M** |
| 5 | `class-surface` | type | same kind as 4 | **M** |

**Five CATALOGUE QUESTIONS, four EMITTERS.** `who-writes` and `who-reads` are
two rows of the catalogue answered by one `-Mode` switch, and `what-it-calls`
is a `-Direction` switch on the existing `Emit-WhoCalls.ps1`. Say it that way
in the report -- counting four emitters as five pieces of work would overstate
the batch, and counting two catalogue rows as one would understate the result.

`effects` was considered and DEFERRED, but **not because it is blocked**: the
`effect_summary` encoding (measured value `g,s,?`) is implemented in this repo
and can simply be read. It is deferred because decoding it is a different kind
of task from drawing a chart, and this batch is already the one that opens two
new selection kinds. Whoever picks it up should read the encoder first, NOT
wait on the engine team.

---

## The four measured findings that decide the design

These cost a measurement pass to establish. Do not re-litigate them; they are
the reason this plan differs from what `question-catalogue.md` implies.

### 1. Use `find-callers --resolved`. Do NOT hand-roll this from `member_accesses`.

```
drag-lint query find-callers --name <member> --db <db> --resolved --json
  -> [ { caller_qname, file, confidence, target_qname, line, mode } ]
```

`caller_qname` IS the enclosing routine, `mode` is `read`/`write`, and
`confidence` is `certain`/`ambiguous`. Measured against SQL ground truth on
`MSCTYPES.RChartSampleData.R` -- identical: `DrawSample` r2/w3,
`DrawSampleChartHoriz` r7, `DrawChartCol` r2/w2, `DrawChartColSampleRec` r2/w2,
20 rows total.

**The verb is NOT subject to the 200-row sql cap** -- measured 602 rows / 598
distinct callers for `Connected`, where the `sql` verb truncates at 200.

**A WARNING, because this nearly became this project's second false defect
report.** `member_accesses.accessor_symbol_id` does NOT mean "who touched the
member" -- it names the property's BACKING (`Connected` -> `FConnected`,
`VERDICT` -> `GetVERDICT`/`SetVERDICT`), and every `field` access has it NULL
(3,355 / 3,355 on CLIENT). That looks exactly like a defect and IS NOT ONE. It
is a shipped, owner-ruled design: *a property read is a call to its read
accessor; a field-backed accessor is a read/write use of that field*
(`docs\INBOX-property-refs-never-resolve.md`, RETIRED, shipped in `bc2e39dc`,
resolver 1.3.0-alpha). The column answers "which accessor implements this
access". That is a real question. It is simply not OUR question.

**Do not file it. Do not "work around" it. Ask the verb instead.**

### 2. The SITE anchor still needs SQL -- `--resolved` gives you the routine, not the spot

Measured: `--resolved`'s `line` is the **caller's DECLARATION line**, uniformly
for methods and members -- `AddOperation` 362, `ImportJenVICI` 376,
`DrawChartCol` 304, each matching `symbols.start_line` exactly. It answers
*which routine*, never *where inside it*.

A row in these charts must open the place the member is actually touched, so
the emitter needs a second, SMALL query for the sites of the routines it is
about to SHOW. That query is where line containment earns its place:

```sql
(SELECT s.qualified_name FROM symbols s
  WHERE s.file_id = r.file_id AND s.impl_start_line IS NOT NULL
    AND r.start_line BETWEEN s.impl_start_line AND s.impl_end_line
  ORDER BY s.impl_start_line DESC LIMIT 1)      -- innermost wins
```

Measured on **BOTH** indexes, not one: CLIENT **9,311 resolved / 0
unresolved**, SERVER **14,836 resolved / 0 unresolved**. Spot-checked correct
(`BASICSF.DrawSample`, `DrawSampleChartHoriz`, `DrawChartCol`,
`DrawChartColSampleRec`).

`ORDER BY impl_start_line DESC LIMIT 1` is load-bearing -- it picks the
INNERMOST enclosing routine. Without it a nested routine's accesses are
attributed to its parent.

This is NOT a workaround for a defect (see finding 1) -- it is how you get a
line+col the engine's verb does not report. Task 0 still isolates it in one
helper so the three emitters cannot drift apart on it.

**STILL UNVERIFIED -- check this in Task 0 before building on it.** Whether
accesses written inside a Delphi `with` block are recorded in
`member_accesses` at all. A `with` suppresses the receiver, so the extractor
may not bind the member. If they are missing, `who-writes` UNDERCOUNTS on
legacy code that uses `with` heavily, and that must be disclosed in the chart
rather than discovered later. Write the check as a query over a unit known to
use `with`; do not assume either answer.

### 3. A ROW IS AN ACCESS SITE (line + col), NOT A LINE

`BASICSF.pas:4072` holds **three** accesses to `RChartSampleData.R`: reads at
col 34 and col 51, a write at col 63. Keying or grouping by line alone silently
merges three facts into one. Same rule as who-calls' call sites; key the port
map by ORDINAL.

### 4. The cap belongs to the `sql` verb only -- but the CHART still needs a cap

The guarded SQL caps at 200 rows and truncation is SILENT. Grouping the 602
reads of `Connected` by routine still returns 200 rows `truncated=True`,
because those 602 sites live in **598 distinct routines**. `find-callers
--resolved` is not capped and returns all 602 -- which is why step 1 uses the
verb and step 2 uses bounded SQL.

**The readability cap is a separate decision and still applies.** A chart with
598 rows is not a chart. Rank, cap and disclose regardless of what the engine
is willing to return. Measured totals:

| target | writes | reads | distinct routines | sites |
|---|---|---|---|---|
| `TPipeClientConnection.Connected` | 0 | 602 | 598 | 602 |
| `ImcINSPRSLT.VERDICT` | 34 | 12 | 30 | 46 |
| `MSCTYPES.RChartSampleData.R` | 7 | 13 | 4 | 20 |

So the emitter must **rank, cap and DISCLOSE** (catalogue branch policy 3):
take totals from a `COUNT` query the cap cannot distort, render the top N
routines, and add an explicit non-anchored row
`"+573 more routines (+577 more sites) not shown"`. **Never drop silently.**

**Two rules that fall out of truncation being silent:**

* **Treat a result of EXACTLY 200 rows as possibly truncated and refuse**, even
  when the `truncated` flag is absent. 200 is the cap; a query that lands
  exactly on it is indistinguishable from one that was cut, and guessing wrong
  renders a short answer as a whole one.
* **Never issue a per-routine follow-up query.** The chart's rows ARE routines
  (tens), not sites (hundreds), so `COUNT(*)` plus `MIN(start_line)` as the row
  anchor answers it in ONE query. A query per shown routine is N extra process
  spawns for information the chart does not display.

---

## Task 0 -- helper additions (do first)

Add to `charts\src\Emit-Common.ps1`; all four new emitters dot-source it.

* `Get-EnclosingRoutineSql([string] $RefAlias)` -- returns the correlated
  subquery in finding 2 as text, so three emitters cannot drift apart on it.
* `Add-DisclosureRow` -- appends a NON-ANCHORED row to a cluster table
  (`"+N more ... not shown"`). There is no line to click; a dead link is worse
  than no link. `touches-tables` already builds one inline for its zero case --
  move that to the helper and have both use it.
* `Get-TopRanked($Rows, [int] $Cap)` -- returns `@{ Shown; HiddenRows;
  HiddenSites }` so every caller discloses in the same words.
* Confirm `Get-EngineText` already brackets on `{` OR `[`. `surface` and
  `query find-callers` both return bare ARRAYS. It does; do not "fix" it back.

**Three measurements to take BEFORE writing any emitter.** Each one changes a
design decision, and each is cheap:

1. **`with`-block attribution** (finding 2) -- are member accesses inside a
   Delphi `with` recorded at all? If not, `who-writes` undercounts on legacy
   code and must say so on the chart.
   **HOLD THIS ONE. Engine reply 2026-09-23:** Task 7 of their enum-binding
   plan measures the `with` risk on CLIENT and will file a note with a real
   number and the METHOD for getting it. That measures **enum-value reads**
   inside `with` -- a DIFFERENT population from our member accesses generally,
   and they explicitly will not assert on ours. Wait for that note, reuse the
   method, then decide whether our half still needs its own pass. If the two
   share a root cause it will be visible there.
2. **`modifiers` shape** (Task 5) -- does it carry visibility in a parseable
   form? If not, cluster `class-surface` by `kind` and label it as such.
3. **Selection ambiguity** -- `Get-SymbolLocation` currently takes the FIRST of
   several matches and only prints a note. For a field/property selection that
   is too quiet: a bare `FConnected` exists in several classes. Decide whether
   the new emitters require a fully qualified name and REFUSE an ambiguous one.
   Prefer refusing: the whole chart is about one member, and picking the wrong
   one silently mislabels every row in it.

**Encoding, after EVERY edit** -- strict 7-bit ASCII, CRLF, no BOM:

```powershell
foreach ($f in (Get-ChildItem "$SRC\*.ps1")) {
  $t=[IO.File]::ReadAllText($f.FullName)
  $bad=([regex]::Matches($t,'[^\x09\x0A\x0D\x20-\x7E]')).Count
  if ($bad) { throw "$($f.Name): $bad non-ASCII byte(s)" }
  [IO.File]::WriteAllText($f.FullName, ($t -replace "`r`n","`n" -replace "`n","`r`n"), [Text.ASCIIEncoding]::new())
}
```

---

## Task 1 -- `what-it-calls` (effort S)

`reverse-calltree --qname <Q> --direction callees --depth <D> --format json`.
**Identical schema to who-calls**, children under `callers` at every level in
BOTH directions (the trap `butterfly` already documents).

Implement as a `-Direction callers|callees` switch **inside `Emit-WhoCalls.ps1`**
rather than a new file: the flatten, the ordinal port map, the cycle handling
and the cluster rule are the same code. Only three things change:

* edge direction -- focus -> row for callees, row -> focus for callers;
* the palette role -- callee amber (`#B45309`) instead of caller blue;
* the empty-result message -- "calls nothing", NOT the event-wiring hint.

**Do NOT run the name-match bucket for callees.** `find-callers --name` answers
the caller question only; there is no name-match analogue downward, and
reporting one would be a fabricated number.

**VERIFY** (`SendDeltaOperation`, `$CLI`):

| depth | node_count | rows | cycles | truncated |
|---|---|---|---|---|
| 1 | 3 | 2 | 0 | True |
| 2 | 9 | 8 | 0 | True |
| 3 | 17 | 16 | 5 | True |

Depth 2 rows must equal `butterfly`'s `Callees` (8) -- that is the regression
tying the two together.

**`rows + 1 -eq node_count` was CHALLENGED and then VERIFIED for callees,
including with cycles present** -- measured 2/3, 8/9, 16/17 and 17/18 at depths
1-4 (5 cycle rows from depth 3 on). The invariant is safe to keep asserting in
the callee direction; it does not need a "unique vs visited" caveat.

---

## Task 2 -- `who-writes` (effort L) and Task 3 -- `who-reads` (effort S)

ONE emitter, `Emit-MemberAccess.ps1`, with `-Mode write|read|both`. The second
task is the `-Mode read` path plus its tests.

Selection is a FIELD or PROPERTY qname. Resolve it with `Get-SymbolLocation`;
if the symbol's `kind` is neither `field` nor `property`, throw
`"<Q> is a <kind>, not a field or property -- ask who-calls instead"`.

**Step 1 -- the routines, from the VERB, uncapped:**
`query find-callers --name <bare member name> --db <db> --resolved --json`.
Filter `target_qname` to the selected member (a bare `--name` can match members
of several classes -- measured: `R` matched only `RChartSampleData.R` here, but
do not rely on that). Group by `caller_qname` + `mode`; that gives totals,
distinct routines and per-routine counts in ONE call with no cap.

**Step 2 -- site anchors, SQL, for the SHOWN routines only:** the containment
query of finding 2, bounded by an IN-list of the routines that survived the
cap, carrying `start_line` AND `start_col`. Bounded that way it cannot approach
200 rows.

Two queries total. **Never one query per routine** -- that is N process spawns
for data the chart does not display.

**Cross-check step 1 against step 2 on the demo target.** If the verb reports
7 writes and the SQL finds 7 write sites, both agree; a mismatch is a finding
worth reporting, not a number to average.

**DECISION -- a property and its backing field are DIFFERENT selections.**
`Connected` is backed by `FConnected`. Asking `who-writes Connected` reports
writes through the PROPERTY only; it does NOT silently union the writes to
`FConnected` inside the class, and it does not hide the setter. Unioning them
would answer a question the user did not ask and would double-count the
setter's own assignment. Instead, when the selected property has a backing
field (`symbols.prop_access` names it), add ONE non-anchored note row:
`"backed by FConnected -- ask who-writes on it for writes that bypass this
property"`. That keeps both answers reachable and neither invented.

Layout: LEFT cluster(s) = WRITERS (grouped by unit, `penwidth=2.2`, edge
routine -> focus), FOCUS = the member, RIGHT = READERS (edge focus -> routine).
A routine that both reads and writes appears on BOTH sides -- that is the
honest answer, same ruling as a table in both `touches-tables` wings. Row label
is the routine's short name, `:line` is its FIRST site, the tooltip names the
site count (`"3 write sites: 4072:63, 4073:9, 4075:57"`).

New role, this emitter only: `state = '#0E7490' / '#ECFEFF'` (cyan) -- distinct
from caller blue, callee amber, focus teal, ui violet, db rose.

**VERIFY**

| command | expect |
|---|---|
| `-Qname MSCTYPES.RChartSampleData.R -Mode both -DbPath $CLI` | Writes **7**, Reads **13**, Routines **4**, Sites **20**, Hidden 0. Writers: `DrawSample` 3, `DrawChartCol` 2, `DrawChartColSampleRec` 2. Readers: `DrawSampleChartHoriz` 7, `DrawSample` 2, `DrawChartCol` 2, `DrawChartColSampleRec` 2. Three routines appear on BOTH sides. |
| `-Qname iINSPRSLT.ImcINSPRSLT.VERDICT -Mode both -DbPath $CLI` | Writes **34**, Reads **12**, Routines **30**, Sites **46** |
| `-Qname uPipeClientConnection.TPipeClientConnection.Connected -Mode read -DbPath $CLI -Cap 25` | Reads **602**, Routines **598**, Shown 25, **HiddenRoutines 573**, disclosure row present, `Truncated` never silently true |

`R`'s accesses are all in `BASICSF.pas` and all UNATTRIBUTED in
`accessor_symbol_id` -- if the emitter reports 0 routines, it read the wrong
column. That is the regression guarding finding 1.

---

## Task 4 -- `hierarchy` (effort M)

`query ancestors --name <T> --json` and `query descendants --of <T> --json`.

**Two measured constraints:**

* `descendants` returns **bare NAMES only** -- no file, no line. Each name needs
  a second `Get-SymbolLocation` to become clickable. Batch them in ONE
  `name IN (...)` query, not N queries. **These are BARE names, not qualified
  ones, so the lookup can collide** -- two units may both declare a `TSettings`.
  On a collision, render the row un-anchored with the ambiguity stated rather
  than linking to an arbitrary one of them; a confidently wrong jump is worse
  than no jump. Count collisions and report them.
* **The hierarchy is a DAG, not a tree.** A class has one parent but any number
  of interfaces, so a node can be reached by several paths. De-duplicate nodes
  by identity and let edges multiply -- do not flatten to a tree and do not
  render the same type twice.
* `ancestors` marks RTL/VCL parents `resolved: false` from a project index
  (`TInterfacedObject` measured as `resolved=false`), because they live in the
  platform library index.

**DECISION -- stay single-DB and DISCLOSE.** Render an unresolved ancestor as a
grey, non-anchored row labelled `"(outside this project's closure)"`. Do not
open the library DB from this emitter: the house rule is that the authoritative
set is the project DB plus the platform library, and mixing them here would
make row provenance ambiguous exactly where the chart claims to be precise.
Note the library-DB option in the artifact's `meta.json` instead.

Layout: ancestors ABOVE the focus (`rankdir=TB`), descendants below. This is
the first emitter that is not left-to-right; keep the rounded-cluster and
clickable-row grammar identical.

**VERIFY** `-Type TBlueprint_ViewModel -DbPath $CLI` -> ancestors include
`TInterfacedObject` rendered unresolved/grey. `-Type TInterfacedObject` ->
descendants include `TBlueprint_ViewModel`, `TBlueprintCADImport_ViewModel`,
`TBlueprintPDFImport_ViewModel`, `TABZLoggingSys`, `TCADFileService`; every
resolved descendant row is clickable; count the unresolved ones separately.

---

## Task 5 -- `class-surface` (effort M)

**Do NOT build this on the `surface` verb.** `surface --format json` returns a
bare ARRAY of `{kind, text, line}` -- measured on
`Blueprint4.ViewModel.TBlueprint_ViewModel` as **212 rows, every one
`kind="source"`, lines 57..525**. It is a flat SOURCE SLICE with no member kind
and no visibility, so consuming it means re-parsing Delphi declarations out of
text in PowerShell. That is a parser, and this project deliberately does not
have one.

**Query `symbols` by `parent_id` instead.** Measured on the same type: **392
members -- 174 field, 115 property, 101 method, 1 constructor, 1 destructor**,
each with `signature`, `start_line`, `modifiers`, `heritage`, `is_virtual` and
`prop_access` already structured.

```sql
SELECT c.kind, c.name, c.signature, c.modifiers, c.start_line, c.impl_start_line
  FROM symbols c JOIN symbols t ON t.id = c.parent_id
 WHERE t.qualified_name = '<Type>'
```

The two counts differ (392 vs 212) because `surface` applies a default
visibility filter -- it has `--all-visibility`. **They are not the same
question, so do not assert one against the other.** The structured query is the
source of truth here.

**Visibility needs one more look before you group on it.** `symbols.section`
measured `interface` for all 392 (that is interface-vs-implementation, not
visibility) and `vis_explicit` measured `1` for all 392 (a boolean "was the
visibility written explicitly", not the value). The visibility itself is in
`modifiers` -- confirm its shape in Task 0 before designing the clusters. If it
proves unreliable, cluster by `kind` (field / property / method) instead, which
is known good, and say in the header that the grouping is by kind.

392 rows is too many for one readable chart: apply `Get-TopRanked` per cluster
and the same disclosure row. **Do not silently truncate.**

**VERIFY** `-Type Blueprint4.ViewModel.TBlueprint_ViewModel -DbPath $CLI` ->
Members **392**, by kind field **174** / property **115** / method **101** /
constructor **1** / destructor **1**; `Shown + Hidden = 392`; every shown row
anchors to `impl_start_line` when present, else `start_line`.

---

## Negative tests -- each MUST fail as stated, leaving no `.svg`

| # | command | expected |
|---|---|---|
| N8 | `Emit-WhoCalls -Direction callees -Qname <a leaf method>` | "calls nothing", NOT the event-wiring message |
| N9 | `Emit-MemberAccess -Qname <a method qname>` | `"... is a method, not a field or property -- ask who-calls instead"` |
| N10 | `Emit-MemberAccess -Qname No.Such.Field` | `"No.Such.Field is not in this index"` |
| N11 | `Emit-Hierarchy -Type NoSuchType` | engine returns no such ancestor (exit 1); emitter throws, no svg |
| N12 | `Emit-ClassSurface -Type <a unit, not a type>` | refuses rather than rendering an empty class |
| N13 | `Emit-MemberAccess -Mode write -Qname ...Connected` | Writes 0 -> renders the focus plus `"no write sites (602 reads)"`, exits 0. A real answer, like `touches-tables`' zero case. |

## Integration

Extend `New-DiagramArtifact.ps1`: add the five ids to the `ValidateSet`, add
`what-it-calls`/`who-writes`/`who-reads`/`hierarchy`/`class-surface` to
`$vocab`, add `-Mode`/`-Cap`/`-Type` to the regenerate string when set. Keep
moving outputs BY PROPERTY. Every new emitter returns `Png` and `Pdf` paths.

Extend `Test-Emitters.ps1` with the tables above and N8-N13, keeping the `Step`
wrapper and `$script:` assignment convention (see its header for why both
exist). Prove the extended suite can still FAIL once before trusting it.

## STOP -- do not

* Touch anything outside `charts\`. The CLI `ask` verb is added LAST, by
  someone else.
* Build `who-writes` on `accessor_symbol_id`, and do NOT file it as a defect --
  it is a shipped owner ruling. Finding 1. Use `find-callers --resolved`.
* Group accesses by line. Finding 3.
* Trust a grouped query to dodge the row cap. Finding 4.
* Open a second project DB. Library-vs-project is the only authoritative pair.
* Run `drag-lint index` / `fb-snapshot` / `autodoc` against ANY database.
  **This rule got much sharper on 2026-09-23.** The enum-binding re-resolve is
  gated on `DRAGLINT_RESOLVER_VERSION` 1.5.1-alpha -> 1.6.0-alpha, and THIS
  worktree's engine is still 1.5.1. Indexing a corpus DB that the engine team
  has already re-resolved silently re-resolves it BACK and drops the enum
  bindings -- recoverable, but indistinguishable from "the feature does not
  work", and we would be the cause. See `STATUS-questions.md`.
* Attempt `effects` until the engine team supplies the `effect_summary` legend.
* Attempt `lands-where` / `feeds-from` / `consumers` -- they need a live
  Firebird connection via `fb-snapshot` and are not near-term work.
* Attempt `protocol-trace` x2 / `crosses-boundary` / `exception-paths` --
  blocked on engine enum-value binding.
* `git push`, `git add -A`, bare `git stash`, or commit `scratch\`/`artifacts\`.

## Gotchas already paid for

* `$E` and `$e` are THE SAME VARIABLE in PowerShell.
* `Invoke-IndexQuery` returns `, $array` -- assign DIRECTLY, never `@(...)`.
* Dot-sourcing a scriptblock inside a function runs it in THAT function's
  scope; a test harness needs `$script:`.
* PowerShell has no heredoc; use `@'...'@` with the closer at column 0.
* `--format json` splices a staleness note INTO the JSON.
* `sql/1` rows are POSITIONAL ARRAYS, cap 200, truncation SILENT.
* `PRAGMA table_info` is refused by the SQL authorizer -- use
  `drag-lint schema --format json` for columns.
* A column existing in schema 23 does not mean it holds rows: `covered_by` and
  `symbol_facts.wiring` are EMPTY in both indexes measured.
