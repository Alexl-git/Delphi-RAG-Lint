# RETIRED ON THE DAY IT WAS FILED -- the O(corpus) affected-set was a FIXTURE ARTEFACT

**Filed and refuted 2026-08-16 (session 23).** Kept, rather than deleted, because
the measurement that killed it is worth more than the hypothesis was.

## The hypothesis

While measuring the (now retired) 25x reindex note on a SYNTHETIC corpus, the
incremental reindex of ONE touched file grew linearly with corpus size:

| N files (synthetic) | reindex of 1 touched file |
|---|---|
| 10  | 1.67 s |
| 50  | 7.85 s |
| 200 | 29.07 s |
| 400 | 59.81 s |

and the exe's own output blamed the call-resolve:

```
resolve: calls  32000 edge(s) from 64120 affected call-site ref(s) in 1 changed file(s)  [57.1s]
```

57.1 s of 57.9 s, with one changed file marking ~every call site in the DB. The
proposed mechanism was a NAME-KEYED affected set: touch a file, and every ref
sharing a name with anything it declares becomes affected. Real Delphi shares
names heavily (`Create`, `Free`, `Execute`, `Add`), so this looked serious.

## The refutation -- measured on real code, which is why it was required first

DataCopy (`DataCopy-App`, 17 files, 10,890 refs). Touch ONE file, reindex:

```
C:\Projects\DataCopy\uFileUtils.pas -> 297 symbols, 1988 refs, 0 errors
resolve: calls  129 edge(s) from 748 affected call-site ref(s) in 1 changed file(s)  [0.8s]
```

* affected set = **748**, i.e. **6.9%** of the DB's 10,890 refs -- not the corpus;
* and decisively, **748 is SMALLER than the changed file's own 1,988 refs**.

The affected set is a subset of the touched file's own call sites. **There is no
amplification at all on real code.** The synthetic result came entirely from the
fixture: its generated units repeat the same method names across every file, so
name-keying selected everything. That is a property of the generator, not of the
engine.

## What this cost, and what it bought

The note's own "suggested first step" was *measure on a real DB before
optimising*, and following it took two commands and refuted the finding
completely. Had it been skipped, the next step would have been an M-L redesign of
the affected-set keying to fix a problem that does not exist -- guided by a
number (400x) that was an artefact of a test harness.

**The generalisable lesson: a synthetic corpus is a valid way to expose a SLOPE
(it did exactly that for the FK-cascade cost, which was real) and an invalid way
to size an effect that depends on the DISTRIBUTION of real identifiers.** The
same fixture proved one defect and invented another.

## Still true, and still worth having

The FK-cascade slope from the same experiment IS real, IS reproducible on a ~3 MB
DB, and its fix has already shipped -- see
`INBOX-Done\INBOX-library-reindex-25x-slower-on-large-db.md`.

## Not closed by this

`INBOX-incremental-index-hangs-on-large-db` remains open on its own evidence.
This note originally speculated the two were the same defect; that link is now
withdrawn, since the mechanism proposed here does not exist. Do not carry the
connection forward.
