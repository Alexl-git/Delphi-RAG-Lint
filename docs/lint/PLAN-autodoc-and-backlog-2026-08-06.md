# PLAN -- autodoc chain + the whole open backlog (2026-08-06)

Written at the user's request as the single tracker for what is left. Supersedes the
"NOT DONE" list in `RESUME-datacopy-inbox-2026-08-06.md` as the ORDERING authority; that
doc keeps the per-defect diagnosis and the gotchas.

Status keys: `[ ]` not started · `[~]` in flight · `[x]` done · `[?]` needs a decision.

---

## >>> RESUME POINT (updated 2026-08-07) -- READ THIS FIRST

**State.** PHASE A is COMPLETE. `main` = **`24eec74`, pushed, in sync with origin**. Battery
**226/226** (~13 min, needs `pwsh`). The exe beside the tests
(`third_party\dll-win64\drag-lint.exe`) is built from that commit -- rebuild only if you
change `src\`.

Working tree carries `FEATURES.txt` (another workstream's, **do not commit**) and untracked
INBOX notes (untracked by convention). Nothing else is outstanding.

**Next action: PHASE B**, ten engine defects below, none started. Suggested order, and why:

1. **B3** -- bare parameterless calls in expression position are unrecorded. Same family as
   the nested-routine gap and the same consequence: `unused-public-symbol` calls live code
   dead, i.e. the tool tells a user to delete working code. Highest harm of the ten.
2. **B7** -- `lint-all --json` prints a banner to stdout, so the output does not parse.
   Small, self-contained, and it blocks anyone scripting a baseline.
3. **B1** -- an `except` handler ending in `exit` still merges with the normal path. One
   wrong CFG edge was ALREADY fixed and did NOT clear the symptom, so a second merge route
   is still unfound. The `finally` equivalent is DELIBERATE -- do not "fix" that one.

Then B2/B10 together (they are the same D-2 rule at two levels), B4/B5/B6 (all the same
unscoped-bucket family), B8/B9 (cosmetic / small).

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

`[ ]` **STILL OPEN, and deliberately not decided here:** the lower-severity hint for a
PRESENT-but-EMPTY body. It needs a new finding kind and a rules-catalogue entry, which adds
findings to every consumer's run -- that is the user's call, not a side effect of A4.

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

### B1 `[ ]` #5b -- `except` handler ending in `exit` still merges with the normal path

`uFileUtils.pas` `srcsize` and the `DPPRoutines` double-free pair at 302-303 are ONE bug.
One wrong CFG edge was already fixed in `src/analysis/DRagLint.Analysis.Cfg.pas` (a
diverting handler still wired to the follow block; `EmitStmt` returns -1 for
exit/raise/break/continue meaning "does not fall through") and it did NOT clear the
symptom -- there is a SECOND merge route still to find. The `finally` branch's equivalent
edge is DELIBERATE (a finally always runs) -- do not "fix" that one.

### B2 `[ ]` #1b -- the IDE reindex ignores the manifest

It writes `<projectRoot>\drag-lint.sqlite` by convention instead of resolving the manifest
section that CONTAINS the path. Consequence: docs generated from one DB, linted against
another, and the manifest's `exclude` never applies to the DB the IDE actually uses -- this
is what produced the 15 spurious `doc-drift` findings. #1a (naming an unbuilt manifest DB
on stderr) already shipped. Fold D-2 in here: when the IDE suspects staleness it should
full-reindex the project into the MANIFEST-resolved DB.

### B3 `[ ]` Bare parameterless calls in expression position are still unrecorded

Left open by step 2a. `if not LoopsBackIntoScan then` is a bare parameterless call in
expression position, which is not an `exprCall` node, so no ref row is emitted and the
symbol shows 0 refs. Same family as the nested-routine gap and the same consequence:
`unused-public-symbol` can call live code dead. See the block comment above
`REF_KIND_CALL` in `DRagLint.Core.Model`.

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

### B7 `[ ]` `lint-all --json` prints a banner into stdout

`docs/INBOX-lint-all-json-stdout-banner.md`. `--json --quiet` still emits
`lint-all: scanning N .pas file(s)` on stdout, so the output does not parse. Progress and
banners belong on stderr. Small, and it blocks anyone scripting a baseline.

### B8 `[ ]` #9b -- report encoding cosmetics

The report file carries a UTF-8 BOM, and `writeln-in-source` uses a real em dash while
every other rule message uses `--`. That one character is what makes the report non-ASCII.
Normalise the message and drop the BOM.

### B9 `[ ]` New noise introduced by the loop-bound fix

`lcount` at `uFileUtils.pas:1045` -- previously invisible because the loop bound was never
read; the bound-as-read fix exposed it. Check whether `exit(False)` inside an if-chain is
being modelled as a divert.

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
