---
id: align-max-column
title: Align max column
summary: Maximum column an alignment may push to. Past this, alignment is skipped.
group: assignment-alignment
order: 60
default: "140"
ini: AlignMaxColumn
since: "1.0.0.0"
status: "stable"
---

# Align max column

Skip Pass-2 alignment for any anchor that would push a line past
this column (prevents one outlier from forcing huge padding on
every neighbor). Also caps the shared column used by
AlignMatchingShapes and by trailing-comment alignment. Wide
tables (e.g. long record-constant arrays) align out of the box at
the default below; very wide ones may still need it raised -- if
any anchor would cross this column the whole run is left
untouched. Raised from 100 to 140 (2026-05-17) so AlignMatchingShapes
aligns typical record-constant tables without a per-project bump.

## Related

- [No space before :=](assign-no-space-before.md) - No space BEFORE := ("X:= 1" not "X := 1").
- [Space after :=](assign-space-after.md) - Single space AFTER := ("X:= 1" not "X:=1").
- [Align const =](align-const-equals.md) - Vertical-align = in const blocks.
