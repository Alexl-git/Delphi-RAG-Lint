# Spec: raise / handle TYPE facts (E-RAISE-HANDLE-FACT, wave 146 lane b5)

Date 2026-11-06. Status: phase 1 built on this branch, for owner review. Predecessor (shipped):
`docs\superpowers\specs\2026-10-26-extract-raise-handle-facts.md` in the main tree, merged as
eb4b2b11 / 3f602034 (1.36.0).

## 1. What the backlog row claimed, measured

The row says "raise/handle fact, too large, do it with the next bump". Half of that is stale:

* SITE fact: FIXED-already. `refs.kind` has raise / raise-expr / reraise / handle / handle-all since
  1.36.0; `enclosing_symbol_id` gives the routine; `usages` has raises/handles buckets;
  `ask exception-paths` joins by kind. Guard `run_raise_handle_refs.ps1` is green on the branch head.
* Measured on `src\cli\_D-RAG\drag-lint.sqlite`: handle 332, handle-all 194, raise 256, reraise 66.

What is still missing for the row's actual question, "which routine raises and handles which
exception TYPE":

| gap | measurement | effect |
|---|---|---|
| G1 a raise / handle row is never bound | `symbol_id` set on 0 of 588 rows; the co-located `read` on 201 of 256, the `type_use` on 34 of 332 | "which type" is a spelling; two EFoo in two units are one row group |
| G2 a re-raise has no type | `reraise` name_text is the literal `raise`, receiver_text '' (66 rows) | `on E: EFoo do raise;` reads as "re-raises something" |
| G3 `raise E` has no type | raise-expr name_text is the variable | `Doc.Facts` already maps it (from source), the index does not |
| G4 no set question | only `usages` (one name) and a chart per routine | "every routine that raises T", "every type routine R handles" needs hand SQL |

## 2. Options

* **A. Close the row, nothing more.** Honest, cheap; leaves G1-G4; the row's question stays a hand
  SQL over a spelling.
* **B. Fill the existing rows, add one read verb (CHOSEN).** No table, no column, no schema bump.
  Parser stamps the handler's type on the rows that lack it; a new resolver stream binds; a new verb
  reads. Rows << 1 % of refs, no new rows at all.
* **C. A derived `exception_facts` table.** Clean to query, but a schema bump, a second copy of the
  refs, a writer on every incremental path. Nothing needs it that a join cannot answer.
* **D. Escape analysis (what escapes R through its callees).** `ask exception-paths` draws that
  already, and Doc.Facts has `IncludeCalleeRaises`. Out of scope.

## 3. Chosen, phase 1

### 3.1 Extractor (`DRagLint.Parser.Delphi13`, fingerprint unit)

`reraise` and an identifier `raise-expr` that names the handler variable get `receiver_text` = the
type of the NEAREST enclosing `on .. do` (rhs of a qualified name, as the `handle` row spells it).
Unchanged: every kind, name_text, span and row count; `raise` / `handle` receiver_text (the qualifier).

| source | row | receiver_text |
|---|---|---|
| `on E: EFoo do raise;` | reraise raise | `EFoo` |
| `on EFoo do raise;` | reraise raise | `EFoo` |
| `on E: EFoo do raise E;` | raise-expr E | `EFoo` |
| `on E: EFoo do raise X;` | raise-expr X | '' |
| `except raise; end` | reraise raise | '' |
| `raise E;` outside a handler | raise-expr E | '' |

Implementation: `TWalkState` keeps a frame list of open handlers by byte range. Walk visits in source
order, so a frame whose end is before the current node is closed for good: no restore, no change to
Walk's recursion or its Exit paths.

Limit, documented: a `raise;` inside an anonymous method inside a handler is stamped with that
handler's type, though it runs later. Rare, and such a `raise;` is itself a defect.

### 3.2 Resolver (`DRagLint.Storage.SQLite` + `DRagLint.Index.CallResolver`, resolver surface)

New stream `ResolveExceptionTypeRefs`, after `ResolveTypeUseRefs`: `raise` and `handle` rows spelled
like an indexed type bind by `TCallResolver.ResolveExceptionType` (same lookup as type_use, identity
only, its own counters so TypeUseStats keeps its meaning). A library type a project DB does not hold
stays NULL; `on E: Exception` is the common case and is not an error. A qualified spelling declines,
as type_use does. New log line `calls      exception-types: N of M`.

Rows carry `symbol_id` beside a co-located read / type_use that already binds, so a reader that counts
refs by symbol sees a second row at the same position. Guarded in 5.E: rename, usages and find-usages
give the same answer before and after.

### 3.3 Read verb: `exception-facts`

```
drag-lint exception-facts --db <db> --target <routine> [--json]   types this routine raises and handles
drag-lint exception-facts --db <db> --name <Type>      [--json]   routines that raise or handle this type
```

One row per site: action (raises / raises-var / reraises / handles / handles-all), type as spelled,
type_qname when known, how the type is known, routine, file, line, col. `via`:

* `bound` the row's own symbol_id;
* `handler` the type came from the enclosing handler (3.1);
* `local` a raise-expr whose name is a local var / param of the routine (its Signature);
* `name` a unique indexed type of that spelling;
* `unknown` nothing: `raise MakeError(..)`, or a bare `except raise; end`.

A type not in the DB prints its spelling with an empty type_qname: not "unknown", not an error.
`--name` matches a reraise / handler-var raise by its stamped type too, and does NOT walk ancestry
(`on E: Exception` is not listed under EFoo). Ancestry is `ask exception-paths`' job. Read-only.

## 4. What a pre-bump DB answers

Rows from 1.36 on exist, so the verb answers; reraise types are '' and via stays `unknown` until the
re-parse, symbol_id NULL until the resolve pass. No fallback path: stale DBs are refused the way every
read verb refuses them.

## 5. Guards

`tests\autotest\run_raise_handle_refs.ps1` extended; expected.tsv re-pinned for receiver_text.
A. rows exact; B. controls; C. negatives (kept). New:
G. binding: raise/handle of a project type have symbol_id = that class; `Exception` stays NULL.
H. `exception-facts` raw JSON pinned, both directions, each `via`; positive control: the baseline
   engine has no such verb, a pre-stamp DB gives via=unknown on the reraise.
E2. rename dry run and `usages` on EFoo equal the baseline engine's (co-located bound rows).

## 6. Cost: measured, see REPORT.md of lane b5

No new rows. Index time and DB size measured with a `--rebuild` of the drag-lint project into a scratch
DB under 1 GB, baseline exe vs this branch.

## 7. Bump

Parser change = `DRAGLINT_EXTRACTOR_VERSION`; new stream = resolver constant + `tests\resolver-surface.txt`.
This lane bumps neither (lane rule): the integrator does, once. Red version guards are expected here.

## 8. What the owner can reverse

* Stamping re-raise type in `receiver_text`: a "receiver" is a stretch; the alternative is a new column
  and a schema bump. Chosen because a column for ~1 row per handler is not worth a migration.
* Binding the rows at all: drop the stream, the verb falls back to `name`.
* The verb name, and `--target` / `--name` over new flags (reused so CLI.pas gains no parser state).

## 9. Trigger for the parked LSP / editor notes

The 09-16 park fires on "exception-HANDLING fact lands". DEC-1 asked which one; both have now landed
(`Catches:` 2026-09-17, index kinds 1.36.0). LSP merge items A1, A3-A6 are delivered; A2 needs the owner
in a live IDE. See `LSP\LSP-BACKLOG.md` and lane b5's REPORT.md.
