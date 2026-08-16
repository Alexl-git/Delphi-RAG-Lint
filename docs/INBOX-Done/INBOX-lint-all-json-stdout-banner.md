> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21).** REFUTED 2026-08-16: `lint-all --db <db> --json --quiet` stdout now begins with `[` and round-trips through ConvertFrom-Json. The banner is no longer on stdout.

# INBOX -- `lint-all --json` prints a banner into stdout, so the JSON will not parse

Found 2026-08-05 while scripting a DataCopy baseline.

## Repro

```
drag-lint lint-all --db C:\Projects\DataCopy\drag-lint.sqlite --json --quiet
```

stdout begins:

```
lint-all: scanning 24 .pas file(s)
[
  {
    "rule": "bare-except",
    ...
```

`ConvertFrom-Json` fails with `Unexpected character encountered while parsing value: l`.
Every consumer has to strip lines until the first `[`, which is exactly the workaround a
`--json` flag exists to make unnecessary.

## Why this matters / same class as a bug already fixed

This is the SAME defect class as the SARIF regression recorded in
`docs/lint/RESUME-autofix-and-hover-2026-08-05.md` section 2: `OpenReadOnlyStore` wrote a
schema-behind message to STDOUT, which landed inside the SARIF document and stopped it
parsing. That one was fixed by gating the store open on `AArgs.Fix` -- i.e. the fix was to
stop *that particular* writer from running, not to stop machine-readable output paths from
receiving human text in general. So the class survived, and here it is again on a different
command.

Note `--quiet` does NOT suppress it. `--quiet` is documented as suppressing the per-file
progress lines written to stderr; this banner is on stdout and is not covered.

## Suggested fix

Route ALL human-facing progress/status text to stderr whenever the selected output format is
machine-readable (`--json` / `--format sarif` / `--format json`), or suppress it entirely.
The durable version is a single "is this a machine-readable output path?" predicate consulted
by every writer, rather than a per-site gate -- otherwise the next writer added reintroduces
this a third time.

A regression test belongs with it: assert that stdout of `lint-all --json` parses as JSON
with no preamble. `tests/ergonomics/run_pipeline_tests.ps1` already has the SARIF equivalent
("sarif parses"), so the shape to copy exists.

## Status

**FIXED 2026-08-06.**

The durable version was taken, not the per-site gate. `DRagLint.CLI.pas` gained one
predicate and one writer, above `FinalizeAndOutput`:

- `IsMachineReadableOutput(AArgs)` -- true for `--json`, `--format json`, `--format sarif`.
- `EmitStatusLine(AArgs, AText)` -- stdout on the text path, **stderr** when the above holds.

The scanning banner, the `ERROR: no drag-lint index found` line and the
`baseline written:` line all route through it, so text output is byte-identical and the
machine-readable paths carry no prose. The banner is REDIRECTED, not deleted -- progress
still reaches stderr, where `--quiet` governs it.

Regression test: `tests\ergonomics\run_pipeline_tests.ps1` section 6 (16 pass / 0 fail).
It parses the RAW stdout with no preamble-stripping, asserts stdout starts at `[`, asserts
the banner is absent from stdout, AND asserts it is still present on stderr -- that last
one so a future "fix" that simply silences progress output fails here instead of shipping.
`--quiet` is deliberately not passed: it never covered this line, and a fix that only works
under `--quiet` is not a fix.

One trap worth recording for whoever writes the next stderr assertion in PowerShell:
`2>&1 1>$null` does NOT isolate stderr -- `2>&1` merges the streams first and `1>$null`
then discards both. Merge, then keep the `[System.Management.Automation.ErrorRecord]`
items. The first draft of the test failed for exactly this reason while the product was
already correct.
