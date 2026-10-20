# wiki

Looks up the **`dl:wiki` concept topics** a team has written into their own doc
comments, and routes a *human* phrase to the code that implements it.

Every other query in drag-lint starts from an identifier you already have.
`wiki` starts from a word somebody says out loud -- "the scheduler", "delta
streaming", "the import path" -- and answers with the owning symbol, the other
symbols that participate, and the prose explaining how they fit together.

Nothing here is inferred. If `wiki --term "the scheduler"` answers, it is
because a person wrote a `dl:wiki` block saying so. That is the point: the
index can tell you what the code *is*, and only a human can tell you what the
team *calls* it.

## Running it from the CLI

```
drag-lint wiki --term "<phrase>" [--json] [--db <file.sqlite>]
drag-lint wiki --list            [--json] [--db <file.sqlite>]
drag-lint wiki --check           [--json] [--db <file.sqlite>]
```

Exactly one of `--term` / `--list` / `--check`.

## Reaching it in the IDE

There is no menu item. What the IDE does show is an **indicator**: hover a
symbol whose doc block carries a topic and the popup adds one line,

```
- Wiki: Delta Streaming -> Micronite.Delta.Pipe - line 3
```

which is clickable and jumps to the `dl:wiki` header itself. The **body is
never rendered in the popup** -- a concept body is paragraphs and a hover is a
glance; putting one inside the other makes the popup useless for its actual
job. Ordinary hand-written `<remarks>` prose around the block is untouched.

Read the body with `wiki --term`, or let `context --task` include it.

## What it needs

An index IS required, and the same DB resolution `query` uses applies: an
explicit `--db`, otherwise the manifest's read list (the project's own index
plus the platform library). A project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

**No reindex is needed to make a topic queryable beyond the ordinary
incremental walk.** A `dl:wiki` block lives inside a normal `///` comment, so
the existing extractor already stores it verbatim in `symbol_docs.raw_block`;
editing a file changes its hash and the next incremental index picks it up like
any other edit. Neither `DRAGLINT_EXTRACTOR_VERSION` nor the schema version
moves for this feature.

## The three modes

### `--term "<phrase>"` -- the lookup

Matches the phrase against every topic's **name and aliases**,
case-insensitively and **in both directions**, so `--term "the scheduler"`
finds a topic whose alias is just `scheduler`. Ranking, best first:

| Band | Meaning |
|---|---|
| exact | the phrase IS the name or an alias |
| prefix | either string starts with the other |
| whole word | either contains the other bounded by non-alphanumerics |
| substring | either contains the other anywhere |

Ties break on the shorter name, the same rule `query --name-like` uses.

Each printed topic carries its owning symbol, the `file:line` of the `dl:wiki`
header itself, its aliases, every `SeeCode` entry **resolved to a `file:line`
or marked `MISSING`**, and the body.

**Exit code 1 means no topic matched.** That is an answer, not a failure -- it
lets a script or an agent branch on "this word is not in the wiki" without
parsing prose.

### `--list` -- everything

Every topic in the resolved index set, ordered by file and line. Use it to see
what vocabulary has actually been written down. `SeeCode` entries are printed
unresolved here; `--check` is what resolves them.

### `--check` -- the drift gate

Body prose cannot be verified, and this does not pretend otherwise. What it
checks is everything that CAN be:

* every `SeeCode` entry resolves to a symbol **in the topic's own database**
  (not in some other project's index that happens to share a name);
* no two topics declare the same name;
* no alias collides with a different topic's name, which would make `--term`
  answer with the wrong topic;
* no `dl:wiki` header was written without a topic name.

Exits **1** when anything is reported, so it belongs in a session's habits next
to `lint`. It prints the number of topics CHECKED as well as the number of
problems -- a check that examined zero topics and said "0 problems" would read
exactly like a working one.

## Flags

| Flag | Meaning |
|---|---|
| `--term "<phrase>"` | look one phrase up against names and aliases |
| `--list` | print every topic |
| `--check` | resolve every `SeeCode` entry and report drift |
| `--db <file.sqlite>` | index to read; repeatable. Omitted, the manifest's read list is used |
| `--format json` / `--json` | machine-readable output |

Exit codes: `0` success; `1` `--term` matched nothing or `--check` found a
problem; `2` usage error (zero or several modes, no index resolved, a named DB
missing).

## Authoring a topic

Full format spec: [Wiki-Blocks-Authoring](Wiki-Blocks-Authoring.md). The short
version -- inside an ordinary `///` comment, above the declaration that owns
the concept, or above `unit X;` when it spans several types:

```
/// <remarks>
/// dl:wiki Delta Streaming
/// Aliases: delta stream, cmdDelta pipeline, the streaming path
/// SeeCode: TDeltaStreamer, TDeltaSet.ApplyDelta
/// Body:
/// How row changes travel from the client to the server.
/// </remarks>
unit Micronite.Delta.Pipe;
```

## Example

```
> drag-lint wiki --term "the streaming path" --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite

== Delta Streaming ==
   owner : Micronite.Delta.Pipe  (unit)
   source: C:\Projects\MyApp\src\Micronite.Delta.Pipe.pas:3
   aliases: delta stream, cmdDelta pipeline, the streaming path
   see: TDeltaStreamer  -> C:\Projects\MyApp\src\Micronite.Delta.Pipe.pas:28
   see: TDeltaSet.ApplyDelta  -> C:\Projects\MyApp\src\Micronite.Delta.Set.pas:112

How row changes travel from the client to the server.

1 match(es) of 6 topic(s).
```

The JSON form emits an array of objects with `name`, `owner_qname`,
`owner_kind`, `file`, `line`, `db`, `aliases`, `seecode` and `body`. `--check`
emits `{ "topics_checked", "problems", "ok" }` instead.

## Related

* [Wiki-Blocks-Authoring](Wiki-Blocks-Authoring.md) -- the format
* [query-find-callers](query-find-callers.md) -- once `wiki` has given you a symbol
* [sql](sql.md) -- when no verb answers the question at all
