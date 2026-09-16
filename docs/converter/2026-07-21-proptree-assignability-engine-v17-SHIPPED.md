# proptree Assignability Engine (v17 / proptree/2) — SHIPPED

- **Date:** 2026-07-21
- **Status:** ✅ SHIPPED to `Delphi-RAG-lint` main + **corpus is LIVE** (library DBs re-indexed at schema v17)
- **Supersedes (as the "what actually shipped" record):** the pre-implementation contract in
  `docs/converter/2026-07-20-proptree-assignability-engine-handoff.md`
- **Engine repo:** `C:\Projects\Delphi-RAG-lint` main, commits `0f187ab..faedcc6` (13 commits, pushed to origin)
- **Deployed engine exe:** `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe` (carries the v17 extraction)

---

## TL;DR for the editor team

`proptree` now emits **per-leaf assignability** so you only ever offer VALID assignment targets.
The JSON schema went `proptree/1 → proptree/2` (additive). Code against these four per-leaf fields —
they are the whole point of this work:

| field | type | meaning |
|---|---|---|
| `is_writable` | bool | a valid assignment TARGET requires `true`. Read-only leaves (`.Handle`-style, `ro` props, typed class consts) are `false`. |
| `visibility` | string | `"published" \| "public" \| "protected" \| "private" \| ""` (strict variants normalized to base). |
| `member_kind` | string | `"property" \| "field"`. |
| `type` | string | now the **class-accurate concrete** per-class type (see R3 below). |

**Back-compat is load-bearing — read the new fields with these defaults when absent:**
`is_writable` → **TRUE**, `visibility` → `""`, `member_kind` → `"property"`.
So the editor run against an old exe / un-re-indexed DB degrades to today's "show everything," never
to "hide every target."

---

## The consumer contract in practice

### Target surface — pass `--min-visibility`
`proptree --qname <Unit.TClass> --min-visibility <published|public> --format json --db <db>`

- **DFM conversion rule** → pass `published`. Yields only the DFM-streamable published surface
  (fields are never included here; deep public internals like `LookAndFeel/Painter/ViewInfo` drop out).
- **PAS conversion rule** → pass `public`. Adds public props **and public fields**
  (`member_kind="field"`), each still carrying its real `visibility`.
- No flag → emit ALL leaves (back-compat).

### R1 — writability (`is_writable`)
Backed by a new `symbols.prop_access` column (`ro`/`rw`/`wo`) extracted from each property's
`read`/`write` clause. `is_writable = (prop_access <> 'ro')`. Write-only (`wo`) is `is_writable=true`
(a valid TARGET; invalid as a SOURCE — the editor owns direction). Fields are writable except a typed
class constant (`false`).

### R2 — visibility (effective, most-derived)
A published redeclaration of a protected/public ancestor property reports `published`. Bare
redeclarations resolve via the ancestor walk.

### R3 — concrete polymorphic type (CLASS-ACCURATE — the load-bearing one)
A control's `Properties` (and any redeclared property) resolves to **that class's own most-derived
concrete type** and recurses into THAT. A wrong-class leaf never appears:
- `TcxCheckBox.Properties` → `TcxCheckBoxProperties`
- `TcxButtonEdit.Properties` → `TcxButtonEditProperties`
- `TcxTextEdit.Properties` → `TcxTextEditProperties`

So a `TcxButton` target pool can **never** contain `TcxCheckBoxProperties.*` leaves. Your `IsCastable`
and `convert-scaffold`'s auto-`#link` matching are correct by construction — no separate matcher needed.

### R4 — public fields as PAS targets
Public/published fields emit as `member_kind="field"`, `is_writable=true` (typed class const = false).
They appear under `--min-visibility public`, **not** under `published`.

---

## convert-scaffold now filters targets for you

`convert-scaffold` restricts auto-`#link` TARGETS to `is_writable=true` and the surface's visibility
bar, using the R3 concrete type for compatibility. New flag:

`convert-scaffold ... --surface <dfm|pas>`  (default `dfm`)

- `dfm` → only writable published properties (no fields).
- `pas` → writable published + public, including public fields.

So generated rule drafts are assignability-correct by construction. On a proptree/1 DB it degrades to
prior behavior via the defaults.

---

## Corpus state — READ THIS

The library DBs were **re-indexed at v17** and are now the live indexes:

| DB | symbols | prop_access | notes |
|---|---|---|---|
| `C:\Projects\.drag-lint\library-Win64.sqlite` | 2.35M | live (ro 88,743 / rw 79,572 / wo 365) | rebuilt, swapped in |
| `C:\Projects\.drag-lint\library-Win32.sqlite` | 2.35M | live (ro 88,750 / rw 79,569 / wo 365) | rebuilt, swapped in; `cxButtons.TcxButton` present |

- The previous indexes are preserved as `library-Win{32,64}.sqlite.bak` (rollback = reverse the rename).
- **Project DBs (ORM3, etc.) are NOT yet re-indexed at v17** — they read `prop_access=NULL` → `is_writable`
  defaults TRUE (correct back-compat, just not writability-aware) until their next index run. Instance
  resolution for a conversion still needs the ORM3 DB in the `--db` set.
- The 3-DB conversion invocation from the handoff is unchanged (ORM3 + library-Win64 + library-Win32).

---

## Verified end-to-end (real DevExpress, not fixtures)

`proptree cxCheckBox.TcxCheckBox`:
- `is_writable=false` on `ActiveProperties` / `IsChanging` / `VisibleCount`; `true` on `Caption` / `Checked` / `Enabled`.
- `Properties` → `TcxCheckBoxProperties` (recurses into checkbox-only leaves).
- public surface 4191 leaves → **published surface 1493** (2698 noise leaves dropped; 0 fields; all remaining writable).

`proptree cxButtons.TcxButton --min-visibility published` → 592 leaves, all writable; `Handle` correctly
absent at the published surface (protected/read-only, not DFM-streamable).

---

## Δ vs the 2026-07-20 handoff

- The handoff's **open R4 question is resolved:** public library fields need **no** re-index (71k were
  already indexed with visibility). Only **writability (R1)** required a re-index — done.
- One implementation nuance to know: an "add-write/drop-read" property redeclaration stores `prop_access='wo'`
  rather than a merged `rw`. `is_writable` is correct either way (both writable). Only relevant if you ever
  use `prop_access` to decide a valid SOURCE (readable) — a source-direction refinement is on the engine
  backlog. It does not affect target selection.

---

## Action items for the editor team

1. Code the To-side candidate pool against `is_writable` + `visibility` + `member_kind` with the
   back-compat defaults above.
2. Pass `--min-visibility published` for DFM rules, `public` for PAS rules.
3. Trust R3: no cross-class `Properties.*` leaf can appear, so no extra matching logic is needed.
4. Ensure your queries hit the **v17** library DBs (already swapped in). If you see `is_writable=true`
   everywhere on a class you expect read-only leaves on, you're likely querying a pre-v17 (project) DB.

Questions → ping the engine side (`Delphi-RAG-lint` main).
