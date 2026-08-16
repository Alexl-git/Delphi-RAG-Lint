# INBOX index -- 59 open notes, triaged 2026-08-15

**49 notes were retired to `INBOX-Done/`** in this pass (108 -> 59). Every retired
note carries a one-line banner saying WHY, so the trail survives the move; nothing
was deleted.

What was retired, by kind: 11 outbound REPLY notes; 11 upstream tree-sitter status
announcements (deliveries, publications, discharged rebuild asks); 21 defect notes
whose fix is shipped AND guarded by a green regression runner; 6 historical
incident reports / superseded surveys.

**Two were retired after RE-MEASURING, not after coding** -- the cheapest kind of
progress here, and worth trying first on anything below:
* `naming-autofix-corrupts-source-on-stale-index` said *"Status: Not fixed"* on a
  HIGH-severity silent-corruption defect. The guard has been in
  `Refactor.Rename.pas:374` since v0.82 with a passing test. A stale note like that
  sends a session chasing a solved problem and its workaround talks people out of a
  working feature.
* `object-leak-is-systematically-false` quoted 3/7/7 across the YADF projects; it
  is **1/1/1**, and all three are the SAME finding in a shared unit.

---

## Priority 1 -- known-wrong output, worth fixing next

| note | why it ranks here |
|---|---|
| `group-E-dataflow-rules-are-majority-false` | **DONE 2026-08-16 -- retire it.** All three sections fixed: `overwrite-before-read` 56 -> 32, `used-before-assignment` closed to a path-sensitivity residue, `double-free` **42 -> 0**. The last one was THREE bugs, not one (member/element free credited to the base var; the for-in iterator not rebound; an inline `var X := ..` not counting as a definition at all -- the fourth "keywords are NAMED nodes" bug). Guard: `run_double_free_loops_and_members.ps1`, 7/7 with three positive controls. |
| `remaining-raw-text-scans-read-comments-as-code` | The audit result for the nine-instance family. Three left: FormsMap launch/show detection (wrong CSV rows), TypeAt hover inference, the `todos` verb. Also records what was CLEARED so nobody re-audits. |
| `audit-store-backed-fix-paths-for-stale-positions` | **DONE 2026-08-16 -- retire it, NOT a live defect.** The note was ~80% stale: `ReplaceEditIsValid` already rejects a past-EOL Col, `AnchorIsValid` + `ExpectLine`/`ExpectText` already IS the one shared boundary assertion, `StampAnchor` already arms it. The one unstamped site (the pure deletion) turned out to be unreachable when stale -- measured: `document --unit`, `document --qname` and `lint-all --fix --apply` all refuse, because `Existing` is recomputed from CURRENT file text. Stamp added for consistency; **no test ships**, because the guard I wrote passed without the fix. |
| `bare-except-anchor-defeats-a-hand-written-marker` | A hand-written `dl:ok` at the obvious place never matches, then gets reported unused. Fixing the anchor invalidates every recorded `@hash` for the rule -- take that churn deliberately, once, and check sibling rules first. |
| `returns-type-baseline-destroys-malformed-blocks` | **MISCLASSIFIED -- not a defect, and now discharged.** The destructive change was REVERTED and never shipped; listing it as DESTRUCTIVE sent a session hunting a live bug that does not exist. Its real content was one unproven precondition ("make the malformed-region guard hold on a declaration the engine DOES have output for") -- **measured 2026-08-16, it holds**, and is now pinned by `run_doc_malformed_region_holds.ps1` (5/5, with the control arm that D5 lacked). Move to a design-record section; the recommendation to NOT generate `<returns>` baselines stands. |
| `shared-unit-empty-render-deletes-block` | **DONE 2026-08-16 -- retire it. It was already guarded.** The fixture this note asks to "check in this time" is inside `run_shared_unit_staleness.ps1:337-352` -- the `Busy` unit, three assertions, naming this defect's mechanism verbatim. Nothing to write; the note simply outlived its fix. |

## Priority 2 -- false positives blocking a true zero

`object-leak-is-systematically-false` (1 finding, a third cause: a tree cursor
whose nodes escape via the returned root -- needs escape-through-constructor-arg
analysis) · `used-before-assignment-array-local-never-counted-as-defined` (its own
first version was WRONG and says so) ·
`used-before-assignment-real-shape-is-intra-item-ordering` (**partly addressed**:
`and`/`or` left-to-right sequencing is now modelled -- see `CollectAndOrLeftDefs`;
the general position-ordered case is not) · `inherited-bare-fires-on-the-mandatory-idiom` ·
`referenced-never-set-false-positive-on-record-factories` · `create-inside-try-qualified-lhs-not-flagged` ·
`deep-nesting-silent-on-trailing-else-call` · `inline-comment-rule-premise-is-false-for-yadf` ·
`field-name-prefix-fixable-flag-lies` (advertises fixable, refuses to fix) ·
`yadf-triage-2026-08-12-out-param-and-object-leak-false-alarms` · `yadfot-loopzero-remainder-2026-08-13`

