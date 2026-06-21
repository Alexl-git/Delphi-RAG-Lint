; 'raise Exception.Create(...)' raises the root Exception class, so callers
; cannot distinguish this error from any other -- raise a specific subclass
; (e.g. EMyError) instead. Matches a raise whose exception is a call on
; 'Exception.<ctor>'.
((raise
  exception: (exprCall
    entity: (exprDot
      lhs: (identifier) @cls))) @warn
  (#eq? @cls "Exception"))
