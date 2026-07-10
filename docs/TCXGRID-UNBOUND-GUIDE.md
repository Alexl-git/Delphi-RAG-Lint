# Building a FIXED, UNBOUND DevExpress TcxGrid (Y rows x X columns, mixed per-column types)

Practical, code-first guide for replacing legacy Orpheus `TOvcTable` spreadsheet grids
with an **unbound** DevExpress `TcxGrid` + `TcxGridTableView`. Target platform:
**Delphi 13 Florence / RAD Studio 37 (VCL + DevExpress)**. DevExpress VCL API version
current at time of writing: **24.2 / 25.1 / 25.2 / 26.1** (all snippets are valid across
these; see the version caveat at the end).

The target design is a spreadsheet-style grid: a fixed number of rows (Y), a fixed set of
columns (X), where **each column carries a different data type** (string / integer / double /
graphic / in-cell button), each column has a **string header**, and cells are filled
**in code** through the View's data controller. No dataset, no `TDataSource`, no navigator.

> All API names below are taken directly from the DevExpress VCL documentation. Cited pages
> are listed at the end. VCL rule of thumb: it is `TcxGridTableView` (unbound) vs
> `TcxGridDBTableView` (bound). We use the **unbound** one.

---

## 1. Classes involved and their roles

| Class | Role |
| --- | --- |
| `TcxGrid` | The visual control you drop on a form/panel. Hosts one or more levels. |
| `TcxGridLevel` | A slot inside the grid that hosts exactly one View. The root level is `Grid.Levels.Add`. |
| `TcxGridTableView` | The **UNBOUND** table View. Owns the columns and the data controller. Created via `Grid.CreateView(TcxGridTableView)`. (`TcxGridDBTableView` is the bound sibling - do NOT use it here.) |
| `TcxGridColumn` | One column in the table View. Created via `View.CreateColumn`. Carries `Caption` (header text), the value type (`DataBinding.ValueTypeClass`), and the in-place editor (`PropertiesClass`/`Properties` or `RepositoryItem`). |
| `TcxGridDataController` (a `TcxCustomDataController`) | The in-memory data store of the View. In **unbound mode** you set `RecordCount` (number of rows) and fill cells via `Values[ARecordIndex, AItemIndex]`. |
| `TcxEditRepository` + `TcxEditRepositoryXxxItem` | Optional shared editor definitions. A single repository item can be reused across many columns/grids. Assigned to a column via `Column.RepositoryItem`. Alternative to setting `PropertiesClass`/`Properties` inline. |

### The unbound data model (records x items)

In unbound mode the View's data controller is a plain 2D store: **records** (rows) by
**items** (columns). It is not connected to any data source, so you populate it manually,
record-by-record and item-by-item ([Unbound Mode], [Unbound Mode: Master-Detail]):

- **`DataController.RecordCount := Y;`** creates Y empty rows.
- **`DataController.Values[ARecordIndex, AItemIndex] := AValue;`** sets one cell.
  - First index = **record index** (0-based row). Record indexes are stable and are NOT
    affected by sorting ([Data Controller: Record Index]).
  - Second index = **item index** = the column's `Index` property.
- `Values` is **`Variant`**-typed - you assign a string, integer, double, etc., directly.
- To make cells show the right editor and sort/edit with the right semantics, also set each
  column's **`DataBinding.ValueTypeClass`** (`TcxStringValueType`, `TcxIntegerValueType`,
  `TcxFloatValueType`, `TcxCurrencyValueType`, ...). See [TcxValueType].

> Index vs ItemIndex: `Column.Index` is the item index used by `Values[...]` - it reflects
> creation order and is what the data controller keys on. `Column.ItemIndex` is the visible
> position of the column in the View (changes if the user or you reorder columns). For a
> fixed spreadsheet you normally cache `Column.Index` right after `CreateColumn` and use that
> for all `Values[]` access. If you never reorder, `Index` equals creation order (0,1,2,...).

---

## 2. Create the grid + level + view in code

`Grid -> Level -> View` wiring, straight from the official unbound example
([TcxGridTableView Class]):

