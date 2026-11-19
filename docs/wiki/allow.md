# allow

Records a `dl:ok` review of one finding, so it stops being reported without
being fixed. Reach for it when a lint finding is a deliberate, reviewed
exception rather than something you intend to change.

## Reaching it in the IDE
drag-lint > Code Quality > Allow a Finding on This Line... works from the caret: confirm the rule (prefilled when the diagnostics hold one for that line), then Yes writes the review and No shows a dry-run preview. The right-click [Allow this message](Allow-this-message) on the Structure form does the same for one tree node.

## Running it from the CLI

```
drag-lint allow <file> --fix-line <L> --fix-rule <id> [--apply] [--reason "<text>"]
```

`--fix-line` and `--fix-rule` identify the exact finding to allow. Per the
usage banner, this is a dry run without `--apply`: "record a dl:ok review of
ONE finding; dry-run without --apply".

## Reaching it in the IDE

Reachable in the IDE through the Structure form's right-click menu -- see
[Allow this message](Allow-this-message) for the IDE-side walkthrough
(drag-lint > Show Structure, then right-click a finding and choose "Allow
this message"). There is no main-menu item; the feature map's internal call
site is `TDragLintStructureForm.ShowInButterflyClick (DragLint.Plugin.StructureForm.pas)`.

## Re-stamping a review (`--reason`, 1.52)

A marker's reason can carry a `REVIEWED <yyyy-mm-dd>` stamp (checked by
`review-marker-reason-unreviewed`). When `allow` re-hashes a STALE marker it keeps
the reason but drops that stamp and says so: a re-hash is not a re-review. After
you have re-read the code, pass the new reason and its stamp:

```
drag-lint allow Unit1.pas --fix-line 42 --fix-rule unused-private-member --apply --reason "REVIEWED 2026-11-18 kept for the RTTI streamer"
```

`--reason` REPLACES the marker's reason (it also re-stamps a marker whose hash is
still current); running it again with the same text changes nothing. A marker that `allow`
moves off a wrapped statement's continuation line keeps its reason, minus the stamp.

## What it needs

No index required -- `allow` records the review directly against the given
file (a `dl:ok` marker), without going through a project index database.

## Example

Illustrative:

```
drag-lint allow C:\Projects\MyApp\Unit1.pas --fix-line 42 --fix-rule unused-private-member --apply
```

This would record `Unit1.pas` line 42's `unused-private-member` finding as
reviewed, so it no longer appears in future lint runs.
