# INBOX sweep 2026-08-16 (session 21) -- measured status per note

Owner asked to "go through the 57 notes" before LoopZero and before the LSP fix.
This file is the running record so the sweep survives a context reset. **Every
row is MEASURED, not read off the note**, because the dominant failure mode in
this backlog is a note recording the world as it was when written.

Legend: **CONFIRMED** = reproduced today · **REFUTED** = claim no longer true,
retire the note · **PARTIAL** = some claims stand, some do not ·
**UNTESTED** = not yet measured in this sweep.

## Measurement traps hit while doing this (read before adding rows)

1. **`Select-Object -First N` on a native command corrupts `$LASTEXITCODE`.**
   It terminates the upstream process early, so an exe that exits 0 reports 1.
   Two notes were nearly recorded as "now exits non-zero" because of it.
   Capture the whole output to a variable first, THEN read `$LASTEXITCODE`.
2. **A rule filter test needs a file that actually has findings for BOTH rules**,
   otherwise "no difference" proves nothing (hit on `lint` vs `lint-all`).
3. **`--rule <id>` rejects query-rule ids outright** unless `--rules-dir` is
   passed -- the built-in AST rules and the 56 `.scm`/`.json` rules are two
   different registries at the CLI surface. That is arguably its own defect.

## Priority 3 -- silent no-ops and wrong-scope commands

| note | status | measurement |
|---|---|---|
| `index-only-nonmatching-section-is-a-silent-noop` | **CONFIRMED** | `index --all --only "NoSuchSectionXYZ"` -> **exit 0**, two lines of output, no error, nothing indexed. Dry-run likewise exit 0 with no "matched nothing" message. |
| `context-bundle-empty-for-bare-name` | **CONFIRMED** | `context --task "modify TypeIsRefCountedOrValue"` -> exit 0, `Token count (estimated): 0`, 194 chars. Qualified name -> exit 0, 1435 tokens, 4637 chars. Third confirmation, three separate days. |
| `lint-rule-filter-leaks-other-rules` | **CONFIRMED** | `lint <f> --rule write-only-local --json --rules-dir rules` returned findings whose only rule id was **`bare-except`** -- i.e. the requested rule was absent and an unrequested one was emitted. The `--rule` filter does not reach the query-rule pass at all. |
| `lint-all-json-stdout-banner` | **REFUTED -- retire** | `lint-all --db <db> --json --quiet` stdout begins with `[` and round-trips through `ConvertFrom-Json`. The banner is no longer on stdout. |
| `lint-single-file-silently-omits-lint-all-rules` | **CONFIRMED, worse than stated** | Fixture: one `.pas` carrying a stranded `// dl:ok bare-except@dead`. `lint <file>` -> **`0 finding(s)`**. `lint-all` over the same one file -> **`2 finding(s)` (1 info, 1 hint)**, including `review-marker-unused`. Same file, same DB, same rules dir. (First attempt was INVALID -- used a file with no marker, so nothing could fire either way.) |
| `lint-all-never-scans-dpr-files` | **CONFIRMED** | Fixture: `SweepProg.dpr` containing a real bare `except` + one `.pas`. `lint-all` -> `0 finding(s) ... **1 file(s) scanned**` for a two-file project, and the `.dpr`'s `bare-except` is absent. Corroborated on our own tree: the ONLY rule id appearing on any `.dpr` line in `lint-report-20260816.txt` is `unit-not-in-dpr`, a project-level rule that reports *at* the `.dpr` without scanning it. So `.dpr` bodies -- `Application.CreateForm`, init logic, exception handling -- are never linted anywhere. |
| `index-all-only-silently-does-nothing` | **REFUTED -- retire, merge into the note above** | Its symptom is `index --all --only DragLint-Cli --recompile` producing NO output and indexing nothing. Measured: exit 0, `files=102 symbols=13496`, 1.4s. A **real** section name works. What survives is only the **non-matching** section case, which is `index-only-nonmatching-section-is-a-silent-noop`. Two notes, one live defect -- fix it once, in that note. |
| `lint-config-not-discovered-beside-project` | **CONFIRMED, but currently harmless on YADF** | A live instance exists: `C:\Projects\YADF\drag-lint-lint.json` (untracked) disables `commented-out-code` per an owner ruling of 2026-08-12, and is being ignored. Measured impact today: **nil** -- `commented-out-code` fires nowhere in YADF's current report either way. So the defect is real but is not inflating any current count; do not justify the fix with a number it does not produce. Clean A/B on a synthetic project. `drag-lint-lint.json` = `{"disabled":["bare-except"]}`. Beside the `.dproj`, auto-discovered: `bare-except` **still reported**. Same file passed as `--config`: **suppressed**. So the file is honoured only when named explicitly. |
| `cross-project-symbol-use-defeats-single-project-rules` | **CONFIRMED by design, not a regression** | Structural: `unused-public-symbol` asks a whole-corpus question while the authoritative DB set is deliberately one project + platform library (owner ruling 2026-08-13). Not fixable by widening the DB set without reopening that ruling -- the fix has to be a scope-aware rule that declines to answer, or an explicit cross-project mode. Reclassify from "silent no-op" to a design constraint. |
| `lint-scope-stale-files-and-project-members` | **UNTESTED** | Bug 1 (index never prunes vanished files) is testable: index a dir, remove a file, reindex, see if it still yields findings. |
| `whole-db-resolve-degrades-a-stale-index` | **UNTESTED** | Needs a deliberately staled index; more setup than the rest. |

