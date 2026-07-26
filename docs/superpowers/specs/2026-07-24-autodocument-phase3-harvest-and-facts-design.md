# Auto-Document Phase 3 -- Comment Harvesting, Output Quality, and Four New Facts

- **Date:** 2026-07-24
- **Status:** APPROVED (brainstorm complete; ready for `writing-plans`)
- **Predecessors:** `2026-07-22-autodocument-phase2-analysis-facts-design.md` (Phase 2, shipped)
- **Schema impact:** `symbol_facts` v18 -> **v19** (four new columns)
- **Packaging:** ONE increment (all three workstreams in a single plan, single reindex at the end)

---

## 1. Motivation -- what the YADF rollout actually showed

Phase 2 shipped six analysis facts. On 2026-07-24 the engine was run for real against
`C:\Projects\YADF` (branch `experiment/drag-lint-autodoc`): `YADF.sqlite` was reindexed to
schema v18 (176 files / 5,587 symbols / **1,089 `symbol_facts` rows**) and
`document --apply` wrote **50 managed blocks** across 8 `.pas` files.

**The run was clean.** Declaration counts are byte-identical between `HEAD` and the working
tree in all 8 files, and every file remains strict 7-bit ASCII -- the `FindDocRegionAbove`
adjacent-declaration fix (`7c551f1`) holds on real code. The doc-block-collapse corruption
class is closed.

But the *output* exposed four quality problems and one large missed opportunity.

### 1.1 Fact yield across the 50 blocks

| Fact line | Count | Note |
| --- | --- | --- |
| `Called from:` | 49 | **every** entry carries a trailing ` ?` |
| `<summary></summary>` | **39** | empty stubs -- blank DocInsight tooltips |
| `Calls:` | 32 | |
| `Covered by:` | 27 | |
| `Observed:` / `Returns:` | 25 | |
| `Used in units:` | 6 | |
| `Complexity:` | 5 | |
| `Reads:` / `Writes:` / `Handles:` / `SQL:` / `Owns returned:` | **0** | |

### 1.2 The missed opportunity -- prose already exists, in the wrong place

A scan for routines whose declaration is directly preceded by a non-DocInsight `//` comment:

| Corpus | Candidates | In `interface` | In `implementation` |
| --- | --- | --- | --- |
| YADF (`*.pas`) | 121 | **1** | **120** |
| M2022 / ORM3 (293 files) | 273 | -- | -- |

Authors comment the **implementation**; DocInsight renders the **interface declaration**.
The prose is there, it is human-written, and the engine ignores it while emitting an empty
`<summary>` next to it. Real example, `YADF.Tokens.pas`:

```pascal
// True for a 7-bit ASCII letter (A-Z / a-z). Shared by the include-directive
// shield and unshield scans; deliberately ASCII-only (not Unicode-aware
// TCharacter.IsLetter) to match the lexer's directive-word grammar.
function IsAsciiAlpha(C: Char): Boolean;
```

Harvesting this beats synthesising a summary: it is genuine author intent, carries zero
hallucination risk, and converts legacy `//` prose into IDE tooltips -- the migration story
for a 1990s-era codebase.

### 1.3 Ownership yield

`returns_owner` is set on **7 of 1,089** fact rows (0.6%), and all seven live in the
DelphiAST dependency -- none in YADF's own eight documented files. `Owns returned:` therefore
rendering zero times is *correct*, not a render bug. But `YADF.Tokens.LoadTokensFromString`
returns `Result := TTokenList.Create` (the mined `Returns:` line proves the site was seen)
and still abstained. That is a yield question worth one investigation.

---

## 2. Scope

Three workstreams, one increment, one schema bump, one reindex.

0. **Uniform provenance marking + `document --strip`** -- foundational (§4.0, §4.0.1)
1. **Comment harvesting** -- new capability (§3)
2. **Output-quality fixes** -- render-time, no schema impact (§4)
3. **Four new fact kinds** -- schema v19 (§5)
4. **Documentation refresh, converter notification, and the Obsidian schema page** -- after
   implementation completes (§8 steps 6, 7 and 8). These are deliverables of this phase, not
   follow-ups.

Workstream 0 is foundational: harvesting's drift protection (§3.3) and exact tag removal
(§4a) both depend on the engine being able to identify its own output with certainty.

