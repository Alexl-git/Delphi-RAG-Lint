# Rule book and source encoding

ConvRulesEditor keeps the text encoding of every rule book you open, so captions
and names with umlauts, accents or Cyrillic stay what they are instead of turning
into question marks. It never changes an encoding silently.

## What you see on open
The editor detects the book's encoding from its bytes and shows it after the file
name, for example `Book.convrules  [UTF-8 with BOM]`. The ladder, lowest first:

| Level | Holds |
|---|---|
| ASCII-7 | plain ASCII only (the default for a new book) |
| ASCII-8 (ANSI) | the machine's ANSI code page |
| UTF-8 / UTF-8 with BOM | all of Unicode |
| UTF-16 with BOM | all of Unicode |

A BOM-less UTF-16 file that the editor is only fairly sure about is read as ASCII-8
and the status line says so.

## The Save question
Save checks the text against the book's encoding first. If every character fits,
the book is written as it is. If some would be lost, a question names the count,
lists the characters (`line N: U+XXXX`) and offers to save the book as the next
level up (UTF-8 for an ASCII book). Yes saves at that level; Cancel writes
nothing and leaves no stray backup. A book that is never given such characters
never sees the question.

UTF-16 is always saved with a BOM: the engine cannot read UTF-16 without one. The
status line says so once per session.

## Save As and File > Encoding
**File > Encoding** lists ASCII-7, ASCII-8 (ANSI), UTF-8, UTF-8 with BOM and
UTF-16 with BOM as radio items; the checked one is what Save and Save As write
(the question above still applies). There is no plain UTF-16 item.

## The Convert tab
Two questions, both asked before the unit or book is touched:

* **Raise a source** -- when the engine refuses a unit because a character the
  rules write does not fit the `.pas` / `.dfm` encoding, the tab asks: Yes raises
  that file to UTF-8 with BOM and converts the unit again (all its books are
  applied again, because a refused unit is restored unchanged); No skips this unit;
  Cancel skips all remaining. This needs an engine that reports the
  `convert_encoding_guard` capability.
* **Lower a book** -- when a book is saved at a higher level than its text needs
  (for example UTF-16 with only ASCII text), the tab offers to lower it before
  converting, as a normal Save with a backup. Yes lowers, No keeps it. Each book
  is asked once per session.

## What is never done silently
* No character is replaced by `?` without the Save question.
* No source file is rewritten to a higher encoding without your Yes.
* No book is lowered without your Yes.

See also: [ConvRulesEditor](convrules-editor.md), `docs/CONVERSION-RULES.md`
("Text encoding of rule books and sources").
