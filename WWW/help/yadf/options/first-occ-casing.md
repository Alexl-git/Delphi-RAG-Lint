---
id: first-occ-casing
title: First-occurrence casing
summary: Cascade casing from the first occurrence of each identifier to all later uses.
group: casing
order: 40
default: "true"
ini: FirstOccCasing
since: "1.0.0.0"
status: "stable"
---

# First-occurrence casing

Normalize identifier casing to the first occurrence in the
file. Pascal is case-insensitive, so this is semantically safe.

## Related

- [Lowercase keywords](lowercase-keywords.md) - Lowercase Pascal keywords (begin, end, if, then ...).
- [Uppercase hex](upper-hex-numbers.md) - Uppercase hex digits in numeric literals ($AB not $ab).
- [Uppercase directives](upper-directives.md) - Uppercase compiler-directive keywords ({$IFDEF}, {$R+} ...).
