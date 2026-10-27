# ConvRulesEditor CHAIN-1 (rule chains) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A rule book with `#convert TA -> TB` and `#convert TB -> TC` (or a duplicate From, a cycle, a unit swap chain) is marked on Save, named in the status line, and offered two one-click fixes: merge into `TA -> TC`, or split the later stages into `<base>.stage<k>.rules` books the Convert tab runs after the base book.

**Architecture:** One new pure unit `ConvRules.RuleChains` owns every decision (detection, texts, keys, marks, merge composition, split planning and stage-book text). One new dialog `ConvRules.ChainForm` lists the findings with Merge / Split / Keep. `ConvRules.MainForm` wires: static marks in `RunScopedValidate` (after `StaticMigrateMarks`), the status note in `SaveBook`, the offer in `DoSaveClick` / `DoSaveAsClick` only, the `Conversion > Rule chains...` menu, and the two actions (Merge = model edit; Split = write stage books through `WriteTextAskingRaise`, then `SaveBook(False)`). The runner and the Convert tab are untouched: they already run checked books in order with a reindex between books (`ConvRules.ConvertRunner.pas:1568-1573`, `:2065-2071`).

**Tech Stack:** Delphi 13 (dcc64), VCL; model tests `tests\ConvRulesModelTests.dpr` (`Check(name, cond, detail)`); GUI drivers `tests\gui\*.ps1` (pwsh, Win32 messages).

**Spec:** `C:\Projects\Delphi-RAG-lint\docs\superpowers\specs\2026-10-27-converter-chain1-design.md` (sections 4, 5 and the Q1-Q8 recommendations are binding unless the owner overrules).

## Global constraints

