> **RETIRED to INBOX-Done/ on 2026-08-15.** FIXED (session 17 case-dataflow work). Guarded by tests/autotest/run_case_dataflow.ps1, green in the full battery.
>
> Original note follows unchanged.

# Dataflow: `case` selector reads and `case..else` assignments are both invisible

Filed 2026-08-12 from the YADF zero-findings pass. Two rules, one root cause:
the dataflow engine does not see through a `case` statement. Both reproduce on
tracked YADF source at `C:\Projects\YADF` (commit `0c5b546`).

Class: **wrong** (the index answers, but incorrectly).

## 1. `write-only-local` misses a read in the case SELECTOR

    C:\Projects\YADF\YADF.Layout.pas:3325:3  [info] write-only-local:
      Local "curlinelast" is assigned but never read.

It is read. `YADF.Layout.pas:3512`:

    case CurLineLast of

Full occurrence list in that file: declared 3325; assigned 3489, 3520, 3541,
3781; **read 3512**. The read is the case selector expression, and only that.

So the rule appears to walk assignment targets and ordinary expression operands
but never visits the selector of a `case`.

## 2. `function-result-not-set` misses assignments in the `else` branch

    C:\Projects\YADF\YADF.Options.pas:593:1  [info] function-result-not-set:
      Function Result is not assigned on every path.

The whole function (`YADF.Options.pas:593-601`):

    function EncodingOf(const E: TYadfEncoding): TEncoding;
    begin
      case E of
        encUTF8BOM : Result:= TEncoding.UTF8;
        encUTF16BOM: Result:= TEncoding.Unicode;
        else
          Result:= TEncoding.ANSI;
      end;
    end;

Every path assigns `Result`. A `case` with an `else` is exhaustive by
construction, so reachability of "no branch taken" is nil. The rule is either not
descending into the `else` arm, or not treating `else` as making the `case`
total.

## Why this matters more than two findings

Both are `case`-shaped, and `case` is everywhere in a tokeniser/formatter. This
is very likely a systematic under-read of `case` in the dataflow layer, so the
same defect will inflate DataCopy and drag-lint's own counts too. Fixing it
removes findings from all three projects at once, which is strictly better than
marking them reviewed in each -- and marking a false positive as "reviewed and
accepted" records something untrue about the code.

Related, previously filed: `docs/INBOX-group-E-dataflow-rules-are-majority-false.md`
(the broader "Group E dataflow rules are majority false" observation). This note
is the precise, reproducing instance of two of them.

## Suggested check when fixing

The `overwrite-before-read` finding at `YADF.Layout.pas:5493` was ALSO sampled
and is **correct** -- a defensive `PendingLabel := ''` at the end of a scope,
genuinely a dead store, deliberately written. Do not "fix" that one by widening
the rule; it is a true positive the owner may reasonably accept.

Sampled 3 of the data-flow family: 2 false, 1 true.
