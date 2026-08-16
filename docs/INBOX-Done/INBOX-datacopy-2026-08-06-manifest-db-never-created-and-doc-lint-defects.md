> **RETIRED to INBOX-Done/ on 2026-08-15.** SUPERSEDED: DataCopy has had its own _D-RAG project DB since the 2026-08-11 layout change, and its lint count went 107 -> 48 -> 0 errors over sessions 17-18. The individual doc/lint defects it lists were split into their own notes and fixed.
>
> Original note follows unchanged.

# INBOX: the manifest DB for DataCopy was never created -- and six defects that fall out of it

- **From:** DataCopy (Alexander Liberov) -- found 2026-08-06
- **Engine:** `drag-lint 1.2.2-alpha (built 2026-08-06 11:43:11)`, Win64 exe at
  `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe`
- **Corpus:** `C:\Projects\DataCopy` (18 source files, ~1,480 symbols). Every row below is a
  verified real case from that tree, not a fixture.
- **Two DBs are involved and the difference between them is the story:**
  - `C:\Projects\.drag-lint\DataCopy.sqlite` -- what the manifest says should exist. **Did not
    exist at all until it was built by hand today.**
  - `C:\Projects\DataCopy\drag-lint.sqlite` -- what the IDE reindex actually writes. 35 files,
    17 of which are gone from disk.
- **Artefacts:** reindex log `%TEMP%\drag-lint-reindex.txt`; lint report
  `C:\Projects\DataCopy\lint-report-20260806-144103.txt` (279 findings, 12 files).

---

## 1. THE REPORTED BUG -- the manifest section exists, the DB never gets built (HIGH)

`third_party\dll-win64\drag-lint.json` has carried a `DataCopy` section since `6e66279`:

```json
{ "name": "DataCopy", "db": "DataCopy.sqlite",
  "include": ["C:\\Projects\\DataCopy"],
  "exclude": ["*Backup-*", "*BACKUP OLD PROJECTS*"] }
```

with `"outDir": "C:\\Projects\\.drag-lint"`. So the configured DB is
`C:\Projects\.drag-lint\DataCopy.sqlite`.

**Actual:**

```
> drag-lint resolve-dbs --platform Win64
C:\Projects\DB\ORM3\drag-lint.sqlite
C:\Projects\DB\SQL\drag-lint-sql.sqlite
C:\Projects\.drag-lint\Loader.sqlite
C:\Projects\.drag-lint\TableTools.sqlite
C:\Projects\.drag-lint\Delphi-RAG-lint.sqlite
C:\Projects\.drag-lint\Delphi-RAG-Lint-Graph.sqlite
C:\Projects\.drag-lint\OCRPDF.sqlite
C:\Projects\.drag-lint\library-Win64.sqlite
```

`DataCopy.sqlite` is absent -- and `Get-ChildItem C:\Projects\.drag-lint\*.sqlite` confirmed no
such file existed. The section had been in the manifest for a day and nothing had ever built it.
One explicit `drag-lint index --all --only DataCopy --jobs 0` created it in 4.1s, first try, no
errors (18 files, 1,412 symbols) -- so nothing about the section is malformed.

Meanwhile the IDE's reindex writes somewhere else entirely. `%TEMP%\drag-lint-reindex.txt`:

```
Database: C:\Projects\DataCopy\drag-lint.sqlite     <-- project-local, NOT the manifest path
...
Done. Files: 35, Symbols: 3244, Refs: 17863, skipped 4 up-to-date, 8.10s
```

**Two things to fix, and they are separable:**