### Explicitly out of scope

- **Synthesised prose.** No LLM-authored or heuristically-invented summaries. Harvest real
  author text or emit nothing.
- **`<param>` harvesting.** Legacy comments rarely name parameters in a parseable form;
  guessing is exactly the hallucination risk being avoided. Empty `<param>` tags are omitted
  (§4a), not filled.
- **Narrow key/value fact storage.** Considered and rejected: `symbol_facts` stays wide and
  gains four columns. Accepted consequence -- a future fact kind repeats the migration and
  full-reindex cycle.
- **Loosening the ownership unanimity rule.** §4d is an investigation, not a mandate to relax
  the gate.
- **Resolver / call-graph accuracy (the "D5 gap").** The `?` saturation in §1.1 is a *symptom*
  of weak `call_edges` resolution in project DBs. Phase 3 changes how the marker is
  *rendered* (§4b), not how callers are resolved.

---

## 3. Workstream 1 -- Comment harvesting

### 3.1 Behaviour

For a documented symbol with **no hand-written `<summary>`**, look for an adjacent
non-DocInsight comment block and promote its text into a **managed** `<summary>` on the
interface declaration.

**Search order** (first hit wins, then stop):

1. The comment block immediately preceding the **interface declaration**.
2. The comment block immediately preceding the **implementation definition**.

Interface-side is preferred because it is unambiguously about the declaration; the
implementation side is where the volume is (120 of 121 in YADF).

### 3.2 Copy, never move

The original comment is **left exactly where it is**. Autodoc's safety contract is preserved:
outside the doc region it rewrites, the engine never deletes a source line -- no code, and no
ordinary comment, is ever removed. (Rewriting content *inside* a doc region is what the engine
already does; see §4a.) The accepted cost is that the prose exists in two places and can
drift; §3.3 makes that drift visible rather than silent.

### 3.3 Managed, with drift protection

The harvested summary is wrapped in the existing managed markers so a later run can refresh
it when the source comment changes:

```pascal
/// <summary><!-- drag-lint:auto -->True for a 7-bit ASCII letter (A-Z / a-z).</summary>
```

Refresh rules on a subsequent `document --apply`:

| Situation | Action |
| --- | --- |
| Summary still matches what the source comment yields | no change (idempotent) |
| Source comment changed, summary untouched by a human | **refresh** the summary |
| Summary edited by a human (differs from the harvest, markers still present) | **do not overwrite** -- report as drift |
| Markers removed by a human | treat as hand-written; never touch again |
| Source comment deleted, so the harvest now yields nothing | remove the managed summary (it is managed content that no longer has a source) and report it as drift |

Detecting a human edit is a string comparison between the stored managed text and a freshly
computed harvest. This reuses the existing drift path rather than adding a new mechanism.

### 3.4 Acceptance guards

Conservative in the Phase-2 house style -- **absence over wrong**. A candidate comment block
is REJECTED when any of these hold:

| Guard | Rule | Rationale |
| --- | --- | --- |
| **Boundary scan** (see §3.4.1) | The candidate is every comment line between the declaration and the previous real code. Blank lines do **not** break the scan. | Authors routinely leave a blank line between a comment and the routine it describes; a strict-adjacency rule would silently skip them. |
| **Banner** | The block is only separator punctuation (`// ----`, `// ====`, `// ****`), or its sole non-punctuation content is a section title | Section banners describe a region, not a symbol |
| **Commented-out code** | Any line contains `:=`, or matches `\bbegin\b` / `\bend;`, or ends in `;` | Legacy Pascal is full of disabled code; promoting it into a tooltip is worse than nothing |
| **Trailer** | The block closes the *preceding* routine -- decided by the whitespace tie-breaker in §3.4.1 | Avoids attributing a trailing note to the next symbol |
| **Empty** | After stripping comment markers the text is whitespace-only | Nothing to promote |

Both `//` line-comment runs and `{ }` / `(* *)` block comments are accepted sources.
A `{ }` source block must not contain `{` or `}` in its promoted text (Pascal comments do not
nest) -- such a block is rejected.

### 3.4.1 The boundary scan

Scan **upward** from the declaration line, accumulating comment lines and blank lines. Stop at
the first line of real code. Everything accumulated is the candidate block; if it spans several
comment paragraphs separated by blanks, they are treated as one candidate and split per §3.5.

