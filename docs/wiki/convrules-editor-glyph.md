# Glyph expressions (G[I/N])

A glyph expression links a From property to a To property through the index of an
item in a list or its count (C10): `G[I/N]`. ConvRulesEditor sets, changes or clears
it on the selected link so you do not edit the `#link` text by hand.

## Where it shows
**Mapping > Glyph expression...** acts on the selected link. The dialog sets, changes
or clears the expression.

## What to know
* The edit is made in the open book and is not saved until File > Save.
* convert-apply REFUSES a book whose `#link` carries a glyph expression until the
  engine realises G-links (CV-2); the refusal is reported on the Convert tab, not
  hidden.