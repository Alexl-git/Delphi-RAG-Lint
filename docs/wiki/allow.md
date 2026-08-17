# allow

Records a `dl:ok` review of one finding, so it stops being reported without
being fixed. Reach for it when a lint finding is a deliberate, reviewed
exception rather than something you intend to change.

## Running it from the CLI

```
drag-lint allow <file> --fix-line <L> --fix-rule <id> [--apply]
```

`--fix-line` and `--fix-rule` identify the exact finding to allow. Per the
usage banner, this is a dry run without `--apply`: "record a dl:ok review of
ONE finding; dry-run without --apply".

## Reaching it in the IDE

Reachable in the IDE through the Structure form's right-click menu -- see
[Allow this message](Allow-this-message) for the IDE-side walkthrough
(drag-lint > Show Structure, then right-click a finding and choose "Allow
this message"). There is no main-menu item; the feature map's internal call
site is `DragLint.Plugin.StructureForm.pas:1061`.

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
