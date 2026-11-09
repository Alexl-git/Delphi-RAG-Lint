# Convert Components

Opens ConvRulesEditor from the IDE on what you selected in the form designer. The editor
shows the scope and the matching books; it never starts the run by itself.

## Reaching it in the IDE
drag-lint > Convert Components

* **Convert Selected Component(s)...** -- the components selected on the form.
* **Convert All of This Type on the Form...** -- every instance on the form of the selected
  components' types. The editor works out which ones.
* **Open Conversion Editor...** -- the editor on the current unit with no request. The unit stays open.

The first two are also on the form designer's right-click menu, as **drag-lint: Convert Selected
Component(s)...** and **drag-lint: Convert All of This Type on the Form...**; they do exactly what
the main-menu items do.

## What happens
1. The selection is read; the form itself never counts. With nothing selected you are told so.
2. `ConvRulesEditor.exe` must be beside the engine. On the first click of an IDE session it is
   asked `--write-capabilities`; a build that does not answer within 5 s is reported as older
   and nothing opens.
3. A modified unit is offered for saving. Cancel stops here: a unit whose buffer differs from
   disk is never converted.
4. The request is written to `%LOCALAPPDATA%\drag-lint\convert-requests\` as `convert-request/1`;
   requests older than 7 days are removed. It stays there as the record of what was asked.
5. The unit closes, the editor opens with `--convert-request`, and you press Convert there.
6. When the editor exits the unit reopens on the designer. If the IDE closes first, the editor
   keeps running and nothing reopens.

One editor at a time: while one lives, another launch names the unit it is open for.

## What it needs
An index of the active project. While the editor lives, drag-lint holds its own reindex and
lint-all jobs on that project's index (they wait in the queue and run when the editor exits),
so saving another unit during a conversion does not collide with the editor's reindex. Jobs on
other projects' indexes run as usual.

## Related
[ConvRulesEditor](convrules-editor)