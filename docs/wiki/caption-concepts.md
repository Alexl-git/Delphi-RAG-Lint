# caption concepts

`drag-lint query --concept "<words>" [--place library,project,repository] [--links N] [--limit N] [--kind k,...] [--json] --db <db>`

Find a database field by what the SCREEN calls it. Type the words of a caption
("customer name", "credit limit") and get the field, where it is shown, where it
is edited and which code uses it. The same query still returns the symbols that
[concept search](concept-search) finds; every hit now says where it came from.

## Three places

| `place` | What is searched |
|---|---|
| `project` | the project index: symbols by identifier words and doc-comment prose, and captions of the project's own forms whose field is not in the repository |
| `repository` | the COPY of the [field repository](field-repository) that `index --project` puts into the project index: captions, descriptions, table descriptions |
| `library` | the platform library index (`library-Win32.sqlite` / `library-Win64.sqlite`): symbols only |

A hit's `place` says where the field or symbol LIVES, not where the matched word
was found: a repository field found through a `DisplayLabel` of a form is still
`place=repository`.

`--place project,repository` narrows the search. An unknown value is a usage
error (exit 2). A place that was narrowed out prints no hit and no note.

The repository is never opened by a query. The copy is refreshed by
`drag-lint index --project <X.dproj> --db <db>` whenever the repository file
changed.

## Ranking

| Tier | A hit is in this tier when |
|---|---|
| 1 exact identifier | the whole query, as one word, is the name of a symbol, of a repository field or of a repository table |
| 2 exact caption words | every query word is a whole word of ONE caption of the field: the repository caption, a `DisplayLabel`, a grid column caption |
| 3 all words elsewhere | every word matches the symbol (identifier words, doc prose), or one description / hint of the field |
| 4 some words | at least one word matches |

Inside tier 2: the caption that IS the query, then captions holding the words in
a row, then any order; a repository caption before a form caption; then the text
shown in more places. Tiers 3 and 4 take one hit of each place in turn (project,
repository, library). Words are compared without case and without diacritics;
there is no stemming in captions: `name` does not find `names`.

A hit appears once, in its best tier. `--limit` cuts after ordering, so an exact
caption is never dropped for a weaker hit.

`--kind` keeps filtering symbol kinds and also accepts `repo-field`,
`repo-table` and `dfm-caption` (a caption of a form whose field is not in the
repository; its name reads `TABLE.FIELD`, or `?.FIELD` when the table of the
dataset is not known).

## Output

```
concept "customer name": 2 hit(s) (2 match every word)
  1  0.00  repo-field CUSTOMERS.NAME   C:\P\_DL-REPO\App.dlrepo:0   [caption,display-label] place=repository
       caption "Customer name"  VARCHAR(40)   also shown as: "Client name" (2), "Cust. name" (1)
       persistent fields 1, grid columns 1, edit controls 1, forms 1, code 2, by name only 1 (2 tables)
         persistent-field  frmMain.qryCustomersNAME   C:\P\uMain.dfm:8
         grid-column       frmMain.colName   C:\P\uMain.dfm:21
         edit-control      frmMain.edName   C:\P\uMain.dfm:25
         code              uMain.TfrmMain.Save   C:\P\uMain.pas:47   FieldByName
         code              uMain.TfrmMain.Save   C:\P\uMain.pas:48   persistent-field
         by name only      uTools.CopyName   C:\P\uTools.pas:19   pDs.FieldByName
  2  9.41  method     uMain.TfrmMain.CustomerNameChanged   C:\P\uMain.pas:19   [tokens] place=project
```

The first line of a hit is the line of earlier versions with ` place=<p>`
appended. The number in brackets after a caption is how many places show
exactly that text.

`--json` keeps every earlier key and adds `places[]` at the top and, per hit,
`place`, `tier`, and for a field `field`, `texts[]` and `links`:

```
"links": {
  "persistentFields": {"count": 1, "rows": [{"file", "line", "form", "component", "dataset", "caption", "via"}]},
  "gridColumns":      {"count": 1, "rows": [...]},
  "editControls":     {"count": 1, "rows": [...]},
  "forms":            {"count": 1, "rows": [{"form", "class", "file"}]},
  "code":             {"count": 2, "rows": [{"file", "line", "in", "via"}]},
  "codeByNameOnly":   {"count": 1, "rows": [{"file", "line", "in", "receiver", "via"}], "candidateTables": 2}
}
```

`count` is always the full number; `rows` holds at most `--links N` rows
(default 5; `--links 0` = counts only). A repository hit has `line` 0 and its
`file` is the repository file.

## Using code

* `via` `FieldByName` / `FindField` / `FieldValues`: the field name is a string
  literal in the code, and the dataset it is asked from is a component whose
  table is known.
* `via` `persistent-field`: the code uses the persistent field component
  (`qryCustomersNAME.AsString`).
* **by name only**: the literal is there but the dataset is a parameter, a local
  or a dataset whose table is not known, so the field could belong to any table
  that has a field of that name. Such a use is listed under EVERY repository
  field of that name, in its own group, with the number of candidate tables. It
  never raises a hit's rank. When more than 5 tables have the name (`ID`,
  `NAME`), only the count is printed; pass `--links N` to see rows.

## Notes on stderr

One line per place that could not be searched as expected; stdout stays
parseable. In `--json` the same line is `places[].note`.

| Line starts with | Meaning |
|---|---|
| `repository: not configured` | the project names no field repository |
| `repository: not copied yet` | the project index was made before 1.56; run `index --project` once |
| `repository: not copied (this index was made by a directory scan` | `index <dir>` has no project file, so it never copies a repository; build a project index with `index --project` to get repository hits |
| `repository: not found at index time:` | the configured file did not exist when the index ran |
| `repository: not readable at index time:` | it could not be opened; the previous copy answers, when there is one |
| `repository: copy from <when> is stale` | the repository file changed since the copy; the line carries the refresh command |
| `repository: copy from <when>; <path> no longer exists` | the copied file is gone |
| `repository: copy from <when> of <path>` | the copy is current and at least one hit came from it |
| `library: not configured` | no library index among the resolved databases |
| `library: no concept-search table` | run `drag-lint index` on the library index once |

A missing place never changes the exit code: 0 = at least one hit, 1 = none,
2 = usage error, 3 = the project index has no concept-search table.

## Pitfalls

* The stale check compares size and modification time of the repository file
  only; a file touched without a change reads stale until the next index run.
* The library place is the resolved database named `library-*.sqlite`. With an
  explicit `--db` list, pass it as a second `--db` to search it.
* Searching the library index adds its time to every query; `--place
  project,repository` skips it.
* Captions of hidden fields are searched too; the hit says `visible: false`.
