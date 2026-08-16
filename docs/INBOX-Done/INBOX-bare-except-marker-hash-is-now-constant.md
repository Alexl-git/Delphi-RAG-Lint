> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21).** FIXED 2026-08-16 (8e9c172): HashWindow widens the hash only when the anchor normalizes to a lone keyword. Unconditional widening was built, measured (stale 0/0/0/0 -> 102/128/114/49) and rejected.

# Every `bare-except` marker now hashes to the same value, so the hash checks nothing

> **FIXED 2026-08-16 (session 21) with fix (1), but only after the obvious form
> of (1) was measured and rejected.**
>
> `TReviewMarkers.HashWindow` hashes the construct (anchor line + up to 6
> normalized code lines, stopping after a line normalizing to `end`). Writer and
> checker share it: `InsertInto` gained an `AHashOverride` because it only ever
> sees ONE line and could never re-derive a window, so letting it fall back to
> `HashLine` would have written markers that were stale the instant they landed.
>
> **THE WIDENING HAD TO BE MADE CONDITIONAL, and that is the whole lesson.**
> Widening unconditionally is not a fix, it is a corpus-wide churn event:
> measured on the four consumer projects, `review-marker-stale` went
> **0/0/0/0 -> 102/128/114/49** and totals **6/6/9/44 -> 232/299/263/152**,
> because ~390 markers anchored on ordinary STATEMENTS were invalidated in order
> to repair twelve anchored on a keyword. A statement line already varies with
> the code, so `HashLine` was always right for it.
>
> The condition is a property of the LINE, not a list of rule ids:
> `NormalizedIsLoneKeyword` widens only when the anchor normalizes to a single
> keyword. Every keyword-anchored rule therefore gets this automatically and no
> code-anchored rule is disturbed.
>
> **The family prediction below was right.** Re-measuring found two
> `try-except-swallowed` markers ALSO carrying the constant `@b112`, plus one
> `duplicate-code` marker on a keyword line. All three re-stamped.
>
> **Result: 12 markers now carry 9 distinct hashes** (was 1), the x2/x3 groups
> being genuinely identical handler bodies -- identical code hashing identically
> is correct, not a collision. Consumer totals returned to **6 / 6 / 9 / 44**
> with `review-marker-stale` and `review-marker-unused` both 0 in all four.

Filed 2026-08-16 (session 21), immediately after the 12-marker restamp that
followed the `bare-except` anchor move (`430fd37`). **This is an unintended
consequence of that fix and I introduced it.**

Class: **wrong** (the accountability mechanism silently stops accounting).

## Measurement

All twelve restamped markers across two repos came out identical:

```
YADF/YADF.Guard.pas:250           except  // dl:ok bare-except@b112
YADF/YADF.Options.pas:969         except  // dl:ok bare-except@b112
YADF/YADF.Tokens.pas:306          except  // dl:ok bare-except@b112
YADF/YadfMain.pas:384             except  // dl:ok bare-except@b112
DataCopy/CSVRoutines.pas:452      except  // dl:ok bare-except@b112
DataCopy/DPPRoutines.pas:528      except  // dl:ok bare-except@b112
DataCopy/uConfigurationService.pas:1140  except  // dl:ok bare-except@b112
... 5 more, all @b112
```

Before the anchor move the same twelve carried **eight distinct** hashes
(`155e` x2, `2b8e`, `5a3b`, `74c3`, `79a5`, `85ba`, `8a13`, `d0de` x3, `ef9f`).

## Why

`HashLine` hashes `NormalizeLine`, which strips comments and whitespace and
lowercases identifiers. The marker now sits on the `except` KEYWORD, so the
normalized line is the single token `except` -- identical for every bare handler
in every file in every project, forever.

## Why it matters

The `@hash` exists so a marker goes **stale** when the code it reviewed changes;
that is the entire difference between `dl:ok` and a blanket suppression. Hashing
a line that cannot vary destroys that:

* the handler body can be rewritten completely and the marker still verifies;
* the review is pinned to a token, not to the risk that was accepted.

Previously the hash covered the handler's first statement (`result := 0;`), which
DOES change when the handler is edited. The anchor move gained the right report
line and lost the checkable content. **Both properties are wanted and the fix
took only one.**

Note this is not an argument to revert: the old anchor made the marker
unwritable at the obvious place, which was worse. It is an argument that the
hash input and the report line should not have been assumed to be the same
thing.

## Candidate fixes

1. **Hash a WINDOW, not the line** -- for a construct-anchored rule, hash the
   normalized text of the construct (the `except` keyword through its `end`),
   not the anchor line. Restores staleness and is strictly more informative than
   the old single-statement hash. Changes every existing hash once more, so it
   should be done deliberately and combined with any other pending churn.
2. **Let the rule declare its hash span**, so construct-anchored rules hash the
   construct while line-anchored rules keep hashing the line.
3. Accept it and document that `bare-except` markers are position-pinned only --
   cheapest, and honest, but it quietly demotes one rule out of the
   accountability story.

(1) is the right shape. Check the sibling keyword-anchored rules first --
`empty-except`, `empty-finally`, `empty-on-handler`, `empty-conditional`,
`empty-loop-body`, `empty-case-branch` all anchor on a bare keyword too, so
**they almost certainly have the same constant-hash property already** and this
is a family, not an instance. That is worth measuring before choosing.
