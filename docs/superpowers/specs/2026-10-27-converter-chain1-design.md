# ConvRulesEditor -- CHAIN-1: rule chains in one book (design)

> **Owner 2026-10-27: GO -- every recommended answer in the open-questions table is accepted as written.**

Date: 2026-10-27. Stream: CONVERTER. Origin: owner input in `docs\CONVERTER-BACKLOG.md`
(2026-10-26 night, "CHAIN-1") and ENGINE's answer `docs\INBOX-engine-to-converter-chain1.md`.
Status: written, awaiting owner approval. Plan: `docs\superpowers\plans\2026-10-27-converter-chain1.md`.

## 1. Intent and why

A rule book with `#convert TA -> TB` and `#convert TB -> TC` LOOKS like it converts a TA all
the way to TC. It does not. ENGINE traced convert-apply (main 67ecfe2a): the book is applied in
ONE pass against the ORIGINAL source; an output is never re-matched. A TA ends as TB, a TB ends
as TC, and nothing tells the author.

The same single pass has three cousins, all silent today:
* two `#convert` rules with the same From type: the first wins, the second is never applied;
* a cycle (`TA -> TB` plus `TB -> TA`): the two classes are SWAPPED in one run, no loop;
* a unit swap chain (`#useswap A -> B` plus `#useswap B -> C`, or a header's `, B` uses-add
  plus `#useswap B -> C`): "ADD wins", so a unit ends with B AND C.

What the owner wants (backlog, condensed): warn, and offer (a) one `TA -> TC` rule, or (b) to
move the stages into separate books that the Convert tab runs one after the other. Decided by
a pure `RuleChains` unit, surfaced in the Save validation (ValidateScope) with two quick fixes.

Success: no chain is ever silent; an author who writes one is told on Save what convert-apply
will really do and can fix it in one click; a book without chains sees nothing new.

## 2. Facts this design stands on (verified in the tree, conv/chain1 base 62439e0a)

| Fact | Where |
|---|---|
| Single pass; first `#convert` per From wins; `#migrate` collected once per block; uses "ADD wins"; a cycle swaps | `docs\INBOX-engine-to-converter-chain1.md` (ENGINE trace, no test) |
| The Convert tab's books are an ORDERED check list (`FBooks: TCheckListBox`, `FEntries`), reorderable with Move Up / Move Down (`MoveBook` -> `MoveEntry`) | `ConvRules.ConvertTab.pas:860-915` |
| Per-unit mode runs the checked books IN ORDER, one `convert-apply` call per (unit, book), with a reindex AFTER each applied book | `ConvRules.ConvertRunner.pas:1568-1573` (`RunUnit`), `:1512-1517` (`Step(rpReindexAfter)`) |
| Batch mode is book-major: for each book, every unit chunk; a reindex before the first book and after every chunk | `ConvRules.ConvertRunner.pas:2040-2071`, `:1918` |
| So a two-book sequence DOES chain: book 2 reads book 1's output from disk after the reindex. "Separate books run one after the other" exists already and needs no runner change | same |
| Save: `SaveBook` writes, then `RunScopedValidate` -> `ApplyValidateMarks` -> `StaticMigrateMarks` -> `RefreshRuleMarks`; then the unit-conflict note (`NormalizeUnitSets`) | `ConvRules.MainForm.pas:8144`, `:7697-7705`, `:8151-8155` |
| Marks are session state on `TRuleNode.Marks` (`TRuleMark`, never emitted); `StaticMigrateMarks` is the precedent for marks the editor adds WITHOUT the engine; its helper `AddWarningMark` is private to `ConvRules.Migrate` | `ConvRules.Model.pas:104-113`, `ConvRules.Migrate.pas:189`, `:515-527` |
| The model: `TRuleBook.ConvertHeaders` (header node indexes), `UnitNodes` (`#use` / `#unuse` / `#useswap`), node fields `FromType`, `ToType`, `Units` (header uses-add, comma-joined), `SwapOld`, `SwapNew`, `LinkTo`, `LinkFrom`, `Cast`, `GlyphExpr`, `DefTo`, `DefValue`, `IgnorePath`, `MigOld`, `MigNew`, `MigUnits`, `ApplyName`, `MapName` | `ConvRules.Model.pas:125-261`, `:388-403` |
| One node per physical line; `SaveToString` emits one line per node, so Raw DSL line N = `Nodes[N-1]` | `ConvRules.Model.pas:186-188`, `MainForm.SyncRawFromModel` |
| Text-level block tools: `SplitRulesBlocks(text)` -> `TRuleBlocks` with `rbkPreamble` / `rbkConvert` / `rbkTrailing`, 1-based `StartLine`/`EndLine`, `JoinBlocks`, `ConcatBlocks`, `SplitOut`, `DuplicateHeaders`; `HEADERLESS_KINDS` never move | `ConvRules.BlockFile.pas:67-112`, `ConvRules.BlockOps.pas:38-96, 483` |
| Moving blocks to another file exists in the Curation form (`DoSplit` -> `AskTargetFile`, `WriteBlocksTo` with backup + duplicate-header warning + encoding ask) | `ConvRules.CurationForm.pas:1016-1150` |
| Encoding-safe writes: `WriteTextAskingRaise(path, text, current, ask, out level, out backup)`, `ReadTextDetect`, `BackupPath` | `ConvRules.WorkingSet.pas`, `ConvRules.TextEncoding.pas` |
| The Save question precedent (`MessageDlg`, Yes / Cancel) and "ask once per path" (`FLowerAsked`) | `ConvRules.MainForm.pas:8091-8105`, `ConvRules.ConvertTab.pas:1802-1819` |
| Menu wiring: `AddMenuCmd(FMnuConversion, caption, hint, handler)`; drivers invoke by path `Conversion|...` | `ConvRules.MainForm.pas:3054-3063` |
| Tests: `tests\ConvRulesModelTests.dpr` (`Check(name, cond, detail)`, `Skip`), one `{$I inc\<Name>Tests.inc}` per lane; GUI drivers `tests\gui\drive-*.ps1` | `CLAUDE.md` (editor) "Test kit" |

