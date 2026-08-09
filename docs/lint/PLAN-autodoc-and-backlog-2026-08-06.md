# PLAN -- autodoc chain + the whole open backlog (2026-08-06)

Written at the user's request as the single tracker for what is left. Supersedes the
"NOT DONE" list in `RESUME-datacopy-inbox-2026-08-06.md` as the ORDERING authority; that
doc keeps the per-defect diagnosis and the gotchas.

Status keys: `[ ]` not started · `[~]` in flight · `[x]` done · `[?]` needs a decision.

---

## >>> RESUME POINT (updated 2026-08-07, second pass) -- READ THIS FIRST

**State.** PHASE A is COMPLETE. **PHASE B: B1, B3, B7, B8 and B9 are DONE.** Battery **228/228**
(~12 min, needs `pwsh`; one runner added for B3). The exe beside the tests
(`third_party\dll-win64\drag-lint.exe`) is rebuilt from that source -- rebuild only if you
change `src\` again.

Working tree carries `FEATURES.txt` (another workstream's, **do not commit**) and untracked
INBOX notes (untracked by convention). Nothing else is outstanding.

**Next action, and it is a VERIFICATION not a fix: B2's code change is written and compiles
but has never run in an IDE.** See B2 for the exact repro. Everything else in this session was
verified end to end; that one was not, because it needs a live IDE. Do it first, then **B10**
(B2's D-2 half), then **B4/B5/B6** (all the same unscoped-bucket family), plus the `rules/`
line-ending sweep noted under B8.

**No decisions are outstanding.** A4's open question -- the hint for a PRESENT-but-EMPTY
`<param>` body -- was ruled on 2026-08-07: report it, as a `hint`, ON by default. Shipped as
`doc-param-no-description`; see A4 for the two design decisions inside it.

**Lessons from this pass, worth carrying:**

1. **Three of the four items were not what the list said they were.** B7 was already fixed and
   the list had simply not been updated -- CHECK BEFORE IMPLEMENTING. B1 was filed as "an
   `except` handler ending in `exit` still merges", which framed it as a divergence problem and
   sent the previous session hunting for a wrong EDGE; it was really TWO defects -- a wrong
   NODE SELECTION duplicating the try body for every handler shape, plus B9 -- and B9 in turn
   was filed as noise about one variable when it was "no divert statement has ever worked".
   Reproduce and characterise the real boundary before accepting a filing's framing.

2. **Build the probe.** Three rounds of plausible reasoning about the try CFG were simply
   wrong. A ~90-line throwaway CFG dumper printed `B6 -> [5]` for a block whose only item is
   `exit;` and ended the argument in one line. Two probes were written this session (an AST
   S-expression dumper and the CFG dumper); both are in the session scratchpad. If a third
   flow defect turns up, promote them into `tools/`.

3. **A fix that removes false positives can add them.** Making `exit` divert exposed two
   modelling gaps that had been unreachable, and the naive change traded 7 FPs for 4. Measuring
   before/after on real corpora with two purpose-built binaries -- and READING every changed
   finding in the source -- is what caught it. Counts alone would have looked like a win.

**One decision is waiting on the user, and only one:** A4 deliberately left open whether a
PRESENT-but-EMPTY `<param>` body deserves its own lower-severity `hint`. It needs a new
finding kind and a rules-catalogue entry, which adds findings to every consumer's run -- the
user's call, not a side effect of A4.

**Build + verify loop** (the recipe that works; see `delphi-build` for why the alternatives
do not): write a 3-line wrapper `.bat` (`rsvars` -> `cd` -> `msbuild src\cli\drag-lint.dproj
/t:Build /p:Config=Debug /p:Platform=Win64`), run it from PowerShell `Start-Process -Wait`
with output redirected, check `BUILD_EXITCODE=0`, then copy
`src\cli\Win64\Debug\drag-lint.exe` over `third_party\dll-win64\drag-lint.exe` before
running any runner.

---

---

## 0. DECISIONS ALREADY TAKEN BY THE USER (2026-08-06) -- do not re-open

These were given as rulings, not options. Implement to them.

**D-1 -- Harvesting from a preceding comment STAYS.** "The usual way to comment is to put
comments before the declaration, so why not harvest additional summary from there." The
refusal-based guard proposed in `INBOX-...(8)` is REJECTED. Instead:
  - if a summary already exists, or the same/similar comment was already harvested,
    **textually compare and delete identical phrases** so the summary does not explode on
    re-runs;
  - **mark the auto-created parts** so they are known VOLATILE and are rewritten even on a
    batch run.

**D-2 -- Suspected stale index => FULL PROJECT REINDEX, immediately.** Not incremental,
not "reindex the changed folder". Whole project, every time staleness is suspected. "This
would not take long, but insures a precise result." (Scope is the PROJECT's DB, not the
whole `--all` manifest.) This becomes a rule the tools follow, not advice in a doc.

**D-3 -- `<param>`: structure always, meaning only if the code carries it.** Automatic
generators supply structure, not meaning. If the source holds extra information about a
parameter -- a comment sitting next to that parameter inside the parameter list, between
the commas / parentheses that separate it from its neighbours -- **harvest it as the
param's text**. Otherwise emit the structure alone.

**D-4 -- Merge safety for params: two parts, two rules.** A `<param>` has a STRUCTURE part
and a MEANING part. **Regenerate the structure; leave the meaning alone if present.** A
hand-written param description is never overwritten.

**D-5 -- a comment about a FOREIGN symbol is DEMOTED to `<remarks>`, never discarded.**
CONFIRMED by the user 2026-08-06; this closes the only question the plan opened. D-1 fixes
the *explosion* and *volatility* halves of #8 but not the *misattribution* half: the live
example is a comment documenting a REMOVAL -- "SourceStampString used to live here. It
MOVED to uFileUtils ..." -- which the harvester attached to the next declaration,
`TZEISSTransfer.Create`. Under D-1 alone that summary is still harvested and still wrong,
merely now volatile. So keep harvesting (D-1 stands), but when the comment's first sentence
names a symbol that is neither the declaration being documented nor declared in this unit,
emit it under **`<remarks>`** instead of `<summary>`. Demote, do not discard -- the prose is
still true about something; it is just not this declaration's summary, and a tooltip that
LEADS with it is what makes the defect harmful.

Implementation notes for D-5, so it is not over-applied:
- "names a symbol" = an identifier in the first sentence that RESOLVES in the index to a
  declaration. If it does not resolve, it is prose, not a symbol reference -- leave the
  comment as the `<summary>`. Be conservative; a false demotion loses a good summary.
- require the named symbol to be **FOREIGN** (declared in another unit), not merely "not
  this declaration". Otherwise a legitimate summary that mentions a helper it calls -- an
  extremely common shape -- would be demoted.
- both lookups already exist: `FindSymbolsByExactName` (`Core.Interfaces` :78) and
  `GetFilePath` for the file-id comparison.
- the demoted text still carries the auto marker per D-1, so a later run can re-promote it
  if the declaration or the comment changes.

---

## PHASE A -- the autodoc chain (the user's chosen order)

Target end state: `document --project --apply` can be run over a whole project and produce
docs that are correct, idempotent, and that `lint-all` then reports clean.

### A1 `[x]` Fix the harvest boundary + attribution (#8) -- DONE 2026-08-06

Two filed instances, one code path:
- `docs/INBOX-harvest-swallows-preceding-banner-comment.md` (2026-08-03) -- a banner /
  section-divider comment one blank line above the real prose is swallowed into ONE block,
  so the BANNER becomes the `<summary>` and the real prose is demoted to `<remarks>`.
- `docs/INBOX-datacopy-...(8)` -- an orphan note about a MOVED-OUT routine became the
  `<summary>` of `TZEISSTransfer.Create`.

Code: `HarvestInterfaceComment`, called from `TDocFactsBuilder.Build` in
`src/doc/DRagLint.Doc.Facts.pas` (~line 844). The long comment above that call already
explains why the scan does not start at the declaration line -- read it before editing;
its idempotency argument is load-bearing and is anchored by
`tests/autodoc/run_doc_p3_harvest_text.ps1`.

Do:
1. Boundary: a blank line between two comment blocks ENDS the block. A banner (a line that
   is all punctuation / dashes / stars, or has no alphabetic word) is never the summary.
2. D-1 dedupe: before writing, compare against the existing summary and drop phrases that
   are already present, so re-runs do not accumulate.
3. D-1 volatility: the harvested region carries the auto marker and is rewritten on every
   batch run.
4. **D-5 (confirmed):** demote a comment whose first sentence names a FOREIGN symbol to
   `<remarks>` instead of making it the `<summary>`. See D-5's implementation notes -- the
   "foreign, and it must resolve" conditions are what keep it from eating good summaries.

Verify: new runner asserting the banner case, the orphan-note case, and idempotency across
two consecutive `--apply` runs.

**SHIPPED.** `tests/autodoc/run_doc_p3_harvest_boundary.ps1` (34 checks) + two fixtures.

- **Boundary** (`DRagLint.Doc.Harvest.HarvestScan`): a blank SOURCE line now ENDS the block,
  and the gap BELOW it is bounded by `BLANK_GAP_MAX = 1` -- the walk used to cross blank
  lines without limit, so it merged separate comment blocks and its header's claim to match
  `FindDocRegionAbove`'s `AllowGap` was false. `HarvestText`'s leading-banner drop STAYS: it
  catches a banner with no blank line after it, which the boundary rule cannot see.
- **D-5** (`DRagLint.Doc.Facts.DemoteForeignSummary`): three conditions, all narrow --
  compound-case spelling, resolves in the index, and EVERY declaration of the name is in
  another file. `Register`/`Create`/`Backup` (single-cased English words that are also
  symbols) do NOT demote; the runner asserts both conservatism arms, because a demoter that
  merely resolved the first identifier would satisfy every positive check and fail these.
- **D-1 dedupe** (`DRagLint.Doc.Regions.DropAlreadyPresentPhrases`): placed where the
  duplication actually happens -- `MergeComment`'s repair path, at the ownership handover. A
  human takes ownership of an engine line by deleting its marker; the harvest is recomputed
  from a source comment that is still in the file, so without the dedupe the engine re-emits
  its own copy underneath the human's, permanently, with no marker for `--strip` to find.
- **D-1 volatility** was ALREADY satisfied before this task (the marker is applied at emit
  time by `MergeComment`, and a marked tag is regenerated). Nothing was needed.

### A2 `[x]` Make the doc applier verify its anchor -- DONE 2026-08-06

`docs/INBOX-document-qname-second-apply-nests-block-on-stale-anchor.md` (filed today). Two
`document --qname --apply` runs against one class nest the second block inside the first,
emit two `<remarks>` opens, and leave the second symbol undocumented -- the second apply
anchors on the DB's pre-edit `start_line`.

This is the FOURTH instance of one root cause this week (`unused-local` destroyed 72 lines;
the naming autofix wrote onto `then`/`else` and exited 0 --
`docs/INBOX-naming-autofix-corrupts-source-on-stale-index.md`; and this). The other three
were fixed by making verification STRUCTURAL in `TTextEditApplier.ExpectText`
(`src/refactor/DRagLint.Refactor.TextEdit.pas`). The doc applier evidently does not route
through that check.

Do: route the doc applier through `TTextEditApplier.ExpectText` (do not add a second
verification path). On mismatch, apply D-2 -- reindex the project and retry once -- and if
it still mismatches, fail loudly. Never write at an unverified coordinate.

**SHIPPED.** `tests/autodoc/run_doc_p3_stale_anchor.ps1` (14 checks, reproduced RED first)
plus 6 new cases in `tests/refactor/TextEditTests.dpr` (20/20).

- The guard extends the EXISTING one rather than adding a path: `TTextEdit.ExpectLine` arms
  `AnchorIsValid` for the LINE kinds, which had no guard at all. `ExpectText` alone is not
  enough -- the stale coordinate in the filed defect landed on `/// Calls: Create`, a line
  that DOES contain the name -- so the anchor must also not be a comment line. That pair is
  what makes it structural.
