# INBOX: two defects found while fixing a `cycles --plan` report (DataCopy, 2026-08-03)

Source: `drag-lint cycles --plan` run from the IDE plugin for
`C:\Projects\DataCopy\DataCopy.dproj`; report at
`%TEMP%\drag-lint-circular-uses.txt`. DB: `C:\Projects\DataCopy\drag-lint.sqlite`.

---

## Defect 1 (`wrong`) -- a local variable is resolved to another unit's field

**Reproducing query**

```
drag-lint cycles --plan --db C:\Projects\DataCopy\drag-lint.sqlite
```

The report listed, under "why `mainzeissconvert` uses `setupfields`":

```
- line 722: `ZFileDir`  [field]  -> declared in `setupfields`
```

**Source snippet** (`C:\Projects\DataCopy\MainZeissConvert.pas`, pre-fix):

```pascal
procedure TfrmZeissConvert.btnSetupFieldsClick(Sender: TObject);
var
	fName    : string;
	SearchRec: TSearchRec;
	ZFileDir : string;          // <-- line 708, LOCAL
begin
	...
	ZFileDir:= edtFrom.Text;    // <-- line 722, reported as SetupFields.TfrmSetupFields.ZFileDir
```

**Expected:** line 722 resolves to the local `ZFileDir` declared at line 708 and
contributes no cross-unit reference.

**Actual:** it resolved to the public field `SetupFields.TfrmSetupFields.ZFileDir`
and was reported as an inter-unit dependency edge.

`drag-lint query --name ZFileDir` does know about the local
(`MainZeissConvert.TfrmZeissConvert.btnSetupFieldsClick.ZFileDir : string [impl-only]`),
so the symbol table is right -- the **reference resolver used by `cycles`** is not
consulting routine-local scope before unit scope.

**Impact:** inflates cycle edges with phantom symbols. Here it made the
`mainzeissconvert -> setupfields` edge look like 3 symbols when only 2 were real
(`frmSetupFields`, `TfrmSetupFields`), and the playbook's step 1 ("pick the edge
with fewer / more incidental symbols") is scored off those counts.

---

## Defect 2 (`out-of-scope`) -- project-scoped command reports out-of-project cycles

The plugin ran `cycles` "for project `C:\Projects\DataCopy\DataCopy.dproj`", but
the only cycle reported was between `MainZeissConvert` and `SetupFields`, and
**neither unit is part of `DataCopy.dproj`**:

- `DataCopy.dproj` `<DCCReference>` list: `uContainerConfig`, `uConfigurationService`,
  `uMainZeissCopy`, `uFileUtils`, `uZeissRoutines`, `uGlobals`, `DPPRoutines`,
  `CSVRoutines`, `uInterface`, `FileLockInfo`, `DataCopy.dxSettings`. No
  `MainZeissConvert`, no `SetupFields`.
- The only project that references them is the retired
  `C:\Projects\DataCopy\BACKUP OLD PROJECTS\ZeissConvert.dproj` (whose relative
  `DCCReference` paths no longer resolve -- the .dproj was moved into the backup
  folder while the units stayed in the parent).

Cause: `currentProjectsIndexing: "perProject"` indexes the whole **folder**, so
`cycles` reports over every unit in the DB rather than over the reachable unit
graph of the named `.dproj`.

**Consequences for the user:** the playbook's step 5/6 ("Build", "re-run cycles to
confirm") cannot be honoured -- building `DataCopy.dproj` never touches these
units. Worse, `MainZeissConvert` cannot be compiled on this machine at all:

```
MainZeissConvert.pas(30): error F2613: Unit 'kbmMemTable' not found.
```

even when compiled with `DataCopy.dproj`'s own verbatim compiler settings
(`kbmMemTable` is absent from the Studio 37 library path; the `kbmMemTable.dcu`
sitting in `DataCopy\Win32\Debug\DCU` is a leftover from an older RAD Studio, and
`C:\Projects\kbmMemTable\Source` fails with `E2072` at line 4939).

**Suggested fix:** when `cycles` is given a project (or the plugin invokes it for
one), restrict the unit set to units reachable from that project's `.dpr`/`.dproj`,
and label out-of-project cycles separately (e.g. "also found in the index, outside
this project") instead of presenting them as the project's cycles.

---

## What was actually done

The cycle was real at the source level, so it was fixed anyway (see
`hg diff` in `C:\Projects\DataCopy`): `TfrmSetupFields` became a self-contained
dialog with `class function Execute(pOwner; pZFileDir; pAllHeaderFields,
pHeaderFields, pNoteFields): Boolean`, so `SetupFields` no longer uses
`MainZeissConvert`. `drag-lint cycles` now reports
`No circular unit dependencies found.`

Verification note: `SetupFields.pas` compiles **standalone, 0 errors 0 warnings**,
in a project that does not contain `MainZeissConvert.pas` -- which is itself the
proof the edge is gone. `MainZeissConvert.pas` could not be compile-verified for
the `kbmMemTable` reason above (pre-existing, unrelated to the change).
