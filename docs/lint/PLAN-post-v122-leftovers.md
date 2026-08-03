# Plan: post-v1.2.2-alpha leftovers, the main merge, and getting to conversions

**Written:** 2026-08-03, at the end of the Auto-Document Phase 3 session.
**Status of the tree at that moment:** `main` = `3b4a877`; `feat/autodoc-phase3`
= `3f7543e` (pushed); `merge/converter-into-main` = `1754061`. Only those two
branches are unmerged into `main` -- every other branch already is.

---

## 0. THE BLOCKER, and it is a one-liner

`git merge --ff-only feat/autodoc-phase3` **fails while RAD Studio is running.**
The fast-forward has to rewrite `third_party/dll-win32/dclDragLintWizard.bpl`
(it genuinely differs between the two commits), and the IDE has that design-time
package loaded, so the file is locked:

```
error: unable to write file 'third_party/dll-win32/dclDragLintWizard.bpl'
       mode 100644: Permission denied
```

**Close RAD Studio (bds.exe) first.** Nothing else about the merge is difficult.
A safety copy of the locally-modified BPL is in `stash@{0}`.

---

## 1. Merge both branches into `main`

Order matters: the autodoc branch is a clean fast-forward, so take it first.

```bash
git checkout main
git merge --ff-only feat/autodoc-phase3      # 149 ahead, 0 behind -> pure FF
git merge merge/converter-into-main           # 3 ahead / 3 behind -> real merge
```

The converter merge should be clean: its three commits touch only
`convrules/BDE-to-FireDAC.rules`, `docs/RESUME-proptree-and-converter.md` and
`convrules-editor/tests/ConvRulesModelTests.dpr`, while `main`'s three commits
since the merge base are parser fixes. Disjoint file sets.

**Then rebuild and re-gate before anything else touches the tree:**

```bash
build/build_draglint.bat                      # or the T17 wrapper
pwsh -File tests\run_battery.ps1              # expect 214/214, quote the driver's OWN denominator
```

Push `main` once green. Note `main` was already 128 commits ahead of
`origin/main` BEFORE this merge -- that backlog is pre-existing, not new.

---

## 2. The one piece of Phase 3 that is genuinely unfinished

**Reindex the nine manifest DBs to schema v19.**

```bash
drag-lint index --all --config third_party\dll-win64\drag-lint.json --jobs 0 --dry-run
drag-lint index --all --config third_party\dll-win64\drag-lint.json --jobs 0
```

`--jobs` **needs** `--config` -- without it the run goes sequential and takes
hours per platform. Preview with `--dry-run` first. Then verify each DB reads
`schema_version = 19` and that `symbol_facts` has non-null values in at least one
of the four new columns.

YADF's two DBs are already done (`YADF.sqlite`, `YADFOT.sqlite`, both v19).

**Then fill in section 6 of
`docs/INBOX-index-schema-v19-reindex-for-converter.md`**, which today
deliberately says "not yet rebuilt" and carries an EMPTY table rather than a list
that is not true yet.

---

## 3. What "ready for conversions" actually requires

Conversions need four things true at once. Two are already true:

| # | Requirement | State |
|---|---|---|
| 1 | Engine carries the converter INBOX fixes (2.1, 2.4, 2.6, 2.8, 2.9, 2.10, 2.11) | **Done**, but split across `main` (2.1, 2.11) and the autodoc branch (the rest) -- **step 1 is what brings them together** |
| 2 | The BDE->FireDAC rules library | **Done**, on `merge/converter-into-main` -- also step 1 |
| 3 | `ConvRulesEditor.exe` + `drag-lint.exe` **deployed as a PAIR** | **Not done** -- see below |
| 4 | Indexes at v19 so the new columns and the NOCASE indexes exist | **Not done** -- step 2 |

**On (3): the pair rule is load-bearing.** The editor and the engine must be
deployed together; a mismatched pair is the failure mode the converter team
already hit. Their phantom-root workaround for INBOX 2.9 can now be REMOVED,
because 2.9 is fixed in the engine -- see
`docs/INBOX-REPLY-2026-08-02-engine-completion-report.md`.

**Known limitation to carry into conversion work:** INBOX **2.5** is deliberately
NOT fixed -- a bare `TEdit` resolves to the FMX one. That was a product decision,
not an oversight; the suggested shape if it ever matters is a
`--prefer-namespace Vcl` hint on the query rather than a baked-in default.

---

## 4. Smaller leftovers, roughly by value

1. **`run_doc_drift_rule.ps1` does not gate `ddHarvestDrift`.** That path was
   verified by hand on a scratch index (`lint-all --json` emits it under rule id
   `doc-drift`; `--fix --apply` clears it), but nothing in the battery would
   catch a regression. Cheapest real win on this list.
2. **The `Pure` gate is an open decision.** `Pure` currently never CREATES a doc
   block -- it only appears on blocks that exist for another reason. The plan's
   literal version turned eleven suites red by giving nearly every trivial
   routine a block. Widening it is one condition in
   `TDocRegions.FormatPhase2FactLines`; unwinding a corpus-wide block explosion
   is not.
3. **`docs/INBOX-bare-call-in-binary-expression-not-indexed.md`** -- a bare
   parameterless call used as a binary-expression operand records NO ref at all.
   `Result := A;` and `Result := Abs(A);` both work; only `Result := A + 1;` is
   dropped. Probable site: `Walk`'s `assignment` arm only inspects
   `ChildByField('rhs')` for a bare identifier. Any fix must keep
   `run_bare_rhs_refs.ps1`'s over-capture guard.
4. **The 39 blank `<summary></summary>` in YADF.** They predate uniform marking
   (that tree had 49 managed blocks and zero markers), so the engine correctly
   treats them as hand-written and `--strip` cannot clear them -- it is
   marker-keyed. They are the reason the harvest yield on YADF was 2 rather than
   a large share of its 120 implementation-side comments. Removing them is a
   deliberate manual edit and needs a decision.
5. **`'event handlers'`** (YADF.OptionsFrame.pas) is a poor harvested summary
   that survives: a bare section label with no separator characters, so not
   decoration by any deterministic test. Left alone on purpose -- widening the
   rule to reject short labels would start rejecting genuine short summaries.
6. **The `Assigned` section feature** -- still 0 lines of code. Spec:
   `docs/lint/FEATURE-assigned-section-autodoc-hover.md`.
7. **Three older untracked INBOX notes** from previous sessions (type-alias
   shapes, converter phase-G findings and its reply).

---

## 5. Suggested order

1. Close RAD Studio -> merge both branches -> rebuild -> battery -> push `main`.
2. Reindex the nine DBs to v19 -> fill INBOX section 6.
3. Deploy the ConvRulesEditor + drag-lint pair. **Conversions can start here.**
4. Then, as separate work: the `ddHarvestDrift` test gate, the `Pure` decision,
   the bare-call ref gap.

Steps 1-3 are what "ready for conversions" means. Step 4 is quality debt that
does not block it.
