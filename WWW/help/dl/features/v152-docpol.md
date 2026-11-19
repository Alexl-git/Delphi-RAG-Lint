---
id: v152-docpol
title: "Documentation policy: missing-doc, doc-placeholder, doc-malformed-summary"
summary: missing-doc covers DFM-bound handlers with code; doc-placeholder (ON, hint) flags template summaries; doc-malformed-summary (OFF) flags declaration-like ones
product: DL
group: documentation
order: 40012
since: 1.52.0-alpha
status: shipped
updated: 1.51.1-alpha
---

# Documentation policy: missing-doc, doc-placeholder, doc-malformed-summary

missing-doc covers DFM-bound handlers with code; doc-placeholder (ON, hint) flags template summaries; doc-malformed-summary (OFF) flags declaration-like ones.

Read this to see which declarations missing-doc expects a doc comment on after 1.52 (a bound Button1Click with code now needs one, an empty one does not), and how doc-placeholder and doc-malformed-summary catch summaries that are not descriptions.

## How to run it

```text
drag-lint lint-all --db <db> [--rule missing-doc|doc-placeholder|doc-malformed-summary] (documentation rules: missing-doc OFF by default, document all real code, an empty DFM-bound handler is exempt; doc-placeholder ON hint; doc-malformed-summary OFF hint)
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<db>` |  |  |
| `--rule` | `<id>` |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

The documentation rules read the symbol store, so they run under `drag-lint lint-all --db <db>` (and `lint` when the file is indexed).

### missing-doc (OFF by default; opt in with `"enabled": ["missing-doc"]`)

A public or published declaration needs a DocInsight doc comment. Since 1.52 the policy is: document ALL real code.

| Declaration | missing-doc |
|---|---|
| DFM-bound handler (`OnClick = Button1Click`) whose body has code | fires (reverses the 1.51.1 skip) |
| DFM-bound handler whose body is empty (only comments) | silent |
| getter / setter of a documented property, `override` | silent (unchanged from 1.51.1) |

### doc-placeholder (ON, hint)

A summary that is a template placeholder (`/// <summary>Summary here ...</summary>`) is not a description. It does not count as documented: the declaration gets a `doc-placeholder` finding. Replace the text with what the routine does.

### doc-malformed-summary (OFF, hint)

A summary that opens like a declaration (`/// <summary>procedure Foo(AValue: Integer);</summary>`) repeats the signature instead of describing the routine. Opt in with `"enabled": ["doc-malformed-summary"]`. Prose such as "Function that returns ..." is not matched.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
