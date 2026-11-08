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

`no-iinterface`: nothing in the chain implements `IInterface`. `--reparent-interfaced` makes a class whose direct parent is `TObject` a `TInterfacedObject`. `Create` and `Free` behave as before until someone holds an interface reference, and from then on the reference count owns the object: decide that before you retype a consumer. A deeper chain is refused; give its base class `IInterface` first.

## The two gates

`--apply` first builds a mirror of the project in a scratch folder: the project's folder and every folder holding an indexed file, source and resource files only, with the output folders forced into the scratch. A failure there leaves the tree alone: `scratch-compile-error` when the mirror builds without the rewrite, `scratch-unusable` when it does not, `scratch-unavailable` when the files have no common folder. Only then does the ordinary compile gate run (see [narrow-param](narrow-param)): baseline build, write under backups, build, roll back on failure. That second build covers what a mirror cannot, such as a unit reached by an absolute search path.

Re-index after `--apply`. Design: `docs\superpowers\specs\2026-11-06-extract-interface-lazy-init.md`.