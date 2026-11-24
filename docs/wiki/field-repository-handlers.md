# Field repository: generated handlers and DLFR regions

Three `repo` sub-verbs write code from the [field repository](field-repository.md) into existing units. All are dry runs
until `--apply`; `--dry-run` wins over `--apply`.

| Sub-verb | Options | What it does |
|---|---|---|
| `gen-handlers` | `--dfm <file.dfm>[;...]` [`--dataset <Name>`] [`--apply`] [`--json`] | Puts the stored bodies of a dataset's fields (`CALC_BODY`, `ONGETTEXT_BODY`, `ONSETTEXT_BODY`, `ONVALIDATE_BODY`, `ONCHANGE_BODY` of the field row) into the event handlers the DFM assigns: `OnCalcFields`, `OnGetText`, `OnSetText`, `OnValidate`, `OnChange`. Needs a schema-3 repository |
| `gen-maxlen` | `--code-dir <folder>` [`--table <T,...>`] [`--apply`] [`--json`] | Writes `<TABLE>_<FIELD>_MAXLEN` constants into region `DLFR 2a` of each interface unit `i<TABLE>.pas`, behind section 2 |
| `renumber-regions` | `--code-dir <folder>` or `--in <file.pas>[;...]` [`--apply`] [`--json`] | Renames the numbered ORM region markers of whole units: `DB-RAD n` becomes `DLFR n` |

Exit code: 0 ok, 1 a failure or at least one region refused (the others are still written), 2 wrong arguments.

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
  your edit outside the region, or delete the region, and run again.
* Every character outside the regions is kept. A second run writes nothing.
* Markers are read by a Pascal scanner: a copy in a comment, a string or a multi-line string is not a region.
* A unit that is not 7-bit ASCII (a BOM included) is refused and left byte for byte.

## Macros

`{{FIELD}}` is the persistent field component of the same dataset; the body carries the member:
`{{TOTAL}}.AsFloat := {{QTY}}.AsInteger * {{PRICE}}.AsFloat;`, `if {{ID}}.IsNull then ...`. `{{TABLE.FIELD}}` is an error.
A calculated field comes after the fields its body names; a cycle is refused and named. A field may read itself.

## Refused, skipped, noted

* Refused: a hand-edited region; a region outside its handler; a missing, repeated or conditional (`{$IFDEF}`) handler; one
  handler used for more than one event; a body with a compiler directive, an open comment or string, or non-ASCII text;
  a body that does not parse inside the handler; a macro for a field the dataset does not have.
* Skipped: an event with stored code and no handler in the DFM. No handler is created and no event assigned: do that in
  the form designer and run again. A dataset without a resolvable table is skipped too.
* Noted: hand code that can `Exit` before the region or assigns the same field; code the handler already holds by hand,
  statement for statement (it is not generated a second time).

## MAXLEN constants

The length comes from the schema facts (`repo refresh-schema` first). A constant the unit declares by hand outside the
region is not declared again; when its value differs that is noted. Section 2 must be the end of the last type of its
section, otherwise the unit is refused.

## Renumbering

Only real markers with an ORM id (`1`, `1A`, ..., `CL-KEY`, ...) change, and a unit changes as a whole: an unnamed or
missing end marker, regions that do not nest, or an id in both spellings leave it as it is. The numbered regions carry no
hash. `--apply` is refused while `repo update-orm` of the same build cannot read `DLFR` regions.
