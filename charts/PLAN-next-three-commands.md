<!-- dl:backlog status=open last-measured=2026-09-23 -->
# PLAN: the next three diagram commands

For a COLD session. Everything you need is in this file plus `charts\README.md`.
Work only in `charts\`. Two commands already ship (`butterfly`, `deps`) and are
the reference implementations.

## Done means

All three commands run through `New-DiagramArtifact.ps1 -Question <q> -Target <t>
-DbPath <db>`, each producing the 8-file bundle with every row clickable, each
verified against the numbers below, each with a negative test that is
demonstrated to FAIL, and each committed by explicit pathspec. Nothing is pushed.

## Read first

1. `charts\README.md` -- house rules, the fact-population table, and four traps
   that have already cost time.
2. `charts\src\Emit-Butterfly.ps1` -- reference emitter. Rows are METHODS,
   clusters are UNITS.
3. `charts\src\Emit-Deps.ps1` -- second emitter. Rows are UNITS, clusters are
   DIRECTORIES. Has the `Invoke-IndexQuery` helper that zips the `sql/1`
   positional-array envelope into objects. REUSE IT; do not rewrite it.
4. `charts\src\New-DiagramArtifact.ps1` -- the bundler and its `-Question`
   dispatch.

---

## TASK 1 -- `who-calls`

**Do NOT build this on `reverse-calltree`.** Measured 2026-09-23: that verb is
RESOLVED-ONLY and returns an EMPTY caller wing for any routine with no enclosing
class. `BASICSF.ProcessMessages` gives 0 callers where `find-callers --name`
finds 63; `Pipes.Protocol.WriteString` 0 versus 88. Filed as
`docs\INBOX-reverse-calltree-resolved-only-and-json-note.md`. A METHOD target is
unaffected, which is why `butterfly` looks fine on `SendDeltaOperation`.

**Build the two-bucket union instead** -- the shape `ComputeCoveredBy` uses:

* RESOLVED bucket: `refs` where `symbol_id` = the target's id and `kind='call'`,
  joined to `enclosing_symbol_id` for the caller.
* NAME bucket: `refs` where `name_text` = the target's bare name, `kind='call'`,
  and `symbol_id IS NULL`, joined to `enclosing_symbol_id`.
* Union at EVERY hop if you go deeper than 1. Cap depth at 2 to start.

**Render the two buckets differently.** A name-matched caller is a weaker claim
than a resolved one, so it is `[inferred]`: draw its edge `style=dashed` and mark
the row. This reuses the certain/inferred channel `deps` already uses for
interface-vs-implementation. **Do not silently merge them into one count.**

**Verify** (ORM3 CLIENT, `Micronite2027.sqlite`):

```
who-calls BASICSF.ProcessMessages      -> resolved 0, name-matched ~63, total > 0
who-calls Pipes.Protocol.WriteString   -> resolved 0, name-matched ~88
who-calls Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation
                                       -> resolved 9  (matches butterfly today)
```

Invariant if a number drifts: **click targets == rows**, and
`resolved + name-matched == total rows`.

**Negative test:** a qname that does not exist must exit non-zero with a message
naming the qname -- not produce an empty chart. Assert the non-zero exit.

---

## TASK 2 -- `event-wiring` (NEW TIER: UI)

Control -> handler method. Fact: `symbol_facts.dfm_event`, **762 rows on ORM3
CLIENT**, shaped `frmMAIN.OnCreate`, `PrinterSetup1.OnClick` i.e.
`Component.OnEvent`.

**Query** (reuse `Invoke-IndexQuery`):

```sql
SELECT sf.dfm_event AS ev, s.qualified_name AS handler,
       f.path AS file, s.start_line AS line
  FROM symbol_facts sf
  JOIN symbols s ON s.id = sf.symbol_id
  JOIN files   f ON f.id = s.file_id
 WHERE sf.dfm_event <> ''
   AND f.path LIKE '%\<Form>.pas'
 ORDER BY sf.dfm_event