## 3. Goals / non-goals / anti-goals

Goals
* G1. Every chain, cycle, duplicate From and unit chain in the open book is found by the
  editor alone (no engine call) and shown as a warning mark on the rule lines involved, on
  every Save and on File > Validate.
* G2. On Save, a chain that has a quick fix is OFFERED once per session: merge into one
  `TA -> TC` rule, or split the stages into stage books the Convert tab runs in order.
* G3. Merge composes the two stages' lines deterministically; anything it cannot compose is
  kept and NOTED in the book, never dropped silently; the result is validated by the next Save.
* G4. Split leaves disk consistent: stage books written, the source saved without the moved
  blocks, backups for every file touched; a partial failure says which files hold what.
* G5. The Convert tab keeps running a checked list of books in order; this spec changes
  nothing in the runner.

Non-goals
* Chaining semantics in the engine (ENGINE owns that; section 7).
* A chain ACROSS books in one Convert run (book 1 `TB -> TC`, book 2 `TA -> TB` -- the wrong
  order): CHAIN-2 (open question Q6).
* Composing two casts into one (`cast f` then `cast g`): noted, not composed.
* Resolving qualified type names through the index: names are compared BARE (section 4).

Anti-goals (a failure even if it "works")
* A Save that blocks or asks every time: the offer is once per chain key per session; the
  marks and the status note are the standing signal.
* A merge that drops a `#link`, `#default` or `#migrate` without a `#note` naming it.
* A split that leaves the moved blocks in BOTH files without saying so.
* A dialog during a Save triggered by closing the editor or by the Convert tab's LowerBook.

## 4. Definitions

* **Rule** = a `#convert` header with a non-empty To type. A From-only header is scratch and
  takes no part.
* **Same type**: two type names are the same when their BARE names (after the last `.`),
  trimmed, compare equal case-insensitively. `Bde.DBTables.TTable` = `TTable` = `ttable`.
  A `.dfm` object carries only the bare class name, which is what the DFM match reads
  (INBOX row 1); the PAS match is an open question for ENGINE (Q5).
* **Winner**: among rules with the same From type, the first in file order (the engine's
  `first match wins`). Losers are **duplicate From** findings and take no part in chains.