```pascal
uses
  cxGrid,            // TcxGrid
  cxGridLevel,       // TcxGridLevel
  cxGridTableView;   // TcxGridTableView, TcxGridColumn

var
  AGrid: TcxGrid;
  ALevel: TcxGridLevel;
  AView: TcxGridTableView;
begin
  AGrid := TcxGrid.Create(Self);   // owner frees it
  AGrid.Parent := SomeParentPanel; // host control
  AGrid.Align := alClient;

  ALevel := AGrid.Levels.Add;      // root level
  AView := AGrid.CreateView(TcxGridTableView) as TcxGridTableView;
  ALevel.GridView := AView;        // wire the View into the level
end;
```

Notes:
- `Create(Self)` (or `Create(Owner)`) hands ownership to the form/frame; do not free it
  manually. The View and columns are owned by the grid and are freed with it.
- Design-time is also fine: drop a `TcxGrid`, use its component editor to add a level and a
  `TcxGridTableView`, add columns visually. Because our converter emits code/DFM we show the
  code path; the DFM path stores the same objects.

---

## 3. Create X columns, each with a string header

`View.CreateColumn` returns a `TcxGridColumn`; set `Caption` for the header text
([Provider Mode] / [TcxGridTableView Class]):

```pascal
var
  ACol: TcxGridColumn;
begin
  ACol := AView.CreateColumn;
  ACol.Caption := 'Name';                              // <-- string header
  ACol.DataBinding.ValueTypeClass := TcxStringValueType; // value type for the store
end;
```

Do this X times, once per column. Cache each column reference (or its `.Index`) so you can
fill cells later.

---

## 4. Per-column editor type (the cell-type -> editor mapping)

Two equivalent ways to give a column an editor:

- **Inline:** `Column.PropertiesClass := TcxXxxProperties;` then cast
  `(Column.Properties as TcxXxxProperties)` to configure it. This creates a per-column
  properties object owned by the column. ([TcxGridTableView Class] uses this.)
- **Repository:** create a `TcxEditRepositoryXxxItem` in a `TcxEditRepository`, configure it
  once, then `Column.RepositoryItem := ARepoItem;`. Reusable across many columns/grids.
  **Note:** when `RepositoryItem` is set, `Properties`/`PropertiesClass` are ignored
  ([TcxCustomGridTableItem.RepositoryItem]).

### Mapping table

| Cell type | Value type (`DataBinding.ValueTypeClass`) | In-place editor properties (inline) | Repository item | Underlying editor |
| --- | --- | --- | --- | --- |
| string | `TcxStringValueType` | `TcxTextEditProperties` (unit `cxTextEdit`) | `TcxEditRepositoryTextItem` | `TcxTextEdit` |
| integer | `TcxIntegerValueType` | `TcxSpinEditProperties` (unit `cxSpinEdit`) | `TcxEditRepositorySpinItem` | `TcxSpinEdit` |
| double | `TcxFloatValueType` (or `TcxCurrencyValueType`) | `TcxSpinEditProperties` with `ValueType := vtFloat` (recommended) OR `TcxCalcEditProperties` / `TcxCurrencyEditProperties` | `TcxEditRepositorySpinItem` / `TcxEditRepositoryCalcItem` / `TcxEditRepositoryCurrencyItem` | `TcxSpinEdit` / `TcxCalcEdit` / `TcxCurrencyEdit` |
| graphic / image | `TcxVariantValueType` (BLOB-like; leave default) | `TcxImageProperties` (unit `cxImage`) with `GraphicClass := TdxSmartImage` | `TcxEditRepositoryImageItem` | `TcxImage` |
| in-cell button | `TcxStringValueType` (button sits on a text editor) | `TcxButtonEditProperties` (unit `cxButtonEdit`) | `TcxEditRepositoryButtonItem` | `TcxButtonEdit` |

> If you set only `ValueTypeClass` and leave the editor unspecified, the grid picks a
> sensible **default editor** from the value type (e.g. Currency -> `TcxCurrencyEdit`,
> Boolean -> `TcxCheckBox`, anything else -> `TcxTextEdit`) - see
> [TcxCustomGridTableItem.RepositoryItem]. For mixed spreadsheet columns we set editors
> explicitly so each column looks and behaves the way we want.

### 4a. string -> `TcxTextEditProperties`

