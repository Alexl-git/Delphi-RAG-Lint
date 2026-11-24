# Field repository: generated handlers and DLFR regions

Three `repo` sub-verbs write code from the [field repository](field-repository.md) into existing units. All are dry runs
until `--apply`; `--dry-run` wins over `--apply`.

| Sub-verb | Options | What it does |
|---|---|---|
| `gen-handlers` | `--dfm <file.dfm>[;...]` [`--dataset <Name>`] [`--apply`] [`--json`] | Puts the stored bodies of a dataset's fields (`CALC_BODY`, `ONGETTEXT_BODY`, `ONSETTEXT_BODY`, `ONVALIDATE_BODY`, `ONCHANGE_BODY` of the field row) into the event handlers the DFM assigns: `OnCalcFields`, `OnGetText`, `OnSetText`, `OnValidate`, `OnChange`. Needs a schema-3 repository |
| `gen-maxlen` | `--code-dir <folder>` [`--table <T,...>`] [`--apply`] [`--json`] | Writes `<TABLE>_<FIELD>_MAXLEN` constants into region `DLFR 2a` of each interface unit `i<TABLE>.pas`, behind section 2 |
| `renumber-regions` | `--code-dir <folder>` or `--in <file.pas>[;...]` [`--apply`] [`--json`] | Renames the numbered ORM region markers of whole units: `DB-RAD n` becomes `DLFR n` |

Exit code: 0 ok, 1 a failure, at least one region refused or at least one unit not written (the others are still written),
2 wrong arguments. A file named twice is read once. After `--apply` every changed unit is listed as `written` or
`NOT WRITTEN` with the reason (locked, read-only, changed meanwhile); such a unit is as it was and no temporary file is left
(`--json`: `written` / `error` per unit, `written` / `not_written` in total).

## The region

```pascal
procedure TdmOrders.memOrdersCalcFields(DataSet: TDataSet);
begin
  Inc(Calls);                                        // your code, kept
  {$REGION 'DLFR memOrders.OnCalcFields hash=5f0c1d2e3a4b5c6d'}
  begin // TOTAL
    memOrdersTOTAL.AsFloat := memOrdersQTY.AsInteger * memOrdersPRICE.AsFloat;
  end;
  begin // VAT
    memOrdersVAT.AsFloat := memOrdersTOTAL.AsFloat * 0.2;
  end;
  {$ENDREGION 'DLFR memOrders.OnCalcFields'}
  if memOrdersTOTAL.IsNull then                      // your code, kept
    memOrdersTOTAL.AsFloat := 0;
end;
```

* A new region goes to the end of the handler. An existing one is replaced where it stands.
* The hash is taken over the lines between the markers (line ends do not count). **A region whose content does not match
  its hash was edited by hand: it is reported and never overwritten**, even when the repository now says the same. Move
  your edit outside the region, or delete the whole region with its markers, and run again. **Deleting only the markers
  does not hand the code over to you**: a block that is still the stored code counts as code the handler holds by hand, an
  edited one refuses the new region.
* Every character outside the regions is kept. A new region adds what it needs inside its handler: a line break when the
  `end` shared its line with other code, and a `;` (inside the region) when the last statement has none in some build.
  A second run writes nothing.
* Markers are read by a Pascal scanner: a copy in a comment, a string or a multi-line string is not a region.
* A unit that is not 7-bit ASCII (a BOM included) is refused and left byte for byte.

## Macros

`{{FIELD}}` is the persistent field component of the same dataset; the body carries the member:
`{{TOTAL}}.AsFloat := {{QTY}}.AsInteger * {{PRICE}}.AsFloat;`, `if {{ID}}.IsNull then ...`. `{{TABLE.FIELD}}` is an error. A macro in a string or a
comment is text. A calculated field comes after the fields its body names; a cycle is refused and named. A field may read itself.

## Refused, skipped, noted

* Refused: a hand-edited region; a region outside its handler; a missing, repeated or conditional (`{$IFDEF}`) handler; a
  handler that any other event of the form names too (`AfterScroll`, another field, ...); a new region beside a top-level
  `begin .. end` block that may be the region without its markers; a local name, a parameter or an inline variable that
  hides a component the code uses; a calculation that calls `Exit` while the block of another field follows; a body with a compiler directive, an open comment or string, or non-ASCII text;
  a body that does not parse inside the handler; a macro for a field the dataset does not have.
* Skipped: an event with stored code and no handler in the DFM. No handler is created and no event assigned: do that in
  the form designer and run again. A dataset without a resolvable table is skipped too.
* Noted: hand code that can `Exit` before the region or assigns the same field; a region that can `Exit` before the hand
  code behind it; code the handler already holds by hand,
  statement for statement (it is not generated a second time).

## MAXLEN constants

The length comes from the schema facts (`repo refresh-schema` first). A constant the unit itself declares by hand outside
the region (not one of a class or a method) is not declared again; when its value differs, or the declaration stands inside
a conditional, that is noted. Refused: a unit whose section 2 is not the end of the last type of its section, a unit that
does not parse before or after the edit, a unit that belongs to two tables (`A$B` and `A_B`).

## Renumbering

Only real markers with an ORM id (`1`, `1A`, ..., `CL-KEY`, ...) change, and a unit changes as a whole: an unnamed or
missing end marker, an end marker of another id or spelling, regions that do not nest, or an id in both spellings leave it as it is. The numbered regions carry no
hash. `repo update-orm` and `repo upgrade-orm-headers` read `DLFR n` like `DB-RAD n`; they never touch another `DLFR`
region. A unit whose renamed regions `update-orm` would read differently is refused.

`update-orm` refuses a unit as a whole (`REFUSED` in its `skipped` line, the file unchanged) when a numbered region has no
end, an unnamed end or the end of another id, when an id is unknown (`DB-RAD notes`), when a marker shares its line with
code, when a region holds another numbered or `DLFR` region or a part of a conditional, or when a comment or string is left
open.