* **Link** R1 -> R2: R1.To is the same type as R2.From (R2 a winner).
* **Root**: a winner whose From is not the To of any winner.
* **Chain**: the maximal path of links from a root, 2 or more rules long, cut before any rule
  already on the path. Two roots sharing a tail (`TA -> TB`, `TX -> TB`, `TB -> TC`) are
  two chains, reported separately.
* **Cycle**: a path of links that returns to its first rule (`TA -> TB`, `TB -> TA`; or
  longer). Reported once, starting at its lowest header index. A chain that runs INTO a
  cycle is reported as the chain up to the cut, plus the cycle.
* **Unit chain**: a `#useswap Old -> New...` whose Old is ADDED by another line of the book:
  by another `#useswap X -> Old`, by a `#use Old`, or by a header's `, Old` uses-add.
  (A plain `#use B` + `#unuse B` is a unit CONFLICT and is already reported by
  `NormalizeUnitSets`; it is not a chain.)
* **Stage** of a winner: 1 for a root or a cycle member; otherwise 1 + the highest stage of
  the winners linking into it. Losers share their winner's stage. Stage k >= 2 rules form
  **stage book k**: `<base>.stage<k>.rules` beside the source (`X.rules` -> `X.stage2.rules`;
  the folder scan and the Convert tab list `X.rules` before `X.stage2.rules`).
* **Chain key**: `<kind>:<bare lowercase names joined by '>'>` -- the identity of a finding
  across saves (`chain:ttable>tfdtable>tfdmemtable`, `cycle:ta>tb`, `dup:ta`,
  `unit:a>b>c`). "Asked once" is per key.

## 5. Behaviour (acceptance criteria, EARS)

### 5.1 Detection (pure, `ConvRules.RuleChains`)
* C1. THE detector SHALL report every chain, cycle, duplicate From and unit chain of a book,
  in file order of their first line, each with the node indexes of the lines involved.
* C2. WHEN two headers have the same From type THE detector SHALL report one duplicate From
  finding per From type, the winner first, every loser after it in file order, and SHALL
  exclude the losers from links.
* C3. WHEN a header's To type is the same type as a later OR earlier winner's From type THE
  detector SHALL link them (file order does not matter for a link: the engine's pass is one).
* C4. IF a path returns to a rule on it THEN THE detector SHALL report a cycle and SHALL NOT
  loop.
* C5. WHILE a header has an empty To type THE detector SHALL ignore it.
* C6. WHEN a `#useswap` names an Old unit that another line adds THE detector SHALL report a
  unit chain with the adding line first.

### 5.2 Marks and status (Save and File > Validate)
* M1. WHEN a Save or a Validate completes THE editor SHALL add one warning mark per finding
  on EVERY line it involves (every stage header; both unit lines; the winner and each loser),
  after `StaticMigrateMarks`, without touching Emit, Snapshot or Dirty, and never twice.
* M2. THE mark text SHALL say what convert-apply will do, in these shapes (exact strings in
  the plan): chain = "chain TA -> TB -> TC: stage i of n -- convert-apply is single pass, so
  a TA ends as TB, never TC"; cycle = "... the classes are swapped in one run"; duplicate =
  "this rule wins; line N is never applied" / "never applied -- line N wins"; unit chain =
  "ADD wins, so B stays and C is added -- rewrite line N as A -> C".
* M3. WHEN findings exist THE Save status SHALL end with "Rule chains: <counts> -- see marked
  rules (Conversion > Rule chains...)"; WHEN none exist THE status SHALL be unchanged.
* M4. "line N" in a mark is the Raw DSL line (node index + 1) at the time of marking.

### 5.3 The offer (File > Save and File > Save As only)
* O1. WHEN a Save completes with at least one finding that can be merged or split
  (chains, unit chains) whose key was not asked this session THE editor SHALL show the Rule
  chains dialog listing every finding (cycles and duplicates too, fix buttons disabled for
  them) with the fixable ones checked.
* O2. THE dialog SHALL offer `Merge`, `Split` and `Keep`. `Merge` is enabled when every
  checked finding can be merged; `Split` when every checked finding is a chain. `Keep` closes
  and records every listed key as asked.
* O3. IF the Save ran from closing the editor, from opening another book, or from the
  Convert tab's LowerBook THEN THE editor SHALL NOT show the dialog (marks and status only).
* O4. WHERE `Conversion > Rule chains...` is chosen THE editor SHALL show the dialog with the
  CURRENT model's findings whether or not they were asked, without saving first.
* O5. WHEN the book is replaced (Open, New) THE asked set SHALL be cleared.

### 5.4 Merge (quick fix a)
For a chain P1 -> P2 -> ... -> Pn the merge composes pairwise from the left: P1 with P2 gives
M; M with P3 gives M'; ... The LAST stage block stays in the book unchanged (its From type may
exist on its own in the sources). The FIRST stage's block is replaced in place.
* A1. THE merged header SHALL be `#convert <P1.From> -> <Pn.To>` with Pn's uses-add (`, unit`)
  and none of P1's.