- Validation is a PRE-PASS over the file as found. The repair path emits delete+insert as a
  pair; validating mid-loop would read the insert's anchor at a shifted offset and could
  half-apply it -- deleting an existing comment and dropping its replacement. Both edits
  carry the same anchor, so they fail or survive together (asserted).
- **D-2 recovery is real, not just a message**: `--unit` and `--qname` reindex and RECOMPUTE
  once, then re-apply; the runner asserts both members end up documented, each above its own
  declaration. The BATCH paths fail loudly instead and name `--reindex` -- their whole edit
  set was computed from the same stale snapshot, so re-applying it would refuse identically.
- `--json` gained an additive `staleAnchorsRefused` key so a machine consumer cannot read
  success where the text path reports a refusal.

### A3 `[x]` Emit `<param>` structure, harvest param meaning (D-3 + D-4) -- DONE 2026-08-06

Do:
1. Emit `<param name="X">` for every signature parameter, always, in batch mode.
2. Harvest the meaning from a comment adjacent to that parameter INSIDE the parameter list
   (`{ ... }`, `(* ... *)` or `//` between the separators around that param). That text
   becomes the param's body.
3. Merge by param NAME: a hand-written body survives untouched (D-4); only the structure
   (presence, name, ordering) is regenerated.
4. Params that vanish from the signature lose their tag; params added gain one.

