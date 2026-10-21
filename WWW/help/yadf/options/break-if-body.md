---
id: break-if-body
title: Break if/then/else body onto its own line
summary: Put the then/else body of a single-line if on its own indented line. Off by default.
group: reflow-whitespace
order: 110
default: "false"
ini: BreakIfBody
since: "1.0.0.0"
status: "stable"
---

# Break if/then/else body onto its own line

Force the then/else body of a single-line if statement onto its own indented line ("if X then A else B;" -> "if X then" / "  A" / "else" / "  B;"). "else if" chains stay glued; a begin/nested-header/comment body is left alone. Off by default.

## Related

- [Reflow long lines](reflow-lines.md) - Reflow lines that exceed MaxLen. When false, long lines are left as-is.
- [Trim trailing spaces](trim-trailing.md) - Trim trailing whitespace from every output line.
- [Max blank lines](max-blank-lines.md) - Maximum consecutive blank lines kept in output. Excess blanks are collapsed.