The scan stops at any of: another declaration (`function` / `procedure` / `constructor` /
`destructor` / a field or property), `end;` or `end.`, `begin`, a section keyword (`type`,
`const`, `var`, `resourcestring`, `threadvar`), a unit-structure keyword (`interface`,
`implementation`, `initialization`, `finalization`, `uses`), or any other non-comment,
non-blank line. Start-of-file also terminates the scan.

**Trailer tie-breaker.** When the scan stops at `end;`, the block is ambiguous -- it may close
the routine that just ended rather than introduce the next one. Resolve by whitespace:

| Layout | Reading |
| --- | --- |
| comment hugs `end;` (no blank between), blank line before the declaration | **trailer** -- reject |
| blank line after `end;`, comment adjacent to the declaration | **header** -- accept |
| any other combination | **header** -- accept |

This replaces the `Trailer` guard row above as the concrete decision procedure for the `end;`
case.

### 3.5 Text transformation

1. Strip comment markers (`//`, `{`, `}`, `(*`, `*)`) and normalise leading indentation.
2. Split into paragraphs on blank comment lines.
3. **First paragraph -> `<summary>`.** Remaining paragraphs -> `<remarks>` prose, emitted
   above the managed facts block inside the same harvest markers.
4. XML-escape via the existing `EscXml` (`<`, `>`, `&`).
5. Re-prefix every line with `///` using the multi-line emitter from `5ebde68` -- the fix that
   closed the original source-corruption bug. Interior newlines must never reach the file
   without a `///` prefix.
6. Preserve strict 7-bit ASCII and CRLF. A source comment containing a non-ASCII byte is
   rejected (it cannot be written back safely).

### 3.6 Placement in the pipeline

Harvesting is **document-time**, not index-time -- it must reflect the comment as it is *now*,
and it needs source text rather than index rows. It therefore lives in `DRagLint.Doc.Facts`
alongside the lazily-computed covered-by path, and is invoked from the same place that
assembles `TDocFacts`.

---

## 4. Workstreams 0 and 2 -- Provenance and output quality

All of these are render-time changes in `DRagLint.Doc.Regions` (plus one investigation). None
requires a reindex.

### 4.0 Uniform provenance marking (foundational)

Today the engine records ownership of its own output **three different ways**, and for one tag
not at all:

| Emitted tag | Current provenance mechanism |
| --- | --- |
| facts block | `<!-- drag-lint:auto BEGIN -->` / `<!-- drag-lint:auto END -->` region markers |
| `<param>` | trailing `<!-- drag-lint:auto param -->` marker |
| `<returns>` | **content sniffing** -- `StartsText('Observed:')` (LATEST-60) |
| `<summary>` | **none** |

Consequences: a human who happens to begin a `<returns>` with `Observed:` has it silently
adopted as managed; an engine-emitted `<summary>` is indistinguishable from a hand-written
one; and the 39 empty stubs in YADF cannot be attributed to anyone.

**Rule: every tag the engine emits carries exactly one provenance marker**, in a single
uniform form, immediately after the opening tag:

```pascal
/// <summary><!-- drag-lint:auto -->True for a 7-bit ASCII letter (A-Z / a-z).</summary>
/// <param name="ASource"><!-- drag-lint:auto -->Source text to lex.</param>
/// <returns><!-- drag-lint:auto -->Observed: TTokenList.Create.</returns>
```

The marker is an HTML comment, so DocInsight tooltips do not render it. The facts block keeps
its BEGIN/END region markers -- it spans lines rather than wrapping one tag.

**The `StartsText('Observed:')` sniff is deleted, not kept as a fallback.** Only 12 `.pas`
files across two repos (drag-lint 4, YADF 8) contain any engine output, and YADF is being
reset (§8), so a compatibility window would cost more than it buys. Anything without a marker
is hand-written, full stop.

### 4.0.1 `document --strip`

A new mode that removes engine output and nothing else: every tag carrying the provenance
marker, and every `BEGIN`/`END` facts region. Hand-written tags, code, and ordinary comments
are untouched.

This is exact rather than heuristic precisely because of §4.0 -- which is why it replaces any
"remove what we believe drag-lint generated" cleanup. It is safe to run over harvested
summaries as well: harvesting copies rather than moves (§3.2), so the original comment is
still in the implementation and nothing is lost.

