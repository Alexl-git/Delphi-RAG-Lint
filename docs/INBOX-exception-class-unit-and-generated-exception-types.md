> # MEASURED 2026-08-16 (session 22). Design question 5 is ANSWERED: build it.
>
> The note said *"Measure the distinct-message count on ORM3 before committing to
> this -- if it is 400, the feature is wrong as stated."* Measured on
> `C:\Projects\DB\ORM3`, all `.pas`:
>
> | | count |
> |---|---|
> | `raise Exception.Create` sites, total text matches | 98 |
> | of which **commented out** and correctly excluded | **9** |
> | LIVE raise sites | **89** |
> | live sites with a static string literal | 87 |
> | live sites building the message from an expression | 2 |
> | **DISTINCT live messages** | **64** |
>
> **64, not 400.** The scope objection does not hold: this is a per-project unit
> of a few dozen classes, not hundreds. Stage 1 and Stage 2 are viable as stated.
>
> **Design question 1 (near-duplicates) is also much smaller than feared.**
> Normalizing (strip format specifiers and punctuation, lowercase, drop
> stopwords) takes 64 distinct messages to **63** -- exactly ONE collapsing pair,
> `'LookupAccountName failed: '` vs `'LookupAccountName failed: %s'`. So the
> normalization layer is still needed (that pair is precisely the
> `EInvoiceNotFound` / `EInvoiceWasNotFound` hazard, and it is real), but it is a
> small, testable component rather than the load-bearing risk the note assumed.
>
> **Method note, because it changes the number:** a naive text scan reports 98
> and is wrong by 10%. Nine of the matches are commented-out code
> (`// raise Exception.CreateFmt(...)`), and Pascal doubled-quote escapes
> (`'Can''t ...'`) truncate a naive literal extraction mid-message. Any
> implementation must read the AST, not the text -- the index already
> distinguishes these.
>
> **Not implemented, deliberately.** Design questions 2, 3 and 4 (static-prefix
> boundary, hierarchy, managed-block ownership) are untouched and still gate
> Stage 3. What changed is that the measurement which was blocking the decision
> now exists, and it points at "build Stage 1".

# INBOX -- a project exception-class unit, and generating exception types from messages

**Filed:** 2026-08-11, from the owner, while triaging the `lint-all` groups.
**Status:** feature request + design question. Not implemented.

## The problem it solves

Group D of the current `lint-all` is **220 findings** about exception handling:

| count | rule |
|---|---|
| 104 | `try-except-swallowed` |
| 72 | `bare-except` |
| 24 | `empty-except` |
| 19 | `raise-bare-exception` |

`raise-bare-exception` and much of `bare-except` share one root cause: the code
raises and catches **`Exception`** itself, because no specific type exists to use.
Telling a developer "don't raise the base class" without giving them a type to raise
instead is advice they cannot act on, so the finding is ignored -- the same failure
mode as any rule that is always wrong.

## The ask

**1. A per-project unit that declares the project's exception classes**, e.g.

```pascal
unit Micronite.Exceptions;

interface

uses
  System.SysUtils;

type
  EOutOfMemory      = class(Exception);
  EPipeClosed       = class(Exception);
  EInvoiceNotFound  = class(Exception);
```

drag-lint should know which unit that is (config key, e.g. `"exceptions_unit"`), so
it can:

* resolve whether a raised type is one of the project's own;
* suggest the right existing class instead of `Exception` at a `raise` site;
* add the unit to `uses` when it proposes a fix (`find-unit` already does this job).

**2. Optionally, generate the class name from the message text.** A site like

```pascal
raise Exception.Create('Invoice not found for customer ' + IntToStr(pId));
```

would yield `EInvoiceNotFound`, appended to the exceptions unit, **provided the name
is not already taken**. That last clause is the whole difficulty.

## Design questions to settle BEFORE building this

