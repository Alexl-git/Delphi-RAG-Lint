# parameter-type-too-wide: ON by default, with an autofix (1.52)

Since 1.52 the project rule [`parameter-type-too-wide`](parameter-type-too-wide.md) ships **ON** as a **warning**
in `lint-all` and `lint-project`, and it has an autofix (owner ruling B7).

## What it reports

A class-typed parameter whose routine only uses members that an ancestor of the declared type already declares:

```pascal
procedure FreeMid(pP: TLeaf);   // warning: only members of TMid are used -- declare it TMid
begin
  pP.MidOp;
end;
```

The proof is the one `drag-lint narrow-param --all --plan` makes. The rule reports exactly that plan's fixes, one
warning per parameter, at the routine's declaration.

## What it skips

Where you have no choice about the signature, the rule is silent:

| Skip class | Why |
|---|---|
| library code (a unit outside the project's own roots) | not yours to change; the index must live in the project's `_D-RAG` folder, or pass `--project` |
| `virtual`, `override`, `dynamic`, `abstract`, `message` methods | the signature is shared with the other methods of the chain |
| interface methods | an interface is implemented by name and signature |
| published methods, and methods a `.dfm` binds to an event | a form file binds a handler by name and signature |
| routines taken as a value (assigned to an event or a method pointer / procedural variable) | the pointer's type names the old parameter type |
| overloaded routines, property accessors, `var` / `out` parameters | see [narrow-param](narrow-param.md) for the full list of refusals |

`lint <unit>` evaluates the rule only with `--rule parameter-type-too-wide` and an index: the proof needs the whole
project, so it is not part of the per-file default set (and so not of the IDE gutter).

## Fixing it

```
drag-lint lint <unit.pas> --db <project.sqlite> --rule parameter-type-too-wide ^
  --fix --fix-rule parameter-type-too-wide --fix-line <n> --apply --project <X.dproj> --compile-gate
```

The fix re-proves the finding first (a body that changed since the index was built is declined, not applied), then
retypes the parameter in the routine's declaration and implementation headers, and adds the ancestor's unit to the
uses clause of the section that declares the routine when it is not in scope yet. With `--compile-gate` the project
is built before and after the write and the edit is rolled back if the build breaks. Without `--fix-line` every
finding of the unit is fixed in one pass; with a platform library index (`--library-db`) VCL and RTL ancestors are
proved too.

## Review instead of fixing

A `dl:ok parameter-type-too-wide` marker on the routine's declaration line reviews one finding; `"parameter-type-too-wide":
{ "enabled": false }` in the project lint config turns the rule off for a project.
