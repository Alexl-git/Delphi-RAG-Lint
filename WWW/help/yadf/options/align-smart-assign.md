---
id: align-smart-assign
title: Smart-align
summary: Master switch for shape-aware alignment of := runs and, with "Align matching shapes", other matching shapes.
group: assignment-alignment
order: 50
default: "true"
ini: AlignSmartAssign
since: "1.0.0.0"
status: "stable"
---

# Smart-align

When adjacent assignment lines share the same token shape (same
sequence of operators/punctuation, identifier names may differ),
pad every common anchor (`.`, `:=`, `(`, `,`, `)`, `;`) to its
max column so they line up.

## Related

- [No space before :=](assign-no-space-before.md) - No space BEFORE := ("X:= 1" not "X := 1").
- [Space after :=](assign-space-after.md) - Single space AFTER := ("X:= 1" not "X:=1").
- [Align const =](align-const-equals.md) - Vertical-align = in const blocks.
