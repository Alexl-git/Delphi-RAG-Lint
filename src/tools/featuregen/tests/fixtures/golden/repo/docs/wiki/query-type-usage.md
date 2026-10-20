# query type-usage

Answers one question, of a **list** of type names, about **one file**:

> Does this file actually *reference* any of these types?

Reach for it when you have a set of names -- an RTL surface, a set of types
you are about to retire, the DevExpress classes a migration touches -- and you
need to know which files really use them.

## Running it from the CLI

```
drag-lint query type-usage --in <file.pas> (--names A,B,C | --names-file <f>) [--db ...] [--json]
```

* `--in` is the source file to examine.
* `--names` is a comma-separated list, `--names-file` is the same list one name
  per line. Blank lines and lines starting with `#` are skipped, which makes a
  names file a comfortable place to keep a commented RTL surface. Both flags may
  be given together; the lists are combined.

## Why not just grep?

Because grep cannot tell a reference from the same word inside a comment or a
string literal, and across a list of thirty names that difference is most of the
output. This verb reads the index, so:

| in the source | reported? |
|---|---|
| `V: TStringBuilder;` (declaration) | yes -- `type_use` |
| `TStringBuilder.Create` (construction) | yes -- `read` + `member-access` |
| `TChild = class(TAncestor)` (inheritance) | yes -- `type_use` |
| `// TFoo is faster here` (comment) | **no** |
| `S := 'TFoo';` (string literal) | **no** |

Comments are not indexed at all and string literals live in their own table, so
the exclusion is a property of the data rather than a filter that might drift.

The construction case is worth calling out: the `member-access` row carries
`Create` in `name_text` and the **type** only in `receiver_text`, so a naive
scan of names misses every `X.Create` site. This verb reads both.

## What it needs

An index that contains the file. `--db` is optional -- drag-lint picks the index
that actually **contains** `--in`, rather than the first one configured, so a
multi-project machine does not silently answer from an unrelated project. If no
index holds the file it says so and exits 2 rather than reporting "no usage",
because those two answers must never look alike.

## The one limitation, stated in the output

Matching is **name-keyed**. `refs.symbol_id` is NULL for every `type_use` row,
so a project type that happens to share a name with an RTL type is
indistinguishable from it. The text output repeats this on its summary line.

## Example

```
drag-lint query type-usage --in src\doc\DRagLint.Doc.GitSince.pas ^
    --names TStringBuilder,THandle,TStringList,TDictionary
```

```
file: src\doc\DRagLint.Doc.GitSince.pas
  TStringBuilder                   REFERENCED  read=1 type_use=1 member-access=1   first line 100
  THandle                          REFERENCED  type_use=2                          first line 93
  TStringList                      -
  TDictionary                      -
2 of 4 name(s) referenced (name-keyed: a same-named project type is indistinguishable)
```

`--json` emits one object per requested name, with `referenced`, `count`,
`first_line` and a `kinds` breakdown. The JSON document is the whole of stdout;
status lines go to stderr, so it can be piped straight into a parser.

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.
