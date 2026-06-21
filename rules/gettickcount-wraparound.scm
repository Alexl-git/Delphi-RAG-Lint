; GetTickCount returns a 32-bit millisecond counter that WRAPS after ~49.7 days,
; so naive elapsed-time math (Now - Start) is wrong across the wrap. Use
; GetTickCount64. Matches the identifier in both 'GetTickCount' and 'GetTickCount()'.
((identifier) @warn
  (#match? @warn "(?i)^gettickcount$"))