Verify: a fixture with (a) an undocumented param, (b) a param carrying an inline comment,
(c) a param with hand-written prose that must survive a re-run, (d) a renamed param.

**SHIPPED.** `tests/autodoc/run_doc_p3_param_structure.ps1` (19 checks) covers A3 and A4 in
one runner, against one file, because they are two halves of one contradiction.

- **No second source read.** The INDEXED signature preserves the parameter list VERBATIM,
  comments included -- verified against a real index -- so `MineParamNotes` reads the
  meaning straight off `ASym.Signature`, with no dependency on line numbers that go stale.
- Attachment rule per D-3: a comment beside ONE NAME is that name's; a comment after the
  shared TYPE covers the group; the name's own comment wins. All three asserted.
- **Two defects surfaced and fixed along the way, both found by the runner, not by review:**
  (1) `ParseParamNames` did not strip comments, so `ALeft { the left edge }` became the tag
  NAME -- malformed, and never equal to itself on the next run. The scan is now ONE
  implementation (`ExtractPascalComments` in `DRagLint.Refactor.DocStub`) read by both the
  name half and the meaning half. (2) A marked param body was classified
  `taPreserveStripped` on the second run, so the engine stripped the marker off its OWN
  output every cycle and quietly handed itself ownership. Resolved EXACTLY rather than
  heuristically: compare the marked body with what the miner produces NOW -- equal means the
  engine wrote it (regenerate, fixed point); different means a human typed it (D-4: leave it
  alone).
