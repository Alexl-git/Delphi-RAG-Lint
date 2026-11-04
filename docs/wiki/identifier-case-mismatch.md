# Identifier case mismatch (`identifier-case-mismatch`)

A name is spelled in a different case from its declaration. Delphi does not care, so this is a readability rule, and also a way to catch code that was never read after a rename. OFF by default.

## Running it
```
drag-lint lint <file> --rule identifier-case-mismatch
drag-lint lint-all --db <project.sqlite> --rule identifier-case-mismatch
```

## What it covers
- Locals and parameters, from the syntax tree, so no index is needed.
- With an index: every ref the resolver bound to a project symbol (methods, properties, routines), across units.

One finding per spelling per routine for locals, and one per spelling per symbol per file for bound refs, so a legacy file does not produce one line per use.

## What stays silent
- Anything inside `with`: a bare name may be a member there.
- A name after a dot, unless the resolver bound it.
- A local declared twice in different spellings (two inline blocks).
- A nested routine's use of an outer local: the nested routine is judged on its own declarations.
- A ref the resolver did not bind, and names from the platform library.