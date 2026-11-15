---
id: v151-dfma-rules
title: Form and unit consistency rules
summary: "Lint rules comparing a form unit with its .dfm and .dpr: fields vs objects, form resource, inherited handlers, self-free, auto-created forms"
product: DL
group: linting
order: 30047
since: 1.51.0-alpha
status: shipped
updated: 1.51.0-alpha
---

# Form and unit consistency rules

Lint rules comparing a form unit with its .dfm and .dpr: fields vs objects, form resource, inherited handlers, self-free, auto-created forms.

Read this when a form loads with a nil field, raises EResNotFound, loses an ancestor's event handler or ends up with two instances: these rules read the .pas, its sibling .dfm and the .dpr together and say which file to change.

## How to run it

```text
drag-lint lint <path> [--profile <name>] [--target-compiler <ver|auto>] [--rule <id>|help] [--disable id1,id2] [--rules-dir <dir>] [--json] [--labels] [--no-preprocess] [--library-db <lib.sqlite>] [--build-config <name>]
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>] [--disable id,...] [--output <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none]
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

A form lives in two files: the `.pas` that declares its class and the `.dfm` the designer writes. The compiler reads only the first, and the form file is read at run time, so the two can drift apart with no compiler message at all. These rules compare them, and compare a unit with the `.dpr` that creates its forms.

They run in `lint <file.pas>` (the sibling `.dfm` with the same base name is read with it) and in `lint-all`. Without an index they still work on what the unit and its folder show; with an index (`--db`) they also follow ancestors, used units and the project's `.dpr` through it. A binary `.dfm`, or a unit that does not declare the class of the form file's root object, keeps every rule silent.

| Rule | Default | What it reports |
|---|---|---|
| `form-field-without-object` | see below | a published field of the form class with no object of that name in the form file: it stays nil after loading |
| `form-object-without-field` | see below | an object (or frame instance) of the form file with no field in the form class or its ancestors |
| `form-field-type-mismatch` | see below | a published field whose class is not the class of the form object, nor an ancestor of it |
| `form-resource-missing` | see below | the unit declares the form file's root class but includes no `{$R *.dfm}`: creating the form raises EResNotFound |
| `inherited-form-handler-without-inherited` | see below | an inherited form re-declares a handler that an ancestor form file assigns, under the same name, without calling `inherited` |
| `self-free-in-event-handler` | see below | a form frees itself (Free, Destroy, DisposeOf, FreeAndNil) in one of its own event handlers |
| `form-autocreate-and-manual` | see below | the `.dpr` creates a form with `Application.CreateForm` and the code assigns `TForm.Create(...)` to the same global variable |
| `form-access-before-create` | see below | the constructor, AfterConstruction or OnCreate handler of an auto-created module reads the global variable of a module the `.dpr` creates later |
| `foreign-form-control-access` | off | code reaches a control of another unit's form through its global variable (`Form2.Edit1.Text`) |
| `unit-missing-from-uses` (form file side) | on (host rule) | a `.dfm` property points at a component of another module (`DataSet = dmMain.qryItems`) whose unit is not in the uses clause |

### Examples

```pascal
type
  TCustomerForm = class(TForm)
    edtName: TEdit;
    btnSave: TButton;   // form-field-without-object: no "object btnSave" in the .dfm
  end;
```

```text
object CustomerForm: TCustomerForm
  object edtName: TButton     // form-field-type-mismatch on the field edtName: TEdit
  end
  object Button2: TButton     // form-object-without-field
  end
end
```

```pascal
procedure TMessageForm.btnOKClick(Sender: TObject);
begin
  Free;        // self-free-in-event-handler: use Release
end;
```

```pascal
// Project.dpr: Application.CreateForm(TReportForm, ReportForm);
ReportForm:= TReportForm.Create(Application);   // form-autocreate-and-manual
```

### What stays silent
- `form-field-without-object`: fields in private, protected or public sections; a name that exists anywhere in the form file.
- `form-object-without-field`: `inherited` objects, objects inside an `inline` frame (they belong to the frame), collection items, unnamed objects, a field declared by an ancestor class (in the unit, or in the index).
- `form-field-type-mismatch`: the object's class is unknown (not in the unit, the index or the library index), or its ancestor chain has a gap and the field's class is a library class.
- `form-resource-missing`: a `{$R *.dfm}` / `{$R Name.dfm}` (or `.fmx`, `.xfm`, `.nfm`) directive in any branch of conditional compilation counts. A directive inside a comment does not. The opposite case -- a `{$R *.dfm}` with no file next to the unit -- is left to the compiler (F1026).
- `inherited-form-handler-without-inherited`: a handler that calls `inherited` anywhere, a handler of a different name (a deliberate replacement), no ancestor form file found (the index, or a used unit in the same folder).
- `self-free-in-event-handler`: statements inside an anonymous method or a `with` block, freeing a control (`btnClose.Free`), `Release`, a method that is neither named in the form file nor has a `Sender: TObject` parameter, frames and data modules.
- `form-autocreate-and-manual`: the routine tests the variable (`Assigned`, a comparison with nil) or frees it first; a local or a field of the same name; a class other than the one CreateForm names; a unit no `.dpr` lists.
- `form-access-before-create`: the routine tests, assigns or shadows the variable; modules created earlier; modules the `.dpr` does not create.
- `unit-missing-from-uses`: references to the form itself or to its own components (an embedded frame), modules whose unit is known neither from the `.dpr` (`Unit1 in 'Unit1.pas' {Form1}`) nor from the index.

### Where the `.dpr` comes from
Every `.dpr` of the index, then every `.dpr` in the unit's folder; the first whose uses clause names the unit is the project. Commented-out `CreateForm` lines do not count.

### Fixes
No autofix: every repair changes run-time behaviour (adding `{$R *.dfm}`, `inherited;`, `Release`, removing a CreateForm line), so each message says what to change instead.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
