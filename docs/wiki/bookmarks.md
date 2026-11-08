# bookmarks

Lists or finds the `dl:bk` comment-anchor bookmarks in a unit or a folder. Reach
for it when you marked code with a comment and want every mark listed, or one
mark found by its code.

## What a bookmark is

A bookmark is an ordinary `//` comment whose first token is the tag, so it moves
with its code through edits, reformatting and moves between units. Two kinds:

```
Foo;   // dl:bk3                           a user bookmark; N is any integer
Bar;   // dl:bk:A7K3QX -- lock order       a DL bookmark: 6-8 letters or digits, then an optional reason
Baz;   // dl:bk12@7f3a                     either kind may carry the construct hash
```

Anything else is not a bookmark: the tag inside a string literal, inside a brace
or star-paren comment, in the middle of a comment's prose, or a DL tag whose code
is not 6-8 characters.

## Running it from the CLI

```
drag-lint bookmarks --in <file.pas|dir> [--name <code>] [--json]
```

`--in` is a unit or a folder (every `.pas` below it). `--name <code>` keeps only
the anchors with that code (tagged codes match case-insensitively). Output is one
line per anchor, `file:line  kind  code  [@hash]  [-- reason]`; `--json` prints a
bare array of `file`, `line`, `kind`, `code`, `hash`, `reason`. Exit 0 with hits,
3 with none, 1 without `--in`, 2 for a missing path.

The verb only reads. Bookmarks are ordinary committed comments (owner ruling
2026-09-22): nothing removes them on its own and nothing is tied to git.

## Taking bookmarks out and putting them back

When YOU want a file without its anchors for a while (to send it, diff it or
publish it), strip them into a sidecar and restore them later:

```
drag-lint bookmarks-strip   --in <file.pas|dir> --out <sidecar.json> [--name <code>] [--apply] [--json]
drag-lint bookmarks-restore --from <sidecar.json> [--apply] [--json]
```

Both are dry runs without `--apply`: they print what they would do and write
nothing.

`bookmarks-strip` removes every `dl:bk` anchor (or only the code given by
`--name`). A trailing anchor (`Foo; // dl:bk3`) loses the comment and the
blanks before it; an anchor on its own line loses the whole line. Everything
removed goes into the sidecar. `--out` is required with `--apply`, and an
existing sidecar is never overwritten (exit 1), so an earlier strip cannot be
lost. Exit 0 with anchors, 3 with none, 1 for usage, 2 for a missing path.

`bookmarks-restore` puts the anchors back. A file that still holds the exact
bytes the strip left is restored byte for byte. A file edited since is
restored anchor by anchor: each goes back on the line it was attached to (the
code line of a trailing anchor, the line below an own-line anchor), found at
its old position or as the only line with that text. When one anchor of a file
cannot be placed (the line is gone, or several lines match), that whole file is
left untouched and the anchor is reported `unplaced` (exit 4). A file that
already has its anchors is reported `already`. The sidecar is never deleted.
Files are handled as raw bytes: line endings and encoding are kept.

`--json` prints one object: `verb`, `apply`, `sidecar`, the counts (`files`,
`count` for strip; `restored`, `already`, `unplaced` for restore) and a
`bookmarks` array of `file`, `line`, `kind`, `code`, `mode` (`trailing` or
`line`) plus `hash` / `reason` (strip) or `status` (restore).

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature (the IDE set / jump / panel half is a
later item).

## What it needs

No index: the usage lines have no `--db` flag; the verbs scan the text of the files.

## Example

```
drag-lint bookmarks --in C:\Projects\App\src --name A7K3QX
```
