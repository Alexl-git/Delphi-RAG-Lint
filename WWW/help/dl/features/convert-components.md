---
id: convert-components
title: Convert Components
summary: Opens ConvRulesEditor on the components selected in the form designer
product: DL
group: component-conversion
order: 60003
since: 1.46.0-alpha
status: shipped
updated: 1.46.0-alpha
---

# Convert Components

Opens ConvRulesEditor on the components selected in the form designer.

Read this when you want to convert components from the form designer. Select them, choose drag-lint > Convert Components > Convert Selected Component(s)...; drag-lint saves and closes the unit and opens ConvRulesEditor on its Convert tab with the matching books checked. You press Convert. The unit reopens when the editor closes.

## Where to click

* RAD Studio main menu: **drag-lint > Convert Components > Convert Selected Component(s)...**
   1. Open the form in the designer and select the component(s)
   2. Choose drag-lint > Convert Components > Convert Selected Component(s)...
   3. Save the unit if asked; it closes and ConvRulesEditor opens on its Convert tab
   4. Check the scope and the books, press Convert, close the editor; the unit reopens
* RAD Studio main menu: **drag-lint > Convert Components > Convert All of This Type on the Form...**
   1. Open the form in the designer and select a component of each type to convert
   2. Choose drag-lint > Convert Components > Convert All of This Type on the Form...
   3. Save the unit if asked; it closes and ConvRulesEditor opens on its Convert tab with every instance of those types in scope
   4. Press Convert, close the editor; the unit reopens
* RAD Studio main menu: **drag-lint > Convert Components > Open Conversion Editor...**
   1. Open the unit
   2. Choose drag-lint > Convert Components > Open Conversion Editor...
   3. ConvRulesEditor opens with the unit loaded and no scope; the unit stays open

## Details

Opens ConvRulesEditor from the IDE on what you selected in the form designer. The editor
shows the scope and the matching books; it never starts the run by itself.

### What happens
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

### What it needs
An index of the active project. Saving another unit during a conversion can still start a
reindex that collides with the editor's own; the run then reports it and you retry.

### Related
[ConvRulesEditor](convrules-editor.md)

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
