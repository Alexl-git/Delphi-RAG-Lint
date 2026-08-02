# The ConvRules DSL -- design and reference

The rule language the **ConvRules editor** reads and writes: a line-based text file that
describes how a legacy Delphi component or form converts to a modern one -- BDE/Orpheus/
in-house controls of the 1990s to FireDAC and DevExpress today.

Companion documents:

* [`convrules-editor-manual.md`](convrules-editor-manual.md) -- how to drive the editor
  that authors these files.
* [`..\CONVERSION-RULES.md`](../CONVERSION-RULES.md) -- the ENGINE side: the `proptree`,
  `convert-scaffold`, `convert-validate` and `convert-apply` verbs that consume a rule
  book, and what applying one actually does to `.pas` and `.dfm` on disk.
* [`refind-corpus.md`](refind-corpus.md) -- the two Embarcadero reFind rule books we
  import verbatim, and an honest account of what the conformance test over them proves.

**Two parsers, one grammar.** The editor parses with `ConvRules.Model.pas`
(`TRuleBook.ParseLine`); the engine parses with `src\report\DRagLint.Convert.Rules.pas`.
This document describes the EDITOR's parser, which is the wider of the two -- it is where
`#mapping` and `#apply` were added, and the engine does not know them yet (see
[Known limits](#known-limits)). Everything else in the table below is recognised by both.

---

## What a rule book looks like

A rule book is a flat sequence of lines. Blank lines and comments are kept. `#convert`
opens a block; the lines under it until the next `#convert` (or end of file) are its body.
Unit directives and `#mapping` declarations are file-scope and normally live above the
first `#convert`.

```
#convert Vcl.Graphics.TFont -> Vcl.Graphics.TFont
#note sample rule-book for ConvRulesEditor -- edit in the visual editor
#link Color <- Color
#link Size <- Size : Round
#default Charset = 1
#ignore Handle
// a hand comment survives round-trip
; so does a semicolon comment
```

That is `convrules\sample.rules`, verbatim.

---

## The load-bearing design decisions

### 1. The model is FLAT -- one node per physical line

`TRuleBook` holds an ordered `TObjectList<TRuleNode>` with **exactly one `TRuleNode` per
physical line of the file**. There is no tree, and no construct introduces one.

The clearest case is `#mapping`. A mapping with three clauses is **three sibling nodes**
that share nothing but a `MapName`:

```
#mapping XYZButtonStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton
#mapping XYZButtonStyle #when Style = stOK     -> Default = True, ModalResult = mrOk
#mapping XYZButtonStyle #else                  -> ModalResult = mrNone
```

Three nodes, all `rnkMapping`, all `MapName = 'XYZButtonStyle'`. The declaration is the
one whose `MapFromType` is non-empty; every other one is a clause. Grouping by name
happens in the consumer (`ConvRules.Mappings`), never in the model.

Why flat:

* **Diffs stay readable.** Adding one `#when` is a one-line diff, not a re-indented block.
  Two people editing different clauses of one mapping do not conflict.
* **Round-trip fidelity is cheap.** A node that owns exactly one line can re-emit exactly
  that line (next section). A tree node would have to decide whitespace and ordering for
  its children, and would lose the original bytes doing it.
* **Every construct stays greppable and hand-editable.** `#mapping XYZButtonStyle` finds
  the whole mapping with one search, whatever file it lives in. A rule book remains
  something you can fix in Notepad when the editor is not to hand.

The editor's mapping window shows a mapping as one row per enum member, which is the shape
a human wants -- but that is a **view**, built by `MappingCasesOf` and unfolded again by
`BuildMappingNodes`. `TMappingCase` is documented as "a VIEW over the flat node model,
never a replacement for it".

### 2. Byte-exact round-trip for unedited lines

`TRuleNode.Emit` opens with:

```pascal
// Untouched lines round-trip verbatim.
if not Dirty then
  Exit(Raw);
```

`LoadFromString` never sets `Dirty`, so **load-then-save reproduces the file byte for
byte**. Only a node whose typed fields were edited is re-serialised, and then it is
written in the canonical spacing (`#link %s <- %s`, `A = 1, B = 2`, ...).

The benefit is that a diff of a rule book shows only what you changed. Reformatting noise
never buries a real edit, and a hand-written file you merely opened comes back unaltered.

**The honest cost -- say this out loud whenever a round-trip test is cited as evidence:**
because `Emit` short-circuits on `Dirty`, a load/save round-trip proves **nothing** about
field decomposition. It exercises `TStringList` line splitting, CRLF handling and the
trailing-newline convention, and nothing else. A parser that classified every line
correctly and a parser that parsed no fields at all pass that test identically.
[`refind-corpus.md`](refind-corpus.md) makes exactly this point about the imported
corpus, and the suite carries a separate test (`TestReFindCorpusReconstructs`) that marks
nodes `Dirty` on purpose so reconstruction is actually measured.

Which kinds can reconstruct at all:

| Reconstructs from parsed fields | Always returns `Raw` |
|---|---|
| `rnkConvert`, `rnkLink`, `rnkDefault`, `rnkIgnore`, `rnkRemove`, `rnkUnuse`, `rnkUse`, `rnkUseSwap`, `rnkNote`, `rnkMapping`, `rnkApply` | `rnkMigrate`, `rnkPcre`, `rnkComment`, `rnkBlank`, `rnkUnknown` |

The right-hand column is deliberate: those kinds are edited as raw text (the editor's
**Raw DSL** tab), so decomposing them would buy nothing and could only lose bytes.

### 3. It is a reFind superset -- and here is exactly how much of one

Embarcadero's **reFind** migration instruction files load as-is. Two of them ship in
`convrules\` as first-class rule books a user can open:
`FireDAC_Migrate_BDE.rules` (77 lines) and `FireDAC_Rename_Units.rules` (211 lines),
byte-identical to the RAD Studio 37.0 samples.

Both load with **zero `rnkUnknown` nodes** and round-trip byte-for-byte. That headline is
true and it is weaker than it sounds. The measured reality:

* **Real superset evidence is 9 lines out of 69** in the BDE corpus: 6 x `#unuse`,
  2 x `#remove`, 1 x `#remove DFM:` genuinely reconstruct from their parsed fields.
* **All 60 `#migrate` lines carry no parsed fields at all.** `ParseLine` sets
  `Kind := rnkMigrate` and stops ("content edited via Raw"), and `Emit` has no
  `rnkMigrate` branch. So every interesting form -- the wildcard receiver
  `#migrate Session.* -> FDManager.*, FireDAC.Comp.Client`, the qualified
  `#migrate TQuery:DataSource -> MasterSource`, the eleven-unit tails -- survives by
  **tolerance, not comprehension**. The model cannot mangle a tail it never parsed.
  A test (`refind.bde.migrate.notdecomposed`) pins 60/60 and fails on purpose if anyone
  teaches the parser to split `#migrate`, forcing this document to move with the code.
* **`rnkPcre` is an unanchored catch-all.** A non-`#` line is classified by
  `if Pos(' -> ', T) > 0`. No anchoring, no validation of either operand, no check for a
  second arrow. 197 of the 211 rename-corpus lines contain that substring -- exactly the
  "recognised" count -- so that file's clean result is explained by its line SHAPE, not by
  anything the grammar worked out. Prose containing " -> " would classify as `rnkPcre`
  just as happily.

Do not cite "0 unknown, byte-exact round-trip" as proof the DSL understands reFind. Cite
the 9 lines.

---

## Line taxonomy

`ParseLine` classifies every line into one `TRuleNodeKind`. It **never raises**: a line it
does not understand becomes `rnkUnknown` and is kept verbatim, never dropped.

| Line | Kind |
|---|---|
| empty or whitespace only | `rnkBlank` |
| starts with `//` or `;` (after trimming) | `rnkComment` |
| starts with `#` and the first token is a known directive | that directive's kind |
| starts with `#` and the first token is anything else | `rnkUnknown` |
| any other line containing ` -> ` | `rnkPcre` |
| anything else | `rnkUnknown` |

The directive keyword is the text up to the first space, lower-cased and compared for
**whole-token equality** -- so `#REMOVE` works and `#removex` is unknown. A directive with
no space at all (`#note` on its own) parses with an empty body.

---

## Directive reference

Twelve `#` directives, plus the bare PCRE line. This list is the parse dispatch of
`TRuleBook.ParseLine` in `ConvRules.Model.pas`, in source order.

### `#convert <From> -> <To>[, <unit>[, ...]]`

Opens a conversion block: everything until the next `#convert` (or EOF) belongs to it.

```
#convert Vcl.StdCtrls.TEdit -> Vcl.StdCtrls.TMemo
#convert Abcbtn.TabcToggleBtn -> cxButtons.TcxButton, cxButtons
```

Split on the FIRST ` -> ` (with spaces). Everything after the first comma on the right is
kept as one `Units` string -- a uses-add list for the target unit(s).
*Limitation:* if the ` -> ` is missing or unspaced, `FromType`/`ToType` stay empty. The
line still round-trips (it is not dirty), but the editor sees a block with no type pair.

### `#link <ToPath> <- <FromPath>[ : <CastFn>]`

The workhorse: one target property gets one source property. **Note the reversed arrow** --
read it "target gets source".

```
#link Color <- Color
#link Size <- Size : Round
#link Style.Active.Font.Size <- Font.Size
```

Split on the first ` <- `. The optional cast is taken from the LAST `:` on the right-hand
side, and only when the tail is a single bare identifier -- no space, no dot, no `<`.
*Limitation:* that heuristic is what stops a dotted path being mistaken for a cast; a cast
function whose name contains a dot cannot be expressed.

### `#default <ToPath> = <value>`

Set a target property to a literal when no source property maps to it.

```
#default Charset = 1
#default Caption = 'untitled'
```

Split on the FIRST `=`, so a value containing `=` survives. With no `=` the whole body
becomes the path and the value is empty.

### `#ignore <FromPath>`

Records that a source property is deliberately NOT mapped, and suppresses its
unmapped-property warning. The whole body is the path.

```
#ignore Handle
```

An `#ignore` counts as a decision: a block whose only body line is an `#ignore` is a real
rule and is **not** dropped on save (`TRuleBook.BlockMapsSomething`).

### `#remove <property>` / `#remove DFM: <property>`

Remove a property. The plain form removes it from both `.pas` and `.dfm`; the `DFM:`
prefix (matched case-insensitively) restricts it to the `.dfm`.

```
#remove SessionName
#remove DFM: Origin
```

### `#use <unit>`

Add a unit to the target `uses` clause. The whole body is the unit name.

### `#unuse <unit>`

Remove a unit from the `uses` clause. reFind's own directive, adopted verbatim.

```
#unuse BDE.DBTables
```

### `#useswap <Old> -> <New1>[, <New2> ...]`

Replace one unit with one or more. Exactly `#unuse Old` + `#use New1` + `#use New2` ...

```
#useswap FOLDERDEF -> imcFOLDERS
#useswap BDE.DBTables -> FireDAC.Comp.Client, FireDAC.Stan.Def
```

Split on the first ` -> `; the right side splits on plain commas with blanks dropped.
Unit directives are **file-level** -- they may live outside any `#convert` block, and the
editor deliberately inserts them above the first `#convert` header so a trailing
incomplete block cannot swallow them.

### `#migrate [<Class>:][<obj>.]<old> -> <new>[, <unit> ...]`

reFind's identifier-level rename. Recognised, **not decomposed**: the node is classified
`rnkMigrate` and its content lives in `Raw` only, edited through the Raw DSL tab.

```
#migrate TTransIsolation -> TFDTxIsolation, FireDAC.Stan.Option
#migrate TQuery:DataSource -> MasterSource
#migrate Session.* -> FDManager.*, FireDAC.Comp.Client
```

*Limitation:* because nothing is parsed, the editor cannot validate a `#migrate` line, and
`Emit` returns `Raw` for it whether or not the node is dirty.

### `#note <text>`

A human comment carried inside the rule book (as opposed to a `//` comment, which is
outside the grammar). `convert-scaffold` emits `#note candidates: ...` and
`#note DROPPED ...` lines.

```
#note Handle is an OS resource -- intentionally not mapped
```

A `#note` is annotation, not a decision: a block whose only body line is a `#note` is
treated as empty and dropped on save.

### `#mapping <Name> ...`

Declares or extends a named, reusable conditional rule. Three line forms; see
[`#mapping` and `#apply` in depth](#mapping-and-apply-in-depth).

### `#apply <Name>`

Pulls the named `#mapping` into the enclosing `#convert` block. The whole body is the
mapping name.

```
#convert XYZ.TXYZToggleButton -> cxButtons.TcxButton
#apply XYZButtonStyle
```

### `<pcre-search> -> <pcre-replace>` (the bare form)

Any non-`#` line containing ` -> ` is a raw PCRE find/replace, kept verbatim and handed to
the regex path untouched.

```
\bTTable\b -> TFDTable
```

*Limitation, stated again because it matters:* this is an **unanchored substring test**.
Neither operand is validated, a second arrow is not detected, and any prose containing
" -> " lands here rather than in `rnkUnknown`.

---

## `#mapping` and `#apply` in depth

`#link` maps one source leaf to one target leaf through a cast. Real conversions also need
*"this enum VALUE means these several target properties take these values"* -- and that
rule has to be written once and reused across a vendor's whole control family. That is
what `#mapping` is.

```
#mapping XYZButtonStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton, cxButtons.TcxBigButton
#mapping XYZButtonStyle #when Style = stOK     -> Default = True, ModalResult = mrOk
#mapping XYZButtonStyle #when Style = stCancel -> Cancel  = True, ModalResult = mrCancel
#mapping XYZButtonStyle #else                  -> ModalResult = mrNone

#convert XYZ.TXYZToggleButton -> cxButtons.TcxButton
#apply XYZButtonStyle
#convert XYZ.TXYZFunnyButton -> cxButtons.TcxButton
#apply XYZButtonStyle
```

### The three line forms

All three start `#mapping <Name>`; the name is what ties them together, and it is compared
case-insensitively everywhere.

**Declaration** -- `#mapping <Name> from <EnumType> to <Class>[, <Class> ...]`

Narrows the mapping to one source enum and one or more target classes, so it can be
validated on its own terms instead of once per applying block. `from ` and ` to ` are
matched case-insensitively; the ` to ` split takes the FIRST occurrence. The target list
is split on **top-level commas** -- a comma inside `()`, `[]`, `<>` or a quoted string does
not separate, so a generic target class such as `Unit.TList<A, B>` stays one entry.

`MapFromType` is what MAKES a node a declaration. A node carrying target classes but no
source type would be re-read as a clause and emitted as a malformed `#when`, so
`BuildMappingNodes` refuses to write one: no source type, no declaration line (and the
target classes go with it). `ValidateMappings` then reports every `#apply` naming that
mapping as undefined, which is the honest signal.

**`#when` clause** -- `#mapping <Name> #when <Path> = <Value> -> <sets>`

Fires when the source property at `<Path>` equals `<Value>`. The condition is split from
the sets on the first bare `->` (with or without surrounding spaces -- `#else -> x` has no
space to its left). The condition itself splits on its FIRST `=`. A `#when` with no `->`
keeps its condition and gets an empty set list.

**`#else` clause** -- `#mapping <Name> #else -> <sets>`

The unlisted remainder. A mapping has at most one meaningful `#else`; its presence turns
off the exhaustiveness warning entirely.

### The set list

`<ToPath> = <Value>[, <ToPath> = <Value> ...]`

* Split on **top-level commas** (same rule as the target class list).
* Each item splits on its **FIRST `=`**, so a value containing `=` survives whole.
* `ToPath` keeps its dots intact. `Style.ModalResult.Default` is ONE path, never segments
  -- multi-level target paths were already supported by the property tree and needed no
  new path model.
* An item with no `=` yields a bare path with an empty value.
* Values are stored as verbatim trimmed text. The model does not interpret or type-check
  them; that is `ValidateMappings`' job, advisory (below).

### `#apply` is deliberately NOT `#use`

`#use` already means "add a unit to the uses clause" (`rnkUse` / `rnkUseSwap` /
`rnkUnuse`). Overloading it would have made "pull in a mapping" and "pull in a unit" the
same word for two unrelated things. `#apply` is a separate directive with a separate node
kind, matched by exact directive equality -- there is no shadowing between the two.

### What an `#apply` does to the editor's view

Within a block that applies a mapping:

* A source property named by any `#when` of that mapping counts as **assigned**. The
  editor's grid shows `<conditional: N cases>` in its To column rather than leaving it
  blank, where N is one per `#when` on that path plus one for the mapping's `#else`.
* The target paths that mapping assigns are withheld from the unassigned To pool -- they
  ARE assigned, by the mapping rather than by a `#link`.
* Auto-Match skips such a row, and manual Assign refuses it outright: *"Blocked: `<path>`
  is already decided by an applied #mapping (N case(s))."*

A mapping is file-scope: `#apply` reaches across blocks, and `ConditionalFromPaths` is
therefore fed the whole book, not one block.

---

## Validation and severities

`ValidateMappings` (`ConvRules.Mappings.pas`) checks one block's context: the flat node
list, the block's To property tree, the source enum's members, and the block's To type.
Any of the last three may be absent, and an absent input **turns its checks off** rather
than reporting everything as broken -- an unknown tree is unknown, not wrong.

Six issue kinds:

| Kind | Severity | Means |
|---|---|---|
| `mikUndefined` | ERROR | an `#apply` names a `#mapping` that was never declared |
| `mikTargetMissing` | ERROR | a set target path is absent from the To class's tree |
| `mikTargetReadOnly` | ERROR | the target exists but cannot be assigned to |
| `mikToTypeNotDeclared` | ERROR | the block converts to a class the mapping never narrowed itself to |
| `mikBadLiteral` | **WARNING** | a `#when` fires on a value that is not in the member list supplied |
| `mikNonExhaustive` | **WARNING** | an enum member has neither a `#when` nor an `#else` |

**`MappingIssueIsWarning(AKind)` is the single source of that split.** Every consumer asks
it; nothing re-derives severity at a call site. The mapping editor reads it exactly once,
and the rule is additionally pinned by a `const array[TMappingIssueKind] of Boolean` in the
test suite, so a future kind added without a classification breaks the BUILD, not merely a
test. Callers gating an OK button let warnings through and stop on errors.

### Why a bad literal is only advisory

This one is worth spelling out, because "the literal is not a member of the enum" sounds
like a fact and is not.

The member list comes from the drag-lint index, and the index routinely cannot see the
enum:

* **Method-pointer and procedural types are not indexed at all.** `TNotifyEvent`,
  `TMouseEvent` and friends return zero rows -- a real extractor gap, filed separately.
* **A bare name resolves ambiguously.** `--name` is a SUBSTRING match, and several
  equally-ranked declarations routinely share a name: `TAlignment` has three,
  `TColor` two. The editor now prefers the VCL declaration on a tie and says which it
  used, but the tie is still a tie.

So the members handed to the check can belong to the wrong type, and a **correct** literal
can be flagged. Blocking a save on a check that may itself be wrong would make the editor
unusable against an imperfect index -- which is the normal case here, not the exceptional
one. `mikBadLiteral` is therefore **reported every time, shown, never silent, never
blocking**.

`mikNonExhaustive` is advisory for a different reason: mapping only the enum members that
matter and leaving the rest to the target's own defaults is authoring intent, not a defect.
It reports one warning per uncovered member, naming both
(`AlignMap: ecUpperCase has neither a #when nor an #else`).

---

## Known limits

Stated plainly so nobody files them as bugs, and so nobody believes the DSL does more than
it does.

1. **`convert-apply` does not evaluate `#mapping` / `#apply`.** Deferred by design --
   spec G6.1. The editor authors rules the engine cannot yet apply. Conditional
   application is genuinely new work: it must read EACH `.dfm` instance's own source value
   and select the matching case, where the existing `#default` is the same for every
   instance.

   The visible consequence today: the engine's parser
   (`src\report\DRagLint.Convert.Rules.pas`) recognises 12 directives and **not** these
   two, so `convert-validate` reports them as unknown. Saving a book that contains a
   mapping puts that on the editor's status bar, e.g.

   ```
   Saved my.rules (backup my.rules.bak). Validate: line 1: unknown directive: #mapping
   ```

   The file on disk is correct and complete; the message is the engine saying it has not
   caught up. (Measured 2026-08-02: `convert-validate` exits 1 and prints
   `line N: unknown directive: #mapping` / `#apply` for each such line.)

2. **`ValidateMappings` is never run over a whole book.** It is invoked only from the
   mapping editor, over the mapping being edited. A broken `#apply` in a block you never
   opened -- one naming a mapping that no longer exists, say -- reports clean.

3. **A `#convert` block whose body maps nothing is DROPPED on save.**
   `TRuleBook.BlockMapsSomething` rescues a block containing at least one `#link`,
   `#apply` or `#ignore`. A block whose body is only `#mapping`, `#default`, `#remove`,
   `#migrate`, `#note`, comments or blanks is treated as scratch and written as zero bytes,
   reported only as `(N empty rule(s) not saved)`. `#mapping` is excluded deliberately: it
   is a DECLARATION and maps nothing until an `#apply` names it. `#default` and `#remove`
   are pre-existing behaviour, not revisited.

4. **`#migrate` is recognised but never decomposed** (see above). No validation, no field
   editing, `Raw` only.

5. **The bare PCRE form is an unanchored ` -> ` substring test** (see above).

6. **A malformed directive line round-trips but does not survive an edit.** If the arrow
   is missing from a `#convert`, `#link` or `#useswap`, the typed fields stay empty. The
   line is preserved exactly as long as nothing marks the node dirty; editing it through
   the grid re-emits from the empty fields.

7. **`SplitTopLevelCommas` treats `<` as an unconditional opener** so generics survive; an
   unbalanced `<` therefore swallows the commas after it.

8. **`.castlib` enum blocks are unimplemented**, and the engine never reads `.castlib` at
   all -- see G6.2/G6.3 in the Phase G spec.

---

## Where things live

| | |
|---|---|
| Editor model / parser | `src\tools\convrules-editor\ConvRules.Model.pas` |
| Mapping fold, unfold and validation | `src\tools\convrules-editor\ConvRules.Mappings.pas` |
| Engine parser | `src\report\DRagLint.Convert.Rules.pas` |
| Rule books (shipped data) | `convrules\*.rules` |
| Tests | `src\tools\convrules-editor\tests\ConvRulesModelTests.dpr` -- 584 pass / 0 fail / 0 skip |

Doc and test must agree. If you change what one of the assertions above asserts, change
this document in the same commit.
