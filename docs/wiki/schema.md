# schema

Prints the live schema of an index database: schema_version, every table
and column, and row counts. Reach for it when you need to know exactly what
an index DB contains before querying it, or to check its schema_version.

## Running it from the CLI

```
drag-lint schema --db <file.sqlite> [--format text|json] [--output <file>]
```

Read-only.

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Resolved facts about a reference

The resolve pass writes these from stored parses, so a re-resolve refreshes them
without a re-parse.

`ref_types` holds the static type of a reference, at most one row per `refs` row
of kind read, write, member-access or call. No row means the pass has no type to
state: a procedure, a type name, an unresolved member.

| column | meaning |
|---|---|
| `ref_id` | the reference; the row goes with it |
| `type_symbol_id` | the type's symbol in this index; NULL for a library type, or once a reindex removed the type |
| `type_qname` | the symbol's qualified name; for a type outside this index, the leaf type text as declared |
| `via` | where the type came from, below |

| `via` | the reference is | the type is |
|---|---|---|
| `decl` | a var, const, parameter, typed local, or enum value | as declared; an enum value's is its enum |
| `member` | a field or property | as declared |
| `result` | a function call, or the implicit `Result` | the return type |
| `ctor` | a constructor call | the receiver's type, not the class declaring an inherited constructor |
| `cast` | a hard cast `TBar(X)` | `TBar` |
| `inline` | an untyped inline `var X := ...` | what the resolver decided for its initializer |
| `literal` | reserved | no row carries it yet |

Only certain bindings are typed. A library method's return type is not stored,
because the pass names the target but does not read its signature. A library
class's `Create` is stored by name when the index was resolved with its library.

`refs.enclosing_symbol_id` of a reference inside an `initialization` or
`finalization` section names that section's symbol. Elsewhere outside a routine
it stays NULL.

## Example

Illustrative only:

```
drag-lint schema --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format json
```

This would print `MyApp`'s index schema -- version, tables, columns, and row
counts -- as JSON.
