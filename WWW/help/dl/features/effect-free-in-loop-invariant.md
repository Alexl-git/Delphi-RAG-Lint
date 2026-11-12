---
id: effect-free-in-loop-invariant
title: Effect-free call in a loop that could move out (lint rule)
summary: "Project-wide lint rule, ON by default since 1.43: a proven effect-free call inside a loop whose arguments, and the state it reads, cannot change in that loop"
product: DL
group: linting
order: 30010
since: 1.42.0-alpha
status: shipped
updated: 1.50.0-alpha
---

# Effect-free call in a loop that could move out (lint rule)

Project-wide lint rule, ON by default since 1.43: a proven effect-free call inside a loop whose arguments, and the state it reads, cannot change in that loop.

Read this to see when effect-free-in-loop-invariant fires and why it stays silent. It reads the stored purity facts in lint-all and names the loop the call can move out of.

## How to run it

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

A project-wide lint rule, severity **info**, ON by default since 1.43 (owner ruling: rules are ON unless they cost time or give many false positives; turn it off with `--disable effect-free-in-loop-invariant`): a call to a PROVEN effect-free, value-returning routine inside a loop, where every iteration would get the same answer. The call can move in front of the loop.

```pascal
for var O in Row do
  if O.StartCol >= RefEnd(ARef) then ...   // RefEnd(ARef) answers the same every time
```

The rule stands on the stored purity facts (`symbol_facts.effect_free`), so it decides from what the index proved, not from a name.

### Running it from the CLI
```text
drag-lint lint-all --db <project.sqlite> --enable effect-free-in-loop-invariant
drag-lint lint-all --db <project.sqlite> --enable effect-free-in-loop-invariant --rule effect-free-in-loop-invariant   (only this rule)
```

### What it reports
* One info finding per (call line, callee): the callee, the line of the loop, and which proof held.
* Inside a loop means its body or a `while` / `until` condition. A `for` bound and a `for .. in` enumerable run once and do not count.

### The proofs
Both of these must hold.

**The arguments and the receiver cannot change.** Each name in them is a by-value local or parameter that the loop does not assign, step or hand to a call not proven effect-free, or it is a constant or a type.

**The state the callee reads cannot change**, by either of:
1. *The loop is frozen*: it writes only local variables, and every call in it is proven effect-free or one of a short list of RTL routines that depend on their arguments alone. Nothing the callee reads can move.
2. *The callee reads no state*: its body names only its own by-value locals, constants and those RTL routines.

### What it does not report
* A routine whose name has any overload or override that is not proven effect-free.
* A local whose address is taken in the routine, or that a nested routine or closure mentions; a `var` / `out` parameter (it may alias state).
* Anything under a `with`, or a loop holding `with` or `asm`.
* A one-line accessor (`Result:= FField`): moving it saves nothing.

It assumes no other thread writes what the callee reads, and that a property getter has no effect (`property-getter-with-effect` looks for those).

Guard: `tests\lint-project\effect-rules\run_effect_rules.ps1` (fixture `uLoopInv.pas`).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
