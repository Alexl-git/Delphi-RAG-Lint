# ask: lands-where

**Where does this field's value end up?**

**Shipping with the charts release.** Its parameters are still settling, so this page describes what the question answers and not yet how to call it. See [Diagrams and Charts](Diagrams-and-Charts) for the `ask` model, the bundle every question produces, and click-to-source.

## The chart answers

For a selected field or property: the path its value takes into storage -- field -> dataset -> table.column.

## It stands on

The ORM links between Delphi classes/fields and tables/columns ([`link-orm`](link-orm)) over a Firebird schema snapshot ([`fb-snapshot`](fb-snapshot)), plus the write accesses [`who-writes`](ask-who-writes) reads.
