> **RETIRED to INBOX-Done/ on 2026-08-15.** FIXED 2026-08-14 (84be4c9): MaskCommentsAndStrings blanks comments and string literals to spaces before the regex, preserving length and line breaks so the line/column arithmetic stays valid. This was the 4th instance of the text-scan-reads-prose family.
>
> Original note follows unchanged.

# INBOX: `undeclared-identifier` tokenises plain `{ }` comment text as code

Found 2026-08-12 while building the store-backed fixture for Task 8
(`used-before-assignment` on a record local initialised by its own method).
Separate, pre-existing defect; not fixed, not related to that task's rule.

## Repro

Any `.pas` file with a plain curly-brace comment containing ordinary capitalised
English words reproduces it. Minimal case:

```pascal
unit repro;

interface

{ Fixture 1: a record local initialised via its own method call (R.Reset),
  then used -- must NOT flag used-before-assignment. This is the false
  positive the task fixes; mirrors YADF.LineScan.ComputeBlockCommentLock,
  where St.Reset is flagged even though it is the initialising call. }
procedure Fixture1;

implementation

procedure Fixture1;
begin
end;

end.
```

Run against any indexed store:

```
drag-lint check-ast repro.pas --db <db> --format json
```

## Expected vs actual

Expected: zero `undeclared-identifier` findings inside the comment -- comment text
is not code and declares nothing.

Actual (from the Task 8 fixture, `tests\lint-store\record-method-call-def\recordmethodcalldef.pas`,
which has four such `{ }` blocks): eight spurious findings, all with start_line/col
pointing INSIDE a comment:

```
undeclared-identifier "Fixture"                  line 45 col 3
undeclared-identifier "This"                     line 46 col 54
undeclared-identifier "YADF"                     line 47 col 36
undeclared-identifier "LineScan"                 line 47 col 41
undeclared-identifier "ComputeBlockCommentLock"  line 47 col 50
undeclared-identifier "MUST"                     line 59 col 17
undeclared-identifier "FIELD"                    line 69 col 35
undeclared-identifier "CallDefs"                 line 81 col 27
```

Every one of those lines is inside a `{ ... }` comment block, never inside a
`begin..end`.

## Where it goes wrong

`TAstChecker.CheckUndeclared` in `src\diagnostics\DRagLint.Diagnostics.AstChecks.pas`
(around `:868`-`:922`) is NOT AST-based despite living in `AstChecks` and being
wired in under `check-ast`. It regex-scans the raw source text directly:

```pascal
Source:= TEncoding.Default.GetString(SrcBytes);          // :889 -- raw file text
...
Matches:= TRegEx.Matches(Source, '\b([A-Z][A-Za-z0-9_]{2,})\b');  // :895
for M in Matches do
begin
  Name:= M.Groups[1].Value;
  ...
  Syms:= AStore.FindSymbolsByExactName(Name);
  if Length(Syms) > 0 then Continue;
  ... { else emit undeclared-identifier at M.Index }
```

`Source` is never stripped of comments (`{ }`, `(* *)`, `//`) or string literals
before the regex runs, so any capitalised 3+-char word inside a comment that
happens not to already be an indexed symbol name (or on `LoadBuiltinAllowlist`)
gets reported as if it were a real, undeclared code identifier. The fix would be
either: (a) walk the AST's `comment` nodes and exclude their byte ranges from the
regex scan, or (b) use tree-sitter's actual token stream (skip comment/string
tokens) instead of a whole-file regex. Likely also affects string literals
containing capitalised words, though not verified here (only comments were hit
in the repro).

## Why it matters

It is noise, not silence -- the opposite failure mode from most of this
project's other lint defects, but the same net effect: a finding count inflated
by content that was never code makes every OTHER `undeclared-identifier` finding
in a file harder to trust, and it specifically punishes well-commented code (the
more explanatory prose in a comment, the more spurious hits).
