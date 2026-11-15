# Extract an interface from the members used (scratch + compile gate)

`extract-interface` declares an interface holding the members of a class that the rest of the project uses, and adds it to the class. Nothing else changes: no parameter or field is retyped, so no object's lifetime changes.

```
drag-lint extract-interface --class <name> --plan --db <db>
drag-lint extract-interface --class <name> --members Open,Close --name IChannel --plan --db <db>
drag-lint extract-interface --class <name> --apply --project <X.dproj> --db <db>
```

Exit: 0 plan (a refusal included, named in it), or applied and built. 1 `--apply` on a refusal, or a gate refused; the project is unchanged. 2 bad flags, no such class, an ambiguous name, or a rollback that failed. `--format json` prints `extract-interface/1`: `applied`, `class`, `file`, `line`, `interface`, `guid`, `text`, `heritage_before`, `heritage_after`, `adds_forward`, `members[]`, `left_out[]`, `refusal{kind,reason}`, `gate{refusal,detail,rolled_back,rollback_failed}`.

## Which members

A member counts as used when a reference from outside the class resolves to it, or names it through a receiver typed as the class or a descendant. A reference inside the class does not count, nor an implicit-Self one in a descendant. `--members a,b` replaces the set. All overloads of a used name go in.

A property goes in only with method accessors, which join the interface; a private accessor is a legal implementer. Method directives an interface cannot hold (`virtual`, `override`, `abstract`, `dynamic`, `reintroduce`, `final`, `inline`, `static`, `message`) are dropped; `overload`, calling conventions and hints stay.

Left out by name, and the run carries on, because the class keeps them: `field`, `not-public`, `class-member`, `generic-method`, `class-scope-name`, `field-backed-property`, `property-specifier`, `no-such-member`.

## Where it goes

The interface stands in the same type block, directly before the class and its doc comment. If a signature names the class itself, a forward `TFoo = class;` goes first unless the block has one. The GUID is a hash of the unit, the interface and its members, so the plan shows the very bytes `--apply` writes.

## Refusals

`include-file`, `stale-file`, `outside-roots`, `class-helper`, `generic-class`, `nested-class`, `ifdef-in-class`, `type-on-same-line`, `name-taken`, `unresolved-ancestor`, `no-iinterface`, `no-used-members`.

`no-iinterface`: nothing in the chain implements `IInterface`. `--reparent-interfaced` makes a class whose direct parent is `TObject` a `TInterfacedObject`; `--reparent-interfaced=norefcount` makes it a `TSingletonImplementation` instead (no reference counting; the unit needs `System.Generics.Defaults`, else `base-unit-missing`). `Create` and `Free` behave as before until someone holds an interface reference, and from then on the reference count owns the object: decide that before you retype a consumer. With `--reparent-interfaced=norefcount` the parent becomes `TSingletonImplementation` (System.Generics.Defaults) instead: an `IInterface` base that never counts references, so `Free` stays your call and no consumer needs a lifetime decision; the unit must already use System.Generics.Defaults (else `base-unit-missing`). `extract-interface` still retypes no consumer. A deeper chain is refused; give its base class `IInterface` first.

## Second step: retype one consumer

```
drag-lint extract-interface --class TFoo --retype-consumer TBar.Show.pItem --plan --db <db>
drag-lint extract-interface --class TFoo --retype-consumer TBar.Show.pItem --apply --project <X.dproj> --db <db>
```

After the interface exists and the project is re-indexed, `--retype-consumer <Routine>.<param>` changes ONE parameter from `TFoo` to the interface the class (or an ancestor) lists; `--name` picks one when the chain lists several. The declaration's header and the implementation's header change, nothing else: callers keep passing their `TFoo`, which converts to an interface it implements.

The catch is lifetime. A caller passes an object reference; the compiler turns it into an interface held in a hidden temporary, and when that temporary goes, `_Release` runs. If the class counts references (`TInterfacedObject` and friends), the count drops to 0 and the caller's instance is freed under it. No build sees that. So the retype goes ahead only when the class's `IInterface` never counts: the chain reaches `TSingletonImplementation`, `TNoRefCountObject` or `TComponent` (while it has no `VCLComObject`), or a project class whose own `_AddRef` body is just `Result:= -1`. That is why the first step offers `--reparent-interfaced=norefcount`.

The body must use the parameter only as `p.Member` with `Member` in the interface, `p = nil`, `p <> nil` or `Assigned(p)`. A cast, an `is`, a store, a `with`, or a member the interface does not hold is refused and the line is named.

Refused, in this order: `param-not-class`, `include-file`, `stale-file`, `outside-roots`, `var-param`, `param-group` (`pA, pB: TFoo`), `virtual-method` (an override and its base keep one signature), `overloaded` (a retype could move a call to another overload), `no-body`, `no-iinterface`, `unresolved-ancestor`, `lifetime-refcounted`, `lifetime-unknown`, `not-implemented`, `interface-ambiguous`, `method-resolution` (`procedure IFoo.Bar = Baz;`: the interface reaches another method), `reimplemented` (a descendant lists the interface again, so its instances would reach its own methods), `use-not-interface`, `header-shape`. `--retype-consumer` with `--members` or `--reparent-interfaced` exits 2: one step per run.

What the plan cannot see, the gates do: a routine whose address is taken with its old signature plans clean and fails the build, and the gate rolls it back. The `compile gate:` lines on stderr list what both builds said.


## The two gates

`--apply` first builds a mirror of the project in a scratch folder: the project's folder and every folder holding an indexed file, source and resource files only, with the output folders forced into the scratch. A failure there leaves the tree alone: `scratch-compile-error` when the mirror builds without the rewrite, `scratch-unusable` when it does not, `scratch-unavailable` when the files have no common folder. Only then does the ordinary compile gate run (see [narrow-param](narrow-param)): baseline build, write under backups, build, roll back on failure. That second build covers what a mirror cannot, such as a unit reached by an absolute search path.

Re-index after `--apply`. Design: `docs\superpowers\specs\2026-11-06-extract-interface-lazy-init.md`.