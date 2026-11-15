; TStrings.DelimitedText parsed after a custom Delimiter was set, but StrictDelimiter was never
; set to True in the same routine. Without StrictDelimiter the parser ALSO splits at every blank
; (and honours the quote char), so 'a b;c' yields three items instead of two.
; Shape: <List>.Delimiter := ..; ... <List>.DelimitedText := ..; and the routine mentions
; StrictDelimiter nowhere. The finding sits on the routine (a tree-sitter pattern cannot capture
; the DelimitedText statement and test the whole routine at once). Known FP: StrictDelimiter set
; in another routine (e.g. a constructor); the message tells the fix: set it next to Delimiter.
((defProc
   body: (_) @body) @warn
  (#match? @body "(?is)^(?!.*\\bStrictDelimiter\\b).*\\b(\\w+)\\.Delimiter\\s*:=.*\\b\\1\\.DelimitedText\\s*:="))
