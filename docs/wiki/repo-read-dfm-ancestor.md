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

The dataset of an inherited form itself (the line `dataset PathToData.dfm tblOSublot ... (inherited: its own properties
are in the ancestor's DFM)`) is still reported as before: its rows come from the ancestor's DFM when that DFM is read.

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
code is not followed for the descendant.

## `AttachTable(X.Table, ...)`

FireDAC's `AttachTable` takes the storage of a dataset, so `memA.AttachTable(tblB.Table, nil)` links `memA` to the
dataset `tblB` (and `dm.tblB.Table` to `dm.tblB`). Before 1.56 `tblB` was taken for a module name and the link was
unresolved. No other call reads `.Table`.

## See also

- [Read a form into the field repository](repo-read-dfm) -- the command, its flags and the change set.
