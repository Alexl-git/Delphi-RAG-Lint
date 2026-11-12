---
id: bookmarks-ide
title: Bookmarks (IDE)
summary: "Lists, finds, strips and restores the // dl:bk comment anchors of the current unit from the IDE"
product: DL
group: documentation
order: 40002
since: 1.50.0-alpha
status: shipped
updated: 1.50.0-alpha
---

# Bookmarks (IDE)

Lists, finds, strips and restores the // dl:bk comment anchors of the current unit from the IDE.

Read this when you marked code with // dl:bk3 or // dl:bk:A7K3QX comments and want to jump to one from the IDE, or take them all out of a unit before a commit and put them back later. drag-lint > Bookmarks runs the bookmarks, bookmarks-strip and bookmarks-restore verbs; Strip and Restore show a dry run first and write only after you say Yes.

## Where to click

* RAD Studio main menu: **drag-lint > Bookmarks > List Bookmarks in This Unit...**
   1. Open the unit
   2. Choose drag-lint > Bookmarks > List Bookmarks in This Unit...
   3. Pick a bookmark; the editor jumps to its line
* RAD Studio main menu: **drag-lint > Bookmarks > Go to Bookmark...**
   1. Open the unit
   2. Choose drag-lint > Bookmarks > Go to Bookmark...
   3. Type the number (3) or the CODE (A7K3QX); the editor jumps to it
* RAD Studio main menu: **drag-lint > Bookmarks > Strip Bookmarks from This Unit...**
   1. Save the unit
   2. Choose drag-lint > Bookmarks > Strip Bookmarks from This Unit...
   3. Read the count and the sidecar path, answer Yes
   4. The anchors are removed and the unit reloads; the sidecar under %LOCALAPPDATA%\drag-lint\bookmarks keeps them
* RAD Studio main menu: **drag-lint > Bookmarks > Restore Bookmarks...**
   1. Save the units the sidecar names
   2. Choose drag-lint > Bookmarks > Restore Bookmarks... and pick the sidecar
   3. Read how many will be restored and how many cannot be placed, answer Yes
   4. The units reload with their anchors back

## Details

`drag-lint > Bookmarks` works on the `// dl:bk` comment anchors of the unit in the editor. It
is the IDE half of [bookmarks](bookmarks.md) and runs the same verbs: `bookmarks` (read-only),
`bookmarks-strip` and `bookmarks-restore`.

### Menu items

| Item | What it does |
|---|---|
| List Bookmarks in This Unit... | Lists every anchor (`bk3  line 12`, `bk:A7K3QX  line 40  -- reason`); pick one to jump to it. |
| Go to Bookmark... | Asks for a number (`3`) or a CODE (`A7K3QX`) and jumps to it. |
| Strip Bookmarks from This Unit... | Dry run first: shows how many anchors and where the sidecar goes. On Yes the anchors are removed and the unit reloads. |
| Restore Bookmarks... | Pick a sidecar. Dry run first: shows how many will be restored and how many cannot be placed. On Yes the anchors go back and the units reload. |

### Rules

* Nothing strips on its own. Strip and Restore always run the dry run first and write only
  after you answer Yes.
* A unit with unsaved changes is never stripped or restored: save it first.
* The sidecar is per user, in `%LOCALAPPDATA%\drag-lint\bookmarks\<Unit>-<yyyymmdd-hhnnss>.json`,
  outside the repo, so personal marks are never committed. A new strip never overwrites an
  older sidecar. Restore never deletes the sidecar.
* An anchor whose line changed so it cannot be found again is `unplaced`; every file holding
  one is left untouched (the verb's rule, see [bookmarks](bookmarks.md)).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