```pascal
uses cxTextEdit;
// ...
ACol := AView.CreateColumn;
ACol.Caption := 'Name';
ACol.DataBinding.ValueTypeClass := TcxStringValueType;
ACol.PropertiesClass := TcxTextEditProperties;
// optional: read-only spreadsheet feel
(ACol.Properties as TcxTextEditProperties).ReadOnly := True;
```

### 4b. integer -> `TcxSpinEditProperties`

`TcxSpinEditProperties.ValueType` defaults to `vtInt`, so an integer spin editor needs no
extra configuration beyond (optionally) `Increment`:

```pascal
uses cxSpinEdit;
// ...
ACol := AView.CreateColumn;
ACol.Caption := 'Qty';
ACol.DataBinding.ValueTypeClass := TcxIntegerValueType;
ACol.PropertiesClass := TcxSpinEditProperties;
(ACol.Properties as TcxSpinEditProperties).Increment := 1;   // vtInt is the default
```

### 4c. double -> cleanest is `TcxSpinEditProperties` with `ValueType := vtFloat`

Recommended for a general numeric double column. Set `ValueType := vtFloat` (from unit
`cxSpinEdit`) so the editor accepts/edits floating-point values, and give the column the
float value type so the store round-trips a Double:

```pascal
uses cxSpinEdit;
// ...
ACol := AView.CreateColumn;
ACol.Caption := 'Weight';
ACol.DataBinding.ValueTypeClass := TcxFloatValueType;
ACol.PropertiesClass := TcxSpinEditProperties;
with ACol.Properties as TcxSpinEditProperties do
begin
  ValueType := vtFloat;   // float mode
  Increment := 0.1;
end;
```

Alternatives if the semantics fit better:
- Money -> use `TcxCurrencyValueType` and let the default `TcxCurrencyEdit` render it (or set
  `PropertiesClass := TcxCurrencyEditProperties`, unit `cxCurrencyEdit`).
- Free-form calculator entry -> `TcxCalcEditProperties` (unit `cxCalc`).

### 4d. graphic / image -> `TcxImageProperties`

Use the **unbound** image editor `TcxImage` via `TcxImageProperties`. Set `GraphicClass` so
the container understands the format; DevExpress recommends **`TdxSmartImage`** so the cell
supports the same formats (BMP/PNG/JPEG/GIF/TIFF/SVG/...) as the rest of the suite
([TcxImage Class], [TcxCustomImageProperties.GraphicClass]):

```pascal
uses cxImage, dxGDIPlusClasses;  // dxGDIPlusClasses declares TdxSmartImage
// ...
ACol := AView.CreateColumn;
ACol.Caption := 'Preview';
ACol.PropertiesClass := TcxImageProperties;
with ACol.Properties as TcxImageProperties do
begin
  GraphicClass := TdxSmartImage;   // universal image container (recommended)
  Stretch := True;                 // optional: fit the picture to the cell
end;
```

To feed a picture into an image cell, assign a graphic object to the cell value (see section
6c). `TcxImageComboBox` is a different beast - it maps an index/value to one of a fixed set
of small images (icons); use it only for enumerated icons, NOT for showing an arbitrary
bitmap in a cell.

### 4e. in-cell button -> `TcxButtonEditProperties`

A `TcxButtonEdit` is a single-line text editor with one or more embedded buttons. In an
unbound grid you attach `TcxButtonEditProperties` to the column and handle its
`OnButtonClick`. The button collection is `Properties.Buttons`; the default editor already
has one button, and you can `Buttons.Add` more ([TcxButtonEdit Class],
[TcxEditButtons.Add]).

```pascal
uses cxButtonEdit, cxEdit;  // cxEdit declares TcxEditButtonKind (bkEllipsis, bkGlyph...)
// ...
ACol := AView.CreateColumn;
ACol.Caption := 'Action';
ACol.DataBinding.ValueTypeClass := TcxStringValueType;  // button rides on a text editor
ACol.PropertiesClass := TcxButtonEditProperties;
with ACol.Properties as TcxButtonEditProperties do
begin
  ViewStyle := vsButtonsOnly;    // hide the text area, show only the button (spreadsheet look)
  Buttons.Items[0].Kind := bkEllipsis;  // or bkGlyph + ImageIndex for a picture
  Buttons.Items[0].Caption := '...';
  OnButtonClick := ButtonColumnClick;   // handler declared on the form/frame
end;
```

