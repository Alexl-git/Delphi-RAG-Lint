# INBOX -- the extraction fingerprint uses the PRODUCT version, so every release re-parses every index

**Filed:** 2026-08-17 (session 25), while cutting v1.4.0-alpha.
**Class:** design / cost. **Pre-existing**, and it bites once per release.

## The shape

`IndexerFingerprint` (`src\cli\DRagLint.CLI.pas`) is documented as *"the identity
of everything that decides WHAT this build extracts from a given byte
sequence"*, and it is built like this:

```pascal
Result:= Format('v=%s;schema=%d;pp=%d;plat=%s',
                [VERSION, Expected, Ord(APreprocess), LowerCase(EffectiveIndexPlatform(APlatform))]);
```

`VERSION` is `DRAGLINT_VERSION` -- the **product** version, the one in the CLI
banner and the LSP handshake. So **any** release bump changes the fingerprint,
and every database in the tree re-parses in full on its next index, whether or
not extraction changed at all.

## What it cost this time, concretely

v1.3.0-alpha -> v1.4.0-alpha was a release bump over a session whose changes were
**two memos, an emit-order sort, a fingerprint normalisation and instrumentation**
-- nothing that alters what the parser extracts from a byte sequence. The forced
re-parse is therefore pure cost:

| index | files | note |
|---|---|---|
| `library-Win64.sqlite` | **6,993** | the walk that has previously taken **12.5 hours** |
| ORM3 (8 project DBs) | 1,618 | just refreshed, will re-parse again |
| everything else (~21 DBs) | ~500 | |

The library index is the painful one, and it is the one the owner needs healthy
right before a DevExpress update.

## Why it is not simply "wrong"

The conservative direction is the safe one: over-invalidating costs time,
under-invalidating leaves **silently stale parses**, which is the failure this
whole mechanism exists to prevent (see
`INBOX-Done\INBOX-index-runs-are-not-resumable.md`). A bug fixed in the extractor
between two releases MUST re-parse, and the product version is a cheap
conservative proxy for "something in this build might extract differently".

So this is a cost/precision trade that was never made explicitly, not a defect.

## Options, cheapest first -- DO NOT pick from this note

1. **Separate `EXTRACTOR_VERSION` from `DRAGLINT_VERSION`.** The fingerprint uses
   the former, bumped by hand only when the parser, the extractors, the
   preprocessor or the DFM/SQL readers change. Cheap to implement; moves the
   burden to remembering to bump it -- and forgetting is the silent-stale-parse
   failure, which is far worse than a redundant re-parse. If this is chosen it
   needs a guard: something that fails the battery when extractor sources change
   without the constant moving.
2. **Derive the token from a HASH of the extraction inputs** -- the grammar
   version, the extractor unit hashes, the rule catalogue. Precise and
   self-maintaining, no discipline required; more work, and it must be stable
   across rebuilds of identical source.
3. **Leave it.** One full re-parse per release is defensible if releases are
   infrequent, and per-file resume (session 24) already means an interrupted
   re-parse continues rather than restarting.

**Measure before choosing:** how often does a release actually change extraction?
Walk the last ten tags and check whether `src\parser`, `src\index`,
`src\preprocess` or `rules\` moved. If the answer is "nearly always", option 3
wins on the spot and this note closes.

## Related

* `INBOX-Done\INBOX-indexer-fingerprint-disagrees-between-entry-points.md` --
  the platform half of this same string, fixed 2026-08-17.
* `INBOX-Done\INBOX-index-runs-are-not-resumable.md` -- per-file resume, which is
  what makes a forced re-parse survivable rather than catastrophic.
