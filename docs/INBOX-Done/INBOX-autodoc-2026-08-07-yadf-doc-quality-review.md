> **RETIRED to INBOX-Done/ on 2026-08-15.** SUPERSEDED by the autodoc work of sessions 17-19: YADF's three projects now converge to a stable fixed point, prose-derived Calls: entries went 150 -> 0, and fabricated exception crefs are fixed. A fresh review against the current output would be worth more than this one.
>
> Original note follows unchanged.

# INBOX: autodoc quality review against the YADF corpus -- overload-blind edges, a duplicated file row, and 81 empty doc elements

- **From:** YADF (Alexander Liberov) -- filed 2026-08-07
- **Affects:** autodoc fact generation (`Called from` / `Calls` / `<returns>` / `Complexity`),
  and index integrity (`files` table path keying).
- **Severity:** mixed. B1/B2/B6 are correctness. B3/B4/B11 are actively misleading text.
  B7-B10 are quality.
- **Evidence base:** `C:\Projects\YADF` at commit `ee08894`, index `C:\Projects\YADF\YADF.sqlite`
  (schema v19, built 2026-08-03 12:55, newer than every `.pas` -- so **not** a staleness artifact).
  89 autodoc blocks across 11 units, 951 `///` lines. Every case below is real, none constructed.
- **Related, already filed:** `INBOX-autodoc-returns-section-incomplete.md` (returns *under*-inclusion --
  B3 below is the opposite failure, over-inclusion) and
  `INBOX-harvest-swallows-preceding-banner-comment.md` (B9 is a surviving variant).

---

## What is already reliable (so it does not get changed by accident)

These were spot-verified against source and were **correct**:

| Fact | Check |
|---|---|
| `Reads:` / `Writes:` field lists | `TLineScanState.Reset` -> `Writes: InBrace, InParenStar, InString, Depth, ClampDepth`. All five, in source order, nothing spurious. |
| `Mutates: X (out)` | Correct on both out-param routines checked (`FormatSource`, `FormatPreservesContent`). |
| `Overload N of M` | `2 of 2` in both `YADF.Guard` and `YADF.Layout` -- correct, and notably it dedupes the duplicated file row that B6 describes. |
| `Covered by:` | 14 of 15 distinct names are genuine test procedures; transitive reachability, genuinely useful. (The 15th is B10.) |
| Marker balance / idempotency | 89 `BEGIN` / 89 `END`. The `ee08894` re-run replaced cleanly in place. |
| Encoding discipline | All emitted comments are pure 7-bit ASCII, CRLF, no BOM. Matches the project rule exactly. |

The `Reads`/`Writes`/`Mutates`/`Covered by` family is the strongest part of the output. The
call-graph family is where the problems are.

---

## B1 -- call edges are arity-blind: a 3-arg call binds to the 2-arg overload (CORRECTNESS)

`YADF.Layout.pas:5589-5594`, the 2-arg delegator:

```pascal
function FormatSource(const ASource: string; const AOpts: TYadfOptions): string;
var Reason: string;
begin
  Result := FormatSource(ASource, AOpts, Reason);   // <-- 3 arguments
end;
```

The index resolves that call site to the **2-arg** symbol -- itself:

```
symbols: id=18641 decl@96  impl 5589-5594  (const ASource; const AOpts): string
         id=18644 decl@113 impl 4984-5587  (const ASource; const AOpts; out ADeclineReason): string

refs+call_edges, enclosing_symbol_id=18641:
  line 5593: 'FormatSource' -> target_symbol_id = 18641   <-- WRONG, should be 18644
```

Consequences in the DB:

- **`id=18644` -- the 603-line function that IS the formatter -- records 0 callers.**
- `id=18641` records a phantom self-recursion.

Same shape in `YADF.Guard.pas`: the 2-arg `FormatPreservesContent` delegates to the 4-arg one,
and the emitted doc says `Calls: YADF.Guard.FormatPreservesContent` on the 2-arg overload,
reading as self-recursion.

**Ask:** resolve overloads by argument count (and ideally by parameter type) before writing
`call_edges.target_symbol_id`. Arity alone would fix every case in this corpus.

## B2 -- `Called from` / `Calls` ignore the resolved edges entirely (CORRECTNESS)

The generated text does **not** come from `call_edges`. It is derived from `refs.name_text`
grouped by `enclosing_symbol_id`, deduped by *(routine name, file basename)*.

