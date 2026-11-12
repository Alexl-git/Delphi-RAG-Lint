---
id: lazy-init
title: Prepare heavy initialization for lazy loading (first phase)
summary: Names what an initialization section does; --apply moves its body verbatim into a run-once routine, through a scratch build and the compile gate
product: DL
group: refactoring
order: 50007
since: 1.50.0-alpha
status: shipped
updated: 1.50.0-alpha
---

# Prepare heavy initialization for lazy loading (first phase)

Names what an initialization section does; --apply moves its body verbatim into a run-once routine, through a scratch build and the compile gate.

Read this when the heavy-initialization rule reports a unit and you want the work out of the section. This first phase changes no behaviour: the plan shows which statement is heavy and which global could go lazy, and --apply only extracts the body, so that moving the call later is a one-line change.

## How to run it

```text
drag-lint lazy-init (--unit <name> | --all) (--plan | --apply --project <X.dproj>) --db <db> [--name <routine>] [--defer] [--no-backup] [--platform <p>] [--rsvars <bat>] [--build-timeout <s>] [--no-compile] [--library-db <db>] [--json|--format json]
```

Example:

```text
drag-lint lazy-init --all --plan --db <db>
```

Full flag list: [lazy-init in the CLI reference](../cli.md#lazy-init).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--unit` | `<name>` |  |  |
| `--all` |  |  |  |
| `--name` | `<routine>` |  |  |
| `--defer` |  |  |  |
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
| `--format` | `json` |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

`lazy-init` shows what an initialization section does and, with `--apply`, moves its body verbatim into a run-once routine that the section calls. Order and effects stay exactly as they were. This phase starts nothing later: it makes that a one-line change, which is yours to make.

```text
drag-lint lazy-init --all --plan --db <db>
drag-lint lazy-init --unit <name> --plan --db <db>
drag-lint lazy-init --unit <name> --apply --project <X.dproj> --db <db>
```

Exit: 0 plan (a refusal included, named in it), or applied and built. 1 `--apply` on a refusal, or a gate refused; the project is unchanged. 2 bad flags, no such unit, or a rollback that failed. `--format json` prints `lazy-init/1`: `applied`, `sections[]{unit,file,line,heavy,evidence,routine,text,statements[]{line,text,heavy},globals[]{name,section,readers_in_unit,readers_elsewhere,lazy_candidate},refusal{kind,reason}}`, `gate{refusal,detail,rolled_back,rollback_failed}`.

### The plan

`--all` lists the sections the [heavy-initialization](heavy-initialization.md) rule reports; `--unit` takes any section. Each top-level statement is marked heavy or light, from that rule's evidence. Each global the section writes shows where it is declared and who reads it. `lazy_candidate` is true when it is declared in the implementation section and no other unit reads it, so a later rewrite stays in one file. It is a hint about the size of the job, not a proof that lazy creation is safe.

### What --apply writes

```text
var
  GEnsureFooInitializedDone: Boolean;

procedure EnsureFooInitialized;
begin
  if GEnsureFooInitializedDone then Exit;
  GEnsureFooInitializedDone:= True;
  <the section's body, verbatim>
end;

initialization
  EnsureFooInitialized;
```

`--name` names the routine. The guard is a plain Boolean: the section, on one thread, is the only caller. Before you add a second caller, decide thread safety.

### Refusals

`include-file`, `stale-file`, `outside-roots`, `no-section` (none, or the `begin ... end.` form), `ifdef-around-section`, `empty-section`, `include-in-section`, `unbalanced-ifdef`, `name-taken` (also the fixed point: the routine exists after a first run).

### The two gates

As in [extract-interface](extract-interface.md): a build on a scratch mirror, then the ordinary compile gate. A build says the code compiles, not that it behaves the same; the extraction keeps the order by construction, and `tests\autotest\run_refact_lazy_init.ps1` compares a program's output before and after.

### --defer: start the work on first use (phase 2)

```text
drag-lint lazy-init --unit <name> --plan --defer --db <db>
drag-lint lazy-init --unit <name> --apply --defer --project <X.dproj> --db <db>
```

Opt-in, one `--unit` (with `--all` it exits 2). The section no longer calls the routine. Every routine of the unit that touches a global the section writes (the entry points, listed in the plan as `entry_points[]{name,line}`, JSON `deferred: true`) calls it as its first statement; the routine gets a forward declaration after the implementation uses clause, and finalization runs its body only when the work ran. A program that never touches the unit never runs the work.

More refusals, after `name-taken`: `no-lazy-global` (the section writes no global, so nothing marks a first use), `global-read-elsewhere` (a global it writes is declared in the interface or read by another unit), `reader-outside-routine` / `asm-reader` (a use the call cannot be put in front of), `parse-failed`, `no-entry-point`. After a deferred run the section is empty, so a second `--defer` refuses with `empty-section`.

Not thread-safe: the guard is a plain Boolean set before the work. A unit first used from two threads at once must call the routine from the application's start. Effects other units rely on without touching the globals (a registration, a print) move to the first use too: read the plan before `--apply`. Design: `docs\superpowers\specs\2026-11-06-extract-interface-lazy-init.md`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