See section 8 for the `OnButtonClick` handler and how to know which row/column was clicked.

---

## 5. Setting a FIXED number of rows (Y)

Two ways; the first is preferred for a fixed grid.

**A. Set `RecordCount` directly** (creates Y empty records at once):

```pascal
AView.DataController.RecordCount := 10;   // exactly 10 rows
```

**B. Append records in a loop** (`AppendRecord` returns the new record index):

```pascal
var i, idx: Integer;
begin
  for i := 0 to 9 do
    idx := AView.DataController.AppendRecord;  // idx = new record index
end;
```

**Always wrap population in `BeginUpdate`/`EndUpdate`** so the grid does not repaint/relayout
on every cell. Correct sequence ([TcxGridTableView Class], [Unbound Mode]):

```pascal
AView.BeginUpdate;    // View-level batch (locks redraw)
try
  AView.DataController.RecordCount := 10;
  // ... fill Values[...] here ...
finally
  AView.EndUpdate;
  AView.ApplyBestFit;  // size columns to content once, after data is in
end;
```

You can also call `DataController.BeginUpdate/EndUpdate` for a data-controller-scoped batch;
`View.BeginUpdate/EndUpdate` is the usual choice when you are also touching columns.

---

## 6. Feeding data into cells

### 6a. The exact API

```pascal
DataController.Values[ARecordIndex, AItemIndex] := AValue;   // Variant assign
```

- `ARecordIndex` = 0-based row (0 .. RecordCount-1).
- `AItemIndex` = the column's `Index` (item index in the data controller). Cache it right
  after `CreateColumn`: `FNameIdx := ANameCol.Index;`
- `AValue` is `Variant`. A string, an integer and a double all assign directly; the value
  type you set on the column governs sorting/formatting.

### 6b. Full Y x X example (string header row + mixed body cells)

This builds a 2-row x 4-column grid (String / Integer / Float / String) and fills it -
adapted from the official unbound sample ([Unbound Mode], [TcxGridTableView Class]):

```pascal
uses cxGrid, cxGridLevel, cxGridTableView, cxTextEdit, cxSpinEdit;

procedure BuildDemo(AParent: TWinControl; AOwner: TComponent);
var
  AGrid: TcxGrid;
  AView: TcxGridTableView;
  cName, cDistance, cPeriod, cOrbits: TcxGridColumn;
begin
  AGrid := TcxGrid.Create(AOwner);
  AGrid.Parent := AParent;
  AGrid.Align := alClient;
  AView := AGrid.CreateView(TcxGridTableView) as TcxGridTableView;
  AGrid.Levels.Add.GridView := AView;

  AView.BeginUpdate;
  try
    // --- Columns (headers + value types + editors) ---
    cName := AView.CreateColumn;
    cName.Caption := 'Planet Name';                       // string header
    cName.DataBinding.ValueTypeClass := TcxStringValueType;
    cName.PropertiesClass := TcxTextEditProperties;

    cDistance := AView.CreateColumn;
    cDistance.Caption := 'Distance';
    cDistance.DataBinding.ValueTypeClass := TcxIntegerValueType;
    cDistance.PropertiesClass := TcxSpinEditProperties;   // integer

    cPeriod := AView.CreateColumn;
    cPeriod.Caption := 'Period (days)';
    cPeriod.DataBinding.ValueTypeClass := TcxFloatValueType;
    cPeriod.PropertiesClass := TcxSpinEditProperties;
    (cPeriod.Properties as TcxSpinEditProperties).ValueType := vtFloat;  // double

    cOrbits := AView.CreateColumn;
    cOrbits.Caption := 'Orbits';
    cOrbits.DataBinding.ValueTypeClass := TcxStringValueType;

    // --- Fixed number of rows ---
    AView.DataController.RecordCount := 2;

    // --- Body cells: Values[recordIndex, column.Index] ---
    AView.DataController.Values[0, cName.Index]     := 'Mercury';
    AView.DataController.Values[0, cDistance.Index] := 57910;
    AView.DataController.Values[0, cPeriod.Index]   := 87.97;
    AView.DataController.Values[0, cOrbits.Index]   := 'Sun';

    AView.DataController.Values[1, cName.Index]     := 'Earth';
    AView.DataController.Values[1, cDistance.Index] := 149600;
    AView.DataController.Values[1, cPeriod.Index]   := 365.26;
    AView.DataController.Values[1, cOrbits.Index]   := 'Sun';
  finally
    AView.EndUpdate;
    AView.ApplyBestFit;
  end;
end;
```