1. **`resolve-dbs` / the consumers silently return a manifest DB that does not exist.** A section
   whose `db` file is missing should be reported -- `resolve-dbs` is the natural place ("DataCopy:
   configured but not built -- run `index --all --only DataCopy`"). Right now the only symptom is
   that queries quietly answer from the wrong set of DBs, or from none.
2. **The IDE reindex path ignores the manifest.** It picks `<projectRoot>\drag-lint.sqlite` by
   convention instead of resolving the section that covers the project root. Everything in
   sections 2-3 below is a direct consequence: docs get generated from one DB and linted against
   another, and the manifest's `exclude` patterns never apply to the DB the IDE actually uses.

**Ask:** when a command is invoked on a path, resolve the manifest section that *contains* that
path and use its `db` + `exclude`; fall back to the project-local convention only when no section
matches, and say so on stderr.

---

## 2. The IDE-written DB is full of ghost symbols -- `--prune` exists but nothing uses it (HIGH)

Ten legacy units were moved out of `C:\Projects\DataCopy\` into `Backup-20260805\` yesterday.
The manifest excludes `*Backup-*`; the project-local DB has no such exclude and has never pruned:

```
> drag-lint query --name TfrmCMMACPYMain --db C:\Projects\DataCopy\drag-lint.sqlite --json
  "qualified_name": "CMMACPY.TfrmCMMACPYMain",
  "file": "C:\\Projects\\DataCopy\\CMMACPY.pas"       <-- this file does not exist

> drag-lint query --name TfrmCMMACPYMain --db C:\Projects\.drag-lint\DataCopy.sqlite --exact
0 match(es)                                            <-- correct
```

Credit where due: `lint-all` **no longer reports findings against vanished files** -- the 14:41
report covers 10 real files and names none of the ghosts. That half of
`INBOX-lint-scope-stale-files-and-project-members.md` (Bug 1) is fixed in the *report*.

But the ghost **rows** survive, and they still feed everything that is reference-based. That is
what produces the 15 spurious `doc-drift: managed facts block is out of date` findings in the
report: the facts blocks were written by `document --project --apply` against the clean manifest
DB (18 files), and then checked by `lint-all` against the project-local DB (35 files) whose
`Called from:` lists still name `DPP2CSV_Main`, `CMMACPY`, `DataCopy2`, `MainZeissConvert`. Two
DBs, one writing the docs and the other grading them.

**Ask:** `--prune` shipped, but a full-root `index <root>` still does not prune by default and the
IDE path never passes it. Either make pruning the default for a full-root walk, or have the IDE
reindex pass `--prune`. As long as a stale row can outlive its file, every reference-derived
artefact (facts blocks, `unused-public-symbol`, `find-callers`, `impact`) is quietly wrong.

---

## 3. `document` and `doc-drift` contradict each other about `<param>` (HIGH -- 22 findings)

This is the one the reporter named: *"Params are not recorded in the documentation."*

`document --project --apply` ran over this tree at 14:29 (37/263 declarations documented, 71
edits). `lint-all` ran at 14:41. 22 of the 40 `doc-drift` findings are
`signature param "X" has no <param> tag` **on declarations the generator had just written**.

Example -- `uZeissRoutines.pas:218`, exactly as `document --apply` left it:

```pascal
      /// <summary><!-- drag-lint:auto -->SourceStampString used to live here. It MOVED to uFileUtils ...</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DPPRoutines.TDPPTransfer.TransferFile (DPPRoutines.pas), ...
      /// Writes: Fconfig, Flogger, Ftrlogger, Fstatus
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(AConfig: IConfigurationService; ALogger: IErrorLogger;
                         ATRLogger: ITransferLogger; AStatus: IStatusService);
```

Four parameters, no `<param>` tags, so `doc-drift` emits four warnings. And it is *correct* to,
under its own rule -- but the only tool that could have written those tags is `document`, whose
batch mode is documented as facts-only: *"an empty tag is never written, `<param>` never gets a
skeleton"*. So the generator's designed behaviour is precisely what the linter reports as drift.
`document --apply` followed by `lint-all` can never converge.

The same pattern hits every batch-documented routine with parameters:
`uZeissRoutines.pas:368` (4 params), `:409` (3), `:433` (6), `:218` (4),
`uConfigurationService.pas:410` (1), `uMainZeissCopy.pas:1120` (1).

**Ask -- pick one, but it has to be one:**
- a `--params` (or `--stubs`-adjacent) flag on `document` that emits `<param name="X"></param>`
  skeletons, so a subsequent `lint-all` is clean and a human fills in the prose; **or**
- `doc-drift` suppresses `no <param> tag` when the declaration carries a managed
  `<!-- drag-lint:auto -->` block, on the grounds that the generator deliberately left it out.

The first is better: an empty `<param>` skeleton is a to-do a human can see in the tooltip. The
second just hides the gap. What is not acceptable is the current state, where the tool's two
halves disagree and the user is handed 22 warnings for obeying it.

---

## 4. `doc-drift` reads a prose `<returns>` as a type name (MEDIUM -- false positive)

```
uFileUtils.pas:76:7  [warning] doc-drift: <returns> names type "DateTimeFileString"
                     but the signature returns "string"
```

The declaration (hand-written, `uFileUtils.pas:76-84`):

```pascal
      /// <summary>The same 15-character stamp shape as <c>DateTimeFileString</c>
      /// (<c>YYYYMMDDHHNNSSZZZ</c>), but derived from the SOURCE file's last-write time instead of
      /// "now", so it is DETERMINISTIC for a given unchanged source.</summary>
      /// <param name="AFile">Full path of the source file whose timestamp is read.</param>
      /// <returns>The stamp, or the wall-clock <c>DateTimeFileString</c> when the file cannot be
      /// stat'ed.</returns>
      function SourceStampString(const AFile: string): string;
```

`<returns>` is a sentence. `DateTimeFileString` inside it is a `<c>` cross-reference to a sibling
function, not a declared type -- and the function does return `string`, so the doc is right and
the linter is wrong. The rule appears to lift the first identifier-shaped token (or the first
`<c>` element) out of `<returns>` and compare it to the signature's return type.

This punishes exactly the documentation style the DocInsight convention asks for -- prose that
cross-references related symbols. **Ask:** only apply the type check when `<returns>` *is* a bare
type name (single token, whole element, resolves to a known type); never when it is prose, and
never on the contents of a `<c>` element.

---

## 5. `used-before-assignment` does not see element assignment `A[i] := ...` (MEDIUM -- 29 findings)

All 29 `used-before-assignment` findings in the report are the same shape: a local
`array[0..2] of X` that is filled element-by-element in a `for` loop and then read after it.

`uZeissRoutines.pas:433` (`ParkStrandedGroup`) -- the assignment the rule misses is at 470-490:

```pascal
  for LJdx:= 0 to 2 do
  begin
    LSource [LJdx]:= pStem + ZEISS_KINDS[LJdx] + '.mm1';   <-- assignment to LSource
    LPresent[LJdx]:= FileExists(LSource[LJdx]);            <-- assignment to LPresent
    ...
  end;
  ...
  for LJdx:= 0 to 2 do
    LDest[LJdx]:= Format('%s%s_%s.mm1', [...]);            <-- assignment to LDest
  ...
  for LJdx:= 0 to 2 do
  begin
    if not LPresent[LJdx] then continue;                   <-- line 516: "may be used before assigned"
    if not CopyFileVerified(LSource[LJdx], LDest[LJdx], LMess) then   <-- line 518: same, twice
```

Reported: `lpresent` (516, 531, 539, 666), `lsource` (518, 541), `ldest` (518, 532), `lstaged`
(669, 821, 834), `loriginal` (782, 821, 834, 845), `lbackup` (747), `lrestore` (688, 747, 755,
764), `ldone` (1577, 1594). Every one of them is assigned in a preceding `for` loop.

`uZeissRoutines.pas:1572` is the clearest -- the assignment is **five lines above** the use:

```pascal
    for LIdx:= 0 to 2 do
      LDone[LIdx]:= LStage[LIdx] + CONSUMED_DONE_EXT;      <-- assigned here
    LMarked:= 0;
    for LIdx:= 0 to 2 do
      if not RenameFile(LStage[LIdx], LDone[LIdx]) then    <-- 1577: "may be used before assigned"
```

**Root cause (hypothesis):** the definite-assignment pass records `Ident := expr` and treats
`Ident[expr] := expr` as a *read* of `Ident` rather than a write. **Ask:** treat an indexed (and
field-access) store as a write to the base variable. Under-approximating here is fine -- the rule
is a heuristic -- but 29 of 29 false positives makes the rule worse than useless: it trains people
to skim past it.

### ANSWERED 2026-08-06 -- the hypothesis is WRONG; fixed elsewhere (`9913ea5`)

`TDefiniteAssignment.Transfer` already resolves the BASE of an indexed/qualified store through
`AssignmentBaseIndex`, so `A[i] := x` *does* define `A`. Implementing the ask would have changed
nothing.

The first repro seemed to confirm the report -- the indexed store was flagged while a plain store
in the same loop was not -- but that was an artefact of the probe: `CollectReadsAndCallDefs`
treats a bare call ARGUMENT as a possible def rather than a read, so `Writeln(Plain)` never read
`Plain` at all. Reading both genuinely (`Acc := Arr[0]` / `Acc := Acc + Plain`) flagged BOTH.

The real cause is the LOOP SHAPE: every for-loop carried a header->follow edge, so control could
skip the body entirely and nothing the body must-assigned survived. `for LJdx := 0 to 2` always
runs. A loop with integer-literal bounds whose direction agrees with them now enters its body
directly (do-while shape); anything unprovable (`0 to List.Count - 1`) keeps the zero-trip edge,
where the warning is correct.

Measured: `uZeissRoutines.pas` 24 -> 3 findings. Battery 221/221.

Incidental gotcha for whoever touches the `for` lowering next: the grammar exposes `for` / `to` /
`downto` / `do` as NAMED children, so "the first named child that is neither start nor body" is
the `for` KEYWORD, not the bound (`boundKind=kFor highTxt="for"` from a probe build).

### 5b. Same rule, second precision gap -- `exit` inside an `except` handler is not modelled

```
uFileUtils.pas:1332:8  used-before-assignment: Local "srcsize" may be used before it is assigned.
```

`CopyFileVerified` assigns `SrcSize:= TFile.GetSize(ASource)` inside the first `try`; every path
out of that block's `except` handler is `exit`. So `SrcSize` is assigned on every path that
reaches 1332. Lower priority than 5a, but the same rule.

### 5c. Same rule, third issue -- findings are emitted twice

Four findings appear as exact duplicate lines in the report:

```
uFileUtils.pas:1332:8   used-before-assignment ... (x2)
uFileUtils.pas:1334:7   used-before-assignment ... (x2)
uZeissRoutines.pas:1577:10  used-before-assignment ... (x2)
uZeissRoutines.pas:1594:10  used-before-assignment ... (x2)
```

Both files are reached twice by the walk (once by path, once as a project member?), and the
dedup that covers the other 40 rules misses these. Deduping on (file, line, col, rule, message)
before writing the report would close it.

---

## 6. `unused-public-symbol` contradicts the facts view in the SAME database (HIGH -- it tells you to delete live code)

```
uFileUtils.pas:120:7  [info] unused-public-symbol: Exported routine SamePathFolder
                      has no references in the index -- possible dead public API
```

Against the clean manifest DB `C:\Projects\.drag-lint\DataCopy.sqlite`:

```
> drag-lint hover --qname uMainZeissCopy.TfrmZeissCopy.DoLastChecks --db <manifest db>
Remarks: Calls: CollidesWithFromPath, Format, HandleException, SamePathFolder, ToString, ...
                                                 ^^^^^^^^^^^^^^ the call edge IS in the DB

> drag-lint query find-callers --name SamePathFolder --db <manifest db>
0 caller(s)
> drag-lint query find-callers --name SamePathFolder --resolved --db <manifest db>
0 caller(s)
```

One database, two answers. The facts extractor sees `DoLastChecks -> SamePathFolder`; the
reference/caller view does not, and `unused-public-symbol` believes the reference view.

`SamePathFolder` is the FROM-vs-TO folder collision guard added during the hardening work -- it is
called, it is load-bearing, and the linter labels it dead public API. This is the most dangerous
finding class in the report, because acting on it deletes working code.

(For contrast, the sibling finding `IsValidFileNameChar` at `uFileUtils.pas:172` **is** genuine --
`IsValidPathChar` has a caller (`IsUNCRooted`), `IsValidFileNameChar` has none. So the rule is not
uniformly broken; the reference index is incomplete for some call shapes.)

**Ask:** find out which call shape `SamePathFolder`'s call site uses that the reference walker
misses while the facts walker catches it, and make `unused-public-symbol` require agreement
between the two views before it accuses a symbol of being dead.

### ROOT CAUSE FOUND 2026-08-06 -- NESTED (local) FUNCTION BODIES ARE NOT WALKED. Not yet fixed.

The call shape is: **the call sits inside a nested/local function.**
`SamePathFolder`'s only call site is `uMainZeissCopy.pas:1628`, inside
`CollidesWithFromPath` -- a local function declared inside `DoLastChecks`.

There is no ref row for it AT ALL (not a resolution failure -- nothing was ever recorded):

```
symbols named SamePathFolder : 1   (the declaration, uFileUtils.pas:120)
refs    named SamePathFolder : 0
```

Isolated against the same DB, which separates "nested" from every other explanation:

| symbol | called from | refs |
|---|---|---|
| `DirNotFound`          | outer method body            | 5 |
| `CollidesWithFromPath` | outer method body            | 4 |
| `SamePathFolder`       | INSIDE a nested function     | **0** |
| `LoopsBackIntoScan`    | declared AND called inside nested functions | **0 refs, 0 symbols** |

So the reference walker records calls made from a method's own body but does not descend into the
bodies of routines nested within it; nested routines are not indexed as symbols either. The FACTS
walker does descend, which is exactly why the two views disagree and why the `Calls:` block names
`SamePathFolder` while `find-callers` returns nothing.

**Blast radius is wider than `unused-public-symbol`:** `find-callers`, `impact`, the call graph and
every reference-derived artefact under-report for any unit using local functions -- an idiomatic
Delphi pattern, and the more so in exactly the large methods people most want a call graph for.

**Ask (revised):** index nested routines as symbols and walk their bodies for refs. The
"require agreement between the two views" guard is still worth having as a belt-and-braces measure
for `unused-public-symbol`, but it treats the symptom -- the reference index is the thing that is
wrong.

---

## 7. Constructor `Called from:` lists are misattributed across types (MEDIUM -- generated docs are wrong)

`uZeissRoutines.pas:218`, `TZEISSTransfer.Create`, as written by `document --apply`:

```
/// Called from: DPPRoutines.TDPPTransfer.TransferFile (DPPRoutines.pas),
///              uConfigurationService.TConfigurationService.Create (uConfigurationService.pas),
///              uFileUtils.ISRunOnStartup (uFileUtils.pas),
///              uFileUtils.RunOnStartup (uFileUtils.pas),
///              uFileUtils.DoNotRunOnStartup (uFileUtils.pas) (+10 more)
```

None of those call `TZEISSTransfer.Create`. The disproof is structural and does not depend on
reading a line of code: **`uZeissRoutines`'s implementation section uses `uFileUtils`**, so
`uFileUtils` cannot use `uZeissRoutines` -- Delphi would reject the circular interface reference.
`uFileUtils.ISRunOnStartup` cannot possibly call this constructor.

What those routines do have in common is that each calls *some* `.Create` (`TStringList.Create`,
`TIniFile.Create`, `TRegIniFile.Create`, ...). The evidence is consistent with unresolved or
receiver-less `Create` calls being attributed by bare name to every `Create` symbol in the index.

Note the blast radius: `Create` is the single most common method name in any Delphi corpus, so
this pollutes the `Called from:` block of essentially every constructor in every documented unit,
and those blocks are what a human reads in the Help Insight tooltip. Also worth checking the same
way: `Destroy`, `Execute`, `Clear`, `Add`.

**Ask:** when a call target cannot be resolved to a receiver type, do not attribute it to a
same-named symbol. Omit it, or mark it as ambiguous the way `find-callers --resolved` already
distinguishes `certain|ambiguous`.

---

## 8. Already-filed defect, still reproducing on fresh code

`INBOX-harvest-swallows-preceding-banner-comment.md` (filed 2026-08-03) -- new instance, and this
one is worse than a row of dashes because it reads as a *plausible sentence about the wrong thing*.

`uZeissRoutines.pas`, implementation side, an orphan note about a routine that was MOVED OUT:

```pascal
// SourceStampString used to live here. It MOVED to uFileUtils (already in this unit's
// implementation uses clause) so CSVRoutines.BackupFile and DPPRoutines.BackupToFolder --
// which had the identical unbounded-backup-accumulation bug -- share one copy instead of three.
```

That comment documents a *removal*. `document --apply` harvested it as the `<summary>` of the
nearest following declaration, `TZEISSTransfer.Create` (see section 3 for the emitted block). So
the constructor's tooltip now claims it has something to do with `SourceStampString`.

**Ask:** in addition to the banner guard already discussed in that note, refuse to harvest a
comment whose first sentence names a symbol that is *not* the declaration being documented and is
not declared in this unit -- a strong signal the prose is about something else.

---

## 9. Minor / cosmetic

- **Severity roll-up is wrong in the summary line.** The report ends with
  `lint-all: 279 finding(s) -- 0 error(s), 279 warning(s) -- 12 file(s) scanned`, but the findings
  it just printed are 62 `[hint]` + 138 `[info]` + 79 `[warning]` = 279. Everything below error is
  being counted as a warning, which makes the one number a reader looks at meaningless. It should
  read `0 error(s), 79 warning(s), 138 info, 62 hint`.
- **The report file carries a UTF-8 BOM**, and one rule message uses a real em dash
  (`writeln-in-source: Direct WriteLn call — consider a logger.`) while every other message uses
  `--`. That single character is what makes the file non-ASCII. Worth normalising to `--` for
  consistency with the rest of the catalogue.
- **`12 file(s) scanned` vs 10 files in the findings.** Not necessarily wrong (two files may be
  clean), but the report gives no way to tell which 12 were scanned. A `--list-scanned` or a
  trailer naming them would make "did it actually cover my project?" answerable -- which is the
  exact question section 1 left the user unable to answer.

---

## Priority as seen from this end

| # | Defect | Severity | Why |
|---|--------|----------|-----|
| 1 | Manifest DB never created; IDE writes elsewhere | HIGH | Root cause of 2 and of the doc/lint disagreement in 3 |
| 6 | `unused-public-symbol` false positive vs facts view | HIGH | Acting on it deletes live code |
| 3 | `document` vs `doc-drift` disagree on `<param>` | HIGH | 22 warnings; the two halves can never converge |
| 2 | Ghost rows survive; `--prune` not wired in | HIGH | Silently corrupts every reference-derived output |
| 5 | `used-before-assignment` blind to `A[i] := ...` | MEDIUM | 29/29 false positives -- rule is noise today |
| 7 | Constructor `Called from:` misattribution | MEDIUM | Wrong facts in the docs humans actually read |
| 4 | `doc-drift` parses prose `<returns>` as a type | MEDIUM | Punishes the documented DocInsight style |
| 8 | Harvest swallows an unrelated comment | MEDIUM | Already filed; fresh reproduction |
| 9 | Severity roll-up, BOM, em dash, scanned-file list | LOW | Cosmetic, but 9a makes the summary number useless |

## What is NOT a drag-lint bug (checked, and worth saying)

- `unit-not-in-dpr: Unit "EExtraExceptionInfo" is in DataCopy.dpr uses clause but missing from
  .dproj DCCReference list` -- **correct and useful.** Verified: the `.dpr` uses it, the `.dproj`
  has no `DCCReference` for it, and it compiles only via the search path. That one is now on the
  DataCopy backlog.
- `IsValidFileNameChar` genuinely has no callers (section 6).
- The `commented-out-code` (61), `try-except-swallowed` (18) and `concat-in-loop` (22) findings
  were spot-checked and look like true positives.
