; A bare 'except' block (no 'on E: ... do' clause) catches EVERY exception,
; including EOutOfMemory, EStackOverflow and hardware faults -- almost never
; what you want. Detected structurally: the except section is plain 'statements'
; (field 'except:') rather than an 'exceptionHandler'. (An empty except is
; covered separately by 'empty-except'.)
;
; @warn is on the 'except' KEYWORD, not on the statements it guards. That is
; deliberate and it is what every sibling rule in this family already does --
; empty-except (kExcept), empty-finally (kFinally), empty-on-handler (kDo),
; empty-conditional (kThen/kElse), empty-loop-body (kDo/kRepeat). This rule was
; the lone outlier.
;
; It is load-bearing, not cosmetic: the reported line is where a reviewer must
; write an accountable 'dl:ok bare-except' marker. Anchored on the statements,
; the marker had to go on the FIRST STATEMENT of the handler -- not on the
; construct the rule is about, and nowhere at all when the handler is empty --
; so the obvious placement silently failed AND was then reported as an unused
; marker. The design spec (docs/superpowers/specs/2026-08-12-reviewed-marker-design.md)
; and this rule's own unit header both show the marker on the 'except' line;
; only the query disagreed.
; NO '.' ANCHOR between kExcept and the statements, deliberately. It looks
; tighter and it silently breaks the whole feature: the marker this rule exists
; to accept is written as a TRAILING COMMENT on the `except` line, which sits
; between the two nodes and defeats immediate-adjacency. The rule then stops
; firing the moment a marker is added -- so the marker silences the rule instead
; of accounting for it, and `review-marker-unused` turns around and tells the
; reviewer to delete it. That is the same no-exit loop COMMENT_SENSITIVE exists
; to break (see DRagLint.CLI.pas), and it is why bare-except must NOT become a
; member of that list. Measured 2026-08-16: with the anchor the prose test's
; suppression arm fails; without it, it passes.
((try
  (kExcept) @warn
  except: (statements)))