## Priority 3 -- silent no-ops and wrong-scope commands

These share one shape: **the command reports success while doing less than asked.**
`context-bundle-empty-for-bare-name` (**new 2026-08-16, confirmed twice**:
`context --task "modify <BareName>"` emits an empty bundle and exit 0 while
`query --name` resolves the same name fine. Ranks high for its size -- CLAUDE.md
tells every session to run this verb BEFORE reading a large `.pas`, so the silent
empty answer costs exactly the ~60x saving the feature exists to provide) ·
`index-all-only-silently-does-nothing` · `index-only-nonmatching-section-is-a-silent-noop` ·
`lint-all-never-scans-dpr-files` · `lint-rule-filter-leaks-other-rules` ·
`lint-config-not-discovered-beside-project` · `lint-scope-stale-files-and-project-members` ·
`lint-single-file-silently-omits-lint-all-rules` (found this session) ·
`cross-project-symbol-use-defeats-single-project-rules` · `whole-db-resolve-degrades-a-stale-index` ·
`lint-all-json-stdout-banner`

## Priority 4 -- indexer coverage gaps (a wrong answer, not a crash)

`procedural-types-not-indexed` · `type-alias-shapes-not-indexed` ·
`parenless-constructor-call-is-member-access` · `qualified-type-receiver-does-not-resolve` ·
`cycles-scope-and-local-var-refs` · `parser-var-named-dynamic` · `parse-error-shellshock-units`

## Priority 5 -- performance and robustness

`incremental-index-hangs-on-large-db` · `library-reindex-25x-slower-on-large-db` ·
`lint-all-project-wide-phase-dominates-runtime` · `index-runs-are-not-resumable` ·
`indexer-livelock-when-two-platforms-run-concurrently` · `index-all-win32-library-rebuild-aborts` ·
`schema-migration-not-atomic` (data integrity -- ranks above the rest of this group) ·
`codelens-cache-has-no-eviction`

## Priority 6 -- doc-engine correctness

`autodoc-caller-list-fabricates-callers-for-common-method-names` ·
`autodoc-returns-section-incomplete` · `docdrift-4-survive-a-converged-autodoc`
(**re-measure first** -- comment-derived facts were a plausible cause and are now
fixed) · `buildfor-defaulted-args-diverge-between-entry-points` (the same
defaults-diverge shape as the cap-parity bug already fixed) ·
`exception-cref-transitive-raise` · `yadf-share-review-marker-hash`

## Not defects -- features, designs, and inbound reports

`QUEUED-editor-integration-vscode-zed-delphilsp` (owner-filed, explicitly
*"NOT YET READ. Do not action this yet"* -- leave it alone) ·
`draglint-lsp-proxy-and-editor-integration` · `editor-integration-and-delphilsp-union` ·
`editor-native-extensions-and-build-orchestration` · `ide-lsp-ram-and-shim-todo` ·
`graph-viewer-open-source-pipe-contract` · `vscode-allow-codeaction-and-lsp-marker-filtering` ·
`exception-class-unit-and-generated-exception-types` · `rule-hardening-plan-2026-08-13` ·
`converter-editor-phase-g-engine-findings` · `loader2019-formcreate-inifile-leak` (a
finding in another repo's code, not a drag-lint defect)

---

## How to work this list

0. **READ THE GUARD FILE FIRST.** Session 20 closed THREE priority-1 notes with
   no code: one asked for a fixture that was already checked in, one made three
   headline claims that were all already false, one had been fixed in v0.82.
   Before rebuilding a repro, `grep` the defect's own vocabulary in
   `tests\` -- the guard, if it exists, was usually written by the session that
   fixed it and names the mechanism verbatim.
1. **Re-measure before coding.** Five notes have now closed on measurement
   alone. A count quoted in a note is a claim about a build that no longer
   exists, and **a note records the world as it was when WRITTEN** -- nothing
   walks back to amend it when the fix lands.
2. **Sample before believing a number** -- `group-E`'s own method, and it is why
   that note is trustworthy where a raw count is not.
3. **Every fix needs a positive control** in its guard test. The cheap fix for
   most rules above is to stop reporting, and a test that only checks "the false
   finding is gone" passes with the rule switched off.
4. **`lint <file>` is a silent subset of `lint-all`** -- whole-index rules are
   absent and it still prints `0 finding(s)`. Two tests went green for that reason.
5. Keep this index current when you retire a note; a stale index is the defect
   this pass was cleaning up.