- **Hover had to change too, and this is worth remembering**: "has `<param>` tags" stopped
  being the same question as "has param DOCUMENTATION". Keying the markdown fallback off tag
  PRESENCE would have replaced the informative signature-derived block (name AND type) with
  a list of bare names on every unit `document --apply` had touched, and plain hover would
  have printed `AValue -- ` rows with nothing after the dash. Both renderers now key off
  whether a tag carries text (`HasAnyParamDescription`).

### A4 `[x]` Teach `doc-drift` to accept the generated form (#3) -- DONE 2026-08-06

Otherwise A3 changes the wording of the 22 findings instead of clearing them. Locate the
rule by its message -- grep `has no <param> tag`. A present `<param>` tag inside a managed
block satisfies "has a tag" whether or not it has a body; a MISSING tag is still reported.
Decide separately whether an empty body deserves its own lower-severity hint (my view: yes,
as `hint`, so the to-do stays visible without being a warning).

**SHIPPED, except that separate decision.** The rule needed almost nothing -- it already
tested tag PRESENCE, and the parser captures an empty-bodied `<param>`. The one change it
did need: its `HumanAuthored` gate counted "at least one `<param>` already written" as
evidence of a human. Since A3 the engine writes one for every parameter, so that term was
about to become true of a block nothing human ever touched -- which would have re-opened the
exact defect the gate was added to close on 2026-08-03 (the tool grading its own output).
Engine-marked params no longer count toward authorship; a hand-written body does.

`[x]` **DECIDED AND SHIPPED 2026-08-07.** The user's ruling: report it, as a `hint`, **ON by
default**. The volume was put to them first -- inline param comments are rare, so this is
roughly one hint per undocumented parameter across a codebase, and `missing-doc` had already
been switched off for exactly that reason (a measured 1302-finding wave). They chose ON
anyway; that is their call and it is implemented as asked.

New rule id **`doc-param-no-description`** at `hint`, new drift kind `ddParamNoDescription`.
Two decisions inside it are worth knowing:

- **It is NOT doc-drift.** doc-drift is a `warning` meaning "the doc and the code moved
  APART". An empty body is not drift -- nothing moved, the description was never written.
  Folding it in would have made every freshly generated file look like it had regressed, at
  warning severity.
- **It is deliberately NOT gated on human authorship**, which is the one place it parts company
  with `ddParamMissing`. That gate exists so the tool does not grade its own output; here,
  grading its own output IS the point -- the engine wrote an empty body because ruling D-3
  forbids it from inventing meaning, and the to-do is for a human. Gating it would have
  silenced the rule on exactly the files it exists to annotate.

Only params in the CURRENT signature are considered, so a tag for a parameter that no longer
exists stays `ddParamRenamedOrRemoved`'s finding and is not named twice.

Test: `tests/autodoc/run_doc_param_no_description.ps1` (8 checks, RED first). It documents a
real fixture and asserts on the generated block, so it also pins the A3 shape it depends on:
the param WITH an inline source comment gets a body, the one without gets an empty tag, and a
parameterless routine produces no `<param>` finding of any kind.

Measured: 0 findings on DataCopy and TableTools today, because the rule fires on `<param>` tags
that already exist and neither project has had autodoc run on it. The volume appears after
`document --apply`, which is what the runner demonstrates.

### A5 `[x]` Whole-project run + diff review -- DONE 2026-08-06

Only after A1-A4. On a clean branch, `document --project --apply`, then read the diff, then
`lint-all` and confirm the `doc-drift` count actually falls. Do NOT run this against
DataCopy while the tester round is live (see C1).

**RUN AGAINST YADF**, copied to `C:\TEMP\a5_yadf` with a pristine twin beside it, so the
diff is reviewable and the user's tree is untouched. DataCopy was correctly avoided.

| measure | before | after |
|---|---|---|
| `doc-drift` findings | 35 | **11** |
| total findings | 673 | 649 |
| `<param>` tags | 50 | 53 |
| **non-doc source lines lost** | -- | **0** |

The last row is the one that matters and it was checked mechanically: every line of every
original file that is not a `///` line is still present, in order, across the whole corpus.

