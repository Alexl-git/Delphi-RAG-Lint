# Wiki-Blocks-Authoring

The format of a `dl:wiki` block -- the concept notes the [wiki](wiki.md) verb
reads.

A block records what your team **calls** something and which code **is** it.
The index can answer neither of those from the source alone, which is why this
is written by hand and not generated.

## Where a block goes

Inside an ordinary DocInsight `///` comment. There are exactly two placements,
and the choice is about who OWNS the concept:

**One type owns it** -- put the block in that type's own `<remarks>`:

```
/// <summary>Streams pending row deltas into the target memtable.</summary>
/// <remarks>
/// dl:wiki Delta Streamer
/// Aliases: the streamer
/// Body:
/// Owns the client half of the delta path: batching, retry and the pipe.
/// </remarks>
TDeltaStreamer = class
```

**Several types share it** -- put the block above `unit X;` in the unit where
the concept's central type lives:

```
/// <remarks>
/// dl:wiki Delta Streaming
/// Aliases: delta stream, cmdDelta pipeline, the streaming path
/// SeeCode: TDeltaStreamer, TDeltaSet.ApplyDelta, Micronite.Delta.Pipe
/// Body:
/// How row changes travel from the client to the server.
/// </remarks>
unit Micronite.Delta.Pipe;
```

**The unit-header placement is the recommended home for a concept**, for a
reason that is structural rather than stylistic: a unit symbol is not in
`DOCUMENTABLE_KINDS`, so `document`, `document-all`, `missing-doc` and
`doc-drift` never open that comment at all. A block there cannot be touched by
the autodoc rewriter even in principle.

A type-attached block is also safe -- the doc engine's provenance contract
preserves any content that does not carry a `<!-- drag-lint:auto -->` marker
byte-for-byte, and `dl:wiki` lines never carry one -- but "structurally out of
reach" is a stronger guarantee than "preserved by a rule".

## Hard requirements

* **`///` comments only.** Loose `//` and `{ }` comments are not attached to
  symbols by the indexer, so a block written in one is invisible. This is not
  configurable in practice; use `///`.
* **No blank line** between the block's comment and the declaration it belongs
  to, or the comment stops attaching.
* **Strict 7-bit ASCII, CRLF** -- the same rule as every other `.pas` line in
  these projects. Use `--` and not an en dash, `"` and not curly quotes.

## The grammar

Line-oriented, after the `///` prefix is stripped. Section keywords are
case-insensitive.

| Line | Required | Meaning |
|---|---|---|
| `dl:wiki <Human Name>` | **yes** | opens a topic. Everything after the marker, trimmed, is the name |
| `Aliases: a, b, c` | no | phrases the team uses for this. Repeatable; entries accumulate |
| `SeeCode: X, Y.Z` | no | other symbols that participate. Repeatable |
| `Body:` | no | starts the prose |
| anything else | -- | joins the body |

Notes that matter in practice:

* **One comment may declare several topics.** A new `dl:wiki` line ends the
  previous one.
* **`Body:` is optional.** Untagged lines after the header join the body
  anyway. Write it when you want the boundary to be obvious, skip it for a
  one-line topic.
* **XML-only lines are dropped** from the body, so the `</remarks>` that closes
  your comment does not end up in the prose. A sentence that merely *mentions*
  a tag is kept.
* **Engine-generated fact blocks are excluded.** Anything between
  `<!-- drag-lint:auto BEGIN -->` and `<!-- drag-lint:auto END -->` is skipped,
  so a topic sitting beside a generated facts region cannot swallow it.
* **`dl:wikifoo` is not a header** -- the marker must be followed by
  whitespace or end of line.

## Aliases are the whole feature

The name is what you would title a wiki page. The **aliases are what people
actually type**, and they are the reason the lookup works:

```
/// Aliases: delta stream, cmdDelta pipeline, the streaming path
```

Matching is case-insensitive and runs **in both directions**, so an alias of
`scheduler` is found by `--term "the scheduler"` and vice versa. Write the
phrases your team says, including the ones with articles in them and the ones
that are slightly wrong -- those are exactly the queries that would otherwise
fail.

Do not invent synonyms nobody uses. An alias that no one says is dead weight,
and an alias that collides with a different topic's name is reported as drift
by `wiki --check` because it makes the lookup answer with the wrong topic.

## SeeCode is a checkable claim

The owning symbol is **implicit** -- the block's own location is already a code
location, so a single-owner topic needs no `SeeCode` line at all. List the
OTHER participants:

```
/// SeeCode: TDeltaStreamer, TDeltaSet.ApplyDelta, Micronite.Delta.Pipe
```

Each entry is resolved against **the topic's own index**, in this order: the
full qualified name, then a bare name, then a dotted suffix. So
`TDeltaSet.ApplyDelta` resolves even though the index stores
`Micronite.Delta.Set.TDeltaSet.ApplyDelta` -- write it the way the code spells
it. An entry resolving to nothing is a `wiki --check` failure naming the
symbol, which is what turns the line from prose into something that goes stale
loudly instead of quietly.

Body prose is **not** checkable, and nothing pretends it is. That is the cost
of a free-text concept note, stated rather than hidden.

## What a hover shows

A short pointer, not the body:

```
- Wiki: Delta Streaming -> Micronite.Delta.Pipe - line 3
```

It is clickable and jumps to the `dl:wiki` header. That is deliberate -- a
concept body is paragraphs and a hover popup is a glance. Ordinary `<remarks>`
prose written around the block is shown as usual, so you can keep normal doc
text and a topic in the same comment without one hiding the other.

## After writing one

```
drag-lint index <the changed dir> --db <the project DB>   # ordinary incremental walk
drag-lint wiki --check --db <the project DB>              # must exit 0
drag-lint wiki --term "<one of your aliases>"             # must find it
```

The last line is not ceremony. A block with a typo'd marker, in a `//` comment,
or separated from its declaration by a blank line produces no error anywhere --
it simply does not exist. Ask for it back.

## Related

* [wiki](wiki.md) -- the verb that reads these