* Worktree `C:\Projects\Delphi-RAG-lint-wt\conv-chain1`, branch `conv/chain1`. DB `<wt>\src\tools\convrules-editor\_D-RAG\ConvRulesEditor.sqlite`; reindex with `drag-lint index --project <wt>\src\tools\convrules-editor\ConvRulesEditor.dpr --db <that db>` after every task's edits, before lint. Exe always by full path `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe`.
* Sources `.pas` / `.dpr` / `.inc` / `.ps1`: 7-bit ASCII, CRLF, no BOM; Write/Edit emit LF -- normalise with `[IO.File]::WriteAllText(p, [IO.File]::ReadAllText(p).Replace("`r`n","`n").Replace("`n","`r`n"), [Text.Encoding]::ASCII)`.
* DocInsight `///` (`<summary>`, `<param>`, `<returns>`, `<remarks>`) on every public type, function and method added; the comment and the test must agree.
* TDD per task: write the test, build the tests, watch it FAIL for the right reason (missing symbol = compile fail counts as RED only for brand-new units; for behaviour, a stub returning nil / '' first), implement, GREEN, commit with a pathspec (`git commit -m "..." -- <paths>`), never `commit -a`, never push.
* Builds (delphi-build skill, PowerShell `Start-Process -Wait`, output to a log in `C:\TEMP\claude\lanes\1027conv\agent-chain1\`): editor `build\_build_convrules_editor_local.bat`, tests `build\_build_convrules_tests_local.bat`. Never `cmd.exe /c` from Bash.
* Model runs without an engine beside the runner (no `drag-lint.exe` next to `tests\ConvRulesModelTests.exe`, `CONVRULES_TEST_ENGINE` unset). Record the BASELINE pass / fail / skip on the branch before Task 1 (CLAUDE.md says 2950 / 0 / 20 on main fa80b602); every later run must be baseline + this plan's new PASS lines, 0 fail, same skips.
* Lint per task: `drag-lint lint <changed unit> --db <db>` AND `drag-lint lint-all --db <db> --enable magic-literal,multiple-statements-per-line,commented-out-code`; every surviving finding on new code gets `// dl:ok <rule>@<hash> -- REVIEWED 2026-10-27 <why>`. Report the commands and counts.
* `IfThen` evaluates both arguments; never a new defaulted parameter on an existing overload (E2250): add a new name. Node indexes shift on insert: re-find headers by NODE after an edit.
* Models: `sonnet` for Tasks 1, 2, 3, 5 (fully specified here); omit the model (session model) for Tasks 4 and 6 (UI flow, final review).

## File structure

| File | Role |
|---|---|
| Create `src\tools\convrules-editor\ConvRules.RuleChains.pas` | PURE: detection, texts, keys, marks, merge, split |
| Create `src\tools\convrules-editor\ConvRules.ChainForm.pas` (+ `.dfm` not needed: built in code like `ConvRules.QualifyForm`) | the dialog |
| Modify `ConvRules.ValidateScope.pas` | public `AddStaticWarningMark` (hoisted) |
| Modify `ConvRules.Migrate.pas` | its private `AddWarningMark` becomes a call to the hoisted one |
| Modify `ConvRules.MainForm.pas` | wiring (Task 4) |
| Modify `ConvRulesEditor.dpr`, `tests\ConvRulesModelTests.dpr` | unit entries, `{$I inc\RuleChainTests.inc}`, the `TestRuleChains*` calls |
| Create `tests\inc\RuleChainTests.inc` | every model test of this plan (Tasks 1-3 append to it) |
| Create `tests\gui\drive-rule-chains.ps1` | GUI driver (written in Task 4, run in Task 6) |
| Modify `src\tools\convrules-editor\CLAUDE.md`, `docs\CONVERSION-RULES.md`; create `docs\wiki\convrules-editor-rule-chains.md`, `features\entries\convrules-rule-chains.json`, `docs\INBOX-REPLY-chain1.md` | Task 5 |

**Tests layout.** Task 1 edits `tests\ConvRulesModelTests.dpr`: adds `, ConvRules.RuleChains in '..\ConvRules.RuleChains.pas'` after the `ConvRules.Migrate` uses line (line 57), adds `{$I inc\RuleChainTests.inc}` after `{$I inc\MigrateTests.inc}`, and adds `TestRuleChainsDetect; TestRuleChainsTexts; TestRuleChainsMarks; TestRuleChainsMerge; TestRuleChainsSplit;` after the `TestMigrateFollowups;` call (line 16196). The include starts with all five procedures; Tasks 2 and 3 fill `TestRuleChainsMerge` / `TestRuleChainsSplit`. A test builds books with a local `Make(text)` into a `TObjectList<TRuleBook>(True)` exactly as `TestQualifyUse` does (`ConvRulesModelTests.dpr:15041-15046`). Use `CRLF = #13#10` joins.

---

### Task 1: `ConvRules.RuleChains` -- detection, texts, keys, marks

**Model:** sonnet.

**Files:** create `ConvRules.RuleChains.pas`; modify `ConvRules.ValidateScope.pas`, `ConvRules.Migrate.pas`, `ConvRulesEditor.dpr` (add `, ConvRules.RuleChains in 'ConvRules.RuleChains.pas'` after the `ConvRules.Migrate` line 65), `tests\ConvRulesModelTests.dpr`; create `tests\inc\RuleChainTests.inc`.

**Interface (exact):**

```pascal
unit ConvRules.RuleChains;

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , ConvRules.Model
  ;

type
  /// <summary>What convert-apply's single pass does to a set of rules that look chained.</summary>
  TChainKind = (
    /// TA -> TB then TB -> TC: a TA ends as TB (spec 4 "Chain")
    ckChain,
    /// TA -> TB then TB -> TA: the classes are swapped in one run (spec 4 "Cycle")
    ckCycle,
    /// two headers with the same From type: the first wins (spec 4 "Winner")
    ckDuplicateFrom,
    /// a #useswap whose Old is added by another line: ADD wins (spec 4 "Unit chain")
    ckUnitChain);

  /// <summary>One line of a finding.</summary>
  TChainStage = record
    /// <summary>Index in TRuleBook.Nodes of the #convert header, or of the unit line (ckUnitChain).</summary>
    NodeIdx : Integer;
    /// <summary>The header's From type as written; ckUnitChain: the unit the line removes ('' for an adder).</summary>
    FromType: string;
    /// <summary>The header's To type as written; ckUnitChain: the unit(s) the line adds, comma-joined.</summary>
    ToType  : string;
  end;

  /// <summary>One finding of FindRuleChains.</summary>
  TRuleChain = record
    Kind  : TChainKind;
    /// <summary>ckChain: the stages root first; ckCycle: the loop from its lowest header, the closing rule
    /// NOT repeated; ckDuplicateFrom: the winner first, losers in file order; ckUnitChain: the adding line, then the swap.</summary>
    Stages: TArray<TChainStage>;
    /// <summary>Identity across saves: 'chain:ta>tb>tc', 'cycle:ta>tb', 'dup:ta', 'unit:a>b>c' (bare, lowercase).</summary>
    Key   : string;
  end;

/// <summary>The bare name of a type or unit: the part after the last '.', trimmed.</summary>
function ChainBareName(const AName: string): string;
/// <summary>True when A and B name the same type for convert-apply's match: bare names equal, case-insensitive (spec 4).</summary>
function SameChainType(const A, B: string): Boolean;
/// <summary>Every chain, cycle, duplicate From and unit chain of ABook (spec 5.1 C1-C6), ordered by the node index of each finding's first stage.</summary>
/// <param name="ABook">The book; not owned, not changed.</param>
function FindRuleChains(ABook: TRuleBook): TArray<TRuleChain>;
/// <summary>'TA -> TB -> TC' from the stages' types as written (a cycle repeats its first From at the end; a duplicate names the From once; a unit chain 'A -> B -> C').</summary>
function ChainPathText(const AChain: TRuleChain): string;
/// <summary>The dialog row: 'chain TA -> TB -> TC (lines 3, 9)', 'cycle TA -> TB -> TA (lines 3, 9)', 'duplicate From TA (line 3 wins; 12 never applied)', 'unit chain A -> B -> C (lines 1, 2)'.</summary>
function ChainRowText(const AChain: TRuleChain): string;
/// <summary>The warning mark for stage AStage (0-based) of AChain -- the exact strings are in the implementation constants and pinned by TestRuleChainsTexts.</summary>
function ChainMarkText(const AChain: TRuleChain; AStage: Integer): string;
/// <summary>True for ckChain and ckUnitChain (spec 5.3 O2).</summary>
function CanMergeChain(const AChain: TRuleChain): Boolean;
/// <summary>True for ckChain only.</summary>
function CanSplitChain(const AChain: TRuleChain): Boolean;
/// <summary>'' when none; else 'Rule chains: 1 chain, 2 duplicate From types -- see marked rules (Conversion > Rule chains...)' with only the non-zero counts, singular/plural by count.</summary>
function ChainStatusText(const AChains: TArray<TRuleChain>): string;
/// <summary>The findings to offer now: those with CanMerge or CanSplit whose Key is not in AAsked (case-insensitive).</summary>
function ChainsToOffer(const AChains: TArray<TRuleChain>; const AAsked: TArray<string>): TArray<TRuleChain>;
/// <summary>Adds the warning mark of every finding to every node it involves (spec 5.2 M1); returns the number added; never adds a mark twice.</summary>
function StaticChainMarks(ABook: TRuleBook): Integer;
```

Mark text constants (implementation; `%s`/`%d` as shown; "line N" = `NodeIdx + 1`):

```
CHAIN_MARK_FMT  = 'chain %s: stage %d of %d -- convert-apply is single pass, so a %s ends as %s, never %s (Conversion > Rule chains...)'
                  [PathText, Stage+1, Length(Stages), Stages[0].FromType, Stages[0].ToType, Stages[High].ToType]
CYCLE_MARK_FMT  = 'cycle %s: convert-apply is single pass, so the classes are swapped in one run -- remove one rule if that is not intended'
                  [PathText]
DUP_WIN_FMT     = 'duplicate From type %s: this rule wins; line %s is never applied'      [FromType, loser lines joined ', ']
DUP_LOSE_FMT    = 'duplicate From type %s: never applied -- line %d wins; delete this block or merge its lines there'  [FromType, winner line]
UNIT_ADD_FMT    = 'unit chain %s: %s is swapped again by line %d (ADD wins: %s stays)'    [PathText, B, swap line, B]
UNIT_SWAP_FMT   = 'unit chain %s: ADD wins, so %s stays and %s is added -- rewrite line %d as %s -> %s (Conversion > Rule chains...)'
                  [PathText, B, C, adder line, A, C]   (A = '' for a #use adder or a header: then 'rewrite line %d to add %s' -- one more constant UNIT_SWAP_ADD_FMT)
QUALIFIER_NOTE  = ' (qualifiers differ: %s vs %s)' appended to CHAIN_MARK_FMT / CYCLE_MARK_FMT when the linked To and From are both qualified and their qualifiers differ (spec Q5)
STATUS_FMT      = 'Rule chains: %s -- see marked rules (Conversion > Rule chains...)'
```

Detection algorithm (deterministic; implement exactly):
1. `Rules` = `ConvertHeaders` with `ToType <> ''`, in file order. `Winner(i)` = the first rule whose From is `SameChainType` with rule i's From. Losers -> one `ckDuplicateFrom` per distinct From (winner first).
2. `Next(i)` = the first WINNER whose From is `SameChainType` with rule i's To; -1 when none; a rule whose To is the same type as its own From links to itself (cycle of one -- report as ckCycle with one stage).
3. Roots = winners that are no winner's `Next`. For each root in file order: walk `Next` collecting stages until -1 or a stage already on the path; if 2+ stages -> `ckChain`.
4. Cycles: for each winner not on any root path, in file order, if not yet in a reported cycle: walk `Next` until returning to the start -> `ckCycle` (stages from the start, closing rule not repeated); mark every member as reported.
5. Unit chains: `Adders` = every `rnkUseSwap` node (adds `SwapNew`), every `rnkUse` node (adds `UseUnit`), every header with `Units <> ''` (adds each comma-separated unit, trimmed). For each `rnkUseSwap` S in file order and each adder A <> S whose added units contain `SameChainType(unit, S.SwapOld)` -> `ckUnitChain` with `Stages = [A, S]` (A.FromType = its SwapOld or '', A.ToType = the one matching unit; S.FromType = SwapOld, S.ToType = SwapNew joined ', ').
6. Sort all findings by `Stages[0].NodeIdx`, then by Kind order. `Key` = kind prefix + bare lowercase names joined '>' (cycle: without the repeated closer; dup: the From only; unit: adder's From (if any), B, C).

`StaticChainMarks`: for each finding and each stage, `AddStaticWarningMark(ABook.Nodes[NodeIdx], ChainMarkText(chain, stage))`.

**Hoist:** in `ConvRules.ValidateScope.pas` add to the interface, after `MarkerText`:
```pascal
/// <summary>Adds a warning mark with AText to ANode unless one with that text is already there (session state; see TRuleMark).</summary>
/// <returns>True when added.</returns>
function AddStaticWarningMark(ANode: TRuleNode; const AText: string): Boolean;
```
with the body of `ConvRules.Migrate.pas:515-527` (`FromSyntax` stays False). In `Migrate.pas` delete that private function and replace its call sites with `AddStaticWarningMark` (`drag-lint query find-callers --name AddWarningMark --db <db>` lists them; `ConvRules.ValidateScope` is already in Migrate's uses -- check; add it if not).

**Tests (`TestRuleChainsDetect`, `TestRuleChainsTexts`, `TestRuleChainsMarks`):**

Fixture texts (headers need no `#link` for FindRuleChains; `Make` loads any text):
* `BOOK_CHAIN` = `#convert TA -> TB` / `#link x <- y` / `#convert TB -> TC` / `#link z <- x`
* `BOOK_SHARED` = `#convert TA -> TB` / `#convert TX -> TB` / `#convert TB -> TC`
* `BOOK_CYCLE` = `#convert TA -> TB` / `#convert TB -> TA`
* `BOOK_INTO_CYCLE` = `#convert TX -> TA` / `#convert TA -> TB` / `#convert TB -> TA`
* `BOOK_DUP` = `#convert TA -> TB` / `#link a <- b` / `#convert TA -> TC`
* `BOOK_FROMONLY` = `#convert TA -> ` / `#convert TA -> TB`  (the From-only line is not a duplicate, not a stage)
* `BOOK_QUAL` = `#convert Bde.DBTables.TTable -> FireDAC.Comp.Client.TFDTable` / `#convert TFDTable -> Lib.TFDMemTable`
* `BOOK_QUALDIFF` = `#convert TA -> Vcl.X.TLabel` / `#convert Lib.TLabel -> TC`
* `BOOK_UNIT_SWAP` = `#useswap UnitA -> UnitB` / `#useswap UnitB -> UnitC`
* `BOOK_UNIT_USE` = `#use UnitB` / `#useswap UnitB -> UnitC`
* `BOOK_UNIT_HDR` = `#convert TA -> TB, UnitB` / `#useswap UnitB -> UnitC`
* `BOOK_UNIT_CONFLICT` = `#use UnitB` / `#unuse UnitB` (NOT a chain: 0 findings)
* `BOOK_CLEAN` = `#convert TA -> TB` / `#convert TC -> TD` / `#useswap U1 -> U2`

Checks (name = condition):
- `chains.detect.chain` BOOK_CHAIN -> 1 finding, ckChain, Stages NodeIdx [0, 2], Key 'chain:ta>tb>tc'
- `chains.detect.shared.tail` BOOK_SHARED -> 2 ckChain findings: [0,2] then [1,2]; keys 'chain:ta>tb>tc', 'chain:tx>tb>tc'
- `chains.detect.cycle` BOOK_CYCLE -> 1 ckCycle, Stages [0,1], Key 'cycle:ta>tb'
- `chains.detect.into.cycle` BOOK_INTO_CYCLE -> 2 findings: ckChain [0,1,2] (cut before repeating TA) and ckCycle [1,2]
- `chains.detect.self.cycle` `#convert TA -> ta` -> 1 ckCycle with 1 stage, Key 'cycle:ta'
- `chains.detect.dup` BOOK_DUP -> 1 ckDuplicateFrom, Stages [0, 2], Key 'dup:ta'; no chain
- `chains.detect.dup.loser.not.linked` `#convert TA -> TB` / `#convert TA -> TX` / `#convert TX -> TC` -> the dup only (TX is a loser's To: no chain)
- `chains.detect.fromonly` BOOK_FROMONLY -> 0 findings
- `chains.detect.bare.match` BOOK_QUAL -> 1 ckChain (qualified/bare match), PathText = 'Bde.DBTables.TTable -> FireDAC.Comp.Client.TFDTable -> Lib.TFDMemTable'
- `chains.detect.qualifiers.differ` BOOK_QUALDIFF -> 1 ckChain and ChainMarkText(.., 0) ends with ' (qualifiers differ: Vcl.X vs Lib)'
- `chains.detect.unit.swap` BOOK_UNIT_SWAP -> 1 ckUnitChain, Stages [0,1], Key 'unit:unita>unitb>unitc'
- `chains.detect.unit.use` BOOK_UNIT_USE -> 1 ckUnitChain, Key 'unit:unitb>unitc' (no A)
- `chains.detect.unit.header` BOOK_UNIT_HDR -> 1 ckUnitChain, Stages [0,1]
- `chains.detect.unit.conflict.not` BOOK_UNIT_CONFLICT -> 0
- `chains.detect.clean` BOOK_CLEAN -> 0; `ChainStatusText(nil) = ''`
- `chains.detect.order` BOOK_INTO_CYCLE + `#useswap A -> B` / `#useswap B -> C` appended -> findings ordered by first NodeIdx
- `chains.text.mark.chain` BOOK_CHAIN stage 0 = 'chain TA -> TB -> TC: stage 1 of 2 -- convert-apply is single pass, so a TA ends as TB, never TC (Conversion > Rule chains...)'; stage 1 = '... stage 2 of 2 ...'
- `chains.text.mark.cycle` = 'cycle TA -> TB -> TA: convert-apply is single pass, so the classes are swapped in one run -- remove one rule if that is not intended'
- `chains.text.mark.dup` winner = 'duplicate From type TA: this rule wins; line 3 is never applied'; loser = 'duplicate From type TA: never applied -- line 1 wins; delete this block or merge its lines there'
- `chains.text.mark.unit` BOOK_UNIT_SWAP adder = 'unit chain UnitA -> UnitB -> UnitC: UnitB is swapped again by line 2 (ADD wins: UnitB stays)'; swap = 'unit chain UnitA -> UnitB -> UnitC: ADD wins, so UnitB stays and UnitC is added -- rewrite line 1 as UnitA -> UnitC (Conversion > Rule chains...)'
- `chains.text.row` the four row shapes from the summary above (BOOK_CHAIN -> 'chain TA -> TB -> TC (lines 1, 3)', BOOK_DUP -> 'duplicate From TA (line 1 wins; 3 never applied)')
- `chains.text.status` BOOK_INTO_CYCLE -> 'Rule chains: 1 chain, 1 cycle -- see marked rules (Conversion > Rule chains...)'; BOOK_SHARED -> '... 2 chains ...'; a 2-dup book -> '2 duplicate From types'
- `chains.text.can` CanMerge: chain True, unit True, cycle False, dup False; CanSplit: chain only
- `chains.text.offer` ChainsToOffer(all of BOOK_INTO_CYCLE, nil) = the chain only; with asked ['CHAIN:TX>TA>TB'] (case-insensitive) = empty
- `chains.marks.added` BOOK_CHAIN: StaticChainMarks = 2; Nodes[0].Marks and Nodes[2].Marks each hold 1 warning with the texts above, FromSyntax False; `#link` nodes have none
- `chains.marks.idempotent` second call returns 0, counts unchanged
- `chains.marks.after.migrate` a node already holding a migrate warning keeps it and gains the chain mark (2 marks)
- `chains.marks.hoist` `AddStaticWarningMark` twice with the same text on one node -> True then False, 1 mark

- [ ] Write the tests (RED: the unit does not exist -> tests build fails; then a stub returning nil/'' -> RED on behaviour)
- [ ] Implement; tests GREEN; editor builds
- [ ] Reindex, lint both scopes, `dl:ok` or fix
- [ ] Commit: `git commit -m "feat(convrules): RuleChains detection, texts, static marks (CHAIN-1 T1)" -- src/tools/convrules-editor/ConvRules.RuleChains.pas src/tools/convrules-editor/ConvRules.ValidateScope.pas src/tools/convrules-editor/ConvRules.Migrate.pas src/tools/convrules-editor/ConvRulesEditor.dpr src/tools/convrules-editor/tests/ConvRulesModelTests.dpr src/tools/convrules-editor/tests/inc/RuleChainTests.inc`

---

### Task 2: Merge composition (spec 5.4 A1-A11)

**Model:** sonnet. **Starts after:** Task 1.

**Files:** modify `ConvRules.RuleChains.pas`, `tests\inc\RuleChainTests.inc` (`TestRuleChainsMerge`).

**Interface additions:**

```pascal
type
  /// <summary>A planned merge of a chain's first stage through its later stages (spec 5.4).</summary>
  TChainMerge = record
    /// <summary>Index of the first stage's header; the replaced range is NodeIdx..LastIdx inclusive.</summary>
    NodeIdx : Integer;
    LastIdx : Integer;
    /// <summary>The replacement lines: the new header, the merge #note, then the body (trailing blank lines of the range kept at the end).</summary>
    NewLines: TArray<string>;
    /// <summary>Links / defaults / migrates rewritten through the next stage.</summary>
    Composed: Integer;
    /// <summary>Lines kept verbatim because the next stage does not map them.</summary>
    Carried : Integer;
    /// <summary>#note lines added (the leading merge note not counted).</summary>
    Noted   : Integer;
    /// <summary>'' or why the merge is refused (spec A11); then nothing else is valid.</summary>
    Problem : string;
  end;

/// <summary>Plan the merge of AChain (ckChain: compose stage 1 through stages 2..n; ckUnitChain: rewrite the adding line).</summary>
function MergeChainPlan(ABook: TRuleBook; const AChain: TRuleChain): TChainMerge;
/// <summary>Replace the planned range with the new lines (parsed through a scratch TRuleBook, nodes moved in). Returns the new header's node index, -1 when AMerge.Problem is set or the range is no longer there.</summary>
function ApplyChainMerge(ABook: TRuleBook; const AMerge: TChainMerge): Integer;
```

Block range: `LastIdx` = the node before the next `#convert` header (any, From-only too) minus a trailing run of file-scope directive / blank / comment nodes WHEN the block is the last one (so the trailer is untouched); for a non-last block the range ends at the next header - 1 (blank lines included and kept). "File-scope directive" = kinds rnkMigrate, rnkUse, rnkUnuse, rnkUseSwap, rnkDepth, rnkMapping.

Pairwise composition `Compose(P: lines of the current result, Q: block of the next stage)` produces the new body; apply it left to right. Rules A1-A8 verbatim from the spec; line matching on `LinkTo`/`LinkFrom`/`DefTo`/`IgnorePath` is `SameText` on the path text. The merge `#note` (A8) is the FIRST line after the header and counts the totals over all pairwise steps. Unit chain (A9): `NewLines` = the one rewritten adder line; `NodeIdx = LastIdx` = the adder.

`ApplyChainMerge`: `LoadFromString(string.Join(CRLF, NewLines))` into a scratch `TRuleBook`, `Extract` its nodes in order, delete `NodeIdx..LastIdx` from `ABook.Nodes`, insert the extracted nodes at `NodeIdx`. Dirty stays False on parsed nodes (the text differs from the snapshot, so the book is dirty by content).

**Tests (`TestRuleChainsMerge`):** book `MERGE_A` =
```
#convert TA -> TB, UnitB
#link Caption <- Text
#link Width <- W cast IntToStr
#link Color <- Col cast ToColor
#link Keep <- K
#default Flag = True
#default Gone = 1
#ignore Old
#migrate DoA -> DoB
#tag t1

#convert TB -> TC, UnitC
#link Title <- Caption
#link Width <- Width cast StrToInt
#link Colour <- Color
#ignore Keep
#ignore Gone
#default Extra = 2
#migrate DoB -> DoC, UnitC
#warn Title "check"
#tag t2
#migrate X -> Y
```
Checks:
- `chains.merge.header` NewLines[0] = '#convert TA -> TC, UnitC'; NewLines[1] starts '#note chain merge: TA -> TB (line 1) + TB -> TC (line 12) = TA -> TC;'
- `chains.merge.link.plain` contains '#link Title <- Text' (A2, no cast)
- `chains.merge.link.one.cast` contains '#link Colour <- Col cast ToColor' (Q's link has no cast; P's kept)
- `chains.merge.link.two.casts` contains '#link Width <- W' with NO cast, preceded by '#note chain merge: casts IntToStr then StrToInt on W cannot be composed -- pick one'
- `chains.merge.link.ignored` '#link Keep <- K' is gone; '#ignore K' present (A3)
- `chains.merge.default.ignored` '#default Gone = 1' gone; a '#note' naming Gone present (A5)
- `chains.merge.default.carried` '#default Flag = True' present verbatim (unmatched, carried)
- `chains.merge.default.q` '#default Extra = 2' present (Q's copied)
- `chains.merge.ignore.p` '#ignore Old' present
- `chains.merge.migrate.composed` '#migrate DoA -> DoC, UnitC' present; '#migrate DoB -> DoC, UnitC' absent; '#migrate X -> Y' present (A6)
- `chains.merge.q.rest` '#warn Title "check"' present after a line starting '#note chain merge: the lines below came from TB -> TC (line 12)'; '#tag t2' absent; '#tag t1' present
- `chains.merge.counts` Composed = 5 (`Title <- Text`, `Width <- W`, `Colour <- Col`, `#ignore K`, `DoA -> DoC`), Carried = 2 (`#default Flag` unmatched, `#migrate X -> Y` of Q), Noted = 3 (the casts note, the dropped-`Gone` note, the "lines below" note). Counting rule: Composed = A2 + A3 + A5-through-link + A6-composed; Carried = A4 + A5-unmatched + every non-composed `#migrate` (P's and Q's); Noted = every `#note` added except the leading A8 note. P's other lines (A7 first sentence) are copied and not counted.
- `chains.merge.range.non.last` merging in MERGE_A: NodeIdx 0, LastIdx 10 (the blank line before the second header is kept at the end of NewLines)
- `chains.merge.range.last.trailer` a book `#convert TB -> TC` / `#link a <- b` / `#convert TA -> TB` / `#link b <- c` / `#migrate M -> N`: the chain's first stage is the LAST block (index 2); LastIdx = 3 (the `#migrate` trailer stays)
- `chains.merge.apply` ApplyChainMerge returns 0; `Nodes[0].Kind = rnkConvert`, FromType 'TA', ToType 'TC', Units 'UnitC'; the second stage block is unchanged; `FindRuleChains` afterwards = 0 findings; `SaveToString` round-trips the new text
- `chains.merge.three.stages` `#convert TA -> TB` / `#link b <- a` / `#convert TB -> TC` / `#link c <- b` / `#convert TC -> TD` / `#link d <- c` -> header '#convert TA -> TD', contains '#link d <- a'
- `chains.merge.unit` BOOK_UNIT_SWAP -> NewLines = ['#useswap UnitA -> UnitC'], NodeIdx = LastIdx = 0; BOOK_UNIT_HDR -> ['#convert TA -> TB, UnitC']; BOOK_UNIT_USE -> ['#use UnitC']
- `chains.merge.refused` a chain whose stage node is no longer a header (book edited: `Nodes.Delete`) -> Problem <> '', ApplyChainMerge = -1, book unchanged
- `chains.merge.refused.kind` ckCycle / ckDuplicateFrom -> Problem = 'only a chain or a unit chain can be merged'

- [ ] Tests RED (stub returns Problem = 'not implemented'), implement, GREEN; editor builds; reindex; lint
- [ ] Commit `feat(convrules): RuleChains merge composition (CHAIN-1 T2)` with a pathspec

---

### Task 3: Split planning and stage-book text (spec 5.5 S1, S2)

**Model:** sonnet. **Starts after:** Task 1 (independent of Task 2).

**Files:** modify `ConvRules.RuleChains.pas` (add `ConvRules.BlockFile`, `ConvRules.BlockOps` to its uses), `tests\inc\RuleChainTests.inc` (`TestRuleChainsSplit`).

**Interface additions:**

```pascal
type
  /// <summary>Which headers go to which stage book (spec 4 "Stage").</summary>
  TChainSplit = record
    /// <summary>Stages[0] = header node indexes that stay (stage 1); Stages[k] = stage k+1, each in file order. Length 1 when nothing moves.</summary>
    Stages  : TArray<TArray<Integer>>;
    /// <summary>Per stage (same index): the #mapping names its blocks #apply, distinct, file order; [] for stage 1.</summary>
    Mappings: TArray<TArray<string>>;
  end;

/// <summary>Assign every winner a stage from AChains (ckChain only; other kinds and losers stay at stage 1).</summary>
function SplitChainPlan(ABook: TRuleBook; const AChains: TArray<TRuleChain>): TChainSplit;
/// <summary>'C:\x\Book.rules' + 2 -> 'C:\x\Book.stage2.rules'.</summary>
function StageBookPath(const ABookPath: string; AStage: Integer): string;
/// <summary>The text of one stage book: the '#depth N' line when ABook has a valid one, the #mapping groups named, then the blocks of AHeaderIdx verbatim (from SplitRulesBlocks of ABook.SaveToString), CRLF, trailing EOL.</summary>
function StageBookText(ABook: TRuleBook; const AHeaderIdx: TArray<Integer>; const AMappings: TArray<string>): string;
/// <summary>The source without the moved blocks: JoinBlocks(SplitOut(...)) of ABook.SaveToString -- preamble and trailer untouched.</summary>
function RemainingBookText(ABook: TRuleBook; const AMovedHeaderIdx: TArray<Integer>): string;
/// <summary>The status line after a split: 'Split 2 block(s) into Book.stage2.rules -- convert with Book.rules first, then Book.stage2.rules (check both on the Convert tab, in that order)' plus '; copied #mapping M1, M2 into the stage book' when any.</summary>
function SplitStatusText(const ABookPath: string; const AStageFiles: TArray<string>; AMoved: Integer; const AMappings: TArray<string>): string;
```

Block <-> header mapping: `SplitRulesBlocks(ABook.SaveToString)`; an `rbkConvert` block with `StartLine - 1 = header NodeIdx`. Stage assignment by fixed-point iteration over the chains' links (stage(R2) = max(stage(R1) + 1) over links R1 -> R2 from ckChain findings; roots 1; repeat until stable, at most Length(rules) rounds).

**Tests (`TestRuleChainsSplit`):**
- `chains.split.path` StageBookPath('C:\x\Book.rules', 2) = 'C:\x\Book.stage2.rules'; ('C:\x\Book.rules', 3) ends '.stage3.rules'
- `chains.split.stages.two` BOOK_CHAIN -> Stages = [[0], [2]]
- `chains.split.stages.three` the three-stage book of Task 2 -> [[0], [2], [4]]
- `chains.split.stages.shared` BOOK_SHARED -> [[0, 1], [2]]
- `chains.split.cycle.stays` BOOK_INTO_CYCLE -> Stages = [[0, 1, 2]] (Length 1): TA -> TB and TB -> TA are cycle members and stay at stage 1, so the chain running into them moves nothing; the UI then reports 'Nothing to split' (Task 4 item 8)
- `chains.split.dup.stays` BOOK_DUP -> [[0, 2]]
- `chains.split.mappings` a book with `#mapping M TEnum -> TC` / `#when ...`-free minimal form the model accepts (take the exact mapping syntax from `TestMappingModel` in the .dpr) in the preamble, stage-2 block `#apply M` -> Mappings[1] = ['M']; Mappings[0] = []
- `chains.split.text.depth` a book starting `#depth 3` -> StageBookText starts '#depth 3' + CRLF
- `chains.split.text.blocks` StageBookText(BOOK_CHAIN, [2], nil) = '#convert TB -> TC' + CRLF + '#link z <- x' + CRLF
- `chains.split.text.mappings` the mapping group lines appear between the depth line and the first block, once
- `chains.split.remaining` RemainingBookText(BOOK_CHAIN, [2]) = '#convert TA -> TB' + CRLF + '#link x <- y' + CRLF; with a trailer `#migrate M -> N` the trailer is still at the end
- `chains.split.roundtrip` RemainingBookText + StageBookText blocks = the original blocks (compare JoinBlocks of the original)
- `chains.split.status` the two exact strings from the summary

- [ ] Tests RED, implement, GREEN; build; reindex; lint
- [ ] Commit `feat(convrules): RuleChains split plan and stage-book text (CHAIN-1 T3)` with a pathspec

---

### Task 4: dialog, MainForm wiring, GUI driver (spec 5.2 M1-M4, 5.3, 5.4 A10, 5.5 S3-S6)

**Model:** omit (UI flow). **Starts after:** Tasks 2 and 3.

**Files:** create `ConvRules.ChainForm.pas`; modify `ConvRules.MainForm.pas`, `ConvRulesEditor.dpr`; create `tests\gui\drive-rule-chains.ps1`.

**`ConvRules.ChainForm`** (code-built like `ConvRules.QualifyForm`): `TChainForm = class(TForm)` with a `TListView` (vsReport, Checkboxes, one column 'Finding'), a word-wrapped `TLabel` reading 'convert-apply applies a book in ONE pass against the original source: a rule''s output is never matched by another rule.', buttons `&Merge` (ModalResult mrYes), `&Split` (mrNo), `&Keep` (mrCancel; Cancel = True). Public: `class function Run(AOwner: TComponent; const AChains: TArray<TRuleChain>; out AChecked: TArray<TRuleChain>): TModalResult;` -- fixable rows start checked, others unchecked and disabled (`ListView.Items[i].Enabled`... VCL has none: leave the checkbox and re-check `CanMerge/CanSplit` in `UpdateButtons`); `Merge.Enabled` = every checked row CanMerge and at least one; `Split.Enabled` = every checked row CanSplit and at least one. Form caption 'Rule chains'.

**MainForm:**
1. `RunScopedValidate` (`:7700`): after `StaticMigrateMarks(FBook);` add `StaticChainMarks(FBook);`.
2. `SaveBook` (`:8145`): `var LChains := FindRuleChains(FBook); var LChainText := ChainStatusText(LChains);` and append `' ' + LChainText` to `LSaveText` when not ''; keep `FLastSaveChains:= LChains` (new field) for the offer.
3. New fields `FChainsAsked: TArray<string>`, `FLastSaveChains: TArray<TRuleChain>`; clear `FChainsAsked` in `LoadText` (book replaced) -- find the one place every Open/New passes through (`LoadText`, `:7969` and the open path).
4. `DoSaveClick` and `DoSaveAsClick`: after a successful save call `OfferRuleChains(ChainsToOffer(FLastSaveChains, FChainsAsked))` -- NOT in `SaveBook`, so `ConfirmDiscard` (close / open) and `LowerBookForConvert` never show it (O3).
5. `OfferRuleChains(const AChains)`: exit when empty; `TChainForm.Run`; on mrYes -> `MergeChains(checked)`; mrNo -> `SplitChains(checked)`; always add every LISTED key to `FChainsAsked`.
6. Menu: `AddMenuCmd(FMnuConversion, 'Rule c&hains...', 'List the rule chains, cycles, duplicate From types and unit chains of the open book; merge or split them', DoRuleChains)` after `Con&vert...`; `DoRuleChains` = `TChainForm.Run(FindRuleChains(FBook))` with every finding (O4), same result handling.
7. `MergeChains`: for each checked chain in REVERSE node order (indexes shift): `MergeChainPlan`, if Problem -> collect; else `ApplyChainMerge`; then `SyncRawFromModel; RefreshRulesList; RefreshGrid;` select the first merged header (`FActiveHdr`), status 'Merged <n> chain(s): <paths> -- review the composed block, then Save' + problems. Record keys asked.
8. `SplitChains`: `SplitChainPlan(FBook, checked)`; when `Length(Stages) = 1` -> status 'Nothing to split: the checked chain(s) run into a cycle or a duplicate' and exit. For each stage k >= 2: `StageBookPath(FFilePath, k)`; text = `StageBookText(...)`; if the file exists, read it with `ReadTextDetect` and append through `SplitBlocksFor` + `ConcatBlocks` + `JoinBlocks` (duplicate headers -> add '; WARNING <file> already had <n> of these header(s)' as `WriteBlocksTo` does); write with `WriteTextAskingRaise(path, text, level, AskRaiseFn, LNewLevel, LBackup)` where `AskRaiseFn` is a `MessageDlg(SaveAskMessage(...), mtConfirmation, [mbYes, mbCancel], 0) = mrYes` like `TCurationForm.AskRaise`; a False return (cancel) before ANY write aborts the whole split with status 'Split cancelled -- nothing was written'. After all stage books are written: `LoadText(RemainingBookText(FBook, moved), FFilePath)` -- CHECK that `LoadText` keeps `FFilePath`, `FBookLevel`, `FSnapshot` semantics (read `LoadText` first; if it resets the snapshot, call the lower-level model reload instead) -- then `SaveBook(False)`; on False, status = 'Wrote <n> block(s) to <files>, but <book> could not be saved -- they now exist in BOTH files. <save error>'; on True, status = `SplitStatusText(...)`; `FConvertTab.RefreshBooks` is already called by `SaveBook`. The split needs `FFilePath <> ''` (a new unsaved book cannot be split: the Save As that precedes the offer gives it a path).
9. `.dpr`: add `, ConvRules.ChainForm in 'ConvRules.ChainForm.pas'` after the `ConvRules.MigrateForm` line (67).

**GUI driver `tests\gui\drive-rule-chains.ps1`** (`param([string]$Exe, [switch]$ProofNoChain)`; copy the `W` class and helpers from `drive-validate-scope.ps1`; fixtures under `%TEMP%\rulechains-<id>`; `$SLOW_SEC = 900`). Fixture `Chain.rules`:
```
#depth 2
#convert Bde.DBTables.TTable -> FireDAC.Comp.Client.TFDTable
#link TableName <- TableName
#convert FireDAC.Comp.Client.TFDTable -> FireDAC.Comp.Client.TFDMemTable
#link Name <- Name
```
`-ProofNoChain` drops the last two lines (and expects NO dialog, NO 'Rule chains:' in the status: the negative control that proves the checks can fail). Checks (names):
1. `main.window`
2. `save1.invoke` File|Save (touch the file's mtime back 2 h first, as validate-scope does); wait for `TEngineWaitForm` to close or 'Saved' in the status
3. `save1.status.chains` status matches 'Rule chains: 1 chain -- see marked rules'
4. `save1.dialog` a top-level 'Rule chains' window appears (WaitFor caption) within 60 s
5. `save1.dialog.row` its TListView has 1 item (LVM_GETITEMCOUNT 0x1004) whose text starts 'chain Bde.DBTables.TTable -> FireDAC.Comp.Client.TFDTable -> FireDAC.Comp.Client.TFDMemTable'
6. `save1.dialog.buttons` TButtons 'Merge', 'Split', 'Keep' present; Merge and Split enabled
7. `save1.keep` click Keep -> dialog gone
8. `save2.no.dialog` File|Save again -> status 'Saved' and NO 'Rule chains' window within 10 s (asked once)
9. `menu.reopens` Conversion|Rule chains... -> the dialog appears (O4), 1 row
10. `split.click` click Split
11. `split.stage.file` `Chain.stage2.rules` exists, text = '#depth 2' + CRLF + '#convert FireDAC.Comp.Client.TFDTable -> FireDAC.Comp.Client.TFDMemTable' + CRLF + '#link Name <- Name' + CRLF
12. `split.source` `Chain.rules` no longer contains 'TFDMemTable'; its `.Bak` exists
13. `split.status` status matches '^Split 1 block\(s\) into Chain\.stage2\.rules -- convert with Chain\.rules first, then Chain\.stage2\.rules'
14. `split.convert.tab` click the 'Convert' tab: the TCheckListBox lists 'Chain.rules' BEFORE 'Chain.stage2.rules' (LB_GETTEXT into a local buffer per the standing trap)
15. `merge.open` File|Open a second fixture `Merge.rules` (same text as Chain.rules) via the open dialog (`SaveDialogTo`-style helper on the '#32770' dialog, button '&Open')
16. `merge.save.dialog` File|Save -> the dialog appears, 1 row
17. `merge.click` click Merge -> dialog gone; status matches '^Merged 1 chain'
18. `merge.raw` Raw DSL contains '#convert Bde.DBTables.TTable -> FireDAC.Comp.Client.TFDMemTable' followed (after the A8 `#note`) by '#link TableName <- TableName' (P's link has no Q link on `TableName`: carried, A4); it does NOT contain a second '#link Name <- Name' inside the merged block (Q's unconsumed `#link` is dropped, A7) and does NOT contain a second '#convert Bde.DBTables.TTable'; the second block ('#convert FireDAC.Comp.Client.TFDTable -> ...' + '#link Name <- Name') is unchanged.
19. `merge.title.dirty` the caption / status shows the book unsaved (whatever the editor's dirty signal is -- read `BookIsDirty` usage; the window caption carries '*' if that is the convention, else skip this check with a reason)
20. `merge.save.no.dialog` File|Save -> 'Saved', no 'Rule chains' window in 10 s, status without 'Rule chains:'
21. `close.no.dialog` make the book dirty (add a `#tag x` through Raw DSL or skip), File|Exit -> 'Save changes' message -> Yes -> the editor closes WITHOUT a 'Rule chains' window (O3) -- use `Merge.rules` restored to the chain text first so a chain exists
22. `proof` with `-ProofNoChain`: checks 3-5 must FAIL (reported as the driver's own 'proof.*' PASS lines when they do)

- [ ] Build editor; run the driver by hand against a STAGED COPY of the pin (`ConvRulesEditor.exe` beside the pinned `drag-lint.exe`); fix until green; record the counts in the commit message
- [ ] Reindex, lint both scopes (`lint ConvRules.ChainForm.pas`, `lint ConvRules.MainForm.pas` per file; `lint-all`)
- [ ] Commit `feat(convrules): Rule chains dialog, Save offer, merge/split actions, driver (CHAIN-1 T4)` with a pathspec

---

### Task 5: docs, feature entry, ENGINE reply

**Model:** sonnet. **Starts after:** Task 4.

**Files:** modify `src\tools\convrules-editor\CLAUDE.md` (unit map: add the `RuleChains` / `ChainForm` line after the `QualifyFix` line 90, the `ValidateScope` line gains "+ `AddStaticWarningMark`"; test kit: add `drive-rule-chains.ps1 <n> -- rule chains on Save (-ProofNoChain)` with the real count from Task 4); modify `docs\CONVERSION-RULES.md` (one paragraph under the `#convert` row: "convert-apply is SINGLE PASS: every rule matches the ORIGINAL source; `#convert TA -> TB` + `#convert TB -> TC` leaves a TA as TB; the first rule per From type wins; a cycle swaps; ENGINE trace 2026-10-26, `docs\INBOX-engine-to-converter-chain1.md` -- ENGINE to confirm"); create `docs\wiki\convrules-editor-rule-chains.md` (what a chain is, the four kinds, the marks, the dialog, Merge rules A1-A9 in user words, Split and the stage-book order on the Convert tab with Move Up / Move Down, the ask-once rule, `Conversion > Rule chains...`); create `features\entries\convrules-rule-chains.json` via `featuregen add --id convrules-rule-chains --title "Rule chains (single-pass warning, merge / split)" --group component-conversion --owner CONVERTER --summary "ConvRulesEditor: marks #convert chains, cycles, duplicate From types and unit swap chains on Save; offers to merge TA -> TB -> TC into TA -> TC or to split the stages into .stage2.rules books" --intro "..." --wiki-page convrules-editor-rule-chains --surface "exe:ConvRulesEditor.exe > Conversion > Rule chains... ;; exe:ConvRulesEditor.exe > File > Save (offer)"`, then `featuregen normalise`, `featuregen build --all`, `featuregen verify --id convrules-rule-chains --by CONVERTER`, `tests\autotest\run_feature_registry_guard.ps1`; create `docs\INBOX-REPLY-chain1.md` (line 1 `<!-- dl:backlog status=open last-measured=2026-10-27 -->`) with spec section 7 E1-E4 as requests to ENGINE.

- [ ] Commit `docs(convrules): rule chains wiki, CLAUDE unit map, feature entry, CONVERSION-RULES single-pass note, ENGINE reply (CHAIN-1 T5)` with a pathspec including `features\generated\`, `docs\wiki\`, `WWW\help\dl\` outputs of the build

---

### Task 6: verify and whole-branch review

**Model:** omit. **Starts after:** Task 5.

- [ ] Build editor and tests; model run without engine = baseline + every `chains.*` line, 0 fail; model run WITH the pin's engine (`CONVRULES_TEST_ENGINE`) = its baseline + the same, 0 fail
- [ ] Run `drive-rule-chains.ps1` (normal and `-ProofNoChain`), `drive-validate-scope.ps1` (18) and `drive-save-encoding.ps1` (15) on the staged pin copy: the Save path changed; record counts
- [ ] Reindex; `lint-all --db <db> --enable multiple-statements-per-line,magic-literal,commented-out-code` over the branch's diff (`git diff --name-only <merge-base>..HEAD`), one `lint <unit>` per changed unit including `review-marker-stale` / `review-marker-unused`; remove any `dl:ok` whose finding no longer fires
- [ ] `tests\autotest\run_docs_sync_guard.ps1`, `run_feature_registry_guard.ps1`, `run_encoding_guard.ps1`
- [ ] Review the full diff against the spec (sections 5.4 / 5.5 line by line); reconcile the spec (step 8 of the loop) where the build deviated; commit `review(convrules): CHAIN-1 whole-branch review` with a pathspec
- [ ] Report: counts, commands, the open questions still open; do not merge or push (the controller merges after the owner's answers to Q1-Q8)
