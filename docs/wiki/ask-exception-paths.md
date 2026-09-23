# ask: exception-paths

**What can this routine raise, and where is each exception caught?**

**Shipping with the charts release.** Its parameters are still settling, so this page describes what the question answers and not yet how to call it. See [Diagrams and Charts](Diagrams-and-Charts) for the `ask` model, the bundle every question produces, and click-to-source.

## The chart answers

For a selected routine: the exception classes it can raise -- directly or through the routines it calls -- and, for each, the `try ... except` / `on E: T do` handlers on the way up that catch it, with the paths that reach no handler shown as escaping.

## It stands on

A raise/handle reference fact: which references are a `raise` and which are an `except` handler, so a handler is never drawn as a thrower. The exception classes themselves, and their ancestry, are already in the index (see also the `Catches:` fact block in autodoc).