Proof: resolved `call_edges` yield **2** callers for the name `FormatSource`. The doc lists **9**
(`5 shown + "(+4 more)"`). A name-text query returns 14 rows collapsing to exactly 9 distinct
(name, basename) pairs -- an exact match for what was emitted.

That is why both overloads received near-identical caller lists (overload 1 shows 9, overload 2
shows 8 -- the difference is only that self is excluded).

Consequences:
- Per-overload caller information is impossible to obtain from the docs.
- A routine appears as its own caller whenever a delegating overload pair exists.
- Any same-named routine anywhere in scope contaminates the list (see B5).

**Ask:** build `Called from` from `call_edges` once B1 lands, and disambiguate overloads in the
rendered text (append the signature or at least the arity).

## B3 -- `<returns> Observed:` aggregates the returns of NESTED routines (MISLEADING)

`YADF.Layout.pas:101`, on `function FormatSource(...): string`:

```
/// <returns>Observed: Length(InlineRenderRange(Tokens, G.OpenIdx + 1, G.CloseIdx - 1)); '';
///          Result + S[i]; Child; nil; True.</returns>
```

`FormatSource` returns a `string`. Those expressions belong to its nested helpers:

| Expression | Actually lives in |
|---|---|
| `Length(InlineRenderRange(...))` | nested `ParensContentInlineWidth()` @ line 5069 |
| `Result + S[i]` | nested `CurrentLineLeadingWS()` @ line 5089 |
| `Child`, `nil` | nested walker helpers returning `TGroup` |
| `True` | a nested `Boolean` predicate |

The implementation range 4984-5587 contains **15 nested routine declarations**, and their
`Result` assignments are all being attributed to the parent. A reader is told a `string`
function returns an `Integer`, a `TGroup`, `nil`, and `True`.

This is the mirror image of `INBOX-autodoc-returns-section-incomplete.md`: that one is
under-inclusion, this is over-inclusion. Both point at the same fix -- the `Result` collector
needs a scope boundary at nested routine declarations.

## B4 -- `Complexity:` reports two different scopes as one metric (MISLEADING)

`YADF.Layout.pas:108`: `Complexity: 24 (cyclomatic), 603 lines`

- `body_loc = 603` counts the **whole** implementation, nested routines included.
- `cyclomatic = 24` covers only the **outer shell**. The same 604-line range contains 109
  decision keywords (`if|while|for|case|and|or|except`), so 24 cannot be whole-body.

Two scopes, one line, no indication they differ. Either compute both over the same scope, or
label them (`cyclomatic 24 (outer body), 603 lines (incl. 15 nested routines)`) -- the second is
more useful, since "603 lines but complexity 24" is itself a meaningful signal about nesting.

## B5 -- `.private` archived copies are indexed and are indistinguishable in the output (SCOPE)

Five files under `.private` are in the index, including an archived pre-fork snapshot:

```
C:\Projects\YADF\.private\issue-1-d10.2.3\YADF.Layout.pas
C:\Projects\YADF\.private\issue-1-d10.2.3\YadfMain.pas
C:\Projects\YADF\.private\issue-1-d10.2.3\YADF.dpr
```

`.private\issue-1-d10.2.3\YadfMain.pas` shares **30 routine names** with the production
`YadfMain.pas`. Because attribution renders the **basename only**, `(YadfMain.pas)` in a doc
line can mean either file. In the `FormatSource` caller set, 5 of 14 rows came from the archive.

Here the (name, basename) dedupe accidentally hid the damage -- every archived routine also
exists in production, so the counts came out right. That is luck, not correctness: a routine
present *only* in the archive would be emitted as a phantom caller of production code, with no
way for a reader to tell.

**Ask:** two things, independently useful -- (a) an ignore-globs setting honoured by `index`
(`.private/**`, `**/*-Copy.PAS`, backup dirs), and (b) render a repo-relative path, not a
basename, whenever two indexed files share a basename.

## B6 -- the same file is indexed TWICE under two drive-letter casings (INDEX INTEGRITY)

The most consequential finding. `files` contains:

```
id=7    'C:\Projects\YADF\YADF.Layout.pas'    <-- current (post-autodoc line numbers)
id=161  'c:\Projects\YADF\YADF.Layout.pas'    <-- STALE   (pre-autodoc line numbers)
```

