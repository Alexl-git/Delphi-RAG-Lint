# CONVERTER backlog -- delayed tasks (do not lose; do not read every session)

Created 2026-10-16; **rewritten 2026-10-19** from the re-triage proposal
`docs\handoffs\CONVERTER-BACKLOG-proposed-2026-10-19.md` (full measurements, file:line
evidence and the engine JSON shapes live THERE -- open it when working an item) with the
owner's 2026-10-19 answers applied. A handoff LINKS to this file instead of repeating it.
Open it when picking the next converter job, not at session start.

Sizes S/M/L; model = haiku / sonnet / session (owner rule 2a). **Measure against the tree
before working on an item.**

## State 2026-10-28 (convrules-editor-31) -- adds to the 10-26 state below

* **SHIPPED 10-27/28 (ENGINE-merged to local main):** conv/regreview -> 4582c280 (15 registry entries
  re-verified, curate busy-guard); conv/chainform -> d837c296 (second Rule chains request, GateBusy);
  conv/libdesc + conv/startup2 -> 84f17966 (class lists + library load behind the progress window).
  CHAIN-1 T1-T6 and D2 split landed earlier (see 10-27 handoffs). Smoke-test group for 1.37.0
  (docs\SMOKE-TEST-1.37.0.html, Converter group, 16 steps) written 10-28.
* **READY conv/dlggap bb1593cc** (gateleak + dlggap + gui-lock token) sent to ENGINE 2026-10-28. A/B vs a
  main 84f17966 build (C:\TEMP\claude\lanes\1027conv\agent-mainab\ab.txt): unit-picker 3/2 on BOTH,
  toolbar 41/0 on both, save-encoding A 8/5 vs B 12/3, glyph-link A 5 vs B 7 fails -> not a dlggap
  regression.
* **DRVLIB (new, M, next):** the GUI drivers fail on MAIN since libdesc/startup2: an unexpected
  progress window or "Add unit (#use)" picker is up (unit-picker picker.opens, save-encoding
  save.nonascii.asks, glyph-link automatch/saveas). First re-run on an IDLE machine (10-28 runs were at
  100% CPU from engine lanes), then fix the drivers' waits. Also file-menu cleanup crash line 329
  (temp dir locked; same wait-for-exit fix as 8c74d790), and the convert-encoding 15-min TIMEOUT.
* **OWNER RULINGS 2026-10-28 (via ENGINE):**
  * **migtypo HOLD.** Source of the name: vendor `FireDAC_Migrate_BDE.rules:36` spells
    `TDBScreenCursors`; today's Data.DB has only `TDBScreenCursor` (dcrDefault, dcrHourGlass,
    dcrSQLWait, dcrOther). The original source is trusted as once compilable; check against an
    old-platform index (Q2, owner) before changing the vendor spelling.
  * **MIGTGT (new, M):** a #migrate / rename whose TARGET does not resolve in the platform library DB
    or the project DB -> warning mark, rename skipped. Type names rename too, not only members.
  * **ENUMMAP (new, M):** old-vs-new enum member map by the name after the lowercase prefix, never by
    ordinal (dcrX -> gcrX; gcrNone is ordinal 0); explicit #mapping when matching fails; warn on each
    unmatched member (dcrOther) the .pas code uses. Needs the old platform indexed (Q2).
  * **D5 inherited .dfm:** convert ROOT first down the chain. Verified on DMTEST: the child .pas
    redeclares nothing; the child .dfm also keeps property-less container entries, order-only
    entries `inherited X: TField [n]` (44 of 52 in dmDrawData.dfm), and collection properties
    (ParamData) streamed WHOLE. Engine side (type rename via #migrate, `inherited ... [n]` retype,
    collection rules in the child): INBOX-converter-to-engine-migrate-type-and-inherited-headers.md.
  * **C8CHAIN (new, M) -- OWNER RULING Q5 2026-10-28, replaces "never blocking":** build an
    inheritance DEPENDENCY GRAPH over the run's units and walk each chain to the very original
    (A inherits B inherits C: convert C, B, A). No inherited unit converts before its ancestor is
    converted. Per ancestor: in the same batch -> order it first; not in the batch -> decide
    "already converted?" by searching the ancestor for the rule books' From types; still there ->
    offer to convert the ancestor first and insert it into the batch ahead (root first); none
    left -> treat as converted. Today `AncestorChain` offers only ancestors whose .dfm declares or
    re-opens one of the descendant's instances (an intermediate class that re-opens none is
    skipped), and E7 is a warning with "anyway": both change. Engine already skips a child whose
    ancestor is unconverted (`ancestor_state` "unconverted").
  * **Q2 (owner):** Delphi 12 is on this machine (may not run); Delphi 5 is on another VM. Indexing
    needs only the library SOURCES, not a working IDE: copy D5's `Source\` tree here and index it as
    a separate library DB for the old-vs-new comparison (MIGTGT / ENUMMAP / migtypo).