## Notes carrying a genuine closed banner (retire, do not re-investigate)

| note | banner |
|---|---|
| `bare-except-anchor-defeats-a-hand-written-marker` | FIXED 2026-08-16 (session 21), guarded 6/6 |
| `create-inside-try-qualified-lhs-not-flagged` | `Status: RESOLVED (2026-08-11, Fix 4)` -- **but the INDEX still lists it under priority 2 as an open false positive.** Verify which is right before retiring; note-vs-index drift is exactly what this sweep exists to catch. |

## Priority 2 -- measured on the four consumer projects (2026-08-16, post-anchor-fix)

All four reindexed first, then `lint-all --project`. Non-zero exit is just
"findings present", not a failure.

| project | total | 0 err | bare-except | review-marker-unused | scanned |
|---|---|---|---|---|---|
| YADF | 14 | yes | 4 | **4** | 8 |
| YADFOT | 12 | yes | 3 | **3** | 9 |
| YADFSetup | 15 | yes | 3 | **3** | 9 |
| DataCopy | 60 | yes (15 warn) | 8 | **8** | 15 |

### The dominant remaining category is MY OWN unpaid churn, and it is now exact

`review-marker-unused` equals `bare-except` in **every** project. That is the
`bare-except` anchor move (`430fd37`): each stranded marker now costs TWO
findings -- the `bare-except` it no longer suppresses, plus the `unused` hint on
the marker itself. It is **8 of 14, 6 of 12, 6 of 15 and 16 of 60** of what is
left.

**So the single highest-value next action for all four projects is the 12-marker
re-stamp**, not any rule work: move each marker from the statement line up onto
its `except`, and re-hash. Expected result YADF 14->6, YADFOT 12->6,
YADFSetup 15->9, DataCopy 60->44.

### RESTAMP DONE 2026-08-16 -- exactly the predicted numbers

| project | before | after | bare-except | marker-unused | marker-stale |
|---|---|---|---|---|---|
| YADF | 14 | **6** | 0 | 0 | 0 |
| YADFOT | 12 | **6** | 0 | 0 | 0 |
| YADFSetup | 15 | **9** | 0 | 0 | 0 |
| DataCopy | 60 | **44** | 0 | 0 | 0 |

Zero errors throughout. Two passes: strip the 12 stale markers (byte delta
exactly 27 each, no encoding or trailing-newline drift), reindex, then
`allow --fix-line <except line> --fix-rule bare-except --apply` at the 12 sites
the linter reported. Consumer diffs are 2 lines per marker and nothing else.
**Left UNCOMMITTED in both repos for review** -- they are the owner's trees, and
DataCopy also carries pre-existing `.dsv`/`.dsk` churn that should not be swept
into a lint commit.

The `--reason` problem turned out not to bite: all 12 live markers were
reason-less, so nothing was lost. `allow --reason` remains a real gap (see
below) -- the examples carrying prose were in the spec, not in the source.