Same file, differing only in the case of the drive letter. Evidence they are different vintages:
`FormatSource` impl is `4984-5587` on id=7 and `4651-5246` on id=161 -- a 333-line shift, exactly
the doc comments autodoc injected.

Scale: **929 of 5,870 symbols (15.8%)** hang off these two rows -- YADF's largest unit is fully
double-indexed. Exactly one file is affected, so this is not systemic yet, but the mechanism is:

**Root cause:** the `files` path key is compared case-sensitively, so an index run launched with a
differently-cased path/cwd (`c:\` vs `C:\`, trivially produced by a shell, a script, or an IDE
plugin on Windows) **inserts a second row instead of replacing the first**.

Downstream damage: stale line numbers coexist with fresh ones in the same DB, so `context`,
`query`, and LSP goto/hover can land on wrong lines with no staleness warning -- the DB looks
freshly built because the *other* row is current.

**Ask:** canonicalize paths on write (upper-case the drive letter and normalize separators), add a
`UNIQUE` index on the normalized path, and ship a one-off dedupe migration -- silently
double-indexed corpora will already exist in the wild.

## B7 -- 81 empty doc elements (QUALITY)

| Element | Count |
|---|---|
| `<summary></summary>` | 39 |
| `<param name="X"></param>` | 40 |
| `<returns></returns>` | 2 |

Concentrated in `YADF.Options.pas` (26 empty summaries) and `YADF.OptionsFrame.pas`.

An empty element is **worse than an absent one**. Help Insight renders a blank tooltip, and any
"is the public surface documented?" check now passes cosmetically on a symbol that carries no
information. Preferred: omit the element when there is nothing to say, or emit an explicit
`<summary>TODO: describe.</summary>` that a lint rule can count.

## B8 -- the singleton `<!-- drag-lint:auto -->` marker is not a delimited pair (QUALITY)

Three occurrences with no matching `END`:

```
YADF.Layout.pas:103        (759 characters on one line)
YADFOT.Wizard.pas:33       (659 characters on one line)
YADF.OptionsFrame.pas:260  (66 characters)
```

Because it is unterminated, the content after it is not delimited for idempotent replacement --
the BEGIN/END contract that makes re-runs safe does not cover it.

Separately, **68 `///` lines exceed 120 characters** while the hand-written ones wrap at ~100.
The two above are extreme. Wrapping generated prose to the same width as the rest of the block
would make the diffs reviewable.

## B9 -- an implementation banner was hoisted onto the INTERFACE declaration (QUALITY)

`YADF.Layout.pas:103` attached this to the *interface* declaration of `FormatSource`:

> "Shared mutable state for the walker (in scope of the nested procs): Tokens - the lexed token
> stream ... Sb - StringBuilder for the rendered output. Cursor - next un-emitted token index ...
> PendingLabel - block-end label ..."

Every one of those is a **private local** of the implementation. The public API doc now documents
the internals. This is adjacent to `INBOX-harvest-swallows-preceding-banner-comment.md`, but note
it **survived the banner-harvest fix** shipped in `ee08894` -- so it is a distinct case: harvested
text crossing the implementation -> interface boundary, rather than a banner/prose boundary error.

**Ask:** never promote a comment found in the implementation section onto an interface
declaration's `<summary>`/`<remarks>`; or if it is genuinely wanted, route it to a separate
`<remarks>` on the implementation side only.

## B10 -- `Covered by` counts any routine in a test file as a test (QUALITY, minor)

`CodeChars` is listed as a coverer on three `YADF.LineScan` symbols
(`YADF.LineScan.pas:87`, `:120`, `:135`). It is not a test -- it is a local helper:

```pascal
// Test\GuardTest.dpr:143
function CodeChars(var AState: TLineScanState; const ALine: string): string;
```

**Ask:** require the `Test`/`Check` naming convention, or better, restrict to routines actually
registered/invoked by the test runner's entry point.

## B11 -- type references in declaration position are rendered as a fabricated "caller" (MISLEADING)

15 occurrences of the pattern `"<TypeName> caller (<unit>.pas)"`. Worst case
`YADF.Options.pas:31`:

```
/// Used by: TYadfEncoding caller (YADF.Options.pas)
```

That is the *entire* fact, and it conveys nothing -- "TYadfEncoding caller" is not a symbol that
exists. `TYadfEncoding`'s real uses are all **declaration sites**, which have no enclosing routine:

- `YADF.Options.pas:85` -- the record field `TYadfOptions.Encoding: TYadfEncoding`
- `YADF.Options.pas:160` -- `ParseEncoding`'s parameter type **and** its return type

Others: `TOptKind`, `TOptGetter`, `TOptSetter`, `TOptInfo`, `TGroupKind`, `TLineScanEvent`,
`TYadfIniStatusEvent`, `TYadfOptionsPersistPolicy`.

**Ask:** when a reference has no enclosing routine, name the real construct rather than
synthesizing one -- `Used by: field TYadfOptions.Encoding; ParseEncoding (parameter, return)`.
A type used only in declarations should say so, not claim a phantom caller.

---

## Suggestions -- what else would be worth emitting

Ordered by how much I would want them in YADF specifically.

1. **Overload disambiguation in every rendered edge.** Once B1 is fixed, print the arity or
   signature (`FormatSource/3`), otherwise a delegating pair stays unreadable.
2. **`<exception cref="">` -- currently zero are emitted.** The indexer can already see `raise`
   statements; the project's CDD standard explicitly asks for this tag. High value, and it is the
   one required tag that is entirely missing.
3. **Totals alongside truncation.** `(+53 more)` loses the count that actually matters. `(53 more,
   63 total)` turns it into a fan-out metric. Same for `(+3 more)` on caller lists -- fan-in is
   exactly the number a reader wants when deciding whether a change is safe.
4. **Separate "reads own field" from "reads unit-level/global var".** Currently `Reads:` merges
   them, and the global case is the one with thread-safety consequences.
5. **Explicit recursion marking.** `Recursive` / `Mutually recursive with X` as a first-class fact,
   rather than letting it fall out of a name collision (which is how B1/B2 manifested).
6. **Thread-safety and ownership facts in `<remarks>`.** The CDD standard calls for these. Some are
   mechanically derivable: touches global mutable state, touches a `TThread`/critical section,
   allocates and returns an object the caller must free (`returns_owner` is already a column and
   appears unused in the emitted text).
7. **Declared section (`interface` / `implementation`).** Already in the schema
   (`usable_from_other_units`); useful to state, since it defines the compatibility surface.
8. **`<seealso>` cross-links** between overloads and between a delegator and its target.
9. **Git-derived `since` version.** "First appeared in 1.0.9.0" is expensive for a human to
   determine and cheap for a tool that can read tags.
10. **A per-run summary artifact.** "N symbols documented, M skipped and why, K empty summaries
    emitted." B7 would have been caught by the generator itself.

---

## Reproducing all of this

```powershell
# B6 -- duplicate file rows and their symbol share
python - <<'PY'
import sqlite3, collections
con = sqlite3.connect(r"file:C:\Projects\YADF\YADF.sqlite?mode=ro", uri=True)
rows = con.execute("SELECT id, path FROM files").fetchall()
d = collections.defaultdict(list)
for i, p in rows: d[p.lower()].append((i, p))
for k, v in d.items():
    if len(v) > 1: print(v)
PY

# B1 -- the mis-resolved edge
#   expect: line 5593 'FormatSource' -> target_symbol_id 18641 (should be 18644)
SELECT r.start_line, r.name_text, ce.target_symbol_id
FROM refs r JOIN call_edges ce ON ce.ref_id = r.id
WHERE r.enclosing_symbol_id = 18641;

# B2 -- name-text set (9 distinct by name+basename) vs resolved edges (2)
SELECT DISTINCT s.name, f.path FROM refs r
JOIN symbols s ON s.id = r.enclosing_symbol_id
JOIN files f ON f.id = s.file_id
WHERE r.name_text = 'FormatSource';
```

```powershell
# B7 -- empty elements
Set-Location C:\Projects\YADF
(Select-String -Path *.pas -Pattern '///\s*<summary></summary>').Count            # 39
(Select-String -Path *.pas -Pattern '///\s*<param name="[^"]*"></param>').Count   # 40

# B11 -- fabricated callers
Select-String -Path *.pas -Pattern '\w+ caller \('                                # 15
```

Happy to re-run any of this against a fixed build -- YADF is a convenient corpus for it, since
the autodoc pass is committed (`95170f9`, `ee08894`) and the whole tree is under git, so a
regenerate-and-diff shows exactly what changed.
