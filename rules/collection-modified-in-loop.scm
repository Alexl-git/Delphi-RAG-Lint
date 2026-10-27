; A collection changed while it is being walked. Two shapes, both matched on the loop's own text so the
; container named in the header is the one mutated in the body (a PCRE back-reference, which a
; tree-sitter pattern cannot express):
;  (a) for X in C do ... C.Add/Insert/Delete/Remove/Clear/Extract/Pack/AddRange/DeleteRange/Exchange(..)
;      -- the enumerator is invalidated (EListError / skipped items).
;  (b) for I := 0 to C.Count - 1 do ... C.Delete(I) / C.Remove(..)  -- the forward-delete bug: the
;      items shift down and the loop runs past the new end. Walk backwards (downto 0) instead.
; Known false positive (named in the message): the mutating statement is followed by Break / Exit.
((foreach) @warn
 (#match? @warn "(?is)^for\\s+\\S+\\s+in\\s+(\\w+)\\s+do\\b.*\\b\\1\\.(Add|Insert|Delete|Remove|Clear|Extract|Pack|AddRange|DeleteRange|Exchange)\\s*\\("))
((for
  start: (assignment lhs: (identifier) @i)
  end: (exprBinary lhs: (exprDot lhs: (identifier) @c))
  body: (_) @body) @warn
 (#match? @warn "(?is)^for\\s+(\\w+)\\s*:=\\s*0\\s+to\\s+(\\w+)\\.Count\\s*-\\s*1\\s+do\\b.*\\b\\2\\.(Delete\\s*\\(\\s*\\1\\s*\\)|Remove\\s*\\()"))
