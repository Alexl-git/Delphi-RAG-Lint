# ask: feeds-from

**Where does the data in this control come from?**

**Shipping with the charts release.** Its parameters are still settling, so this page describes what the question answers and not yet how to call it. See [Diagrams and Charts](Diagrams-and-Charts) for the `ask` model, the bundle every question produces, and click-to-source.

## The chart answers

For a selected data-aware control: the chain behind it -- control -> datasource -> dataset (or memtable) -> table and column.

## It stands on

The DFM data bindings already used by [`shown-where`](ask-shown-where), joined through the dataset definitions to the Firebird schema snapshot ([`fb-snapshot`](fb-snapshot)) and the ORM links ([`link-orm`](link-orm)).
