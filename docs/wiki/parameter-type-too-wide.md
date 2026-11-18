# Parameter type too wide (`parameter-type-too-wide`)

A class-typed parameter whose routine only uses members that an ancestor of the declared type already declares. The signature promises more than the body needs, and callers are tied to the wider type. ON by default since 1.52 (a warning), with an autofix: see [v152-ptw](v152-ptw.md).

## Running it
```
drag-lint lint-all --db <project.sqlite> --rule parameter-type-too-wide
drag-lint lint-project --db <project.sqlite> --rule parameter-type-too-wide
```

## What it reports
One warning per parameter, at the routine's declaration, naming the parameter, the narrower type and the unit that would join `uses`. It reports exactly the fixes of `drag-lint narrow-param --all --plan`; the proof (and every refusal: virtual, overloaded, published, interface method, member write, `with`, by-reference, ...) is that verb's, see its page. The refusals are not findings.

## Applying it
`drag-lint lint <unit.pas> --db <project.sqlite> --rule parameter-type-too-wide --fix --fix-rule parameter-type-too-wide --apply --project <x.dproj> --compile-gate` fixes the unit's findings (1.52); `drag-lint narrow-param --routine <name> --project <x.dproj> --apply` rewrites one routine through the compile gate.
