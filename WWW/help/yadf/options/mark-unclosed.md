---
id: mark-unclosed
title: Mark unclosed blocks
summary: Add a "// TODO -oYADF" marker where a begin/record/... has no matching end.
group: labels-markers
order: 30
default: "false"
ini: MarkUnclosed
cli: --mark-unclosed
since: "1.0.0.0"
status: "stable"
---

# Mark unclosed blocks

When true, force-closed openers (a `begin` with no matching
`end`, etc.) emit a `// TODO -oYADF : '<keyword>' on line N has
no matching 'end'` marker so they show up in the IDE's To-Do list.

## Related

- [Label long blocks](label-long-blocks.md) - After a block longer than LabelMinLines, mark its end with the block keyword: "end; // while", "end; // procedure".
- [Label min lines](label-min-lines.md) - Minimum lines a block must span before LabelLongBlocks adds the marker.
