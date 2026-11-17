# review-marker-remeasured

A hint (default ON, severity `hint`, group review-markers, since 1.52.0-alpha) on a `dl:ok`
marker that still suppresses its finding but was not stamped under the current hash.

## When it fires

A `dl:ok <rule> @<hash>` on a routine-metric rule (cyclomatic, length, nesting and the like)
carries a hash of the routine and the measured metric. 1.52 measures with the v2 hash. A marker
whose hash is not the v2 one can still be valid:

* **re-measured** -- the routine is unchanged since the review; only the engine's
  measure algorithm moved. The marker stays valid.
* **legacy** -- the marker was stamped under the 1.51.0 "v1" header|metric hash and that hash
  still matches the routine. The marker stays valid.

In both cases the finding stays suppressed and the hint names the re-stamp command:

```
dl:ok marker for "<rule>" was stamped under the 1.51.0 hash; re-measured under the v2 hash and
still valid (finding stays suppressed). Re-stamp it with: allow --fix-line <N> --fix-rule <rule>
```

A marker whose hash matches neither is stale and gets `review-marker-stale` instead.

## What to do

Run the command the hint names, for example:

```
drag-lint allow <file.pas> --fix-line 120 --fix-rule cyclomatic-complexity --apply
```

Without `--apply` it is a dry run; with it, it rewrites the marker's `@hash` to the current one; the reason text is kept.

## Related

* `review-marker-stale` -- the code changed since the review.
* `review-marker-unused` -- the marker suppresses nothing.
* Runner: `tests\autotest\run_v152_MARK_remeasured.ps1`.