`--strip` also yields the strongest available round-trip test: **`strip` -> `apply` -> `strip`
must return the file to its pre-`apply` bytes** (§7).

### 4a. Omit empty tags

Emit `<summary>`, `<param name="X">` and `<returns>` **only when they have content** --
hand-written, harvested, or mined. Today the engine emits empty shells: 39 `<summary></summary>`
and a matching run of empty `<param>` tags in the YADF diff, which render as blank DocInsight
tooltips.

**Stop creating them, and remove the ones already there.** With §4.0 in place removal is
exact, not a guess: a whitespace-only tag **carrying the provenance marker** is engine output
and is dropped when the doc region is rewritten. A whitespace-only tag *without* the marker is
hand-written and is left alone -- a human may be holding the slot open deliberately.

The 39 stubs already in YADF predate §4.0 and carry no marker, so they are not covered by this
rule; they are removed by the `--strip` + re-apply reset in §8, which is what that reset is for.

A tag that has content is never removed, whatever its origin. All of this is confined to the
doc region and never touches code or ordinary comments (§3.2).

### 4b. Suppress the `?` marker when the list is uniform

`JoinRefs` (`DRagLint.Doc.Regions.pas`, ~line 331) appends ` ?` to any caller whose
`Confidence` is neither `''` nor `certain`. In YADF that fired on 49 of 49 entries, so the
marker distinguishes nothing and is pure noise.

New rule -- emit the marker **only when the list is mixed**:

- all entries certain -> no markers (unchanged from today)
- all entries uncertain -> **no markers**
- mixed -> markers on the uncertain entries (unchanged from today)

The existing ordering (certain entries before uncertain ones) is retained, so a mixed list
still reads plain-first. No new line, no legend, no flag.

### 4c. Correct verb for non-routine symbols

For a symbol that is not callable (type, record, class, interface, constant), `Called from:`
is the wrong verb -- those are usages. Render **`Used by:`** instead. The YADF diff shows
`TToken` (a record) with `Called from: YADF.Layout.NormalizeAssignSpacing ...`.

The reference list, ordering, `(+N more)` suffix and `?` rule (per §4b) are unchanged; only
the label is selected by symbol kind.

### 4d. Investigate the ownership yield

`returns_owner` fires on 0.6% of fact rows and abstained on
`YADF.Tokens.LoadTokensFromString` despite a `Result := TTokenList.Create` site being mined.

Approach: `superpowers:systematic-debugging`. Determine which gate in `AnalyzeReturnsOwner`
(`DRagLint.Doc.SymbolFacts.pas:1842`) rejects it -- the `Disposed` early-exit, an
`unknown` classification from `ClassifyReturnSite` on an aliased generic type
(`TTokenList = TList<TToken>`), or the `ResultIdx` lookup.

**Timeboxed.** Outcome is one of:

- a genuine bug -> fix it with a regression test;
- correct conservative behaviour, or a cause with no immediate fix -> **document the finding
  and defer the solution to the next cycle**. Do not hold Phase 3 open for it.

**The unanimity rule is not to be loosened as part of this task.**

---

## 5. Workstream 3 -- Four new fact kinds (schema v19)

### 5.1 Storage

```sql
ALTER TABLE symbol_facts ADD COLUMN mutates_params TEXT;
ALTER TABLE symbol_facts ADD COLUMN ui_affinity    TEXT;
ALTER TABLE symbol_facts ADD COLUMN touches        TEXT;
ALTER TABLE symbol_facts ADD COLUMN wiring         TEXT;
```

`schema_version` 18 -> 19, behind the existing `>=` version gate so a v18 database degrades
gracefully: the columns are absent, the fact lines are omitted, nothing renders wrong.

### 5.2 The four facts

