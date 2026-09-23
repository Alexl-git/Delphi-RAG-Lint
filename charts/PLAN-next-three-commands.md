<!-- dl:backlog status=open last-measured=2026-09-23 -->
# PLAN: the next three diagram commands

For a COLD session. Work ONLY under `charts\`. Two commands already ship
(`butterfly`, `deps`) and are the reference implementations.

**Every number below was MEASURED on 2026-09-23 against the named indexes. Do
not re-derive them -- compare against them.** If a number does not match, that is
a finding: investigate before "fixing" the number.

```
$E   = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\third_party\dll-win64\drag-lint.exe'
$DOT = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe'
$CLI = 'C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite'
$SRV = 'C:\Projects\DB\ORM3\SERVER\_D-RAG\MicroniteMW1Service.sqlite'
$SRC = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\charts\src'
```

## Done means

Three emitters (`Emit-WhoCalls.ps1`, `Emit-EventWiring.ps1`,
`Emit-TouchesTables.ps1`) each take a selection and `-DbPath`, emit dot with
rounded clusters whose rows are clickable `draglint://` cells, run `dot.exe` ONCE
for svg/plain/png/pdf, and return counts a test compares.
`New-DiagramArtifact.ps1` dispatches all five questions. `Test-Emitters.ps1`
reproduces every positive number AND proves seven negative cases fail with the
stated messages, leaving no `.svg`. Committed by pathspec, NOT pushed.

## House rules (each has already cost time)

1. PowerShell only. Wait by BLOCKING -- `& $E ...` blocks by itself. No polling.
2. Strict 7-bit ASCII + CRLF, no BOM, every `.ps1`. Write/Edit emit LF --
   normalise after EVERY edit (Task 0.4). Use `&#183;` entities, never a literal
   non-ASCII byte.
3. Never name a parameter `-Db`; `[CmdletBinding()]` aliases it to `-Debug`.
4. `@()` around every `-split` before indexing; a single token otherwise yields
   a `[char]`.
5. Commit by explicit pathspec. Never `git add -A`, never bare `git stash`,
   NEVER push.