1. **Name collisions and near-duplicates.** "Invoice not found" and "Invoice was not
   found" must map to the SAME class, or the unit accumulates
   `EInvoiceNotFound` / `EInvoiceWasNotFound` / `EInvoiceNotFound2`. Needs
   normalization (stopwords, stemming, casing) plus a persisted
   message-pattern -> class-name map so the mapping is STABLE across runs. An
   unstable generator that renames classes between runs would be far worse than the
   status quo -- it rewrites source.
2. **Messages with runtime data.** Most raise sites concatenate values. The class
   name must come from the STATIC prefix only, and the generator has to decide where
   the literal ends and the data begins.
3. **Hierarchy.** Flat `class(Exception)` is easy but gives callers nothing to catch
   in groups. Better: a per-project root (`EMicroniteError = class(Exception)`) with
   generated classes descending from it, so `on E: EMicroniteError` becomes possible.
4. **Who owns the file.** If drag-lint appends to the unit it becomes generated code
   and needs the same managed-block discipline the doc engine uses
   (`drag-lint:auto BEGIN/END`), or hand-written entries will be destroyed.
5. **Scope.** Generating a class per distinct message could produce hundreds of
   types. A frequency floor (only messages raised from N+ sites, or only in
   non-test code) is probably required. **Measure the distinct-message count on
   ORM3 before committing to this** -- if it is 400, the feature is wrong as stated.

   > ### MEASURED 2026-08-17 (session 25). It is 42, not 400 -- the feature survives its own kill-criterion.
   >
   > Taken from the ORM3 `lint-all` report, reading each finding's source line:
   >
   > | | count |
   > |---|---|
   > | `raise-bare-exception` findings | **139** |
   > | of those, with a recoverable STRING LITERAL message | **80** |
   > | **DISTINCT message texts** | **42** |
   > | distinct messages raised from **2+ sites** | **12** |
   >
   > Most-repeated: `'This plan is set on the HUB screen'` (10 sites),
   > `'Internal Error: Unknown control mode='` (8), `'Z1.9: Wrong Call'` (5),
   > `'Statsman: Wrong Call'` (5).
   >
   > So a frequency floor of 2+ sites yields **12 classes**, and no floor at all
   > yields 42. Ruling 5 is answered: scope is not the obstacle.
   >
   > **The other 59 findings are the finding that matters here.** They carry no
   > string literal -- they are `Exception.Create(Format(...))`, a variable, or a
   > concatenation. **Stage 3 (generate a class per message) cannot serve them at
   > all**, which means the generated-class idea covers at best 80 of 139 sites
   > even before deduplication. Stage 1 (report which existing class fits) does
   > not care, because it matches on the RAISE SITE, not on the text. That is an
   > argument for shipping stage 1 and being sceptical of stage 3, and it was not
   > visible before counting.
   >
   > Rulings 1-4 still need the owner -- above all what *"fits"* means in stage 1
   > (normalized message match, or class-name match?), since normalization is only
   > spec'd for stage 3. The count no longer blocks that conversation.

## Suggested staging

| Stage | What | Risk |
|---|---|---|
| 1 | Config key naming the exceptions unit; `raise-bare-exception` reports which existing class fits, or says none exists | none, read-only |
| 2 | `--fix` rewrites `raise Exception.Create(...)` to an EXISTING project class + adds the `uses` entry | source rewrite, but human-chosen target |
| 3 | Generate NEW classes from message text into a managed block | needs 1-5 answered first |

Stage 1 alone probably converts most of the 19 `raise-bare-exception` findings from
un-actionable to actionable, and it cannot damage anything.

## Related

* `docs/AI-CODING-CONVENTIONS.md` -- conventions stated as the rule ids that enforce
  them; a project exceptions unit belongs there once this exists.
* The owner's standing rule: a finding count in the thousands is itself the defect,
  and every class ends with the CODE fixed or the RULE fixed --
  see the `feedback_lint_count_must_be_small` memory.