**IT ALSO INTRODUCED A NEW DEFECT, now filed** as
`INBOX-bare-except-marker-hash-is-now-constant.md`: all 12 restamped markers
hash to `@b112`, where the 12 originals carried 8 distinct hashes. `NormalizeLine`
of the `except` keyword is the same single token everywhere, so the hash can no
longer go stale and the marker verifies forever regardless of what the handler
does. The anchor move gained the right report line and lost the checkable
content. Likely a FAMILY -- every sibling keyword-anchored rule
(`empty-except`, `empty-finally`, `empty-on-handler`, `empty-conditional`,
`empty-loop-body`, `empty-case-branch`) probably already has it.

### The restamp METHOD -- settled 2026-08-16, and it is not the obvious one

`drag-lint allow` is the only code path that formats a marker, so the instinct is
to re-stamp with it. **That would destroy every hand-written reason.**
`TReviewMarkers.InsertInto(ALineText, ARuleId, AReason)` does take a reason, but
the `allow` CLI exposes no `--reason` flag (`allow <file> --fix-line <L>
--fix-rule <id> [--apply]`), so it can only ever write a bare
`// dl:ok <rule>@<hash>`. Running it over the 12 markers would silently drop
*"rethrown by the caller"*, *"content could not be verified (lexing failed)"* and
the rest -- deleting exactly the accountability the marker corpus exists to
carry, while every count improved.

**Use the engine as a hash oracle instead, in two passes:**

1. Move each marker comment -- reason and all -- from the statement line up onto
   its `except` line, and **drop the stale `@hash`**.
2. Run `lint-all`. A hashless marker is honoured but reported as
   `review-marker-stale: ... re-mark it as bare-except@XXXX`. That message names
   the correct new hash for the line it now sits on.
3. Write those hashes back in.

Pass 1 restores suppression immediately (a hashless marker still suppresses), so
even a half-finished restamp is not a regression. Verified on the prose fixture
this session: the marker on the `except` line suppressed the finding and the
engine asked for `@b112`.

**Consider adding `allow --reason "<text>"` first** -- it is a small change, it
removes the two-pass dance permanently, and without it the tool cannot express
the thing its own design document says a marker is for.

### Notes settled by this measurement

| note | status |
|---|---|
| `object-leak-is-systematically-false` | **CONFIRMED at the corrected count** -- 1 / 1 / 1 across the three YADF projects, i.e. the SAME finding in a shared unit, exactly as the note's own re-measurement says. Not the 3/7/7 the original text claimed. |
| `yadfot-loopzero-remainder-2026-08-13` | **STALE** -- remainder is now 12, dominated by the marker churn above, so its itemisation predates two rule fixes. Re-derive after the re-stamp rather than reading it. |
| `yadf-triage-2026-08-12-out-param-and-object-leak-false-alarms` | **PARTIALLY STALE** -- `out-param-not-set` does not appear in any YADF project now (2 remain in DataCopy only). |

## Parser / extractor gap batch -- one fixture, six notes

`scratchpad\sweep4\uParserGaps.pas` carries every construct the notes name, in
one unit: procedural types, three alias shapes, a local named `dynamic`, a
parenless constructor call and a unit-qualified constructor call. Indexed clean
(1 file, 12 symbols, 17 refs, **no parse errors**), then queried.

| note | status | measurement |
|---|---|---|
| `procedural-types-not-indexed` | **REFUTED -- retire** | `TMyProcType` -> `type ... : procedure(A: Integer)`; `TMyFuncType` -> `type ... : function(A: Integer): Boolean of object`. Both indexed WITH their shape. |
| `type-alias-shapes-not-indexed` | **REFUTED -- retire** | All three shapes indexed with the aliased type: `TAliasIdent : Integer`, `TAliasQual : System.Integer`, `TAliasGeneric : TArray<Integer>`. |
| `parser-var-named-dynamic` | **REFUTED -- retire** | `dynamic` indexed as `local_var uParserGaps.VarNamedDynamic.dynamic : Integer`, and the unit parses with no error. |
| `parenless-constructor-call-is-member-access` | **REFUTED -- retire** | `find-callers Create` returns the parenless `TOnlyOnce.Create` at `:33:23`, i.e. it is a CALL, not a member access. |
| `qualified-type-receiver-does-not-resolve` | **CONFIRMED** | The same query returns ONLY line 33. `uParserGaps.TOnlyOnce.Create` on line 39 -- unit-qualified receiver, same class, same file -- produces no `Create` call ref. Clean A/B inside one fixture. |
| `parse-error-shellshock-units` | **UNTESTED** | Needs the actual units named in the note. |