* **conv/dlggap MERGED** by ENGINE (9269c588), owner pushed main 97a99bc4.
* **DOCSCHECK-C3 (S, after the reboot):** featuregen 1.38 check C3 flags the rule-chains wiki page
  ("does not yet warn ... planned as CHAIN-2" on a shipped entry; waived as triage). Reword it, or
  split CHAIN-2 into its own planned entry. Details: C:\TEMP\claude\lanes\gaps\agent-ki-docscheck\REPORT.md.
* **NEW backlog (from the dlggap lane):**
  * gui-lock `-Acquire` timeout is ignored by the runners (they loop until exit 0).
  * drive-book-depth uses fixed sleeps; replace them with WaitIdle.
  * `HarvestFormTypes` unused locals (lint).
  * the native MessageBox loop is not gated (ConvRulesEditor.dpr:313): a posted command under a
    MessageBox is not refused by NativeLoopVerdict (it only gates RunNativeDialog).
  * Unregistered features (featuregen): Mappings, Glyph, Examine, Unit Rules tab, inherited offer,
    scope validation, D2 split.
  * CHAIN-1 E2: the engine matches PAS names case-INsensitively by bare name, while the editor
    compares exactly. Check, and align the editor.

## State 2026-10-26 (convrules-editor-31) -- historical

* Deep review R1-R7, the test-kit gaps, ENC-a, the re-pin (1.35.0-alpha-20261025-125433) and FG-M are
  CLOSED: lane A 985c3447 (R1, R4 = cancel/stop restores partly reached units, R5), lane B 197fca60 (R2
  bounded startup probe; R7 ruling: engine pipes are CP_ACP), lane C 54e2c81a (R6), lane E 9e0ad239,
  FG-M 8234fe33. #migrate slice 1 merged 3b96f1ec; main pushed e98a0125.
* Shared encoding contract (owner via ENGINE + CONVERTER, 2026-10-26): (a) engine pipe output
  `--output-encoding ascii|utf8|utf16`, default ascii, reversible escapes (ENGINE lane OUTENC);
  (b) written .pas/.dfm level = user-specified or inferred from the file; when rules need a higher
  level and lossless down-convert is impossible: warn, list each place (book, line:col, U+XXXX, rule,
  target unit), ask up-convert vs change rules. Editor side incl. the lone-surrogate no-op RaiseTo,
  C-1 verify and B2 RefusalHint delete: ENGINE's lane CONV (wt conv-1026); CONVERTER reviews it.
* D2 DONE on conv/d2-split (2026-10-27; split books + Q4b merged to main only after review): BDE + Data.DB books, guard `run_convert_book_split.ps1` green on pin 1.36.0-alpha-20261027-142316. Q6 DONE on conv/q6 (2026-10-27): Preflight note via BookOrderNote when DataDB-to-FireDAC.rules is listed before BDE-to-FireDAC.rules (warning only). Was open: D2 owner decision (BDE tail: 15 of 43 `#migrate` lines are member form); L1
  fix/conv-apply-read-encoding (Convert.Apply ANSI reads, to ENGINE for merge); L2 #migrate D5 + D6-B;
  L4 VARINSP 5 with-engine fails; non-ANSI identifiers in the index = ENGINE EXTRACT, 1.36.0;
  re-pin + baseline after ENGINE's next deploy.
