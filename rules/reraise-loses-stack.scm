; 'raise E;' inside 'on E: ... do' re-raises by instance, which RESETS the
; exception's stack trace. Use a bare 'raise;' to preserve the original origin.
; Precise: the raised identifier must equal the handler's exception variable
; (single-statement handler form).
((exceptionHandler
  variable: (identifier) @var
  body: (raise
    exception: (identifier) @reraised) @warn)
  (#eq? @var @reraised))
