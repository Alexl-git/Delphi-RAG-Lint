# INBOX -- `BuildFor`'s defaulted arguments still diverge between entry points

- **Filed:** 2026-08-13, immediately after fixing the `AIncludeSeeAlso` half of it
  (commit `9414826`).
- **Class:** `wrong` -- two callers render the same declaration's facts block
  differently, and neither is aware of it.
- **Related:** the fixed half is the same bug one argument to the left.

## The shape

`TDocumenter.BuildFor` carries a long defaulted tail:

```pascal
class function BuildFor(const AStore: ISymbolStore; const AQName: string;
  AIncludeSeeAlso: Boolean; AIncludeSince: Boolean = False;
  const ABaseDir: string = ''; const AExtraStores: TArray<ISymbolStore> = nil;
  AMaxReturnCases: Integer = 20; AMaxCallers: Integer = 5;
  AComplexityMin: Integer = 10): TDocumentResult;
```

Every `document` entry point passes the REAL values, read from the manifest
(`CLI.pas:9101`):

```pascal
AArgs.DocSince, AArgs.DocBaseDir, OpenExtraStores(AArgs),
LoadDocMaxReturnCases, LoadDocMaxCallers, LoadDocComplexityMin
```

`TDocLintRules.FixEditsForDocDrift` passes **none of them**. It now passes
`AIncludeSeeAlso` (that was the measured defect, fixed 2026-08-13) and takes the
defaults for the rest.

## Why that is a live defect, not tidiness

The manifest and the defaults DISAGREE today:

| setting | manifest (`dll-win64\drag-lint.json`) | `BuildFor` default |
|---|---|---|
| `max_return_cases` | **6** | **20** |
| `max_callers` | 5 | 5 |
| `complexity_min` | 10 | 10 |
| `accessor_trivial_max_lines` | 2 | (not a BuildFor arg) |

So for any function with more than 6 minable return cases, the checker renders a
`Returns:` list capped at 6 and the repairer renders one capped at 20. That is
EXACTLY the failure just fixed for `<seealso>`: the checker reports "managed
facts block is out of date", the repairer regenerates something that does not
match what the checker wanted, and either nothing happens or the two fight.

`AExtraStores` is the same story for INBOUND facts (`Called from:`, `Used by:`):
`document` searches every resolved db, the repair path searches one.

## Why it was not fixed at the same time

It has NOT been observed producing a wrong result -- it is derived from reading
the signatures. Three plan-stated mechanisms died this session from being
implemented on reasoning alone, so this is filed rather than guessed. **Reproduce
first**: find (or construct) a decl with >6 return cases, documented, in a store
where the manifest cap is 6, and check whether `lint-all --fix` and
`document --qname` disagree.

## The real fix, when someone does it

Stop passing nine positional arguments from two places and expecting them to stay
in step. Give the doc layer ONE options record, built once per run from the
manifest + args, and thread that. The defaulted tail is what made this class of
bug invisible: omitting an argument silently substitutes a different
configuration, and the compiler is happy.

## Second, smaller finding: the two commands discover different config files

From the SAME working directory (`C:\Projects\YADF`):

```
drag-lint lint-all --project YADF.dproj   ->  (loaded defaults from C:\Projects\.drag-lint.json)
drag-lint document --qname <X> --db <db>  ->  (loaded defaults from C:\Projects\YADF\.drag-lint.json)
```

`C:\Projects\YADF\.drag-lint.json` is `{"docs":{"max_return_cases":20}}` -- a doc
setting. So the two commands can read different doc configuration on the same
project, which is the same hazard by another route.

**Measured NOT to be the cause of the 2026-08-13 doc-drift defect** -- forcing
`lint-all --config C:\Projects\YADF\.drag-lint.json` changed nothing, and running
`document --project` from a neutral CWD changed nothing. Recorded so the next
person does not re-derive it, and because two commands disagreeing about which
config governs a project is a defect on its own.