* 2026-10-26 later: L4 VARINSP fixture merged (with-engine 2956/0/0); L1 merged by ENGINE 891543ae (ships
  1.35.1). **Owed at the 1.36.0 re-pin:** the engine's text output becomes ascii with `\uXXXX` escapes by
  default -- the editor (Engine.pas pipe readers) must pass `--output-encoding utf8` (probe the
  capability) or decode the escapes; add a model test with a non-ASCII name before re-pinning.
* 2026-10-26: L2 #migrate D5 + D6-B merged; ENGINE lane CONV (pre-run encoding question) reviewed +
  merged 45d84771. Its follow-ups (CONVERTER, review a1514a9a, all minor):
  * **ENC-N1** DONE (lane N13, branch conv/n13-bookplaces): `EncodingPlacesFor` + `FromTypeApplier`.
    A #convert block's own lines (header, #link, #default, #ignore, #remove, #migrate, #apply, #tag,
    #warn, #check-ref) count only for a unit whose text .dfm headers (`ListDfmInstances`), .pas
    identifiers or C8 verdicts (`InheritanceOf`) name its From type; book-scope lines, unit
    directives, #mapping, #note, pcre/unknown lines always count. DECISION (units without a .dfm):
    they get the blocks their .pas / C8 analysis names (runtime creators, code uses); a binary or
    unreadable .dfm, or an unreadable .pas, = every block applies (needless question, never a missed one).
  * **ENC-N2** DONE (lane N2, 34663029): `TPreRunPlan.Notes` + `PlaceNoteText`; Yes keeps every place
    as note rows, Cancel adds none (even after an earlier Yes).
  * **ENC-N3** DONE (lane N13): `RuleExcerpt` windows 80 chars around the column, '...' on a cut
    side, never splits a surrogate pair.
  * **ENC-N4** DONE (lane N4, 75fc2309): `BatchSplit` batches the unraised units, raised ones run
    per-unit; `ContinuedStep`/`RunMixedParts` keep one total and continued steps; `PerUnitPartMayStart`
    skips the per-unit part after a batch stop/cancel.
