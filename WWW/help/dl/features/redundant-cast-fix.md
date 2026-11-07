---
id: redundant-cast-fix
title: Remove redundant casts (compile-gated)
summary: Removes hard casts whose operand already has exactly the target type, proved from the index's static types and written through the compile gate
product: DL
group: refactoring
order: 50011
since: 1.44.1-alpha
status: shipped
updated: 1.46.0-alpha
---

# Remove redundant casts (compile-gated)

Removes hard casts whose operand already has exactly the target type, proved from the index's static types and written through the compile gate.

Read this when lint reports redundant-cast. The fix removes a cast only when the index proves the operand has the very type it is cast to; everything it cannot prove stays in the source and is listed with a named refusal. With --apply it builds the project first and after, and rolls back on any error.

## How to run it

```text
drag-lint lint --fix --fix-rule redundant-cast --db <db> [--project <X.dproj> --apply] [--in <f.pas>] [--fix-line <L>] [--no-backup] [--platform <p>] [--rsvars <bat>] [--build-timeout <s>] [--no-compile] [--library-db <db>] [--format json]
```

Example:

```text
drag-lint lint --fix --fix-rule redundant-cast --db <db> --project <X.dproj> --apply
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--fix` |  |  |  |
| `--fix-rule` | `redundant-cast` |  |  |
| `--db` | `<db>` |  |  |
| `--project` | `<X.dproj>` |  |  |
| `--apply` |  |  |  |
| `--fix-line` | `<L>` |  |  |
| `--no-backup` |  |  |  |
| `--rsvars` | `<bat>` |  |  |
| `--build-timeout` | `<s>` |  |  |
| `--no-compile` |  |  |  |
| `--library-db` | `<db>` |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

`lint --fix --fix-rule redundant-cast` removes a hard cast `TFoo(x)` when the index proves `x` already has exactly the type
`TFoo`. A dry run prints the plan; `--apply --project <X.dproj>` writes it through the compile gate.

```text
drag-lint lint --fix --fix-rule redundant-cast --db <db> --project <X.dproj>            plan
drag-lint lint --fix --fix-rule redundant-cast --db <db> --project <X.dproj> --apply    write
```

Exit: 0 plan, or applied and built, or nothing to do. 1 the gate refused and the project is unchanged. 2 bad flags, an index
older than `ref_types`, or a rollback that failed. `--format json` prints `redundant-cast/1`: `fixes[]`, `refused[]` (each with
`kind` and `reason`), `not_identity`, `not_identity_by`, `gate`.

### What it proves

The operand's last name has a row in `ref_types`, the cast has one too, and both name the SAME type symbol. Removing such a cast
changes nothing: same type, same overloads, same member binding. Identity only: an upcast can change which hidden non-virtual
member binds, so `TBase(Derived)` is a real conversion and is left alone (counted as `not_identity`, not listed).

`not_identity_by` splits that count by why the two types differ, each class with one example: `enum-target` (a scalar to an enum, `TCommandID(Hdr.CommandID)`),
`other-target`, `downcast`, `upcast`, `unrelated`, `chain-unknown` (an ancestor no index holds: attach the library) and `same-name` (two symbols of one
name). A zero fix count beside a large `not_identity` means those casts do real work, not that the proof gave up.

### What it refuses, and why

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

### The batch

A plain `lint --fix` no longer touches `redundant-cast`: it says so on stderr and points here. The IDE's "Fix it" runs without
`--project`, so `--apply` from there answers exit 2 with the command to run.

### See also

The compile gate: `DRagLint.Refactor.CompileGate`, shared with [`cycles --fix`](circular-uses-report-cycles-fix-plan.md). Guard:
`tests\autotest\run_refact_redundant_cast.ps1`.

### Cancel

An `--apply` run listens on the maintenance control channel: `drag-lint shutdown --db <db>` (or the IDE's Cancel) kills the
build the gate waits on, restores every written file and ends the run with exit 1 and the refusal `cancelled`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
