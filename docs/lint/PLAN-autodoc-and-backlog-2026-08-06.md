# PLAN -- autodoc chain + the whole open backlog (2026-08-06)

Written at the user's request as the single tracker for what is left. Supersedes the
"NOT DONE" list in `RESUME-datacopy-inbox-2026-08-06.md` as the ORDERING authority; that
doc keeps the per-defect diagnosis and the gotchas.

Status keys: `[ ]` not started · `[~]` in flight · `[x]` done · `[?]` needs a decision.

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

**Open question I could not resolve from the above (ASK BEFORE PHASE A2):** D-1 fixes the
*explosion* and *volatility* halves of #8, but not the *misattribution* half. The live
example is a comment that documents a REMOVAL -- "SourceStampString used to live here. It
MOVED to uFileUtils ..." -- which the harvester attached to the next declaration,
`TZEISSTransfer.Create`. Under D-1 that summary is still harvested and still wrong; it is
merely now marked volatile and rewritten each run. My recommendation is a narrow ADDITION
that does not weaken D-1: keep harvesting, but when the comment's first sentence names a
symbol that is neither the declaration being documented nor declared in this unit, emit it
under `<remarks>` rather than `<summary>` (demote, do not discard). Confirm or overrule.

---

## PHASE A -- the autodoc chain (the user's chosen order)

Target end state: `document --project --apply` can be run over a whole project and produce
docs that are correct, idempotent, and that `lint-all` then reports clean.

### A1 `[ ]` Fix the harvest boundary + attribution (#8)

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
4. (Pending the open question above) demote a comment whose first sentence names a foreign
   symbol to `<remarks>`.

Verify: new runner asserting the banner case, the orphan-note case, and idempotency across
two consecutive `--apply` runs.

### A2 `[ ]` Make the doc applier verify its anchor

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

### A3 `[ ]` Emit `<param>` structure, harvest param meaning (D-3 + D-4)

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

### A4 `[ ]` Teach `doc-drift` to accept the generated form (#3)

Otherwise A3 changes the wording of the 22 findings instead of clearing them. Locate the
rule by its message -- grep `has no <param> tag`. A present `<param>` tag inside a managed
block satisfies "has a tag" whether or not it has a body; a MISSING tag is still reported.
Decide separately whether an empty body deserves its own lower-severity hint (my view: yes,
as `hint`, so the to-do stays visible without being a warning).

### A5 `[ ]` Whole-project run + diff review

Only after A1-A4. On a clean branch, `document --project --apply`, then read the diff, then
`lint-all` and confirm the `doc-drift` count actually falls. Do NOT run this against
DataCopy while the tester round is live (see C1).

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

### C1 `[ ]` The tester round is live -- do not disturb it

hg branch `datacopy-hardening-2026-08-05` at rev 33; `default` clean at 17. The user is
sending `C:\Projects\DataCopy\TEST-INSTRUCTIONS-2026-08-06.txt` to a human tester. If it
passes: merge to default + final build.

### C2 `[ ]` MERGE BLOCKER -- 19 tracked files show `!`

The user moved 10 retired units into `Backup-20260805\`. Both projects build clean without
them, which is empirical proof they were dead. Record the move with `hg remove --after`
BEFORE merging, or the merge carries phantom deletions.

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

- `[ ]` `main` is **1 commit ahead of origin** (`d21ef58`, the #7 fix). Push was not
  requested; ask before pushing.
- `[ ]` `FEATURES.txt` is modified in the working tree and predates this work -- the user's,
  left alone deliberately.
- `[ ]` INBOX notes stay UNTRACKED by convention. Seven are open in `docs/`.
- Battery is **223/223** at `d21ef58`. It needs `pwsh`; ~12 min. Never rebuild the exe
  mid-battery, and never edit `src\*.pas` mid-battery (some runners compile from source).
- Normalise every new/edited repo file to CRLF before running the battery -- the agent
  `Write`/`Edit` tools emit lone LF and `run_encoding_guard.ps1` fails the whole battery
  for it. This bit twice today.