* 2026-10-26 (night) ready-wave CLOSED: W0 re-pin 1.35.1-alpha-20261026-134311 (SHA256 92E4655A...),
  HLP 677ba1a3, N13 f5c01c3c, N2 34663029, N4 75fc2309, DRV fa80b602 (driver audit: WaitCls 0-timeout,
  stale status, WaitIdle before Convert, convert-encoding lost first copy). main: 2950/0/20 no engine,
  3068/0/0 with the pin; lint 0 on the wave's changed lines. Follow-ups:
  * **DONE (conv/namedrop, 2026-10-26): name-drop workaround removed** -- `ListCodeRefs` (`CODE_REFS_SQL`) now reads FIELD-resolved refs only; the unresolved-ref read and its local/param name-drop are gone; tests `coderefs.live.fields.only` / `.library.member.dropped`. Was: ENGINE (2026-10-26) says 1.35.1 already binds cross-unit
    implicit-Self reads/writes of inherited fields (7 shapes; guard lands with 1.36.0). Limit: members
    of a LIBRARY ancestor (TForm.Tag) still need the library store attached.
  * **DONE (conv/drvfix 1e42235c, merged ab1058a1, 2026-10-27): DRV-1** copy retry ported. Was: drive-save-encoding `save.nonascii.asks` read '' from the warning (1 of 3 runs): same
    lost-first-copy race DRV fixed in convert-encoding -- port the copy retry.
  * **PARTLY DONE (conv/drvfix adbd042c): DRV-2** -- the engine call is now held (C8 child suspended), so the
    progress-window precondition is deterministic; `n1.lost.click.reported` still flaky on warm runs ->
    lane drv2b (conv/drv2b, suspected LostClickTimerFire vs AddSources status race). Was: drive-convert-tab N1/N7 precondition "progress window never appeared" (2 of 3 runs):
    the engine call is too fast to catch; make the fixture slower or hold the window deterministically.
  * **DONE (conv/drv3 4fdcf11d, 2026-10-27): DRV-3** driver defects, both 3x green. Side effect found: open
    status lost its line/rule counts since cd8cdc07 -> owner: counts must show (lane opencounts). Was: FAIL on main before the wave: owning-open 3/6 (`owning.row.found` picks the Work-list
    filter list), glyph-link 22/1 (`glyph.open.good` no "Loaded" in 30 s).
  * **DONE (conv/drvfix 1e42235c, merged ab1058a1): DRV-4** tracked `tests\gui\gui-lock.ps1` with a
    heartbeat. Was: gui.lock needs a heartbeat: a 30-min takeover broke a 38-min run (two editors).
  * **DONE (conv/drvfix 1e42235c, merged ab1058a1): DRV-5** busy query added; all four drivers now ask
    `ConvRulesEditor.Busy` (re-measured 2026-10-27). Was: glyph-link, inherited-offer, qualify-fix,
    work-list did not ask the editor's busy message.
  * **DONE (conv/n13 54cda2b1, merged c4728fd8): N4-1** drive-convert-encoding `mixed.*` case (3 units, one
    raised) + `-ProofNoMixed` RED. Was: no GUI case for a mixed raise.
  * **DONE (conv/n13 3c39d49d, merged c4728fd8): N13-1** `EncodingPlacesFor` splits via `BookLines` (CRLF,
    LF, lone CR); tests `n13.split.*`. Still open: `RuleLinesOnly` splits on LF only (other callers).
  * **DONE (conv/opencounts d88412a4, merged 274e5e73): opencounts** File > Open status shows
    "Loaded <book> (<enc>): N line(s), N rule(s)" again (`OpenedStatusText`, model-tested).
* 2026-10-27 small-items wave (merged to main d67dd619; model 2975/0/20 no engine):
  * **DONE rlines** (f3ca6f07): `RuleLinesOnly` splits via `BookLines` (CRLF, LF, lone CR); output is
    LF-joined, no trailing break (one caller re-splits); tests `rlines.*`.
  * **DONE ndgate** (0892f00d, 90e53ab6): engine < 1.35.1 (or unreadable version) -> `ListCodeRefs`
    fails with `FieldRefsGateNote` text instead of an empty answer; tests `ndgate.*`. No capability
    exists for inherited-field binding, so the gate is the version.
  * **DONE Q08** (7d8bfc66): `qualify.apply.retarget.requires.applied`; the mutant also dies on the
    older `.skips.refused`, so Q08 was partly stale.
  * **DONE ewait** (b7bc2fc9): `wait.reload.no.window` flake was a DRIVER defect (cached proptree
    still opens DBs; slow-machine excuse timed `--version`). Excuse now times the real child; a
    window before 350 ms always fails. RED with SHOW_DELAY_MS=0. **Owed:** a 16/16 run on an
    unlocked desktop (`save.key.*` cannot send Ctrl+S while locked; lane skiplock makes them SKIP).
  * **CLOSED by re-check:** B2 `RefusalHint` is gone from the index; B10 `inherited_code_unconverted`
    capability is wired (Engine.pas CAPABILITY_INHERITED_CODE_UNCONVERTED).
  * **migtypo** on conv/d2-split (34a9d25d): `#migrate TDBScreenCursors` -> `TDBScreenCursor`
    (Data.DB enum, library-Win32 + Data.DB.pas:3190) in DataDB-to-FireDAC.rules; rides with the D2
    merge (book-split guard will flag that one-line difference). Open question: does a book-wide
    `#migrate` rename a TYPE name, or members only? `convrules\vendor\FireDAC_Migrate_BDE.rules:36`
    keeps the typo (vendor copy, left as is).
