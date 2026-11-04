# Examine (mark the properties a form really uses)

A class can have hundreds of properties and a form uses a handful. Examine reads the
`.dfm` / `.pas` files you pick and marks, in green, the From properties those files
actually use, so you map those first.

## Where it shows
**Conversion > Examine...** picks the files. **Conversion > Clear marks** drops the
examination and unmarks every row. "Types on form (Examine to fill)" is the list the
examination fills.

## What it changes
Nothing in the book: the marks are a view aid and never touch the rule book, its
Snapshot or its dirty flag.