6. `charts\scratch\` and `charts\artifacts\` are gitignored regenerable output.
7. **The engine prints `drag-lint: note: N of M indexed file(s) changed ...` and
   with `2>&1` it lands INSIDE the JSON, breaking `ConvertFrom-Json`.** Filter
   `^drag-lint:` and ErrorRecords. **Already fixed in both existing emitters
   (commit 91660bcc) -- copy that filter into the new ones.** Do NOT reindex to
   silence it (STOP list).
8. `symbol_facts` is a WIDE table: one row per symbol, columns `dfm_event`,
   `sql_reads`, `sql_writes` (TEXT, NULL when absent). "762 rows" means
   `dfm_event IS NOT NULL` on 762 rows.
9. `sql --format json` = schema `sql/1`: `columns` + `rows` as POSITIONAL
   ARRAYS, **hard row cap 200** (`truncated` flag), 10 s cap, one statement.
   Reuse `Invoke-IndexQuery` from `Emit-Deps.ps1`. Assert `truncated -eq $false`
   where stated.
10. `unit_name_norm` is the last dotted segment, lowercased, and ambiguous. Join
    on ids. No query here touches it.

## A withdrawn claim, so you do not resurrect it

An earlier version of this plan said `reverse-calltree` silently drops callers of
unit-level routines. **That was WRONG and is withdrawn** -- it was built on JSON
parse failures reported as zeros. `reverse-calltree` resolves correctly
(`Pipes.Protocol.WriteString` 13, `MStreams.ReverseBytes` 9). You MAY build on
it. See the WITHDRAWN section of `charts\README.md`.

Be precise about WHICH kind of wrong each case was, because they differ:
`WriteString` and `ReverseBytes` were **parse artifacts masking correct non-zero
answers** (WriteString measures 13 bound / 75 unbound / 88 total -- 13 real
callers plus 75 `TIniFile.WriteString` name matches). Only
`BASICSF.ProcessMessages` was **a correct zero AND a pure name-match artifact**.

The `BASICSF.ProcessMessages` case is still worth knowing: it has 0 resolved
callers and 63 NAME matches, and all 63 are `Application.ProcessMessages;` --
a VCL symbol sharing a name. **A name bucket presented as fact would have been
confidently wrong 63 times.** That is why `who-calls` may show name matches but
must LABEL them, never merge them into one count.

---

## Task 0 -- shared helper (do first)

### 0.1 `charts\src\Emit-Common.ps1`, dot-sourced by the three NEW emitters

Functions only, no top-level side effects:

* `ConvertTo-XmlText`, `Get-UnitName`, `Get-ShortName` -- copy from
  `Emit-Butterfly.ps1`.
* `Get-EngineText([string[]] $ArgList)` -- runs `& $Engine @ArgList 2>&1`, drops
  every `[System.Management.Automation.ErrorRecord]` and every string matching
  `^\(?loaded defaults|^drag-lint:`, joins with LF, then trims to the substring
  from the first `{` to the last `}`. Returns `''` if no `{`. Records
  `$LASTEXITCODE` into `$script:LastEngineExit`.
* `Invoke-EngineJson` -- `Get-EngineText`, throws
  `"engine returned nothing for <args> (exit $script:LastEngineExit)"` on empty.
* `Invoke-IndexQuery` -- copy the sql/1 zip helper from `Emit-Deps.ps1`, routed
  through the same filter. Keep the unary comma on `, $out.ToArray()`.
* `Get-SymbolLocation([string] $Qname)` --
  `SELECT s.id, s.kind, s.start_line, s.impl_start_line, s.impl_end_line, f.path
   FROM symbols s JOIN files f ON f.id=s.file_id WHERE s.qualified_name='<Q>'`
  (escape `'` as `''`). 0 rows -> throw `"<Qname> is not in this index"`.
  >1 -> take the first and `Write-Host` a note. **Callers use
  `impl_start_line` when present, else `start_line`** -- you want the body, not
  the interface declaration.
* `Invoke-DotLayout($DotText, $OutDir, $Base)` -- writes `<Base>.dot` CRLF/UTF8
  no BOM, runs the ONE dot invocation
  (`-Tsvg -o .. -Tplain -o .. -Tpng -Gdpi=110 -o .. -Tpdf -o ..`), throws
  `'dot produced no SVG'`, returns `@{Dot;Svg;Plain;Png;Pdf;Anchors}`.
* `New-RowHref($File,$Line)` ->
  `'draglint://open?file=' + [uri]::EscapeDataString($File) + '&amp;line=' + $Line`.

### 0.2 ~~Repair Emit-Butterfly~~ ALREADY DONE (commit 91660bcc)

Both existing emitters already filter `^drag-lint: ` and its continuation lines.
Verify only: `& "$SRC\Emit-Butterfly.ps1" -Qname
Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation -DbPath $CLI
-Depth 2` must give `Callers 9, Callees 8, ClickTargets 18, AllClickable True`.

### 0.3 ASCII/CRLF normaliser -- run after EVERY edit

```powershell
foreach ($f in (Get-ChildItem "$SRC\*.ps1")) {
  $t=[IO.File]::ReadAllText($f.FullName)
  $bad=([regex]::Matches($t,'[^\x09\x0A\x0D\x20-\x7E]')).Count
  if ($bad) { throw "$($f.Name): $bad non-ASCII byte(s)" }
  [IO.File]::WriteAllText($f.FullName, ($t -replace "`r`n","`n" -replace "`n","`r`n"), [Text.ASCIIEncoding]::new())
}
```

---

## Task 1 -- `who-calls`

Verb: `reverse-calltree --qname <Q> --direction callers --depth <D> --format json`.

Schema `reverse-calltree/1`: `root { qname, site:"", file, line:0, callers:[...] }`;
each node `{ qname, site:"File.pas:4099", file, line, cycle, callers:[...] }`.
**Children are under `callers` at EVERY level**, both directions. `root.line` is
0 -- get the focus line from `Get-SymbolLocation`.

**A ROW IS A CALL SITE, not a method.** Key the port map by ORDINAL, never by
qname: the same method legitimately appears twice at different sites
(`ReserveNextID` has `AddOperation` at :4084 depth 1 and again at :4102 depth 2
as a cycle row). CLUSTER = `(Level, Unit)` so the picture flows depth N -> ... ->
depth 1 -> focus, and no edge joins two ports of one table. Header:
`"<unit> &#183; depth <n>"`. Cycle rows append ` &#183; cycle` and their edge is
`style=dashed`; never expand them.

Colours: reuse butterfly's `$PAL` verbatim. No new roles.

**Assertions inside the emitter:** `rows.Count + 1 -eq summary.node_count`, else
throw `"flatten mismatch: <rows> rows vs node_count <n> -- did you read the wrong
child key?"`. If `rows.Count -eq 0` throw
`"<Q> has 0 callers in call_edges (node_count 1). If it is an event handler the
caller is the DFM -- ask event-wiring instead."` Never render an empty chart.

Returns: `Dot, Svg, Plain, Png, Pdf, Callers, Cycles, MaxDepth, Truncated,
Clusters, ClickTargets, Expected=rows+1, AllClickable`.
Note: `truncated=true` means the depth limit was TOUCHED, not that rows were
dropped.

**VERIFY**

| command | expect |
|---|---|
| `-Qname ...SendDeltaOperation -DbPath $CLI -Depth 2` | Callers **9**, Cycles 0, MaxDepth 1, Truncated False, Clusters 1, Expected 10. Rows: AddOperation:4099, DoAfterDeleteOperation:3957, DoAfterPostOperation:3951, ImportJenVICI:1853, ImportLK:2175, ImportNikon:2441, ImportSheffield:3124, ImportZEISS:3416, VerifyAll:4273. Focus href line **3960** (impl; decl is 279) |
| `-Qname ...ReserveNextID -DbPath $CLI -Depth 3` | Callers **10**, Cycles **1**, MaxDepth 2, Clusters 2. Depth-1 has 9 rows; depth-2 has exactly 1, `AddOperation:4102` cycle=true, dashed edge to the AppendCharGroups row. Focus href **4018**. `graph.dot` must hold exactly **10** lines matching `^\s+n\d+:p\d+ -> ` |
| same, `-Depth 1` | Callers 9, Truncated **True** |

---

## Task 2 -- `event-wiring` (NEW TIER: UI)

Select the form CLASS qname (`uMain.TfrmMAIN`) -- component names repeat across
forms. Optional `-Control` filter.

**Q1 handlers:**
```sql
SELECT sf.dfm_event, s.name AS handler, s.qualified_name AS qname,
       s.start_line AS decl_line, s.impl_start_line AS impl_line, f.path AS pas
  FROM symbol_facts sf JOIN symbols s ON s.id=sf.symbol_id
  JOIN symbols c ON c.id=s.parent_id JOIN files f ON f.id=s.file_id
 WHERE c.qualified_name='<Form>' AND sf.dfm_event IS NOT NULL ORDER BY sf.dfm_event
```
Split `dfm_event` at the **FIRST** `.` only -> component, event.

**Q2 component lines** in `[IO.Path]::ChangeExtension($pas,'.dfm')`. The IN-list
is MANDATORY -- Blueprint4.dfm has **516** `dfm-type` rows, over the 200 cap:
```sql
SELECT sl.owner_name AS comp, sl.start_line AS line FROM string_literals sl
  JOIN files f ON f.id=sl.file_id
 WHERE f.path='<dfm>' AND sl.kind='dfm-type' AND sl.owner_name IN (...)
```

**Q3 event assignment lines**, bounded by the handler-name list, `sl.kind='dfm-prop'`,
`owner_name LIKE 'On%'`, `text IN (...)`.

Mapping: DFM line = smallest Q3 `line >= ` the component's Q2 line with matching
`ev` and `handler`. Miss -> fall back to `decl_line` in the `.pas`, count in
`DfmFallback`, say so in the tooltip. Assert Q2/Q3 `truncated -eq $false`.

Layout: LEFT clusters = EVENT KIND (`OnClick`, `OnCreate`, `OnShow`), rows =
COMPONENTS, href `<dfm>:<line>`. RIGHT cluster = the form UNIT, rows = HANDLER
METHODS, href `<pas>:<impl_line>`. Edge component -> handler. No focus node; the
form name goes in the right header (`"uMain &#183; TfrmMAIN"`).

New colour role, this emitter only: `ui = '#7C3AED' / '#F3EEFF'` (violet --
distinct from callers-blue, callees-amber, focus-teal, external-grey). Handlers
reuse the callee role.

**VERIFY** `-Form uMain.TfrmMAIN -DbPath $CLI` -> Events **41**, Handlers **41**,
Components **40**, EventKinds **3** (OnClick 39, OnCreate 1, OnShow 1),
`DfmResolved + DfmFallback = 41`, Expected 82.
Spot-check hrefs in `graph.dot`: `frmMAIN.OnCreate` -> `uMain.dfm:52`,
`PrinterSetup1.OnClick` -> `:790`, `Exit2.OnClick` -> `:4371`.
Right side: `PrinterSetup1Click` -> `uMain.pas:1122`, `FormCreate` -> `:266`,
`FormShow` -> `:956`.

**`Exit2.OnClick` maps to handler `WindowClose1Execute`** -- a name that does NOT
follow the component. That is the proof rows come from the FACT, not from a
naming convention. Never match handlers to components by name.

`-Control PrinterSetup1` -> Events 1, Handlers 1, Expected 2.
Scale check `-Form Blueprint4.TfrmBlueprint4` -> Events **96**, Handlers 96,
Components **74**, Expected 192, and NO truncation note.

Caveat for the header comment: `dfm_event` is ONE value per handler symbol, so a
handler shared by two controls is reported once. Render the fact; do not repair it.

---

## Task 3 -- `touches-tables` (NEW TIER: DATABASE)

**Step 1, index-wide pre-check BEFORE anything else:**
```sql
SELECT SUM(sql_reads IS NOT NULL) AS r, SUM(sql_writes IS NOT NULL) AS w,
       SUM(sql_reads IS NOT NULL OR sql_writes IS NOT NULL) AS either,
       COUNT(*) AS n FROM symbol_facts
```
CLIENT measures `0 | 0 | 0 | 11005`; SERVER `19 | 148 | 157 | 8921`.
If `either -eq 0`, throw this sentence with the numbers substituted, write
NOTHING, and exit non-zero:

> touches-tables: this index has NO SQL facts at all (0 sql_reads, 0 sql_writes
> across 11005 symbol_facts rows). That is correct, not a gap: this project has
> no FireDAC connection, so no method can touch a table. Ask on the index of the
> process that owns the connection (for ORM3 that is the SERVER index).

**Step 2:** `Get-SymbolLocation`, then `SELECT sf.sql_reads, sf.sql_writes FROM
symbol_facts sf WHERE sf.symbol_id=<id>`. Value shape is
`"COMPGRP, DRA1, MSCLIST, PROCPARO, PROCPART"` -- split on `,\s*`, trim, upper,
unique.

**Step 3, provenance per table** so a table row clicks to the SQL naming it:
```sql
SELECT sl.start_line AS line, sl.kind, sl.text FROM string_literals sl
  JOIN files f ON f.id=sl.file_id
 WHERE f.path='<path>' AND sl.kind IN ('literal','format')
   AND sl.start_line BETWEEN <impl_start_line> AND <impl_end_line> ORDER BY sl.start_line
```
Per table `T`, first row whose text WORD-matches T:
`(?i)(^|[^A-Z0-9_])$T([^A-Z0-9_]|$)` -- `GEN_DRA1_ID` must NOT match `DRA1`.
Miss -> href the method's impl line, tooltip
`"(fact only; no literal names <T> inside the method)"`, count in `Unresolved`.

Layout: LEFT cluster `reads` (table -> focus), FOCUS centre, RIGHT cluster
`writes` (focus -> table, `penwidth=2.2`). A table in both sets appears in BOTH
clusters -- that is the honest answer. New role `db = '#BE185D' / '#FDF2F8'`
(rose) for both wings; direction and header carry the mode.

**Zero-for-this-symbol is a real answer, not a failure:** index has facts but
this symbol has none -> render the focus alone plus one non-anchored note row
`"touches no tables (157 methods in this index do)"`, exit 0.

**VERIFY** `-Qname uPipeSessionBuilder.TPipeSessionBuilder.HandleCopyOperation
-DbPath $SRV` -> Reads **5**, Writes **5**, Both **2** (PROCPARO, PROCPART),
Distinct 8, Unresolved 0, IndexSqlSymbols 157, Expected 11.
Reads = COMPGRP, DRA1, MSCLIST, PROCPARO, PROCPART. Writes = DRA2, PROCPARO,
PROCPART, TOOLASSG, TOOLFLDR. Focus href `uPipeSessionBuilder.pas:1381`.
Per-table lines: COMPGRP 1600, DRA1 1654, MSCLIST 1563, PROCPARO 1697,
PROCPART 1700, DRA2 1649, TOOLASSG 1675, TOOLFLDR 1681. Grep `graph.dot` for
`line=1654` and `line=1681` at minimum.

`-Qname ...HandleTableLoad -DbPath $SRV` -> the zero case: Reads 0, Writes 0,
an `.svg` IS produced, exit 0.

---

## Negative tests -- each MUST fail as stated

| # | command | expected failure |
|---|---|---|
| N1 | `Emit-WhoCalls -Qname No.Such.Method -DbPath $CLI` | engine exits 2 with `ERROR: no readable drag-lint index among --db path(s)` (misleading wording -- it means the qname resolved nowhere); emitter throws `engine returned nothing for ...`; no `.svg` |
| N2 | `Emit-WhoCalls -Qname uMain.TfrmMAIN.FormCreate -DbPath $CLI -Depth 2` | `node_count 1`, 0 callers; throws the `... ask event-wiring instead` message; no `.svg` |
| N3 | `Emit-EventWiring -Form uMain.TfrmMAIN -Control NoSuchControl` | throws `control NoSuchControl has no dfm_event rows on uMain.TfrmMAIN (the form has 41)`; no `.svg` |
| N4 | `Emit-EventWiring -Form Blueprint4.ViewModel.TBlueprint_ViewModel` | Q1 returns 0; throws `no dfm_event facts under ... (index has 762 across all forms) -- is this a form class?`; no `.svg` |
| N5 | `Emit-TouchesTables -Qname ...SendDeltaOperation -DbPath $CLI` | pre-check `0/0/0/11005`; throws the no-FireDAC sentence; no `.dot`, no `.svg` |
| N6 | `Emit-TouchesTables -Qname No.Such.Method -DbPath $SRV` | pre-check passes (157); throws `No.Such.Method is not in this index`; no `.svg` |
| N7 | `New-DiagramArtifact -Question touches-tables -Target ...SendDeltaOperation -DbPath $CLI` | N5 message propagates AND the bundle directory does NOT exist afterwards |

---

## Integration into `New-DiagramArtifact.ps1`

1. `[Alias('Qname','Unit','Form')]` on `$Target`; add `[string] $Control`.
2. `ValidateSet('butterfly','deps','who-calls','event-wiring','touches-tables')`.
3. Slug: `(($Target + $(if ($Control) { ".$Control" } else { '' })) -replace '[^A-Za-z0-9]','_')`.
4. Wrap the dispatch in `try { ... } catch { if (-not (Get-ChildItem $dir -Force)) { Remove-Item $dir -Force }; throw }` so a failed emitter leaves no empty bundle (N7).
5. **Have every emitter return `Png` and `Pdf` paths**, and move by property
   instead of guessing `<slug>.png` -- that removes the slug-matching coupling.
6. Label vocabulary:
```powershell
$vocab = @{
  'butterfly'      = @('Callers','callers',     'Callees','callees')
  'deps'           = @('UsedBy', 'used by',     'Uses',   'uses')
  'who-calls'      = @('Callers','call sites',  'Cycles', 'cycle rows')
  'event-wiring'   = @('Events', 'events',      'Handlers','handlers')
  'touches-tables' = @('Reads',  'tables read', 'Writes', 'tables written')
}
```
7. Regenerate string: append `-Depth` for butterfly AND who-calls; `-Control`
   for event-wiring when set.
8. `meta.json`: add `emitter = ($r | Select-Object -ExcludeProperty Dot,Svg,Plain,Png,Pdf)`.

**Bundle verification** (8 files each):
```
-Question who-calls      -Target ...ReserveNextID   -DbPath $CLI -Depth 3   # meta left 10, right 1
-Question event-wiring   -Target uMain.TfrmMAIN     -DbPath $CLI            # meta left 41, right 41
-Question touches-tables -Target ...HandleCopyOperation -DbPath $SRV        # meta left 5, right 5
-Question butterfly      -Target ...SendDeltaOperation  -DbPath $CLI -Depth 2  # regression 18
-Question deps           -Target Blueprint4.ViewModel   -DbPath $CLI           # regression 21
```
Assert one `index.html` contains `<b>41</b> events`.

## `Test-Emitters.ps1`

Mirror `Test-FormA.ps1` (param block, `$fail` list, `Fail code msg`, exit 0/1,
`-Quiet`). Byte check; the positives above with `-eq` / `-ge`; href spot checks
by `Select-String` on `.dot` (`line=52`, `line=790`, `line=4371`, `line=1654`,
`line=1681`, `line=4018`); N1-N7 in `try { ...; Fail } catch { match the phrase }`
asserting the `.svg` is absent. **Then prove it can FAIL once** -- run the
who-calls block against `$SRV` and confirm exit 1. Do not commit that scratch.

## STOP -- do not

* Touch anything outside `charts\`. No `src\`, `tests\`, `docs\`, `third_party\`.
  The CLI verb is added LAST, by someone else.
* Add/rename/change any lint rule or `dl:` marker.
* Bump any version constant or schema number.
* Run `drag-lint index` / `fb-snapshot` / `autodoc` against ANY database --
  including to silence the staleness note or populate `orm_links`/`fb_*`
  (measured empty by construction; `touches-tables` uses `symbol_facts` only).
* `git push`, `git add -A`, bare `git stash`, `git rebase -i`, amend a prior
  commit, or commit `scratch\` / `artifacts\`.
* Use Bash, polling, a `-Db` parameter, or a literal non-ASCII byte.
* Parse dot, or read Graphviz output other than the four files from the one run.
* Join on `unit_name_norm`, or match handlers to components by NAME CONVENTION
  (`Exit2.OnClick -> WindowClose1Execute` is the counter-example).
* Render an empty chart in place of a message for N1-N6.
* "Fix" the misleading engine text `no readable drag-lint index` -- report it as
  an INBOX candidate in the commit message instead.
* Use `uPipeClientConnection.TPipeClientConnection.Log` as a test target -- its
  `reverse-calltree` JSON comes back as two summaries, an overload oddity
  outside this scope.
* Attempt the four BLOCKED questions (`protocol-trace` x2, `crosses-boundary`,
  `exception-paths`). They wait on the engine team's enum binding.
* Rebuild the IDE plugin BPL -- the owner's IDE is usually open.

## Gotchas already paid for

* `-Db` is aliased to `-Debug`.
* `--format json` splices the staleness note INTO the JSON.
* `sql/1` rows are POSITIONAL ARRAYS, cap 200.
* `unit_name_norm` is the last segment, ambiguous.
* `butterfly/1` nests the CALLEES tree under `callers`.
* `@()` before indexing a `-split`.
* A column EXISTING in schema 23 does not mean it holds rows.
* `refs.symbol_id IS NULL` mostly means OUT OF CLOSURE, not "missed".
* **COUNT, THEN READ.** A name-bucket count is a hypothesis, not evidence.
