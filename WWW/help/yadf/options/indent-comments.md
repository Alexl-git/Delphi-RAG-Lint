---
id: indent-comments
title: Indent comments
summary: Re-indent comment-only lines to the surrounding code depth. A "//." comment keeps its indentation.
group: comments
order: 10
default: "true"
ini: IndentComments
cli: --indent-comments
since: "1.0.0.0"
status: "stable"
---

# Indent comments

Re-indent comment-only lines to the surrounding code depth. When off, every comment keeps the indentation the author gave it. A comment line that starts with "//." always keeps its authored indentation even when this is on (an explicit "pin this comment" marker).
