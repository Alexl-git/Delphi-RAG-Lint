# query unit-usage

Answers one question, about **one unit** and **one file**:

> Of everything this unit exports, does this file reference any of it?

An empty answer is the interesting one: it means the `uses` entry is a **dead
import**. Reach for it when you are cleaning a uses clause, when a build pulls in
a package you think nothing needs, or when you want to check a
`unused-unit-in-uses` finding before acting on it.

## Running it from the CLI

```
drag-lint query unit-usage --in <file.pas> --unit <UnitName> [--db ...] [--json]
```

* `--in` is the source file to examine.
* `--unit` is the unit whose exports you are asking about, spelled as the `uses`
  clause spells it (`System.IniFiles`, not `IniFiles`).

## It usually needs TWO databases

This is the part that catches people out. The question spans two indexes:

* the **file** lives in a project index;
* the **unit** usually does not -- `System.IniFiles` is RTL, so it lives in the
  **library** index.

So pass both:

```
drag-lint query unit-usage --in C:\Projects\DataCopy\uGlobals.pas ^
  --unit System.IniFiles ^
  --db C:\Projects\DataCopy\_D-RAG\DataCopy.sqlite ^
  --db C:\Projects\.drag-lint\library-Win64.sqlite
```

Given only the project index, the unit cannot be found, and a unit with no known
exports produces no answer at all. Use `resolve-dbs` if you are unsure which
databases cover a file.

## What counts as an export

The unit's **interface-section** declarations, and only those. Implementation
declarations are invisible to an importer, so they cannot keep an import alive.

That distinction is not academic. The rule this engine backs used to match *any*
symbol of the same name anywhere in the unit, which meant a loop counter named
`I` inside a unit made every file that used a variable `I` count as a user of
it.

## Reading the output

Every export is listed with its verdict, and the last line is the roll-up.

```
file: C:/Projects/DataCopy/CSVRoutines.pas
unit: System.IOUtils
  TSearchOption      System.IOUtils.TSearchOption      UNUSED
  TDirectory         System.IOUtils.TDirectory         UNUSED
  TPath              System.IOUtils.TPath              USED  read=3 call=3 member-access=3   first line 85
2 of 11 export(s) referenced
```

`2 of 11` is a **live** import: one export is enough. Compare a dead one:

```
file: C:/Projects/DataCopy/uGlobals.pas
unit: System.IniFiles
  EIniFileException  System.IniFiles.EIniFileException  UNUSED
  TCustomIniFile     System.IniFiles.TCustomIniFile     UNUSED
  ...
0 of 6 export(s) referenced
```

`0 of 6` means nothing in the file names anything the unit offers -- the `uses`
entry can go.

## Relationship to `unused-unit-in-uses`

The lint rule asks this same question of every entry in every uses clause, so
this verb is the way to **check a finding by hand** before you act on it. They
share their semantics deliberately: if the rule reports a unit and this verb
says `0 of N`, they agree.

Two cases where a `0 of N` is still correct to keep:

* **registration units** -- a DevExpress skin (`dxSkin*`) or EurekaLog's injected
  block exists for its `initialization` section. It exports nothing anyone
  references, so `0 of N` is true of it and means nothing. The rule skips these
  families; this verb reports them honestly.
* **conditional compilation** -- if the references sit inside a branch the
  preprocessor blanked for the current profile, they are genuinely not there for
  this configuration.

## Why not just grep

Grep cannot tell a reference from the same word in a comment or a string
literal, and it cannot tell which unit a name came from. `TcxCheckBoxState`
looks like it belongs to `cxCheckBox`; it is declared in `cxLookAndFeelPainters`.
Using it does not keep `cxCheckBox` alive, and only an index knows that.

## See also

* [`query type-usage`](query-type-usage) -- the same shape, but for a list of
  type names rather than one unit's exports
* [`resolve-dbs`](resolve-dbs) -- which databases cover a given file or project