| Column | Rendered line(s) | Derivation |
| --- | --- | --- |
| `mutates_params` | `Mutates: pReason (out), pList (var)` | AST: assignment-LHS and `Inc`/`Dec` targets that resolve to a `var`/`out` parameter of the routine. Closes the Phase-2 T4 deferred deviation. |
| *(derived, not stored)* | `Pure` | Render-time only: emitted for a routine with a body when `writes_fields`, `mutates_params`, `touches`, `sql_writes` and `sql_reads` are all empty. No column of its own -- it is a conclusion drawn from the others, so it cannot disagree with them. |
| `ui_affinity` | `UI thread only -- touches cxGrid1, Application` | AST: identifiers resolving to a VCL/DevExpress control type, or to `Application` / `Screen`. Emitted only on a positive finding -- never a "thread-safe" claim, which cannot be proven this cheaply. |
| `touches` | `Touches: file system, registry, network` and `Transaction: starts, commits` | AST: call targets matched against a curated surface list (RTL file/registry/network units; FireDAC `StartTransaction` / `Commit` / `Rollback`). Categories, not call sites. |
| `wiring` | `Registered as: IFolderService (singleton)` and `Dataset: qryFolders -> FOLDERS (ID, NAME)` | A **join over already-indexed tables** -- `di_bindings` (interface/impl/lifetime), `orm_links`, `fb_relations`, `fb_columns`. No new AST analysis. |

### 5.3 Shared discipline (inherited from Phase 2, non-negotiable)

- Bounded and single-pass at index time; reuse `TAstParseCache.Get(AFilePath)`, do not add a
  third parse per file.
- **Omit when empty.** No fact line for an empty result.
- **Absence over wrong.** Under-report rather than emit a claim that might be false.
- Rendered through the single shared `TDocRegions.FormatPhase2FactLines`, so `document` and
  `hover` cannot drift.
- `--jobs` spawns separate child processes, so module-level memo caches cannot race.

### 5.4 Curated surface lists

`ui_affinity` and `touches` depend on name lists (control base types, RTL I/O units, FireDAC
transaction methods). These live as constants in `DRagLint.Doc.SymbolFacts` next to the
analyses that consume them, not in the manifest -- they are engine knowledge, not user
configuration.

---

## 6. Architecture

| Unit | Change |
| --- | --- |
| `DRagLint.Core.Model` | `TSymbolFacts` gains `MutatesParams`, `UiAffinity`, `Touches`, `Wiring` |
| `DRagLint.Doc.SymbolFacts` | `TSymbolFactsAnalyzer.Analyze` gains the four index-time analyses + the curated lists; `AnalyzeReturnsOwner` investigated per §4d |
| storage layer | schema 19 migration; `Get`/`Put` symbol-facts plumbing extended by four columns |
| `DRagLint.Doc.Facts` | new document-time comment harvester feeding `TDocFacts`; sits beside the lazy covered-by resolver |
| `DRagLint.Doc.Regions` | uniform provenance marking + deletion of the `StartsText('Observed:')` sniff (§4.0); empty-tag suppression (§4a); `JoinRefs` marker rule (§4b); kind-selected verb (§4c); harvest merge + drift compare (§3.3); four new fact lines in `FormatPhase2FactLines` |
| `DRagLint.Doc.Document` + CLI | new `--strip` mode (§4.0.1) |

The overall shape is unchanged from Phase 2: facts materialise at index time, one shared
formatter renders them for both `document` and `hover`, and the document writer only ever
appends.

---

## 7. Testing

Per-fact pattern established in Phase 2: **fixture -> index -> `document --unit --apply` ->
assert the rendered line**. Because the four new facts are index-time, every such test must
reindex after building the exe.

### Harvesting battery (new, the highest-risk area)

| Test | Asserts |
| --- | --- |
| interface-side harvest | comment above the declaration lands in `<summary>` |
| implementation-side harvest | comment above the body lands in the *declaration's* `<summary>` |
| precedence | interface-side wins when both exist |
| boundary scan | a blank-line-separated comment IS harvested; the scan stops at the previous real code and never crosses `end;` / `begin` / a section keyword / another declaration |
| trailer tie-breaker | comment hugging `end;` with a blank before the declaration is rejected; the reverse layout is accepted |
| banner rejection | `// -----` and section titles are NOT harvested |
| commented-out code rejection | a block containing `:=` / `begin` / `end;` is NOT harvested |
| trailer rejection | a comment closing the previous routine is NOT harvested |
| paragraph split | first paragraph -> `<summary>`, remainder -> `<remarks>` |
| XML escape | `<`, `>`, `&` in the comment survive |
| multi-line prefix | every emitted line carries `///` (guards the `5ebde68` corruption class) |
| non-ASCII rejection | a comment with a non-ASCII byte is NOT harvested |
| **idempotency** | `document --apply` twice produces a zero-byte diff |
| **human-edit drift** | edit the summary, re-run -> not overwritten, drift reported |
| hand-written summary wins | a symbol with a real `<summary>` is never harvested into |

