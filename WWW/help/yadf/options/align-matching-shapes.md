---
id: align-matching-shapes
title: Align matching shapes
summary: Align matching "shapes" (record-init lines, repeated field declarations).
group: assignment-alignment
order: 70
default: "true"
ini: AlignMatchingShapes
since: "1.0.0.0"
status: "stable"
---

# Align matching shapes

Generalises AlignSmartAssign beyond `:=` lines. When two or more
ADJACENT lines share an identical structural skeleton (same
sequence of operators/punctuation in the same order -- identifier
names, strings, and numbers are ignored), every shared anchor is
padded to a common column so the lines form a neat table. Applies
anywhere -- record-constant arrays, declarations, repeated calls
-- not just constant definitions. Lines whose skeletons differ
are never touched. Set false to keep the old `:=`/const-only
behaviour.

## Related

- [No space before :=](assign-no-space-before.md) - No space BEFORE := ("X:= 1" not "X := 1").
- [Space after :=](assign-space-after.md) - Single space AFTER := ("X:= 1" not "X:=1").
- [Align const =](align-const-equals.md) - Vertical-align = in const blocks.
