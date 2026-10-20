# Format Whole Project with YADF

Runs YADF formatting across a project's files, with indexing involved as
part of the same action. Reach for it to bring a whole project's source to
house style in one action instead of file by file.

## Running it from the CLI
No single combined command is documented for this action. The feature map
lists its CliVerb as "format + index" and its Mechanism as "lsp+shells",
meaning it is built from the `format` verb (run per file) and the `index`
verb, not one dedicated whole-project-format command:
```
drag-lint format <file> [--yadf-path PATH]
drag-lint index <path> [--db <file.sqlite>] [--watch [--interval N]] [--library-db <lib.sqlite> ...]
```
No documented flag runs both across a whole project in a single CLI call;
that orchestration is the IDE menu action itself.

## Reaching it in the IDE
drag-lint > Format Whole Project with YADF...

## What it needs
The feature map marks this row's Index column "no/optional": the
formatting part needs no index. Where indexing is involved, the `--db`
flag on `index` is optional -- drag-lint auto-resolves the index when
omitted -- but an index must still exist for that step to do anything.

## Formatting does NOT invalidate your review markers

This is the question people ask before letting a formatter loose on a
reviewed codebase, so it was tested rather than assumed.

`// drag-lint:ignore` comments and `// dl:ok <rule>@<hash>` reviewed markers
**survive YADF formatting.** A `dl:ok` marker carries a 4-char hash of the
line's code so that a review cannot outlive the code it reviewed -- but that
hash is computed over a NORMALISED line: comments and whitespace stripped,
identifiers lowercased, string-literal content preserved verbatim. Reindenting
and re-spacing therefore cannot change it.

Measured on `YADFOT.Wizard.pas` (10 markers) before and after a real
`drag-lint format` run: all 10 markers survived, and the only change to those
lines was whitespace --

```
BEFORE: try UnregisterYADFOptions;  except end;  // dl:ok empty-except@1500, try-except-swallowed@1500
AFTER : try UnregisterYADFOptions; except end; // dl:ok empty-except@1500, try-except-swallowed@1500
```

Note what did NOT happen: the one-line `try ... except end;` statements were
not rewrapped. That is the case that would matter, because splitting or joining
a line changes the normalised content and WOULD re-hash the marker. So the
guarantee is precisely "reindentation and re-spacing are safe" -- not "any
transformation is safe".

## Example
Illustrative only, showing the per-file and index verbs this action is
built from:
```
drag-lint format C:\Projects\MyApp\Unit1.pas
drag-lint index C:\Projects\MyApp --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