The 7 surviving `has no <param> tag` findings are NOT the contradiction #3 described. They
sit on declarations `document` did not touch -- `YADF.OptionsFrame.pas` is outside
`YADF.dproj`'s closure, and two `YADF.Layout.pas` routines were skipped by the facts-only
default. Proven by running `document --unit` on that one file: 3 of them cleared
immediately. The two halves converge now; they simply have to meet first.

Also confirmed on the real corpus: `YADFOT.Wizard.pas`'s `Register` -- the original banner
defect -- reads with the genuine eleven-line prose as its `<summary>`, no row of dashes
anywhere.

---

## PHASE B -- remaining engine defects

### B1 `[x]` #5b -- `except` handler ending in `exit` still merges with the normal path
-- DONE 2026-08-07, and the cause was WIDER than the filing

**SHIPPED.** Five new cases in `tests/lint/double-free.pas` (+ expectations), RED first on
three of them.

The second merge route was not an edge at all -- it was a **node selection**. The handler
scan accepted any `'statements'` child at index > 0, and the `try` node's children are
`(kTry) (statements = THE TRY BODY) (kExcept) (statements = the handler) (kEnd)`. Index 1 is
the try body, so **every `try..except` emitted its own try body into the CFG a second time**,
as a pseudo-handler wired from the try entry and on into the follow block. One statement was
analysed as two on a single path: a lone `X.Free;` in a try body was reported as a double
free -- the `DPPRoutines` 302-303 pair -- and the duplicate reached the code after the try,
which is the merge the previous session was looking for.

It was never conditional on the handler diverting. Measured before the fix, all three handler
shapes were wrong: `except exit;`, `except Writeln(...);` and `except on E: ... do exit;`.
`try..finally` was correct throughout (different code path), so the deliberate finally edge
was never touched.

Fix: track the `kExcept` token and treat only children AFTER it as handlers, mirroring the
`SeenFinally` scan directly above it. Skipping "index 1" would have worked and said nothing;
the token test states what the grammar means. If `kExcept` is somehow absent no handler is
emitted, which loses handler analysis but cannot invent a path.

Controls are part of the fixture on purpose (P10/P11): a genuine double free inside a try
body, and one straddling the try boundary, must still fire -- otherwise a "fix" that merely
stopped analysing try bodies passes.

### B2 `[~]` #1b -- the IDE reindex ignores the manifest
-- CODE CHANGED 2026-08-07, **NOT VERIFIED IN THE IDE**

**Root cause, confirmed in the code and matching the filed evidence.** It is not that the
reindex ignores the manifest -- `InvokeReindexProject` has called `ResolvePrimaryIndexDb`
since 2026-08-03, and that resolves manifest-first. The hole is one existence test:
`ResolveActiveIndexDbs` gates its manifest branch on `TFile.Exists(ManifestDb)`
(`DragLint.Plugin.DbResolver.pas` ~:521). That is right for a READER -- never point a consumer
at a DB that is not there -- and **self-defeating for the WRITER**, whose whole job is to
create it. A section whose DB has never been built fails the test, the resolver falls through
to the per-.dproj convention, and the reindex builds `<projdir>\drag-lint.sqlite` instead. The
manifest DB still does not exist, so the next reindex makes the same choice. It is a stable
loop, which is exactly why DataCopy's section could sit in `drag-lint.json` from `6e66279`
onward with `C:\Projects\.drag-lint\DataCopy.sqlite` never existing at all, while the IDE
maintained a project-local DB holding 17 files that were gone from disk
(`docs/INBOX-datacopy-2026-08-06-manifest-db-never-created-and-doc-lint-defects.md` section 1).

**Change:** `ResolvePrimaryIndexDb` now asks `ManifestDbForFile` DIRECTLY and accepts a path
that does not exist yet -- that function has no existence check of its own, it answers "which
section covers this file", which is the writer's question. It also creates the manifest
`outDir` if missing, since a first-ever build has nowhere to write. Only when no section
covers the file does it fall back to the readers' resolution and then to the per-project
convention, so a project outside the manifest is unchanged.

**WHAT IS NOT DONE, and it is the part that matters.** The BPL compiles (`-B`, 0 errors, the
edited unit really was recompiled) but **this has not been exercised in a running IDE**, which
is the only place the OTA calls it depends on -- `GetActiveEditorFilePath`,
`GetActiveProjectFile` -- return anything at all. Do not treat it as shipped. To verify: open a
manifest-covered project whose DB does not exist (delete `C:\Projects\.drag-lint\DataCopy.sqlite`
first), run Reindex Project, and confirm from `%TEMP%\drag-lint-reindex.txt` that the
`Database:` line names the manifest path and not `<projdir>\drag-lint.sqlite`.