The "string header row" here means the column captions (the header band). If you instead
want the FIRST DATA ROW to display header-like text (true spreadsheet), just write those
strings into `Values[0, ...]` and start real data at record index 1 - captions and data rows
are independent.

### 6c. Feeding an image cell

For a `TcxImageProperties` column, assign a graphic to the cell. The image editor's value
holds picture data; the simplest robust path is to load into a `TdxSmartImage` (or the
`GraphicClass` you chose) and assign it:

```pascal
uses dxGDIPlusClasses;   // TdxSmartImage
var AImg: TdxSmartImage;
begin
  AImg := TdxSmartImage.Create;
  try
    AImg.LoadFromFile('C:\pics\thumb.png');
    AView.DataController.Values[ARow, cPreview.Index] := AImg;  // cell takes a copy
  finally
    AImg.Free;
  end;
end;
```

The cell stores its own copy of the picture data; free your temporary graphic afterward.
(This mirrors how DevExpress binds image data to `TcxImage`/`TcxDBImage` via a
`TGraphic` descendant container - see [TcxImage Class],
[TcxCustomImageProperties.GraphicClass].)

---

## 7. Reading a cell value back

`Values` is read/write, so reading is symmetric:

```pascal
var
  V: Variant;
  S: string;
  N: Integer;
begin
  V := AView.DataController.Values[ARow, cName.Index];
  if not VarIsNull(V) then
    S := VarToStr(V);

  N := AView.DataController.Values[ARow, cDistance.Index];  // implicit Variant->Integer
end;
```

For the display string of a cell (what the user actually sees, after formatting) use the data
controller's `DisplayTexts[ARecordIndex, AItemIndex]` instead of `Values`
([TcxCustomDataController.FilteredRecordCount] shows `DisplayTexts` usage). Guard against
`Null` with `VarIsNull` before converting.

---

## 8. Events you need

### 8a. `OnButtonClick` for in-cell buttons - mapping back to record/column

When a column uses `TcxButtonEditProperties`, its `OnButtonClick` fires on a click. The
signature is `TcxEditButtonClickEvent` -> `(Sender: TObject; AButtonIndex: Integer)`
([TcxCustomEditProperties.OnButtonClick], [TcxEditButtonClickEvent]).

Key subtlety in a **grid**: `Sender` is the shared in-place editor, not a per-row control, so
you cannot read the row from `Sender`. Instead, at click time the clicked cell is the
**focused** cell, so read the focused record/column from the View. Use the data controller's
`FocusedRecordIndex` (the record index into `Values[]`) and the View controller's
`FocusedColumn` ([TcxCustomGridTableController.FocusedRecordIndex],
[TcxCustomDataController.FocusedRecordIndex]):

```pascal
procedure TMyFrame.ButtonColumnClick(Sender: TObject; AButtonIndex: Integer);
var
  ARecIdx: Integer;
  ACol: TcxGridColumn;
begin
  // Which row: the record index into DataController.Values[...]
  ARecIdx := AView.DataController.FocusedRecordIndex;

  // Which column: the focused column of the View
  ACol := AView.Controller.FocusedColumn as TcxGridColumn;

  ShowMessageFmt('Button in row %d, column "%s" (button #%d)',
    [ARecIdx, ACol.Caption, AButtonIndex]);

  // e.g. read that row's key cell to act on it:
  // DoAction(AView.DataController.Values[ARecIdx, FKeyColIdx]);
end;
```

`AButtonIndex` distinguishes multiple buttons on the same editor (0 = first button). If you
share one handler across several button columns, `ACol` tells you which column it was.