* A2. WHEN a `#link B.x <- A.y [cast] [glyph]` of P and a `#link C.z <- B.x [cast2]` of Q
  meet on `B.x` (same path text, case-insensitive) THE merge SHALL emit `#link C.z <- A.y`
  with the one cast present (P's or Q's) and P's glyph; IF both have a cast THEN it SHALL
  emit the link with NO cast and a `#note chain merge: casts <cast> then <cast2> on A.y
  cannot be composed -- pick one` before it.
* A3. WHEN Q has `#ignore B.x` for P's `#link B.x <- A.y` THE merge SHALL emit `#ignore A.y`
  (the From property is not mapped).
* A4. WHEN Q has no line for `B.x` THE merge SHALL keep P's `#link B.x <- A.y` verbatim
  (counted as carried; the next Save's validation says whether C has `x`).
* A5. `#default B.x = v` of P: through a Q link on `B.x` it becomes `#default C.z = v` (a Q
  cast adds a `#note`); through a Q `#ignore` it is dropped with a `#note`; unmatched it is
  carried verbatim. `#default` of Q is copied verbatim.
* A6. `#migrate Old -> New[, units]` (plain member form) of P followed by Q's
  `#migrate New -> Newer[, units2]` becomes `#migrate Old -> Newer[, units2]`; every other
  `#migrate` of P and of Q is carried verbatim, de-duplicated on its text.
* A7. Every other line of P (`#ignore`, `#remove`, `#apply`, `#tag`, `#warn`, `#checkref`,
  `#pcre`, `#note`, comments, blanks) is carried verbatim; the lines of Q not consumed above
  (`#apply`, `#warn`, `#checkref`, `#remove`, `#pcre`) are carried after one
  `#note chain merge: the lines below came from <Q.From> -> <Q.To> (line N); review`;
  Q's `#tag`, `#note`, comments and blanks are dropped; Q's `#link` and `#ignore` lines not
  consumed by A2 / A3 / A5 are dropped (they name B paths that A never maps -- a TA instance
  has no value for them; the next Save's validation reports what is left unlinked on TC).
* A7a. Counters: Composed = lines rewritten through Q (A2, A3, A5 through a link, A6
  composed); Carried = A4, A5 unmatched and every `#migrate` not composed; Noted = every
  `#note` added except the leading A8 note.
* A8. THE merged block SHALL start with `#note chain merge: <P.From> -> <P.To> (line a) +
  <Q.From> -> <Q.To> (line b) = <P.From> -> <Q.To>; <n> composed, <m> carried, <k> noted --
  validate on Save` right after the header. Trailing blank lines of the replaced range are
  kept.
* A9. WHEN a UNIT chain is merged THE merge SHALL rewrite the ADDING line only: `#useswap A ->
  B[, X]` becomes `#useswap A -> C[, X]` (B replaced by the swap's New list, de-duplicated);
  a header's `, B` uses-add becomes `, C`; `#use B` becomes `#use C`. The `B -> C` swap stays.
* A10. THE merge SHALL edit the model only (the block is selected and the status reads
  "Merged ... Review, then Save"); it SHALL NOT save. The merged key is recorded as asked.
* A11. IF a stage block no longer exists in the model (edited since detection) THEN THE merge
  SHALL refuse with a reason and change nothing.

### 5.5 Split (quick fix b)
* S1. THE split SHALL assign every winner a stage (section 4); losers, cycles and the
  file-scope lines (preamble, trailer) stay in the source at stage 1.
* S2. FOR each stage k >= 2 THE split SHALL write `<base>.stage<k>.rules` holding: the
  source's `#depth` line when it has a valid one; a copy of every `#mapping` group a moved
  block `#applies` (declaration and clause lines, verbatim, one copy per name); then the
  moved blocks verbatim in file order. IF the stage file exists THEN the blocks are APPENDED
  and a duplicate-header warning is reported (the Curation rule).
* S3. THE split SHALL write the stage books FIRST, then remove the moved blocks from the
  model and save the source (`SaveBook(False)`, no dialog possible: the chains are gone).
  IF the source save fails THEN the status SHALL name both files and that the blocks exist
  in both; the stage books are not deleted.
* S4. Every write goes through `WriteTextAskingRaise` (backup + encoding question); a
  cancelled encoding question aborts the split before any write.
* S5. WHEN the split completes THE status SHALL read "Split <n> block(s) into <files> --
  convert with <base>.rules first, then <base>.stage2.rules (check both on the Convert tab,
  in that order)", and the Convert tab's book list SHALL refresh.
* S6. IF `#mapping` lines were copied THEN the status SHALL add "; copied #mapping <names>
  into the stage book" (Q3).

### 5.6 Convert tab (no change, documented)
* T1. THE Convert tab SHALL keep applying the checked books to every unit in list order, with
  a reindex between books, so `X.rules` then `X.stage2.rules` chains TA -> TB -> TC.
* T2. The wiki page SHALL document this sequence and the Move Up / Move Down buttons as the
  way to order stage books.

## 6. Unit map fit (`src\tools\convrules-editor\CLAUDE.md`)

* `RuleChains` (decisions) -- chains, cycles, duplicate From, unit chains over `#convert`
  headers and unit lines; `FindRuleChains`, mark / row / status texts, `StaticChainMarks`,
  `MergeChainPlan` / `ApplyChainMerge`, `SplitChainPlan` / `StageBookPath` /
  `StageBookText`. Pure: no UI, no engine, no file I/O.
* `ChainForm` (dialog) -- the Rule chains list with Merge / Split / Keep (editor-only).
* `ValidateScope` -- gains the public `AddStaticWarningMark` (hoisted from `Migrate`'s
  private `AddWarningMark`; `Migrate` calls it) so every static mark is added one way.
* `MainForm` -- wiring only: marks + status in `RunScopedValidate` / `SaveBook`, the offer in
  `DoSaveClick` / `DoSaveAsClick`, `Conversion > Rule chains...`, the two fix actions.
* `ConvertRunner` / `ConvertTab` -- untouched.

## 7. ENGINE requests (not designed here; file as `docs\INBOX-REPLY-chain1.md`)

* E1. The guard test ENGINE itself suggested: `TA -> TB` + `TB -> TC` => TB, DFM and PAS,
  pinning single pass (`tests\autotest\run_convert_rules.ps1` has only A->B fixtures).
* E2. How `FindConvertRuleFor` (PAS) compares a QUALIFIED From type with a declaration: bare
  name, or resolved through the index? The editor compares bare (section 4) and says so in
  the mark when the qualifiers differ (Q5).
* E3. If ENGINE adds its own book-level check ("warn on chains / duplicate FromType" per the
  INBOX), its diagnostic text should start `line N: warning: chain` / `duplicate From` so
  the editor can recognise and not double-mark (the editor's marks are de-duplicated on
  text only).
* E4. Documentation: `docs\CONVERSION-RULES.md` does not state single pass; the plan adds
  one paragraph citing the INBOX, for ENGINE to confirm.

## 8. Open questions (recommended answers; proceed on them unless overruled)

* Q1. **Cycle severity.** The backlog says "cycle = error"; ENGINE says a cycle is a
  deliberate SWAP that cannot loop. Recommend: a WARNING mark and a dialog row with no fix
  (a merge would be `TA -> TA`; a split would turn the swap into "everything ends as TA").
  Save never blocks on it.
* Q2. **Does the offer dialog pop for duplicates and cycles alone?** Recommend: no -- marks
  and status only; they are listed in the dialog when it opens for a fixable finding or from
  the menu.
* Q3. **`#mapping` copies in stage books** breach the one-rule-one-place rule (BlockOps
  remarks). Recommend: copy (the engine resolves `#apply` inside the book it runs) and say so
  in the status; the alternative -- refuse to split such a chain -- would make the fix
  useless on real books (BDE-to-FireDAC applies mappings).
* Q4. **Merge saves or not.** Recommend: Merge edits the model and does not save (review
  first, like New Conversion); Split must save (two files have to agree on disk).
* Q5. **Qualified names.** Recommend: compare bare names; when the two qualifiers differ
  (`Vcl.X.TLabel` vs `Lib.TLabel`) still report, with "(qualifiers differ: X vs Y)" in the
  mark; ask ENGINE (E2) and tighten later.
* Q6. **Cross-book chain order on the Convert tab** (book 1 `TB -> TC`, book 2 `TA -> TB`):
  recommend CHAIN-2 -- a preflight note on the Convert tab using the same detector over the
  checked books in order; out of this slice.
* Q7. **Stage file naming** `<base>.stage2.rules`: recommend as is (sorts after the base in
  the folder scan; `-stage2` would sort BEFORE it because `-` < `.`).
* Q8. **DUnitX.** The lane brief says DUnitX; the editor's kit is `ConvRulesModelTests.dpr`
  (`Check` / `Skip`, include files). Recommend: stay in the kit (one runner, one baseline);
  the plan is written for it.

## 9. Test strategy (summary; the plan has every name)

* Model tests, no engine: `tests\inc\RuleChainTests.inc` -- detection (chains, shared
  tails, cycles, chain into cycle, duplicates, From-only ignored, bare-name match, unit
  chains from swap / use / header), texts, keys, asked filter, marks (idempotent, after
  migrate marks), merge composition (every rule A1-A11, counts, note lines, refusal), split
  (stages, mapping copies, depth line, existing stage file, remaining text, round trip).
* GUI driver `tests\gui\drive-rule-chains.ps1` (~24 checks, `-ProofNoChain` = a book
  without a chain must show no dialog and no status note): Save -> status note, dialog, Keep,
  no second ask, menu reopens, Split writes `.stage2.rules` and saves the source, a fresh
  chain book -> Merge rewrites the header and the links in the Raw DSL, Save then shows no
  dialog; Save from close shows no dialog.

## 10. As built (T6 review, 2026-10-27)

Deviations of T1-T5 from sections 4-5, judged in the whole-branch review; all ACCEPTED
unless marked FIXED.
* Chain key: when a chain loops back into a cycle the key omits the repeated last To (the
  cycle is its own finding). Cycle detection walks from every winner not yet reported.
* A2 casts are written `: Cast` (the DSL's cast form); the merge parses P/Q lines with
  `TRuleBook.ParseLine`.
* Block range: a Q stage that runs to the end of the book keeps a trailing `#migrate` as its
  own (the grammar cannot tell a file-scope trailer from a block line); A6 carries it
  de-duplicated, so the worst case is one duplicated `#migrate` line in the merged block.
* S5 with more than two stages reads "... first, then A, then B"; `TChainSplit.Stages` lists
  every non-moved `#convert` header at stage 1.
* S2 append: when the stage book exists its own `#depth` line governs; the moved blocks' copy
  is dropped (wiki says so). Every encoding question is asked before the first write (S4).
* M3: the unit-conflict Save status also ends with the chain text.
* M1 FIXED in T6: `StaticChainMarks` now drops every chain mark the current findings no longer
  give. Before, the last stage block kept "chain ... stage 2 of 2" after a Merge, and a mark
  whose "line N" moved was kept beside the new one (tests `chains.marks.merge.*`,
  `chains.marks.replaces.shifted`). `MergeChains` refreshes the marks at once.
* Driver: 22 checks (`-ProofNoChain` 5); the dirty check uses File > New's "Save changes"
  question (the editor has no caption marker).
