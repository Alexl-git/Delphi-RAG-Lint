# Bookmarks (IDE)

`drag-lint > Bookmarks` works on the `// dl:bk` comment anchors of the unit in the editor. It
is the IDE half of [[bookmarks]] and runs the same verbs: `bookmarks` (read-only),
`bookmarks-strip` and `bookmarks-restore`.

## Menu items

| Item | What it does |
|---|---|
| List Bookmarks in This Unit... | Lists every anchor (`bk3  line 12`, `bk:A7K3QX  line 40  -- reason`); pick one to jump to it. |
| Go to Bookmark... | Asks for a number (`3`) or a CODE (`A7K3QX`) and jumps to it. |
| Strip Bookmarks from This Unit... | Dry run first: shows how many anchors and where the sidecar goes. On Yes the anchors are removed and the unit reloads. |
| Restore Bookmarks... | Pick a sidecar. Dry run first: shows how many will be restored and how many cannot be placed. On Yes the anchors go back and the units reload. |

## Rules

* Nothing strips on its own. Strip and Restore always run the dry run first and write only
  after you answer Yes.
* A unit with unsaved changes is never stripped or restored: save it first.
* The sidecar is per user, in `%LOCALAPPDATA%\drag-lint\bookmarks\<Unit>-<yyyymmdd-hhnnss>.json`,
  outside the repo, so personal marks are never committed. A new strip never overwrites an
  older sidecar. Restore never deletes the sidecar.
* An anchor whose line changed so it cannot be found again is `unplaced`; every file holding
  one is left untouched (the verb's rule, see [[bookmarks]]).