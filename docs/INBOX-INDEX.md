# INBOX index -- 57 open notes (was 59); 4 retired + 2 filed on 2026-08-16

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

> **2026-08-16: four notes RETIRED to `INBOX-Done/` (files moved, renames staged).**
> `group-E-dataflow-rules-are-majority-false` (all three sections fixed;
> `double-free` 42 -> 0), `shared-unit-empty-render-deletes-block` (already
> guarded), `audit-store-backed-fix-paths-for-stale-positions` (~80% stale, the
> residual measured NOT reachable), `returns-type-baseline-destroys-malformed-blocks`
> (misclassified -- a reverted design record, its open precondition now proven).
> One note FILED: `context-bundle-empty-for-bare-name`.
> **Priority 1 is now TWO items.**
>
> **2026-08-16 (session 21).** Priority 1 **cleared of its original two**, and one
> new item filed into it.
> * CLOSED: `remaining-raw-text-scans-read-comments-as-code` #1 (FormsMap comment
>   scrub) -- its stated harm was wrong; see the note.
> * CLOSED: `bare-except-anchor-defeats-a-hand-written-marker` -- fix (A), and the
>   "is it a family?" question is answered NO: every sibling already anchored on
>   its own keyword. **Consumer churn measured but deliberately NOT paid**: 12
>   recorded markers in DataCopy (8) and YADF (4) now need a move + re-stamp.
> * FILED: `lsp-rejects-the-stdio-flag-its-own-client-appends` (owner-reported
>   live, owner deferred the fix).
> * FILED: `rule-edits-are-inert-until-hand-copied-to-three-deploy-dirs` -- found
>   the hard way during the bare-except fix.
>
> **Priority 1 is TWO items**, both new.

## Priority 1 -- known-wrong output, worth fixing next

Two items, both filed 2026-08-16. The four originals were retired earlier the
same day; the last two were closed by the work described in the banner above.

| note | why it ranks here |
|---|---|
| `lsp-rejects-the-stdio-flag-its-own-client-appends` | **The VS Code language client has never once completed a start** -- and nothing in `git log -S "'--stdio'"` says otherwise. `vscode-languageclient` appends `--stdio` because `extension.js` declares `transport: TransportKind.stdio`; `ParseArgs`' strict catch-all (`CLI.pas:1075`) kills the process before the `lsp` command is dispatched. `587546e` did not cause this -- it *uncovered* it by moving the fatal off stdout, so a two-week-old outage is only readable today. Two candidate fixes in the note (accept-and-ignore the flag; drop the transport declaration) and a warning that the guard must drive a real handshake, not just assert exit 0. Check the sibling flags a stock client may append (`--clientProcessId`, `--pipe=`, `--socket=`) against the same catch-all. |
| `rule-edits-are-inert-until-hand-copied-to-three-deploy-dirs` | **A silent no-op in the build.** `rules\` is the source of truth but the exe reads `<exe-dir>\rules`, and no build script stages it -- so a rule edit is inert and the suite passes, reporting the OLD behaviour as correct. This has already happened unnoticed: the Release and Win32 corpora are 35 and 104 files behind. `run_exe_freshness` does not cover it. Fix is a `copy /Y` beside the existing tree-sitter staging, plus a content-hash drift assertion. |

**Closed the same day** (kept one line each so the trail survives, full detail in
the notes): ~~`remaining-raw-text-scans-read-comments-as-code`~~ #1 FormsMap --
the real harm was a wrong CAPTION on a real edge, not a wrong row; and
~~`bare-except-anchor-defeats-a-hand-written-marker`~~ -- fix (A), no family
existed, consumer churn (DataCopy 8 + YADF 4 markers) measured and left as its
own task.

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
