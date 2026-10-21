---
id: break-loop-body
title: Break loop body onto its own line
summary: Put the body of a single-line for/while loop on its own indented line. Off by default.
group: reflow-whitespace
order: 90
default: "false"
ini: BreakLoopBody
since: "1.0.0.0"
status: "stable"
---

# Break loop body onto its own line

Force the body of a single-line for/while loop onto its own indented line ("while X do Dec(k);" -> "while X do" + newline + "  Dec(k);"). A begin block, a nested control header, or a body with a trailing comment is left alone. Off by default.

## Related

- [Reflow long lines](reflow-lines.md) - Reflow lines that exceed MaxLen. When false, long lines are left as-is.
- [Trim trailing spaces](trim-trailing.md) - Trim trailing whitespace from every output line.
- [Max blank lines](max-blank-lines.md) - Maximum consecutive blank lines kept in output. Excess blanks are collapsed.
