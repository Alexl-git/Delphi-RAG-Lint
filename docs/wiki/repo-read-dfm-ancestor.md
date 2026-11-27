# Datasets of an inherited form or data module (`repo read-dfm`)

`drag-lint repo read-dfm` follows a dataset name into the DFM of the ancestor form or data module. Nothing new is
typed: the same command reads more.

```
drag-lint repo read-dfm --dfm <form.dfm>[;...] --direction dfm-to-repo (--repo <file> | --project <project file>)
```

## Why

A DFM whose first line is `inherited dmOrders: TdmOrders` holds only what the descendant changes. The table name, the
SQL and the persistent fields of an inherited dataset are in the DFM of the ancestor class. Before 1.56 a memory table
filled from such a dataset, and a lookup field that names one, were reported as unresolved:

```
dataset uForm.dfm memOrders (TFDMemTable) -> UNRESOLVED (linked to dmDerived.tblOrders (CopyDataSet), which has no table: ...)
```

Now the dataset is read as the form has it at run time:

```
dataset uForm.dfm memOrders (TFDMemTable) -> ORDERS (via CopyDataSet dmDerived.tblOrders)
warning: uDerived.dfm tblOrders: read from the ancestor uBase.dfm
```

## Where it applies

| Place | What is followed |
|---|---|
| the source of a link (`AttachedTo`, `AttachTable`, `CloneCursor`, `CopyDataSet`, `CopyData`, `AppendData`, `Data :=`) | a dataset the module only inherits, or does not mention at all |
| `LookupDataSet` of a lookup field | the same |
| the dataset behind the data source of a grid view | the same |

The `inherited` dataset of an inherited form itself is read the same way (1.56 GCR-2): the line
`dataset PathToData.dfm tblOSublot (TFDTable) -> OSUBLOT: ...` now has the ancestor's table and fields, then the fields
the descendant adds. Its handler code is read where it is written: the calc bodies from the unit of the form whose DFM
states `OnCalcFields`, the events of a field from the unit of the form whose DFM declares the field. Only when no
ancestor is found the line still ends in `UNRESOLVED (... (inherited: its own properties are in the ancestor's DFM))`.

## How the ancestor is found

1. The first object line of the DFM says `inherited Name: TClass` (text or binary DFM).
2. The unit beside the DFM declares `TClass = class(TAncestor)`. Comments are not read; a unit qualifier and type
   arguments are dropped.
3. The ancestor DFM is the ONE DFM of the same folder whose root class is `TAncestor`. Its own ancestor is followed the
   same way.

What the descendant states wins (`TableName`, `UpdateOptions.UpdateTableName`, `SQL`, `OnCalcFields`, `AttachedTo`);
the fields are the ancestor's, then the fields the descendant adds.

## What is not followed (each is a warning, nothing is picked)

| Warning | Meaning |
|---|---|
| `X.dfm: inherited from an ancestor form, but no unit beside the DFM names it: ancestor not read` | no `X.pas` next to the DFM |
| `X.dfm: X.pas declares no ancestor class for TClass: ancestor not read` | the class declaration was not found in the unit |
| `X.dfm: no DFM of this folder has the ancestor class TAncestor: ancestor not read` | the ancestor form is in another folder, or has no DFM |
| `X.dfm: 2 DFMs of this folder have the ancestor class TAncestor: ancestor not read` | a copy of the ancestor DFM is in the folder |

Known limits: a property an inherited FIELD overrides (for example `DisplayLabel`) is not applied to the ancestor's
field; a property the descendant resets to an empty value reads as the ancestor's value; a link in the ANCESTOR's unit
code is not followed for the descendant; the calc bodies of an inherited dataset that is a JOIN are looked for in the
descendant's unit only.

## A module in another folder (1.56 GCR-2)

`dmX.tblY` in a link, a `LookupDataSet` or a grid's data source names a module. The module is first looked for in the
folder of the form (one DFM with the root object `dmX`). When that folder has none:

1. The form's unit must USE the module's unit (interface or implementation `uses`; comments are not read).
2. The DFM of that unit (`uMod.dfm` for `uses uMod`) is looked for in the project folder and every folder below it.
   The project folder is the nearest folder, from the form's folder up to three levels above it, that holds a
   `.dpr`, `.dproj` or `.dpk`; without one it is the form's own folder. Folders whose name starts with `__` or `.`
   (`__history`, `__recovery`, backup copies, `.git`) are not searched.
3. Exactly one such DFM with the root object `dmX` is the module. Two give the warning
   `X.dfm: 2 DFMs of the used unit uMod have the root dmX (dm\uMod.dfm, old\uMod.dfm): module not read` and nothing
   is picked.

A module whose unit the form does not use is not found: the dataset stays `UNRESOLVED (linked to dmX.tblY (...), which is no dataset of the form or of a module
beside it)`.

## Search path, ancestor in another folder, inherited code (1.56 GCR-3)

* **Search path.** When the project folder holds no DFM of the used unit, the `DCC_UnitSearchPath` of the `.dproj` found as above (the base groups and the active configuration's group) is searched too: every entry without an unresolved `$(...)` macro is a folder (`$(DCC_UnitSearchPath)` itself is skipped), and `<uUnit>.dfm` is looked for flat in it. Hits join the same candidate list: two candidates are still a warning and nothing is picked.
* **Ancestor form in another folder.** When the form's own folder holds no DFM with the ancestor class, the ancestor is looked for by its class among the DFMs of the module finder (project folder, search path); the own folder still wins.
* **Inherited code.** For a component the form inherits, the link sources, the field writes and the calc bodies are read from the units of the ancestor chain (the unit of the form that states them), not only from the descendant's unit; a calc body of an inherited JOIN dataset is looked for in the same chain.
* **Write side.** `repo write-dfm` no longer proposes removing a derived field (a `DL_FIELDS_INFO` row with `DERIVED_KIND`) that the selection leaves out; derived rows are not table data.

## `AttachTable(X.Table, ...)`

FireDAC's `AttachTable` takes the storage of a dataset, so `memA.AttachTable(tblB.Table, nil)` links `memA` to the
dataset `tblB` (and `dm.tblB.Table` to `dm.tblB`). Before 1.56 `tblB` was taken for a module name and the link was
unresolved. No other call reads `.Table`.

## See also

- [Read a form into the field repository](repo-read-dfm) -- the command, its flags and the change set.