### Provenance and strip tests

- every engine-emitted `<summary>`, `<param>` and `<returns>` carries exactly one provenance
  marker; the facts block keeps its BEGIN/END region markers
- a hand-written `<returns>` beginning with `Observed:` is **not** adopted as managed (the
  deleted `StartsText` sniff must not regress)
- `--strip` removes every marked tag and every facts region, and nothing else -- hand-written
  tags, code and ordinary comments are byte-identical afterwards
- **round trip:** `strip` -> `apply` -> `strip` returns the file to its pre-`apply` bytes
- `--strip` on a file with no engine output is a no-op (zero-byte diff)

### Output-quality tests

- empty `<summary>`/`<param>`/`<returns>` are not emitted
- a whitespace-only *marked* tag is removed on rewrite; a whitespace-only *unmarked* tag
  survives; a tag with content is never removed
- `?` markers: all-certain -> none; all-uncertain -> none; mixed -> markers on the uncertain
- a record/type renders `Used by:`, a routine renders `Called from:`
- §4d yields either a regression test (bug) or a documented rationale (correct abstention)

### Regression

The existing **31-test autodoc + hover battery must stay green**, and the doc/hover
consistency assertions must cover at least one of the four new facts.

---

## 8. Rollout

1. Build the CLI (`build/build_draglint_win64.bat`, `Start-Process -Wait`, `BUILD_EXITCODE=0`).
2. Reindex all 9 manifest DBs to v19. **Wire `--jobs` together with `--config`** -- LATEST-62
   ran this sequentially at roughly 3h per platform because `--jobs` needs `--config`;
   parallelising it is part of this rollout, not a follow-up.
3. Reindex `YADF.sqlite` (already v18) and `YADFOT.sqlite` (**still v17** -- never refreshed).
4. **Reset YADF, then re-apply.** On branch `experiment/drag-lint-autodoc` in `C:\Projects\YADF`:
   1. Run `document --strip` over the project to remove the 50 pre-§4.0 managed blocks. Because
      those blocks predate uniform marking, verify the result against `HEAD` -- the stripped
      tree should differ from `HEAD` only by the 14:54 self-format changes. Any residue is a
      `--strip` bug and must be fixed before proceeding.
   2. **Keep YADF's hand-written DocInsight.** `YADF.Guard.pas` in particular carries authored
      `<summary>` / `<param>` / `<returns>` / `<remarks>`; that prose is the control group for
      "hand-written wins", the merge-into-existing-`<remarks>` path, and the drift detector.
      Deleting it would remove the most valuable test surface in the corpus.
   3. Re-run `document --apply` and review the diff. Expect: no blank stubs, no `?` markers,
      `TToken` reading `Used by:`, hand-written summaries untouched, and a large share of the
      120 implementation-side comments promoted into summaries.
5. Version bump off `1.2.1-alpha` (`src/cli/DRagLint.CLI.pas:6`) + `pack-lint-release.ps1`.

6. **Refresh the documentation** -- after all implementation is done, not alongside it, so it
   describes what actually shipped rather than what was planned:

   | Document | Update |
   | --- | --- |
   | `docs/INDEX-SCHEMA.md` | v18 -> **v19**; section 2.15 (`symbol_facts`) gains the four new columns with their value formats; refresh the stated counts |
   | `CHANGELOG.md` | Phase 3 entry: provenance marking, `--strip`, comment harvesting, the four render fixes, the four new facts, schema v19 |
   | `docs/AI-USAGE.md` | the `document` verb section: new `--strip` mode, the harvesting behaviour and its guards, the provenance-marker contract (what the engine owns vs. what a human owns) |
   | CLI `--help` | `--strip` and any new `document` switches |
   | unit banner comments | `DRagLint.Doc.SymbolFacts` (the four analyses + curated lists), `DRagLint.Doc.Regions` (the provenance contract), `DRagLint.Doc.Facts` (the harvester) |

   The DocInsight rule applies to every new public declaration added by this phase.

