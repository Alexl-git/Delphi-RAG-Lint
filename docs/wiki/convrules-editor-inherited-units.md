# Inherited units, ancestors first (C8CHAIN)

A form that inherits from another form can only be converted after its ancestor: the
descendant's `.dfm` re-opens the ancestor's components (`inherited Name: TClass`), so a
descendant converted first keeps the old types. ConvRulesEditor builds the inheritance graph of
the units in the run and keeps every chain in root-first order.

## Where it shows
**Convert tab > Add...** offers every ancestor that still holds a From type of the checked
books, root first (intermediate classes included). **Convert** re-checks the list and asks before it
runs anything.

## What to know
* Convert never runs a descendant above its ancestor: it asks to reorder the list ancestor-first.
  **No runs nothing.**
* An unconverted ancestor that is not in the run blocks too: **Yes** adds the missing ancestors
  root-first and runs; **No** cancels the whole run. A No given when the unit was added does not
  exempt it later.
* An ancestor class found in neither the project index nor the platform library index blocks the run:
  add its unit to the `.dproj`/`.dpr` and reindex. A library class (`TForm`, a vendor base) ends the chain.
* A class declared in more than one project unit is ambiguous and blocks with its own message: remove
  the duplicate or qualify the class.
* If the platform library cannot be asked, only `TForm`, `TFrame`, `TDataModule` and their
  `TCustom*` forms still count as roots; any other class blocks.
* The 1.42 engine also orders a batch ancestor-first (a second net).

See also [ConvRulesEditor](convrules-editor).
