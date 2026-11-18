---
id: v152-atlb-rules
title: member-could-be-private lint rule (lane ATLB)
summary: Hint (OFF in 1.52) on a public member used only in its own unit; published, virtual, interface, attributed and shared-unit members stay silent
product: DL
group: linting
order: 30066
since: 1.52.0-alpha
status: shipped
updated: 1.52.0-alpha
---

# member-could-be-private lint rule (lane ATLB)

Hint (OFF in 1.52) on a public member used only in its own unit; published, virtual, interface, attributed and shared-unit members stay silent.

Read this to see when member-could-be-private reports a public member, which members it never touches, and why component-create-without-override was refused in favour of hides-ancestor-virtual.

## How to run it

```text
drag-lint lint-all --rule member-could-be-private --db <db> (default OFF in 1.52; naming it with --rule runs it, category project-wide, hint)
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--rule` | `<id>` |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

### member-could-be-private (hint, project-wide, default OFF)

A `public` member of a class that no file except the one declaring it references could be
`private`: Delphi's `private` is visible to the whole unit, so narrowing it breaks no caller the
index can see. The rule runs in `lint-all` only (it needs every file's references) and is OFF
by default until the false-positive measurement of the FPM lane; run it with
`drag-lint lint-all --db <db> --rule member-could-be-private`.

It stays silent whenever it cannot prove the narrowing safe:

| Case | Why silent |
|---|---|
| published member, or the unlabelled leading section of a class | streamed by the form loader / RTTI |
| virtual, dynamic, override, abstract, message, reintroduce, external routines | called through dispatch |
| constructors, destructors, members of a helper | called through the type name / not owned |
| the name is also declared by an interface of the class, or an interface ancestor does not resolve | interface implementation |
| the member carries an attribute (`[Attr]`; read from the attributes index fact, see [v152-attrrules](v152-attrrules.md)) | RTTI may read it |
| no reference at all | dead code is the business of `unused-public-symbol` |
| the name is referenced from a second file (another unit, a form file) | used elsewhere |
| the unit lists more than one project in its `dl:shared` header | a sibling project's index is not open in the run |

The check is NAME keyed, like `unused-public-symbol`'s own-unit tier: a same-named reference in
another file keeps every member of that name silent. Known limit: a unit used by a second
project WITHOUT a `dl:shared` header is judged on this project's index alone.

### component-create-without-override: refused, covered by hides-ancestor-virtual

`constructor Create(AOwner: TComponent);` without `override` in a descendant is exactly dcc
W1010, already reported by `hides-ancestor-virtual`. No new id. The fixture
`tests\lint\hides-ancestor-virtual-component-ctor.pas` and `tests\autotest\run_v152_ATLB.ps1`
prove it fires on that shape (positive control: the rule disabled).

### debug-display-placeholder: implemented in 1.52 BK-ATTRRULES

It landed on the attributes index fact; see [v152-attrrules](v152-attrrules.md).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
