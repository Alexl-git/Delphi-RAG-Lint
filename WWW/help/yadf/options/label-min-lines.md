---
id: label-min-lines
title: Label min lines
summary: Minimum block length in lines before a long block gets an end label.
group: labels-markers
order: 20
default: "15"
ini: LabelMinLines
cli: --label-min-lines
since: "1.0.0.0"
status: "stable"
---

# Label min lines

Minimum block size, in output lines, before LabelLongBlocks adds
a trailing label.

## Related

- [Label long blocks](label-long-blocks.md) - After a block longer than LabelMinLines, mark its end with the block keyword: "end; // while", "end; // procedure".
- [Mark unclosed blocks](mark-unclosed.md) - When an opening begin/record/... has no matching end, add "// TODO -oYADF : 'begin' on line N has no matching 'end'".
