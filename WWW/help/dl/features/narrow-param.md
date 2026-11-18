---
id: narrow-param
title: Narrow parameter types (compile-gated)
summary: Retypes a class-typed parameter to the deepest ancestor that declares every member the routine uses, when a static proof holds, through the compile gate
product: DL
group: refactoring
order: 50009
since: 1.44.1-alpha
status: shipped
updated: 1.51.1-alpha
---

# Narrow parameter types (compile-gated)

Retypes a class-typed parameter to the deepest ancestor that declares every member the routine uses, when a static proof holds, through the compile gate.

Read this when a routine asks for a wider dependency than it needs: a parameter typed TLeaf whose body only uses what TBase declares. The verb narrows it only when it can prove every use still binds to the same member, names every refusal, and with --apply builds the project before and after and rolls back on any error.

## How to run it

```text
drag-lint narrow-param (--routine <QName> [--param <name>] | --all) (--plan | --apply --project <X.dproj>) --db <db> [--no-backup] [--platform <p>] [--rsvars <bat>] [--build-timeout <s>] [--no-compile] [--library-db <db>] [--show-bound] [--json|--format json]
```

Example:

```text
drag-lint narrow-param --routine <QName> --plan --db <db>
```

Full flag list: [narrow-param in the CLI reference](../cli.md#narrow-param).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--routine` | `<QName>` |  |  |
| `--param` | `<name>` |  |  |
| `--all` |  |  |  |
| `--plan` |  |  |  |
| `--apply` |  |  |  |
| `--project` | `<X.dproj>` |  |  |
| `--db` | `<db>` |  |  |
| `--no-backup` |  |  |  |
| `--platform` | `<p>` |  |  |
| `--rsvars` | `<bat>` |  |  |
| `--build-timeout` | `<s>` |  |  |
| `--no-compile` |  |  |  |
| `--library-db` | `<db>` |  |  |
| `--show-bound` |  |  |  |
| `--format` | `json` |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

`narrow-param` retypes a class-typed parameter to the deepest ancestor that still declares every member the routine uses.

```text
drag-lint narrow-param --routine <QName> [--param <name>] --plan --db <db>
drag-lint narrow-param --all --plan --db <db> --project <X.dproj>
drag-lint narrow-param --routine <QName> --apply --project <X.dproj> --db <db>
```

Exit: 0 plan, or applied and built, or nothing to do. 1 the gate refused and the project is unchanged, or `--apply` on one routine
whose parameter was refused. 2 bad flags, no such routine, or a rollback that failed. `--format json` prints `narrow-param/1`.
Without `--library-db` the library the manifest names is used; `--library-db none` proves against the project alone.

### The proof

Delphi binds `p.m` to the first class from `p`'s type upward that declares `m`. Take that class, D(m), for every member used;
TNarrow is the D(m) nearest `p`'s type. No class strictly below D(m) declares `m`, so from TNarrow every use binds to what it binds
to today, hidden non-virtuals included, and virtual dispatch is dynamic and unchanged. Callers compile: an argument of the old type
is an argument of an ancestor. **dcc does not catch a rebound hidden member; this rule does.** The compile gate is the backstop,
not the proof. An `override` counts as a declaration, so v1 stops at the overriding class.

### What it refuses, and why

| Kind | Why |
|---|---|
| `stale-file`, `include-file`, `outside-roots`, `ifdef-in-routine` | not what the index read, or a branch cannot be seen |
| `no-body`, `asm-body` | no body says what is used, or it uses names the index does not type |
| `virtual-routine`, `implements-interface`, `property-accessor` | the signature is a contract with something else |
| `overloaded-routine` | a new type could change which overload a caller gets |
| `published-routine` | a `.dfm` binds it by name and signature |
| `routine-as-value` | a method pointer's type names the old parameter type |
| `by-reference`, `grouped-param`, `shadowed` | `var`/`out` needs the exact type; `a, p: T` is not split in v1; another `p` inside |
| `unresolved-ancestor`, `generic-type`, `ambiguous-type-name` | the chain, or the name, is not one known thing |
| `generic-ancestor` | the narrow type would be a generic ancestor (`TBase<T>`): its bare name does not compile and the type arguments are not carried (1.47) |
| `with-body`, `other-use`, `no-member-use` | not only `p.m` reads, writes and calls and nil tests. Stored, passed on, cast, `is`, `@`: refused. A member write `p.m:= v` binds like a read and counts as a use of m (1.47; `member-write` is no longer a refusal) |
| `member-not-in-chain`, `overloaded-member`, `binding-mismatch` | the walk cannot name one declaring class |
| `dfm-bound` | a method outside the published section that a form file assigns to an event by name (1.51) |
| `uses-cycle` | the narrow type's unit cannot be added without risking a cycle |

A narrow type outside the unit's scope adds its unit to the section's uses clause. Interface-typed parameters are left alone in v1.

### Scope and bindings (1.51)

Without `--project` the plan is bounded by the project the index belongs to (the parent of its `_D-RAG` folder): a unit outside it, such as a library unit the compile closure pulled in, is refused `outside-roots` and left out of the plan. `--show-bound` adds, per parameter that reached the member proof, one line (JSON: a `bound` array) per member: the class on the chain that declares it first and why that class was chosen, including whether the index's own binding of the call agrees.

### See also

[Remove redundant casts](redundant-cast-fix.md), same gate. Guard: `tests\autotest\run_refact_narrow_param.ps1`.

### Cancel

An `--apply` run listens on the maintenance control channel: `drag-lint stop-now --db <db>` (or the IDE's Cancel) kills the
build the gate waits on, restores every written file and ends the run with exit 1 and the refusal `cancelled`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
