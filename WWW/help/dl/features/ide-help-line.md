---
id: ide-help-line
title: Help line (DL page)
summary: Type part of a feature name on the DL page, pick a match (with its menu path) and open that feature's help page at the configured help root
product: DL
group: editor-integration
order: 110006
since: 1.33.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# Help line (DL page)

Type part of a feature name on the DL page, pick a match (with its menu path) and open that feature's help page at the configured help root.

Read this to find help for a feature from inside the IDE and to point the plugin at an offline copy of the help.

## Where to click

* Tool window: **View > Tool Windows > drag-lint**
* RAD Studio main menu: **drag-lint > Help > Help on a feature...**
* RAD Studio main menu: **drag-lint > Help > All features (web)**

## Details

The **help line** sits at the top of the drag-lint dock page (View > Tool
Windows > drag-lint). Type part of a feature's name, pick one of the matches --
each shows where the feature lives in the menus -- and its help page opens in
your browser. The **All features...** button next to it opens the complete
feature list.

### What it does

* Typing filters the published feature list. A feature matches when what you
  typed appears in its title, in the caption of one of its menu items, in its
  registry id or in its command-line verb. The one-line summary is not searched.
* Matches are ranked: title starts with the text, then title contains it, then a
  menu caption contains it, then the id or verb. At most 12 are shown.
* Each row reads `<title> - <menu path>` (the shortest path when a feature has
  several), `<title> - CLI: drag-lint <verb>` for a command-line-only feature,
  or just the title.
* Keys: Down / Up move through the list, Enter (or a double-click) opens the
  selected feature, Esc clears the line. Enter with no list open opens the first
  match.

### How to turn it on

Nothing to turn on: the line is part of the dock page. Two menu items reach it:

* **drag-lint > Help > Help on a feature...** -- shows the dock and puts the
  caret in the help line.
* **drag-lint > Help > All features (web)** -- opens the complete feature list.

The two older Help items (*IDE Menu Reference*, *Effect Summary Legend*) now open
their pages through the same help root.

### The Help root setting

In the IDE options dialog (Tools, Options, Third Party), open the drag-lint **General** page, group **Help**:

* **Help root (URL or folder)** -- where help pages are opened from. Two forms:
  * the website, default `https://www.delphi-rag-lint.com`; a feature page is
    `<root>/help/dl/features/<id>/`;
  * an offline copy: a folder (`C:\dl-help`) or a `file:///C:/dl-help` URL that
    holds the **rendered** help site. Pages are then opened as
    `<root>/help/dl/features/<id>/index.html`. A plain folder is stored as a
    `file:///` URL; trailing slashes are dropped; an empty value means the
    website.
* **Test** opens the all-features page of the root exactly as typed, before you
  press OK.

### Where the feature list is read from

The list of features is the generated `help\dl\index.json`. The plugin looks in
three places and uses the first that exists:

1. `<engine folder>\help\dl\index.json` -- the folder of the configured
   `drag-lint.exe`; the release package installs the file there.
2. `<help root folder>\help\dl\index.json` -- only when the help root is an
   offline copy.
3. `<plugin BPL folder>\..\..\WWW\help\dl\index.json` -- a developer checkout.

The list is read on the first keystroke and re-read when the file changes. When
none of the three exists, the match list shows
`(feature list not installed: help\dl\index.json)`; **All features...** and the
Help menu still work.

A feature id that the list does not carry opens the all-features page rather
than a missing page.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