> Alternative binding: set a button's `Action` property to a `TBasicAction` to route it to an
> action object instead of `OnButtonClick` ([TcxCustomEditProperties.OnButtonClick]).

### 8b. `OnGetDisplayText` (and `OnGetDataText`) - custom cell text / styling

To format what a cell shows without changing the stored value, handle the column's
`OnGetDisplayText` ([TcxCustomGridTableItem.OnGetDisplayText], example at
[Example: Column.OnGetDisplayText]):

```pascal
procedure TMyFrame.PeriodColGetDisplayText(Sender: TcxCustomGridTableItem;
  ARecord: TcxCustomGridRecord; var AText: string);
begin
  AText := AText + ' d';   // append a unit suffix to the displayed value
end;
```

`OnGetDataText` is similar but its text is also used for sorting/grouping. For color/font
styling per cell, use `Styles` or the `OnCustomDrawCell` event on the View.

---

## 9. Gotchas / notes

- **Unbound vs bound.** Unbound = `TcxGridTableView`, you own the data in the controller;
  edits raise `DataController.OnDataChanged` but nothing is written anywhere else. Bound =
  `TcxGridDBTableView` + a dataset. Do not mix. For a fixed generated spreadsheet, unbound is
  correct ([Unbound Mode]).
- **`Values` is `Variant`.** Assigning the wrong runtime type still "works" but may sort/format
  oddly; always set `DataBinding.ValueTypeClass` to match the data you store so the store
  round-trips the right Delphi type and the default editor/sorting is correct.
- **Cache `Column.Index`, not `ItemIndex`, for `Values[]`.** `Index` is the item index the
  data controller keys on; `ItemIndex` is the visible position and changes on reorder.
- **Image cells** need a real `TGraphic` descendant assigned (recommended container:
  `TdxSmartImage`); the cell copies the data, so free your temporary graphic. `TcxImageComboBox`
  is for enumerated icons, not arbitrary bitmaps.