**Note:** the package build writes the BPL to `third_party\dll-win64`, so the plugin the IDE
loads has ALREADY changed on disk. If the IDE misbehaves before this is verified, rebuild the
BPL from the previous commit.

**Still open under this item:** folding D-2 in (a suspected-stale IDE index should full-reindex
the PROJECT into the manifest-resolved DB) -- that is B10's half and was not touched.

### B2-original `[ ]` the filed description, kept for reference

It writes `<projectRoot>\drag-lint.sqlite` by convention instead of resolving the manifest
section that CONTAINS the path. Consequence: docs generated from one DB, linted against
another, and the manifest's `exclude` never applies to the DB the IDE actually uses -- this
is what produced the 15 spurious `doc-drift` findings. #1a (naming an unbuilt manifest DB
on stderr) already shipped. Fold D-2 in here: when the IDE suspects staleness it should
full-reindex the project into the MANIFEST-resolved DB.

### B3 `[x]` Bare parameterless calls in expression position are still unrecorded
-- DONE 2026-08-07

**SHIPPED.** `tests/autotest/run_expr_bare_call_refs.ps1` (19 checks), reproduced RED first
with all five expression shapes at ZERO refs.

`DRagLint.Parser.Delphi13.EmitExpressionIdentReads`, called last inside the `EmitUsageRefs`
block and deliberately NOT exiting. It covers the slots the v0.42 usage-ref handlers left
untouched -- those reached only `obj.Member`, an assignment's bare-identifier RHS and a bare
argument -- namely `exprUnary`, `exprBinary`, `exprParens`, `exprBrackets`, `exprSubscript`
and the `if` / `while` / `repeat` / `for` / `foreach` / `with` / `case` / `caseLabel` /
`raise` slots.

**The kind is `read`, not `REF_KIND_CALL`, and that is the whole design decision.** In
expression position the tree cannot distinguish a parameterless call from a variable read --
`KeepGoing` is spelled identically either way and only cross-unit symbol resolution could
decide. Emitting a call ref would put every variable read into the universe
`ResolveCallTargets` resolves and that BOTH unresolved-call queries take their complement
against, which is precisely the defect T3i closed. `read` is already what the identical
ambiguity gets in `Result:= MaxItems;` and `Foo(Bar)`, and it is sufficient for the harm being
fixed: `FindCallersByName` -- what `unused-public-symbol` and `query find-callers` consult --
matches ANY ref kind. `call_edges` is unchanged, so anything needing certainty still has it.
The runner asserts the non-widening directly: a local variable used in a condition gains a
ref but NOT a call-kind one.

`exprBinary` skips its RHS when the operator is `kIs`/`kAs` -- that RHS is a type name and
already carries a `type_use`, and two ref rows of different kinds at one span is the
co-located-duplicate shape behind register E1.

The DISCLOSED CONSEQUENCE paragraph in `Core.Model`'s `REF_KIND_CALL` comment still stands as
written: the paren-less DOTTED invocation (`N:= Obj.Func;`) remains outside the call universe,
carrying only its `member-access` ref. That is a different, narrower gap and is not B3.

### B4 `[ ]` Receiver-aware unverified caller bucket (residual of #7)

#7's uses-scope filter removes the IMPOSSIBLE attributions. Same-unit and reachable-unit
noise survives -- e.g. `TStringList.Create(True)` inside a unit that legitimately uses the
target. The index already records the receiver but does not associate it: for
`Lst:= TStringList.Create(True)` the refs are `read 'TStringList'` then `call 'Create'`,
recoverable today only by position arithmetic. Proper fix: carry the receiver token on the
call ref (or a call_edges row with confidence `unresolved` + receiver text), then reject a
name match whose receiver cannot denote the target's owner.

### B5 `[ ]` `ComputeCoveredBy` still takes the unscoped bucket

`src/doc/DRagLint.Doc.SymbolFacts.pas` ~2851. Same pollution exposure, and its own comment
says so ("a phantom name-match inside a `*Test.pas` would assert Covered by"). Needs a
per-hop file id its `Walk` does not currently carry.

### B6 `[ ]` Extra (cross-DB) stores are unscoped

#7 passes 0 for extra stores deliberately -- file ids are per-DB keys. Section-7 noise can
still arrive from an extra store. Fix needs the target unit resolved BY NAME inside each
extra store before its uses graph can be used.

### B7 `[x]` `lint-all --json` prints a banner into stdout -- ALREADY FIXED 2026-08-06

**This item was stale when it was written into this plan.** The INBOX note
(`docs/INBOX-lint-all-json-stdout-banner.md`) already carried a `Status: FIXED 2026-08-06`
section; the plan's PHASE B list was assembled from the older resume doc and did not pick it
up. Re-verified empirically on 2026-08-07: `lint-all --db <db> --json` stdout begins at `[`
and round-trips through `ConvertFrom-Json`.

