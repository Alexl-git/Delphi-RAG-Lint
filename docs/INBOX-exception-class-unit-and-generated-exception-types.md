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
