# Parameter type too wide (`parameter-type-too-wide`)

A class-typed parameter whose routine only uses members that an ancestor of the declared type already declares. The signature promises more than the body needs, and callers are tied to the wider type. OFF by default.

## Running it
```
drag-lint lint-all --db <project.sqlite> --rule parameter-type-too-wide
drag-lint lint-project --db <project.sqlite> --rule parameter-type-too-wide
```

## What it reports
One hint per parameter, at the routine's declaration, naming the parameter, the narrower type and the unit that would join `uses`. It reports exactly the fixes of `drag-lint narrow-param --all --plan`; the proof (and every refusal: virtual, overloaded, published, interface method, member write, `with`, by-reference, ...) is that verb's, see its page. The refusals are not findings.

## Applying it
`drag-lint narrow-param --routine <name> --project <x.dproj> --apply` rewrites the parameter through the compile gate.
