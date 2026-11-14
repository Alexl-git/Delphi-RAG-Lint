; An assignment to the process-wide FormatSettings (FormatSettings.DecimalSeparator := '.') or to
; one of the deprecated global format variables (DecimalSeparator := '.', ShortDateFormat := ...).
; The change leaks into every thread and every later conversion in the process; a local
; TFormatSettings passed to the conversion keeps the effect where it is wanted.
; A bare identifier is matched only for the documented legacy globals, and only when it is NOT
; the field of an enclosing class (`#not-in?` class) - a class property with the same name is
; the common false positive.
((assignment
   lhs: (exprDot
          lhs: (identifier) @obj
          rhs: (identifier) @field)) @warn
  (#match? @obj "(?i)^FormatSettings$"))
((assignment
   lhs: (identifier) @glob) @warn
  (#match? @glob "(?i)^(DecimalSeparator|ThousandSeparator|ListSeparator|DateSeparator|TimeSeparator|ShortDateFormat|LongDateFormat|ShortTimeFormat|LongTimeFormat|TimeAMString|TimePMString|CurrencyString|CurrencyFormat|NegCurrFormat|CurrencyDecimals|TwoDigitYearCenturyWindow)$")
  (#not-in? @warn "defProc" "(?i)\\."))
