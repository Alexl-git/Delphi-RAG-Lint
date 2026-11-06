# Remove redundant casts (compile-gated)

`lint --fix --fix-rule redundant-cast` removes a hard cast `TFoo(x)` when the index proves `x` already has exactly the type
`TFoo`. A dry run prints the plan; `--apply --project <X.dproj>` writes it through the compile gate.

```
drag-lint lint --fix --fix-rule redundant-cast --db <db> --project <X.dproj>            plan
drag-lint lint --fix --fix-rule redundant-cast --db <db> --project <X.dproj> --apply    write
```

Exit: 0 plan, or applied and built, or nothing to do. 1 the gate refused and the project is unchanged. 2 bad flags, an index
older than `ref_types`, or a rollback that failed. `--format json` prints `redundant-cast/1`: `fixes[]`, `refused[]` (each with
`kind` and `reason`), `not_identity`, `gate`.

## What it proves

The operand's last name has a row in `ref_types`, the cast has one too, and both name the SAME type symbol. Removing such a cast
changes nothing: same type, same overloads, same member binding. Identity only: an upcast can change which hidden non-virtual
member binds, so `TBase(Derived)` is a real conversion and is left alone (counted as `not_identity`, not listed).

## What it refuses, and why

| Kind | Why |
|---|---|
| `stale-file`, `include-file`, `outside-roots` | the file is not what the index read; an include compiles in many units; not this project's |
| `not-a-plain-cast`, `multi-line`, `comment-in-cast`, `ifdef-line` | the text is not a one-line, comment-free `T(x)` |
| `operand-shape` | index, dereference, operator, literal, `nil`: the row would type something else than the operand |
| `nested-cast` | inner first; the outer half is decided after a re-index |
| `operand-untyped`, `operand-type-unresolved`, `type-not-indexed` | no static type, or only bare text: `Integer(N)` lands here, the project does not declare `Integer` |
| `alias-not-identical` | `TA = type TBase` is a distinct type |
| `ambiguous-type-name` | the name also means another type or a routine: the call cannot be proved a cast |
| `generic-type` | the symbol id does not carry the type arguments |
| `procedural-type` | a procedural value without its cast may be called instead of read |
| `overloaded-operand` | the index picks an overload by heuristics |
| `conditional-decl` | the type or the operand is declared under `{$IF...}`: another configuration may differ |
| `with-body` | a `with` precedes it in the routine: its names may bind to the subject |
| `unresolved-ancestor` | a member of an unindexed ancestor could hide these names; attach the library (`--library-db`) |

A qualified cast (`Unit1.TFoo(x)`) has no cast row and is not seen at all.

## The batch

A plain `lint --fix` no longer touches `redundant-cast`: it says so on stderr and points here. The IDE's "Fix it" runs without
`--project`, so `--apply` from there answers exit 2 with the command to run.

## See also

The compile gate: `DRagLint.Refactor.CompileGate`, shared with [`cycles --fix`](Circular-Uses-Report-cycles-fix-plan). Guard:
`tests\autotest\run_refact_redundant_cast.ps1`.