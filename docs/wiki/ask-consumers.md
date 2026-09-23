# ask: consumers

**Which code reads or writes this table or column?**

**Shipping with the charts release.** Its parameters are still settling, so this page describes what the question answers and not yet how to call it. See [Diagrams and Charts](Diagrams-and-Charts) for the `ask` model, the bundle every question produces, and click-to-source.

## The chart answers

For a selected database table or column: every unit and routine that reads it and every one that writes it, grouped by source-directory zone.

## It stands on

The Firebird schema snapshot ([`fb-snapshot`](fb-snapshot), taken against a LIVE database) joined to the Delphi index by [`link-orm`](link-orm), plus the per-routine SQL read/write facts [`touches-tables`](ask-touches-tables) uses in the other direction.
