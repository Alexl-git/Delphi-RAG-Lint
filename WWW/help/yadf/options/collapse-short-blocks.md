---
id: collapse-short-blocks
title: Collapse short begin..end blocks
summary: Fold a short begin..end body of if/for/while/with onto one line when it fits. Off by default.
group: reflow-whitespace
order: 80
default: "false"
ini: CollapseShortBlocks
since: "1.0.0.0"
status: "stable"
---

# Collapse short begin..end blocks

Fold a short control-statement begin..end body onto one line when it fits MaxLen: an if/for/while/with/else header whose block holds only simple one-statement-per-line code becomes "if X then begin A := 1; B := 2; end;". Only pure simple-statement bodies fold -- a nested block, a multi-line statement, or any comment leaves the block expanded; routine bodies are never folded. Off by default.

## Related

- [Reflow long lines](reflow-lines.md) - Reflow lines that exceed MaxLen. When false, long lines are left as-is.
- [Trim trailing spaces](trim-trailing.md) - Trim trailing whitespace from every output line.
- [Max blank lines](max-blank-lines.md) - Maximum consecutive blank lines kept in output. Excess blanks are collapsed.