* 2026-10-26 (night) OWNER: main pushed (1b7a70d3..7c7746b4, 81 commits). Two owner inputs:
  * **D2 -> SPLIT (owner option, preferred)**: split BDE-to-FireDAC.rules into a BDE book and a
    "Book-2" with every rule unrelated to the BDE conversion. First step: classify the 43 book-wide
    `#migrate` lines + the blocks (BDE vs not); BDE book keeps its book-wide lines ABOVE the first
    `#convert` header (rule A; check the engine's scoping first). No trailer special case needed.
  * **CHAIN-1 spec + plan DONE (8917176d, 6 tasks; owner Q1-Q8 open) / D2 plan DONE (2c53947e; owner Q1-Q7 open)** --
    docs\superpowers\specs\2026-10-27-converter-chain1-design.md, plans\2026-10-27-converter-chain1.md, plans\2026-10-27-converter-d2-book-split.md.
  * **CHAIN-1 (new, M, needs ENGINE answer first)**: rules A->B and B->C in one book. Owner: warn and
    offer an A->C rule, or offer to move them to separate books run one after the other. FIRST ask
    ENGINE whether convert-apply applies a book in ONE pass (each node matched against the original
    type, so B->C never sees A's output) or sequentially (A->B->C chains); the DSL doc does not say.
    Then: a pure `RuleChains` decision (From/To graph over #convert headers + unit swaps, cycle
    A->B, B->A = error), surfaced in ValidateScope on Save with the two quick fixes.

## State 2026-10-23 (autonomous run 20261023-1100-converter3d) -- historical

* DONE on local main: A1 re-pin (1.33.0, 10-20), A2/A3 merges (faffc407, d7a289ba),
  C-1 (ENGINE castlib 8d0e2e3b + test 06439a4e), E2 (3200fc0e), B2 (c8e33da7, caller removed
  too), B9 (Model part was in faffc407; BDE book lines 8af2f8a5), N3 (e17f455c, 9ff9b242:
  recapture.ps1 + fixtures on 1.33.0), N2 / D4 / D6 (already in faffc407; verified, N2 mutant
  RED/GREEN), item F (registry review, 20ffb523). Item F's URL form is
  `/help/dl/features/<id>/`, not `/help/<id>/` (www-40, 2026-10-23).
* A4 #migrate: spec + plan written 2026-10-23 (`docs\superpowers\specs|plans\2026-10-23-converter-migrate-slice1*`,
  gitignored). OWNER DECIDED 2026-10-24: all recommendations, with D0 = B (build after ENGINE's
  final deploy + re-parse + re-pin, dropping the G4/G7/G8/G9 workarounds); D5 and D6-B as
  follow-ups. Spec section 12a records it. NEXT after the re-pin.
  Engine gaps G8/G9/G10 filed `docs\INBOX-2026-10-23-converter-to-engine-migrate-gaps.md`
  (ENGINE lane e3d/migrate-gaps).
* DONE later the same day: N1 (9941b39e), D2 (ecc90bfd), B10 (45c149e1), Qualify-all driver
  (dea6c6f4), featuregen site fields (02b11037), **B4 batch mode** (2b713460..eec26734; model
  2571/5/0, drive-convert-batch 22/0). Pin 1.33.0-alpha-20261021-122057 ADOPTED (2460/5, 14
  drivers; pin editor = main 1dc238da build).
* Owed after ENGINE's final deploy (end of day 3, owner rule: no approval-needing step mid-run):
  `featuregen verify --id convert-apply` / `convert-scaffold --by CONVERTER`; re-pin + baseline.
* DONE in wave 3: **N9** 6b21a559 (drive-convert-tab 3b fails cleanly without the progress
  window); **N8** e52df7bb (converted-ancestor code use with mapped pas_uses is not "left");
  **N7 + N11** a246e716 (`ConvRules.InputGate` on Application.OnMessage refuses main-form
  clicks/commands while busy, reports the first, never queues; `ConvRulesEditor.Busy` message for
  drivers' WaitIdle; drive-convert-tab 32/0 x6, batch-driver Add retry removed; model 2615/5/0).
* Open todos from this run:
  * DONE: **N7 leftover** 72ec46ed (drive-engine-wait 9 -> 16: File|Save under the progress
    window refused + reported; the Ctrl+S check cannot go red -- regression guard only);
    B4 test-dpr lint debt 328f8569 (44 -> 0 on B4 lines); **N10** in the run's scratch
    `gui-lock.ps1` (stale = over 60 min, or over 10 min with no ConvRulesEditor running;
    positive + negative control passed) -- the lock is scratch, not tracked.
  * DONE 2026-10-24: **FG-M + FG-N** merged 8234fe33 after ENGINE's 1.34.0-alpha deploy
    (0b308ab9); featuregen 244/0, registry + docs-sync guards PASS; convert-apply /
    convert-scaffold verified by CONVERTER on 1.34.0-alpha. Also helpOrder tiebreak 2c912ce4 and
    the frozen-banner test 65550658.
  * DONE 411c1ca7: FG-O + FG-P (featuregen 245/0).
* **Deep review 2026-10-25** (Fable, read-only; full text `docs\INBOX-2026-10-25-converter-deep-review-editor.md`):
  * **R1** (M) batch exit 6 marks every chunk unit "config error, nothing written" and drops its
    backups (ConvertRunner.pas:1625-1639) -- safe only on today's engine internals. ENGINE
    2026-10-25: correct today; ENGINE is making it CONTRACT (castlib parsed once before the unit
    loop; top-level exit 6 = no unit touched, no backups) -- MERGED 675006b6 (guard
    run_apply_batch_gaps CL6a-d, CONVERSION-RULES.md after line 879), ships with the NEXT engine
    deploy, not 1.34.0-alpha. Remaining
    editor fix: refused entries in an exit-6 chunk are relabelled csConfigError.
  * **R2** (M) a failed/timed-out `info --json` reads as "no capabilities", cached for the session
    (ConvertTab.pas:669-683, Engine.pas:1659-1667) -- features switch off naming the wrong cause.
  * **R3** (M) Save writes TEncoding.ASCII: non-ASCII in a rule book silently becomes '?'
    (MainForm.pas:7696, WorkingSet.pas:546, Engine.pas:3269); validation passes on the '?'.
    CLOSED 2026-10-26 (encoding Tasks 2-4): every user-file write goes through WriteTextAtLevel / EncodeText
    after PreSaveDecision; the only TEncoding.ASCII write left is the editor's own skip list (MainForm).
  * **R4** (M) batch cancel between chunks leaves units with book A but not B, reported "not
    reached" (ConvertRunner.pas:1737-1742) -- breaks the per-unit "never some books" invariant.
  * **R5** (L) the batch per-entry path never reads the 1.33 per-entry `exit_code`
    (ConvertRunner.pas:1667-1687). ENGINE 2026-10-25: per entry = THAT unit's code (0 ok, 1 refused
    incl. unindexed, 2 write failure/rollback, 6 config/castlib); root `exit_code` = the worst
    unit's = the process exit code (CLI.pas:27758, 27783-27790). Read it per entry.
  * **R6** (L) InputGate reports a swallowed SELECTION click as a red error (InputGate.pas:132/136).
  * **R7** (L) engine output decoded ANSI per 4 KB chunk (Engine.pas:1752) then written as UTF-8.
  * ~~Test-kit gaps~~ CLOSED 2026-10-26 (lane E): exit-6 mixed (lane A: `batch.exit6.*`, `config.stop.*`), probe-failure decision (lane B: `probe.*`, `StartupProbeDue`), BatchDistrust partial rule_errors (`batch.untrusted.partial.rule.errors`), non-ASCII Save round trip byte-exact (`save.bytes.exact.*`), `TRestorePoint` direct (`restorepoint.*`, type now public in ConvertRunner).
  * ~~**ENC-a**~~ CLOSED 2026-10-26 (lane E): Task 1 minors -- detect branches, surrogate Col, FF FE sniffing, lone surrogate pinned by tests (`detect.*`, `lost.col.after.surrogate`, `presave.lone.surrogate.*`); dead `RaiseTarget` clause removed. Open: a lone surrogate in a UTF-8 book still offers RaiseTo = the current level (no level above UTF-8 helps short of UTF-16).
  * **Re-pin** after ENGINE's "re-parse done" (engine 1.34.0-alpha, sha 7EF273E2...), full
    baseline, then **A4** slice 1.
  * **FG-M** featuregen: Harvest via `menu-tree --format json`, path-based checks B/C, caption-key
    parity vector, drop 14 stale exemptions (in flight, branch feat/conv-fgm-menu-tree).
  * ~~`GlyphForm.pas:60` unused `dl:ok` marker~~ CLOSED 2026-10-26 (lane E): line 60 is a `dl:unit` accepted marker; `review-marker-unused` does not flag it (lint-all, 0 hits in GlyphForm.pas).
* E3 + this run's worktrees `C:\Projects\Delphi-RAG-lint-wt\conv-*`: owner removes (approval).

## State at the rewrite

* Pin `third_party\engine-pinned\1.31.5-alpha-20261019-071827`; re-pin to 1.32.0-alpha
  (extractor 1.22) waits for ENGINE's "re-parse done".
* On main (pushed 4fa585c4): A2 qualify fix (3cdadd60), C minors + `#depth` repair (1d888db1).
  Merged-tree baseline on the 1.31.5 pin: model tests 2281 pass / 5 fail (VARINSP), 14 drivers.
* Unmerged, under review: `feat/converter-apply-fields` (B1 B3 B6 B7 B8, C-2, B4 helpers) and
  `fix/converter-testkit` (D1, N5); worktrees `C:\Projects\Delphi-RAG-lint-wt\conv-apply-fields`
  and `conv-testkit`.

## F. Feature-registry review (owner request 2026-10-20, via www-2a) -- after E18 + next release

CONVERTER owns the coordination (featuregen is ours); each team (ENGINE, CONVERTER, CHARTS,
YADF) reviews its OWN entries. Start only after ENGINE E18 is merged AND the next release is
published. Not urgent. Review every entry for:

* (a) outdated features (owner saw at least one stale item on the GitHub wiki);
* (b) features with no IDE menu access;
* (c) features needing 2-3 IDE clicks: spell out "where to click"; owner wants unique help ids
  at that granularity (one page per id, maybe anchors per click path).

**Registry ids are now PUBLIC URLs** (www-2a renders `WWW\help\dl\features\<id>.md` at
`https://www.delphi-rag-lint.com/help/<id>/`): treat ids as permanent; a rename needs a
redirect. www-2a uses `featuregen build --site` and will ask before relying on front-matter
beyond id/title/summary/group/order/since/status/updated. ENGINE separately owns an IDE help
framework keyed by the registry help id.

## A. Queued work, in order

1. **Re-pin to 1.32.0 + baseline** -- S, session. After "re-parse done". Procedure: editor
   CLAUDE.md "Re-pin"; then model tests + all 14 drivers on main; re-judge lint (new rule
   `confusable-identifier`).
2. **Merge `feat/converter-apply-fields`** -- M, session. Review + mutation positive controls,
   `ParseApplyJson` bad-shape reads, B8 legacy text match keep/drop; drivers owed: convert-tab,
   convert-request, work-list (+ refused Convert keeps rows with the "previous run" summary),
   validate-scope, inherited-offer.
3. **Merge `fix/converter-testkit`** -- S, sonnet. Run drive-file-menu with a forced FAIL
   (must exit 1) and drive-work-list.
4. **A4 C18 member replacement, slice 1** (`#migrate X -> Y` / `-> DL_NONE` + rename) -- M,
   session. Contract `docs\NOTICE-2026-10-19-c18-slice1-migrate.md`; design
   `docs\superpowers\specs\2026-10-11-member-replacement-design.md` (Q1-Q4 answered, Q5
   deferred). Spec + plan first, owner approves, then implement on the 1.32.0 pin.
5. **N1 Convert click lost while an analysis or Save validation is pending** -- M, session.
6. **N3 re-create the apply1270 capture project as a script**, then re-capture the
   `tests\fixtures\apply1270\` uses rows -- M, sonnet. Needs an indexed unit (after the re-parse).
7. **B9 `#warn` / `#check-ref` in the Model + display + BDE book lines** -- M, sonnet.
8. **D4 + D6 qualify follow-ups** -- M each, sonnet. Owner ADDED both 2026-10-19.
9. **B4 runner batch mode** (`apply-batch/1`) -- L, session. Parse helpers exist on
   apply-fields (not wired).
10. **B10 `inherited_code_unconverted` capability + model test on a real capture** -- S, sonnet.
11. **N2 QualifyFix mutant Q08 "retarget ignores Applied" survives** -- S, sonnet (low).
12. **D2 `drive-engine-wait.ps1` `wait.reload.no.window` flake** -- M, sonnet.
13. **E2 one doc line: in a worktree pass `--db <wt>\src\tools\convrules-editor\_D-RAG\
    ConvRulesEditor.sqlite` and index with `--project ConvRulesEditor.dpr`** -- S, haiku.

## B. Engine-contract follow-ups

- **B1** scoped note from `only_matched[]` / `only_unmatched[]` -- on apply-fields (A2 above).
- **B2** E10 refusal hint gated on `only_skips_unit_rules` -- DROPPED (owner 2026-10-19):
  never fires on 1.31.5 (uses reconciliation keeps the unit). `RefusalHint` is dead code;
  delete it with its test when next in `ConvertRequest` (S, haiku).
- **B3** C13 index-gap refusal reads "fix the index" -- on apply-fields.
- **B4** runner batch mode -- A9.
- **B5** C8 code refs filtered to field-resolved -- DROPPED (owner 2026-10-19): the engine's
  `inherited[]` is authoritative (ruling M4) and the note is off when it reports.
- **B6** `descendants[]` on the ancestor's row + report -- on apply-fields.
- **B7** `only_included[]` / `unlinked[]` -- on apply-fields (texts were already done).
- **B8** half-apply guard on the exit contract -- on apply-fields; text match kept as a legacy
  fallback pending the review's keep/drop decision.
- **B9** `#warn` / `#check-ref` -- A7.
- **B10** `inherited_code_unconverted` -- A10.
- **B11** castlib `dfmdata` -- DONE (shared parser reads it).

## C. Owner minors

- **C-1 Picker does not offer StripDB for a `TFileName` From** -- BLOCKED on ENGINE castlib
  (`accepts string, TFileName`), asked in
  `docs\INBOX-REPLY-2026-10-19-converter-to-engine-qualify-and-castlib.md`. Then verify the
  picker (S, haiku).
- **C-2 Refused Convert keeps the previous Work list** -- DONE on apply-fields (owner chose:
  keep rows, label "from the previous run ...; the last Convert was refused").
- All other section-C minors -- DONE, merged in 1d888db1 (plan
  `docs\superpowers\plans\2026-10-19-converter-c-minors.md`, triage table names the closed ones).

## D. Test-kit debts

- **D1** `drive-file-menu.ps1` exit 1 on FAIL -- on fix/converter-testkit (A3).
- **D2** `wait.reload.no.window` flake -- A12.
- **D3** "rerun alone under load" -- DROPPED as an item (note kept in D2).
- **D4 / D6** -- A8.
- **N5** `drive-work-list.ps1` clipboard retry -- on fix/converter-testkit (A3).

## E. Housekeeping

- **E1 instruction-file trim** -- DONE 2026-10-19 (editor CLAUDE.md 7.5 KB, archive in
  `docs\handoffs\archive\convrules-editor-HANDOVER-ARCHIVE.md`).
- **E2 worktree `--db` doc line** -- A13 (N4 "no .dproj" is not a defect).
- **E3 merged/scratch worktrees** (conv-trial, conv-qualify-fix, conv-c-minors,
  conv-integrate + branches tmp/conv-trial, feat/convert-qualify-fix, fix/converter-c-minors,
  conv/integrate) -- remove, owner approval batched.
