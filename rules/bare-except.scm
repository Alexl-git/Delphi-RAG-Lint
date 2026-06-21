; A bare 'except' block (no 'on E: ... do' clause) catches EVERY exception,
; including EOutOfMemory, EStackOverflow and hardware faults -- almost never
; what you want. Detected structurally: the except section is plain 'statements'
; (field 'except:') rather than an 'exceptionHandler'. (An empty except is
; covered separately by 'empty-except'.)
((try
  except: (statements) @warn))
