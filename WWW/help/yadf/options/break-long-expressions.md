---
id: break-long-expressions
title: Smart expression breakup
summary: When a line exceeds the max length, break it at every top-level operator, one component per line. Off = greedy packing.
group: reflow-whitespace
order: 120
default: "true"
ini: BreakLongExpressions
since: "1.0.0.0"
status: "stable"
---

# Smart expression breakup

ON (default): when a line exceeds MaxLen, break it at every top-level operator -- one component per line, with the connecting operator LEADING each line ("and X" / "or Y"). A parenthesised group is one component and stays whole; a component that still does not fit is broken the same way, one indent step deeper. A trailing "then" or "do" moves to its own line at the column of the "if" / "while" that introduced it. Lines that already fit are never touched. OFF reverts to the greedy breaker, which packs as many components per line as fit.

## Related

- [Reflow long lines](reflow-lines.md) - Reflow lines that exceed MaxLen. When false, long lines are left as-is.
- [Trim trailing spaces](trim-trailing.md) - Trim trailing whitespace from every output line.
- [Max blank lines](max-blank-lines.md) - Maximum consecutive blank lines kept in output. Excess blanks are collapsed.
