; DEC-16 (wave 146, lane g2). A line comment of the old shape
; `// note // dl:shared A`: a second `//` precedes the tag on the same line.
; The scanner (DRagLint.Lint.SharedUnit.ScanHeader, ruling R12) treats the tag as
; a marker only when it is the FIRST token of its comment, so such a unit reads
; unshared and add-project writes a fresh marker that drops the old list.
; It cannot tell this from prose `// see // dl:shared below` (R12), so the rule
; warns on both; the fix is the same: lead with the tag or reword.
; RF 2026-11-08: prose with MORE words after the tag (// see // dl:shared below for
; details) is not a project list and no longer fires: after the tag the comment must be a
; comma-separated list of names, optionally followed by // note. Prose that is exactly one
; word after the tag stays indistinguishable (R12) and still warns.
; The correct writer shape `// dl:shared A, B // note` has the tag first and does
; not match. Comment nodes only, so string literals never fire.
((comment) @warn
  (#match? @warn "(?i)^//[^\\r\\n]*[^\\s/][^\\r\\n]*//[ \\t]*dl:shared[ \\t]+[A-Za-z_][\\w.-]*([ \\t]*,[ \\t]*[A-Za-z_][\\w.-]*)*[ \\t\\r]*(//[^\\r\\n]*)?$"))