The durable form was taken rather than a per-site gate: `IsMachineReadableOutput(AArgs)` plus
`EmitStatusLine(AArgs, AText)` in `DRagLint.CLI.pas`, which routes the scanning banner, the
no-index error and the baseline line to **stderr** whenever the output is machine-readable.
Regression test: `tests\ergonomics\run_pipeline_tests.ps1` section 6, which asserts the banner
is absent from stdout AND still present on stderr.

### B8 `[x]` #9b -- report encoding cosmetics -- DONE 2026-08-07

**SHIPPED.** `tests/autotest/run_report_encoding.ps1` (5 checks, RED first with 6 non-ASCII
bytes in the report: 3 BOM + 3 em dash).

Two independent causes, both fixed:
- the report was written with `TFile.WriteAllText(..., TEncoding.UTF8)`, and that encoding
  carries a PREAMBLE, so every report opened `EF BB BF`. Now
  `TFile.WriteAllBytes(OutPath, TEncoding.UTF8.GetBytes(...))` -- same UTF-8, no preamble, so
  a path that genuinely needs non-ASCII still round-trips while the ordinary report is plain
  ASCII;
- `rules/writeln-in-source.json` held a real em dash (U+2014). Normalised to `--`, which is
  what every other message in the catalogue uses.

The runner drives the report END TO END -- index a fixture, `lint-all --output`, read the
bytes -- rather than only scanning the rule files, so a future writer that reintroduces a
preamble fails here too. It also asserts the fixture actually fired `writeln-in-source`,
without which the ASCII check would pass vacuously. (That check earned its place immediately:
the first draft spelled the call `Writeln` and the rule's `#eq?` predicate is case-SENSITIVE
on `WriteLn`, so the rule never fired and the em dash never reached the report.)

**Observed while doing this, NOT fixed, for a later sweep:** 13 of the 112 files in `rules/`
(`empty-on-handler`, `gettickcount-wraparound`, `hardcoded-absolute-path`,
`hardcoded-connection-string`, `hardcoded-ip-address`, `locale-sensitive-conversion`,
`not-comparison-precedence`, `outputdebugstring`, `public-field`, `redundant-not-not`,
`uppercase-compare`, `uppercase-compare-always-false`, `writeln-in-source` -- each in both its
`.json` and `.scm` form) use LF line endings where the rest of the repo is CRLF.
`run_encoding_guard.ps1` does not cover `rules/`, which is why it never showed. Normalising
them and adding `rules/` to the guard's roots is a self-contained follow-up; it was left out
of B8 deliberately because it is a different invariant from the one B8 is about, and folding
it in would have made this commit a 26-file line-ending churn.

### B9 `[x]` New noise introduced by the loop-bound fix -- DONE 2026-08-07.
The suspicion in the original note was exactly right, and much bigger than one variable

`exit(False)` was NOT being modelled as a divert. **Neither was anything else**: EmitStmt
asked "is this a divert?" by comparing a `statement` node's WHOLE TEXT against `'exit'`, and a
statement node includes its terminating semicolon, so the test read `'exit;' = 'exit'` and was
always false. **No bare `exit;`, `exit(v);`, `break;` or `continue;` had ever left the flow**
in any drag-lint release. Each fell through to whatever followed it.

It hid because a guard clause's join block normally holds the very assignment the fall-through
would have skipped, so the wrong edge changed no answer. It stopped hiding where the
assignment sits BEYOND the join -- which is why it surfaced as `lcount` here and, separately,
as the `srcsize` half of B1. **B9 and the unexplained half of B1 were one defect.**

Fix: `StatementKeyword` reads the statement's leading identifier (or the entity of its leading
`exprCall`, which is what also repairs `exit(v)`, whose text never resembled `'exit'` at all).

**Making exit divert exposed two modelling gaps that had been unreachable, and both had to be
closed for the change to be a net improvement -- measured, not assumed:**

- **`exit(v)` assigns Result.** A check for this already existed in `TDefiniteAssignment`, but
  it asked for `NodeType = 'exprCall'` while a CFG block stores the STATEMENT node, so it had
  never fired once. Now `IsValuedExit` in `DRagLint.Analysis.Cfg`, exported so the question has
  ONE answer; it accepts either node shape.
- **A divert inside a `try..finally` runs the finally.** `DivertVia` emits a COPY of each
  enclosing finally body on the divert path -- a copy, not an edge into the block the normal
  path uses, because sharing it would let divert state flow on into the code AFTER the try,
  i.e. B1's fall-through one level up. `TLoopCtx` gained `FinallyDepth` so `break`/`continue`
  replay only the finallys opened INSIDE their loop; a `try..finally` wrapping the whole loop
  correctly keeps running afterwards.

Measured before/after on three corpora with two binaries built for the purpose:

