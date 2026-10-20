# Reindex project

Conversion > Reindex project in ConvRulesEditor refreshes the editor's project
index: an incremental `drag-lint index --project <Project>.dproj --db <project index>`. Use it after editing units in the IDE, or between the stages
of a multi-step conversion, so the Convert tab and the property trees read the
current code.

## Reaching it
ConvRulesEditor menu: Conversion > Reindex project (no shortcut). It runs behind
the progress window and can be cancelled. It is disabled while a Convert run is
in progress (the run reindexes on its own).

## What it says
`Reindexed Fix.dproj (Fix.sqlite): 3 file(s) in the index, compile closure 4 (0:01)`
on success -- the index's file count and the length of the project's compile-closure
list. The index is named here and in the menu hint. A failure
shows the engine's error in red. A cancel says the index may be partly
refreshed; run it again.

## What it needs
The project index must have its project file beside its `_D-RAG` folder
(`<dir>\_D-RAG\<Name>.sqlite` -> `<dir>\<Name>.dproj`). Without it the command
refuses with the same text Convert uses.