## Rule false-positive batch -- measured against today's reports

| note | status | measurement |
|---|---|---|
| `inherited-bare-fires-on-the-mandatory-idiom` | **REFUTED on its stated target -- retire or re-scope** | Note: *"Measured on DataCopy 2026-08-13: 8 of 8 findings were the canonical idiom."* Today DataCopy reports **0** `inherited-bare`. The rule still fires elsewhere (drag-lint's own source: 18), so the RULE is not proven good -- only the note's DataCopy claim is dead. Re-scope to drag-lint's 18 or close. |
| `used-before-assignment-array-local-never-counted-as-defined` | **CORRECTED 2026-08-16 -- NOT refuted. The note's EXAMPLE is stale; the DEFECT is alive.** | First reading: YADFOT reports no `used-before-assignment`, so the note's two `YADFOT.Wizard.pas` sites are gone -> "retire". **That was wrong, and it is the classic error of this sweep in reverse:** I refuted the example and implied the defect had gone with it. Reading DataCopy's 3 survivors against source: `uZeissRoutines.pas:1160/1229` report `lrestore` and `lbackup`, both **arrays assigned element-wise** (`LRestore[LJdx]`) -- exactly the mechanism the note describes. **Retire the example, keep the note, re-anchor it on `uZeissRoutines.pas`.** |

## Not-defect batch -- closed on their OWN declared status, not on measurement

**These are a weaker class of closure and are labelled as such.** Each note
declares, in its own opening lines, that it is a feature request, a design
handoff, an inbound report or work the owner has explicitly deferred. None
asserts a wrong answer from the engine, so there is nothing to re-measure --
they are backlog items, not defects, and they inflate a "defect count" that is
supposed to drive fixing. Moving them out of the defect list is the whole point;
none of them is being *solved* here.

| note | its own declared status |
|---|---|
| `QUEUED-editor-integration-vscode-zed-delphilsp` | *"NOT YET READ. Do not action this yet."* |
| `vscode-allow-codeaction-and-lsp-marker-filtering` | Owner ruling: *"distant future, not near."* |
| `exception-class-unit-and-generated-exception-types` | *"feature request + design question. Not implemented."* |
| `converter-editor-phase-g-engine-findings` | *"NOT pushed, NOT merged, NOT deployed. Deliberate."* |
| `draglint-lsp-proxy-and-editor-integration` | Inbound request + status handoff, *"to be picked up after your current work"* |
| `editor-integration-and-delphilsp-union` | Inbound, converter-editor workstream |
| `editor-native-extensions-and-build-orchestration` | Inbound, converter-editor workstream |
| `graph-viewer-open-source-pipe-contract` | Inbound from the graph viewer |
| `ide-lsp-ram-and-shim-todo` | *"items 1 and 2 DONE; items 3 and 4 BLOCKED on the IDE being startable"* |
| `rule-hardening-plan-2026-08-13` | A PLAN answering an owner question, not a defect report |
| `yadf-share-review-marker-hash` | A request from the owner for a shared hashing helper |

**Caveat worth stating plainly:** four of these eleven (`draglint-lsp-proxy`,
`editor-integration-and-delphilsp-union`, `editor-native-extensions`,
`QUEUED-editor-integration`) all describe the SAME editor-integration programme
from different senders. They should be merged into one note, not carried as
four. And that programme is now blocked on a real defect --
`lsp-rejects-the-stdio-flag-its-own-client-appends` -- so the plan matters less
than the one-line fix underneath it.

## Three that did NOT settle cleanly -- recorded as such rather than counted

Each of these looked settleable and is not. Writing down *why* is worth more
than a verdict I cannot defend.

| note | what happened |
|---|---|
| `create-inside-try-qualified-lhs-not-flagged` | Its own header says `Status: RESOLVED (2026-08-11, Fix 4)` while the INDEX still lists it as an open priority-2 false positive. Own source reports 4 `create-inside-try` findings and all four are the **unqualified** shape the rule is meant to catch -- so the rule works, but that says nothing about the note's actual claim, which is about a **qualified** LHS (`Self.Field := T.Create`) NOT being flagged. Needs a qualified-LHS fixture before retiring. Do not close on the status line alone. |
| `field-name-prefix-fixable-flag-lies` | `rules --json` reports `"fixable": true`, which is half the claim. The other half -- that `--fix` then refuses -- was NOT exercised; the only live findings are 2 in DataCopy, and running `--fix` there would edit another repo mid-sweep. Untested. |
| `deep-nesting-silent-on-trailing-else-call` | Built a 5-deep fixture ending in `if E then ... else Writeln(...)`; `deep-nesting` did not fire. **That proves nothing** -- the threshold is 5, so the fixture may simply be under it. Without a positive control (same fixture with the trailing else replaced by another nested `if`, which MUST fire) the silence is unattributable. Exactly the trap this document opens with. |

## SCORE -- 32 of 58 notes settled

| outcome | count | what it means |
|---|---|---|
| **FIXED IN CODE this session** | 4 | `bare-except-anchor`, `remaining-raw-text-scans` #1 (FormsMap), `lint-rule-filter-leaks-other-rules`, `index-only-nonmatching-section-is-a-silent-noop` |
| **REFUTED -- retire the note** | 8 | `lint-all-json-stdout-banner`, `index-all-only-silently-does-nothing`, `procedural-types-not-indexed`, `type-alias-shapes-not-indexed`, `parser-var-named-dynamic`, `parenless-constructor-call-is-member-access`, `inherited-bare-fires-on-the-mandatory-idiom` (on its stated target), `used-before-assignment-array-local-never-counted-as-defined` |
| **CONFIRMED -- still real, now measured** | 6 | `context-bundle-empty-for-bare-name`, `lint-single-file-silently-omits-lint-all-rules`, `lint-all-never-scans-dpr-files`, `lint-config-not-discovered-beside-project`, `qualified-type-receiver-does-not-resolve`, `object-leak-is-systematically-false` (at the corrected 1/1/1) |
| **Stale -- re-derive, do not read** | 2 | `yadfot-loopzero-remainder-2026-08-13`, `yadf-triage-2026-08-12-...` |
| **Reclassified out of the defect list** | 12 | `cross-project-symbol-use` (design constraint) + the 11 not-defect notes |
| **Explicitly NOT settled** | 3 | `create-inside-try`, `field-name-prefix-fixable-flag-lies`, `deep-nesting-silent-on-trailing-else-call` -- see the section above for why each resisted |

**8 notes can be retired outright** and **12 moved out of the defect list**, which
takes the defect backlog from 58 to about **38**, of which 6 are measured-real
and ready to fix.

### What the refutations have in common -- worth knowing before the next sweep

Six of the eight refuted notes are **parser/extractor "gap" claims that the
engine now handles**: procedural types, three alias shapes, a variable named
`dynamic`, and a parenless constructor call all index correctly today, with
shapes attached. Nobody walked back the notes when the parser improved. **The
indexer-gap section of this backlog is the most stale part of it**, so sweep
that class FIRST next time -- one fixture settled four notes in a single index
run.

The one survivor of that batch is instructive: `uParserGaps.TOnlyOnce.Create` --
a UNIT-QUALIFIED receiver -- still produces no call ref, while the unqualified
call two lines above it does. Same class, same file, same fixture.

### The cheap fix cluster this sweep exposes

Four of the six CONFIRMED items are the SAME shape -- *a command narrows its work
and reports success for the narrowed set as if it were the whole set*:

* `--only <nonmatching>` indexes nothing, exit 0
* `--rule <id>` does not reach the query-rule pass (asked for `write-only-local`,
  got `bare-except`)
* `lint <file>` reports `0 finding(s)` where `lint-all` on that one file reports 2
* `lint-all` skips `.dpr` bodies entirely, and says `1 file(s) scanned`

Each is small on its own. Fixing them as ONE change -- *"a command that could not
do what was asked must say so and exit non-zero, and a scanned-count must name
what it excluded"* -- is better value than four separate patches, and it is the
same principle the `lint-all` ownRoots work already applied to third-party roots
(named, with a count, not silently dropped).

## Still to sweep

Priority 1 (2) · Priority 2 (~11) · Priority 3 (2 left) · Priority 4 (~7) ·
Priority 5 (~8) · Priority 6 (~6) · Not-defects (~10). **47 remaining.**