| corpus | before | after | changed |
|---|---|---|---|
| DataCopy | 473 | **465** | -4 `double-free`, -3 `used-before-assignment`, -1 `function-result-not-set`; **0 new** |
| TableTools | 424 | 424 | nothing |
| Loader2019 | 3367 | 3366 | -2 `used-before-assignment`, **+1 `object-leak`** |

Every removal was read in the source and confirmed a false positive. The single addition is a
**REAL LEAK**, previously invisible: `Loader2019.Main.pas` `FormCreate` creates `INIFile` at
3121 and frees it at 3335, and the `Exit;` at 3142 returns between the two.

Tests: three flowengine cases asserting the EDGE (`tests/flowengine/FlowEngineTests.dpr`,
61/61) -- deliberately the edge and not a downstream finding, because a rule-level test goes
green again the moment any rule stops looking while the fall-through survives for the next
analysis -- plus fixture cases in `object-leak.pas`, `function-result-not-set.pas` and
`used-before-assignment-clean.pas`, each with a control (an exit OUTSIDE the try still leaks; a
BARE exit still leaves Result unset), and each verified RED against the intermediate binary
that had the divert fix but not the gap fixes.

### B10 `[ ]` Make D-2 a rule the tools follow

Today "reindex if stale" is advice in `CLAUDE.md`. Per D-2 it should be behaviour: when a
command detects that a file's mtime/sha differs from the indexed row, or that an anchor
does not match, it reindexes the whole PROJECT and retries once before reporting. Decide
where the check belongs (store open? per-verb preflight?) and make the message say what it
did.

---

## PHASE C -- DataCopy (the consumer project)

### C1 `[x]` Merged and shipped to the tester -- do not disturb the round

**Done by a concurrent session while this plan was being written; verified here.** `default`
is at **rev 47**, SINGLE HEAD, hardening branch merged and closed. Exe
`Win64\Debug\EXE\DataCopy.exe` v2.1.1.69 went to a human tester for 2026-08-07. Cold-start
state for that project: `C:\Projects\DataCopy\RESUME-2026-08-06.md`. Next there is triaging
the tester's report -- not ours unless asked.

### C2 `[x]` MERGE BLOCKER -- resolved by the merge above

The 19 `!` files (10 retired units moved to `Backup-20260805\`) are no longer blocking; the
branch merged cleanly to a single head. Nothing to do.

**Standing caution:** because DataCopy has shipped to a tester, A5 (the whole-project
document run) must NOT be pointed at it until that round closes.

### C3 `[ ]` Source work never started

- rename `FName1` / `FName2` / `FName3` / `FNameOut` to something meaningful;
- add `try-finally` to the unprotected findings;
- run autodoc across the project and clear `doc-drift` -- gated on PHASE A.

---

## PHASE D -- filed by other workstreams, not started, not owned

Both are staked ground rather than requests; neither blocks anything here.

- `docs/INBOX-editor-integration-and-delphilsp-union.md` -- item 1 (VS Code / Zed can use
  drag-lint today, config only) is DONE by them; item 2 is a **DelphiLSP union design that
  needs an engine-team ruling before anyone codes**. Design doc:
  `docs/superpowers/specs/2026-08-05-delphilsp-union-design.md`. This is the one item in
  Phase D that is actually WAITING ON US.
- `docs/INBOX-editor-native-extensions-and-build-orchestration.md` -- LOW urgency, nothing
  started, filed only so the ground is not claimed twice.

---

## Housekeeping

- `[x]` `main` is **pushed and in sync with origin** at `24eec74` (PHASE A1-A5). The user
  authorised pushing after each green battery on 2026-08-06.
- `[ ]` `FEATURES.txt` is modified in the working tree and predates this work -- the user's,
  left alone deliberately.
- `[ ]` INBOX notes stay UNTRACKED by convention. Seven are open in `docs/`.
- Battery is **226/226** at `24eec74` (3 new runners since `d21ef58`). It needs `pwsh`;
  ~13 min. Never rebuild the exe mid-battery, and never edit `src\*.pas` mid-battery (some
  runners compile from source -- `tests/refactor/*.dpr`, `lintconfig`, `projectchecks`,
  `rules-catalog`, `sarif`, `searchparse`, `baseline`, `preprocess/run_tolerance`. None
  compiles `DRagLint.CLI.pas`, so a CLI-only edit is the one safe exception).
- **The battery's own log is BUFFERED** when redirected with `*>`, so the tail lags by
  minutes and looks stalled. Read `C:\TEMP\draglint_battery_<stamp>\` instead -- two files
  per finished runner, written live -- or wait for `results.csv` to appear.
- Normalise every new/edited repo file to CRLF before running the battery -- the agent
  `Write`/`Edit` tools emit lone LF and `run_encoding_guard.ps1` fails the whole battery
  for it. This bit twice today.