- **Make it look like a fixed grid (no navigator, no user data-shaping):**

  ```pascal
  // Turn OFF interactive features to get a static spreadsheet feel:
  AView.OptionsData.Editing   := False;   // cells not editable
  AView.OptionsData.Deleting  := False;   // rows cannot be deleted
  AView.OptionsData.Inserting := False;   // rows cannot be inserted
  AView.OptionsCustomize.ColumnMoving   := False;  // fixed column order
  AView.OptionsCustomize.ColumnSorting  := False;  // no sort-by-click
  AView.OptionsCustomize.ColumnFiltering := False;
  AView.OptionsView.GroupByBox := False;  // hide the Group-By box
  AView.OptionsView.Navigator.Visible := False;    // no record navigator (default is hidden)
  // Per-column: disable sorting individually if you kept ColumnSorting on:
  // ACol.Options.Sorting := False;
  ```

  (`Options.Sorting` and `OptionsCustomize.*` are documented at
  [TcxCustomGridColumnOptions Properties] and the View's OptionsCustomize.)
- **`ApplyBestFit` after populating**, inside/after `EndUpdate`, to size columns to content.
  Or set each `Column.Width` explicitly for a truly fixed layout.
- **RAD Studio 37 / DevExpress version:** the unbound API surface (`CreateView`,
  `CreateColumn`, `DataController.RecordCount`, `DataController.Values`,
  `PropertiesClass`/`Properties`, `TcxEditRepository*Item`, `OnButtonClick`) has been stable
  for many major versions and is documented identically for 24.2 through 26.1. Prefer
  `TdxSmartImage` for image containers (post-GDI+ recommendation). No 37-specific breaking
  change applies to this pattern.

---

## 10. Minimal end-to-end code listing (copy-paste)

Builds a **3-column** (String header "Name" / Integer "Qty" / Button "Action") **x N-row**
unbound `TcxGrid` on a given parent, populates it, and wires the button click back to the
row. Static spreadsheet feel (read-only, no navigator/sorting).

```pascal
unit UnboundGridDemo;

interface

uses
  System.Classes, Vcl.Controls,
  cxGrid, cxGridLevel, cxGridTableView, cxGridCustomTableView, cxCustomData,
  cxTextEdit, cxSpinEdit, cxButtonEdit, cxEdit;

type
  /// <summary>Builds and owns a fixed, unbound TcxGrid: 3 typed columns x N rows.</summary>
  /// <remarks>Grid + View + columns are owned by AOwner; not thread-safe (VCL UI).</remarks>
  TUnboundSheet = class(TComponent)
  private
    FGrid: TcxGrid;
    FView: TcxGridTableView;
    FColName: TcxGridColumn;   // string
    FColQty: TcxGridColumn;    // integer
    FColAction: TcxGridColumn; // in-cell button
    procedure ActionButtonClick(Sender: TObject; AButtonIndex: Integer);
  public
    /// <summary>Creates the grid on AParent and fills it with ARowCount rows.</summary>
    /// <param name="AParent">Host control (e.g. a panel). Must not be nil.</param>
    /// <param name="ARowCount">Fixed number of rows (Y) to create.</param>
    constructor CreateSheet(AOwner: TComponent; AParent: TWinControl;
      ARowCount: Integer); reintroduce;
    /// <summary>Sets one row's cells. ARow is 0-based (0..RowCount-1).</summary>
    procedure SetRow(ARow: Integer; const AName: string; AQty: Integer);
    property View: TcxGridTableView read FView;
  end;

implementation

uses
  System.SysUtils, Vcl.Dialogs;

constructor TUnboundSheet.CreateSheet(AOwner: TComponent; AParent: TWinControl;
  ARowCount: Integer);
begin
  inherited Create(AOwner);

  // 1. Grid -> Level -> View
  FGrid := TcxGrid.Create(AOwner);
  FGrid.Parent := AParent;
  FGrid.Align := alClient;
  FView := FGrid.CreateView(TcxGridTableView) as TcxGridTableView;
  FGrid.Levels.Add.GridView := FView;

  FView.BeginUpdate;
  try
    // 2. Columns with string headers + value types + editors
    FColName := FView.CreateColumn;
    FColName.Caption := 'Name';
    FColName.DataBinding.ValueTypeClass := TcxStringValueType;
    FColName.PropertiesClass := TcxTextEditProperties;

    FColQty := FView.CreateColumn;
    FColQty.Caption := 'Qty';
    FColQty.DataBinding.ValueTypeClass := TcxIntegerValueType;
    FColQty.PropertiesClass := TcxSpinEditProperties;   // vtInt default

    FColAction := FView.CreateColumn;
    FColAction.Caption := 'Action';
    FColAction.DataBinding.ValueTypeClass := TcxStringValueType;
    FColAction.PropertiesClass := TcxButtonEditProperties;
    with FColAction.Properties as TcxButtonEditProperties do
    begin
      ViewStyle := vsButtonsOnly;             // show only the button
      Buttons.Items[0].Kind := bkEllipsis;    // built-in "..." button
      Buttons.Items[0].Caption := 'Go';
      OnButtonClick := ActionButtonClick;
    end;

    // 3. Fixed row count (Y)
    FView.DataController.RecordCount := ARowCount;

    // 4. Static spreadsheet look
    FView.OptionsData.Editing := False;
    FView.OptionsData.Deleting := False;
    FView.OptionsData.Inserting := False;
    FView.OptionsCustomize.ColumnMoving := False;
    FView.OptionsCustomize.ColumnSorting := False;
    FView.OptionsCustomize.ColumnFiltering := False;
    FView.OptionsView.GroupByBox := False;
    FView.OptionsView.Navigator.Visible := False;
  finally
    FView.EndUpdate;
    FView.ApplyBestFit;
  end;
end;

procedure TUnboundSheet.SetRow(ARow: Integer; const AName: string; AQty: Integer);
begin
  FView.DataController.Values[ARow, FColName.Index] := AName;
  FView.DataController.Values[ARow, FColQty.Index]  := AQty;
  // Action column: give the button cell a caption/hint value if desired
  FView.DataController.Values[ARow, FColAction.Index] := 'Row ' + IntToStr(ARow);
end;

procedure TUnboundSheet.ActionButtonClick(Sender: TObject; AButtonIndex: Integer);
var
  ARecIdx: Integer;
  AName: Variant;
begin
  // Which row was clicked (record index into Values[...])
  ARecIdx := FView.DataController.FocusedRecordIndex;
  AName := FView.DataController.Values[ARecIdx, FColName.Index];
  ShowMessage(Format('Action on row %d (Name=%s, button #%d)',
    [ARecIdx, VarToStr(AName), AButtonIndex]));
end;

end.
```

Usage:

```pascal
FSheet := TUnboundSheet.CreateSheet(Self, PanelHost, 5);   // 5 rows
FSheet.SetRow(0, 'Alpha', 10);
FSheet.SetRow(1, 'Beta',  20);
// ...
```

---

## Sources (DevExpress VCL documentation)

- **Unbound Mode** - https://docs.devexpress.com/VCL/171061 (RecordCount, Values[record,item], BeginUpdate/EndUpdate, ValueTypeClass)
- **Unbound Mode: Master-Detail** - https://docs.devexpress.com/VCL/171055 (record-by-record / item-by-item population, GetDetailDataController, Values[r,c])
- **TcxGridTableView Class** - https://docs.devexpress.com/VCL/cxGridTableView.TcxGridTableView (full code-built unbound example: Grid->Level->View, CreateColumn, PropertiesClass, RecordCount, Values, ApplyBestFit)
- **TcxGridLevel Class** - https://docs.devexpress.com/VCL/cxGridLevel.TcxGridLevel (Levels.Add, CreateView, GridView wiring)
- **Provider Mode / Using provider mode: Creating columns** - https://docs.devexpress.com/VCL/171060 , https://docs.devexpress.com/VCL/166038 (CreateColumn, Caption, ValueTypeClass patterns)
- **Data Controller: Record Index** - https://docs.devexpress.com/VCL/166027 (record index stable under sorting)
- **TcxCustomGridTableItem.RepositoryItem** - https://docs.devexpress.com/VCL/cxGridCustomTableView.TcxCustomGridTableItem.RepositoryItem (repository vs PropertiesClass; default-editor-by-value-type table)
- **Edit Repository Items / The Repository Concept** - https://docs.devexpress.com/VCL/153050 , https://docs.devexpress.com/VCL/167026 (TcxEditRepository + TcxEditRepositoryXxxItem)
- **TcxEditRepository.CreateItem** - https://docs.devexpress.com/VCL/cxEdit.TcxEditRepository.CreateItem(cxEdit.TcxEditRepositoryItemClass) (repository-item-type -> in-place-editor table: ButtonItem->TcxButtonEdit, etc.)
- **TcxButtonEdit Class / TcxEditButtons.Add** - https://docs.devexpress.com/VCL/cxButtonEdit.TcxButtonEdit , https://docs.devexpress.com/VCL/cxEdit.TcxEditButtons.Add
- **TcxCustomEditProperties.OnButtonClick / TcxEditButtonClickEvent** - https://docs.devexpress.com/VCL/cxEdit.TcxCustomEditProperties.OnButtonClick , https://docs.devexpress.com/VCL/cxEdit.TcxEditButtonClickEvent (signature Sender + AButtonIndex)
- **TcxImage Class / TcxImageProperties / GraphicClass** - https://docs.devexpress.com/VCL/cxImage.TcxImage , https://docs.devexpress.com/VCL/cxImage.TcxImageProperties , https://docs.devexpress.com/VCL/cxImage.TcxCustomImageProperties.GraphicClass (unbound image editor; recommend TdxSmartImage)
- **TcxCustomGridTableController.FocusedRecordIndex / TcxCustomDataController.FocusedRecordIndex** - https://docs.devexpress.com/VCL/cxGridCustomTableView.TcxCustomGridTableController.FocusedRecordIndex , https://docs.devexpress.com/VCL/cxCustomData.TcxCustomDataController.FocusedRecordIndex (map a click back to the record index)
- **TcxCustomGridTableItem.OnGetDisplayText / OnGetDataText** - https://docs.devexpress.com/VCL/cxGridCustomTableView.TcxCustomGridTableItem.OnGetDataText , example https://docs.devexpress.com/VCL/170087
- **TcxCustomGridColumnOptions Properties** - https://docs.devexpress.com/VCL/cxGridTableView.TcxCustomGridColumnOptions._properties (Options.Sorting per column)
