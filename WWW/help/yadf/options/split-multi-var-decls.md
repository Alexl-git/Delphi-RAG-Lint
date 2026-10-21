---
id: split-multi-var-decls
title: Split multi-var decls
summary: Split "I, J: integer;" into one line per name so the type colons align.
group: declarations
order: 10
default: "true"
ini: SplitMultiVarDecls
since: "1.0.0.0"
status: "stable"
---

# Split multi-var decls

Split "I, J: integer;" into one line per name so the type colons align.

## Related

- [Align decl semicolons](align-decl-semicolons.md) - After AlignTypeColon, align the trailing ; on consecutive declaration lines.
- [Break case labels](break-case-labels.md) - Break a multi-label case arm ("a, b, c: Stmt;") into one label per line, duplicating the statement. Off by default -- multi-label case arms are kept on one line (only genuine variable/field declarations are split, per SplitMultiVarDecls).
- [Break parameters one per line](break-params-one-per-line.md) - Lay out a routine declaration with one parameter per line ("procedure Go(const A: string; B: Integer);" -> one parameter per line). Fires on named routine declarations with 2 or more parameters; a grouped declaration ("const A, B: string") is split into one name per line, repeating the modifier. Separator placement follows UsesCommaLast. A group carrying an attribute, an interior comment, or an "=" default value is kept whole. Call-site argument lists are never touched. Off by default.