7. **Notify the component-conversion workstream.** Write
   `docs/INBOX-index-schema-v19-reindex-for-converter.md`, following the structure of the v18
   message (`docs/INBOX-index-schema-v18-reindex-for-converter.md`, acked in
   `docs/INBOX-REPLY-converter-v18-ack.md`). It must state:

   - **schema 19 = 18 + four additive columns** on the existing `symbol_facts` table
     (`mutates_params`, `ui_affinity`, `touches`, `wiring`). Nothing removed or renamed; the
     gate stays a `>=` check. A consumer issuing `SELECT *` against `symbol_facts` will see
     four extra columns -- select by name if that matters.
   - **`symbols.id` is reassigned again** by the full reindex. Re-resolve by
     `qualified_name`; do not trust cached ids. This bit the converter last time and is the
     single most important line in the message.
   - **Which DBs were rebuilt** to v19 and their `schema_version`, including `YADF.sqlite` and
     `YADFOT.sqlite` (the latter was still on v17 before this phase).
   - **`wiring` may be directly useful to the converter** -- it surfaces Spring4D DI bindings
     and dataset-to-table links that the conversion analysis already cares about.
   - **The `document --strip` verb now exists**, and the provenance-marker contract that makes
     it exact -- relevant to anyone whose tooling reads or writes DocInsight comments.
   - A short "not relevant to the converter" context section, as in the v18 message.

8. **Record the DB structure in the Obsidian wiki.** No schema page exists there today, so
   this is a **new** page: `C:/Projects/claude-obsidian/wiki/entities/DragLint_Index_Schema.md`,
   written per the `obsidian-markdown` skill (frontmatter, `[[wikilinks]]`, `related:`).

   Content: the v19 table inventory with each table's purpose and key columns -- `symbols`,
   `files`, `refs`, `call_edges`, `symbol_docs`, **`symbol_facts` (all 14 columns)**,
   `type_ancestors`, `type_helpers`, `unit_uses`, `di_bindings`, `orm_links`, `fb_*`,
   `string_literals` + the `string_fts*` FTS5 shadow tables, `compiler_findings`,
   `symbol_trigrams`, `schema_meta`. Note the schema-version history (17 -> 18 `symbol_facts`
   -> 19 four columns) and the `>=` gate contract.

   `docs/INDEX-SCHEMA.md` in the repo stays the authoritative reference; the wiki page is the
   cross-project view for work that spans repos, and links to it. Link it from
   [[DragLint_Linter]] and update `wiki/index.md` + `wiki/hot.md`.

---

## 9. Risks

| Risk | Mitigation |
| --- | --- |
| **Harvesting writes prose into source for the first time** | copy-never-move; adjacency-only; banner / commented-out-code / trailer / non-ASCII rejection; drift-never-overwrite; idempotency test |
| A rejected-but-legitimate comment is silently skipped | Accepted. Absence over wrong -- the guard set is deliberately conservative and can be relaxed later on evidence. |
| **`--strip` removes hand-written documentation** | Removal is keyed to the provenance marker (§4.0), never to content. Locked by the round-trip test and by the `HEAD` comparison in rollout step 4.1. Git is the backstop -- strip only ever runs on a branch. |
| The boundary scan over-reaches and harvests a section banner or a trailer | The stop-set (§3.4.1) halts at `implementation`, section keywords and `end;`; the banner guard and the trailer tie-breaker cover the rest. Each has a dedicated test. |
| v19 reindex is a multi-hour operation across two large library DBs | Parallelise via `--jobs` + `--config` (rollout step 2) |
| Wide-table choice defers cost to a future fact kind | Accepted explicitly (§2, out of scope) |
| `ui_affinity` / `touches` curated lists go stale | Positive-finding-only rendering means a stale list under-reports; it never emits a false claim |

---

## 10. Follow-ups (not in this increment)

- Resolver accuracy for the `?` saturation root cause (qualified constructors, generic
  members, interface dispatch) -- the D5 milestone.
- `<param>` text harvesting, if a parseable convention is found in a real corpus.
- Narrow key/value fact storage, if fact kinds keep growing.
- Hover/doc consistency fixtures for the remaining facts not yet consistency-asserted.
- YADF's own formatter reindented implementation-section comments during its 14:54 self-format
  run (`YADF.Tokens.pas`: the `IsAsciiAlpha` banner is now indented under `const`). That is a
  **YADF** issue, recorded here only because it shares the working tree.
