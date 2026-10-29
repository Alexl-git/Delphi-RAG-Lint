; A secret written to an INI file / registry value in clear text (CWE-312, CWE-256).
; Fires on X.WriteString(section, '<key>', V) where the key literal looks secret-like
; (pass|pwd|secret|token) and V is not a call -- an Encrypt(..) / Protect(..) argument is
; the sanctioned shape and stays silent. Receivers are not type-checked: WriteString with a
; secret-named literal key is the signal (TIniFile, TMemIniFile, TRegistry, TRegIniFile).
((exprCall
   entity: (exprDot rhs: (identifier) @fn)
   args: (exprArgs
     (literalString) @key
     [(literalString) (identifier) (exprDot) (exprBinary)] @val)) @warn
  (#eq? @fn "WriteString")
  (#match? @key "(?i)pass|pwd|secret|token"))