```

**Decomposition:** split `dfm_event` on the LAST `.` -> component, event name.
Cluster by COMPONENT; rows are `OnEvent -> HandlerMethod`; the row's anchor is
the HANDLER's file:line (that is where you want to land). Colour by event family
if you like, but one colour is fine.

**Verify:** `uMain` (ORM3 CLIENT) must yield rows including
`frmMAIN.OnCreate -> uMain.TfrmMAIN.FormCreate`. Invariant: rows == query row
count, click targets == rows.

**Negative test:** a form with no `dfm_event` rows must say so explicitly and
exit non-zero, NOT emit an empty rounded rectangle.

---

## TASK 3 -- `touches-tables` (NEW TIER: DATABASE)

Method -> database table. Facts: `symbol_facts.sql_writes` (**148 rows**) and
`sql_reads` (**19**) -- **SERVER ONLY**.

**ORM3 CLIENT is 0/0 and that is CORRECT, not a gap**: the client owns
`TFDMemTable`s and has no FireDAC connection at all. The command MUST detect a
client-shaped index and say so plainly rather than render an empty chart. That is
the whole point of the task.

**Query:**

```sql
SELECT s.qualified_name AS qname, f.path AS file, s.start_line AS line,
       sf.sql_writes AS w, sf.sql_reads AS r
  FROM symbol_facts sf
  JOIN symbols s ON s.id = sf.symbol_id
  JOIN files   f ON f.id = s.file_id
 WHERE (sf.sql_writes <> '' OR sf.sql_reads <> '')
```

**Decomposition:** rows are METHODS grouped by unit on the left; rows are TABLE
names grouped into one "database" cluster on the right; an edge per
(method, table). Writes solid, reads dashed -- reuse the channel.

**Verify** (ORM3 SERVER, `MicroniteMW1Service.sqlite`): at least 148 write edges
across the index; `uAREAOFINTEREST_SERVER...PrepareSaveQuery` must show
`AREAOFINTEREST`. Invariant: click targets == method rows + table rows.

**Negative test:** run it against ORM3 CLIENT. It must print that this index has
no SQL facts BY DESIGN, name the reason, and exit non-zero. Assert that message.

---

## Integration (do this once, after Task 1)

In `New-DiagramArtifact.ps1`:
* add each id to the `-Question` `ValidateSet`;
* add a `switch` branch calling the new emitter;
* set `$leftLabel` / `$rightLabel` per question (`who-calls` -> "callers" /
  "name-matched"; `event-wiring` -> "components" / "handlers";
  `touches-tables` -> "methods" / "tables").

## STRETCH -- `tested-by`

Same two-bucket union as Task 1, walking backwards from the target to find
callers whose unit looks like a test. `symbol_facts.covered_by` is **empty BY
DESIGN and always will be** -- read the note in `charts\README.md` before going
near it. A production project DB cannot hold a test caller, so this needs the
test project's own index and an absence-tolerant join.

## STOP -- do not do any of this

* Do NOT touch `src\` anywhere. All work is in `charts\`.
* Do NOT add a lint rule. Rule counts are pinned in four docs plus a guard.
* Do NOT bump `DRAGLINT_VERSION`, `DRAGLINT_EXTRACTOR_VERSION` or
  `DRAGLINT_RESOLVER_VERSION`.
* Do NOT push. Commit by explicit pathspec; never `git add -A`; never a bare
  `git stash`.
* Do NOT reindex another project's DB, and never `index <dir> --db <projectDb>`.
* Do NOT attempt the four BLOCKED questions (`protocol-trace` x2,
  `crosses-boundary`, `exception-paths`). They wait on the engine team's enum
  binding, which is being implemented separately.
* Do NOT rebuild the IDE plugin BPL. The owner's IDE is usually open and a
  design-time BPL cannot be rebuilt under it.

## Gotchas that have already cost time

* `-Db` is aliased to `-Debug` by `[CmdletBinding()]`. Use `-DbPath`.
* `--format json` splices the human staleness note INTO the JSON. Strip
  `^drag-lint: ` and its continuation lines before parsing. Both emitters do.
* `sql/1` returns `rows` as POSITIONAL ARRAYS, not objects.
* `unit_name_norm` is the LAST DOTTED SEGMENT lowercased -- ambiguous. Join on
  resolved `target_file_id`.
* `butterfly/1` nests the CALLEES tree under a field named `callers`.
* Force arrays with `@()` when indexing a `-split` result.
* Strict 7-bit ASCII + CRLF on every `.ps1`. Write/Edit emit LF -- normalise.
