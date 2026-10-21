---
id: label-long-blocks
title: Label long blocks
summary: Mark the end of long blocks with the block keyword: "end; // while".
group: labels-markers
order: 10
default: "true"
ini: LabelLongBlocks
since: "1.0.0.0"
status: "stable"
---

# Label long blocks

When true, long begin/record/case/try/asm/object blocks get a
trailing `// while`, `// procedure`, etc. comment so the closing
`end;` is self-describing.

## Related

- [Label min lines](label-min-lines.md) - Minimum lines a block must span before LabelLongBlocks adds the marker.
- [Mark unclosed blocks](mark-unclosed.md) - When an opening begin/record/... has no matching end, add "// TODO -oYADF : 'begin' on line N has no matching 'end'".
