; Str<->Float/Date/Time/Currency conversions without an explicit TFormatSettings
; use the GLOBAL locale, so the same code parses/formats differently on machines
; with different regional settings -- a classic cross-machine data bug. Pass a
; TFormatSettings (e.g. a fixed invariant one). 'Single argument' (no settings)
; is approximated by the absence of a comma in the argument list.
((exprCall
  entity: (identifier) @callee
  args: (exprArgs) @args) @warn
  (#any-of? @callee "StrToFloat" "FloatToStr" "StrToDate" "DateToStr" "StrToDateTime" "DateTimeToStr" "StrToTime" "TimeToStr" "StrToCurr" "CurrToStr")
  (#not-match? @args ","))
; v151 WID-SCM: Format('...%f...', [..]) without a TFormatSettings (the 3-argument
; overload) formats floats / currency with the user's decimal separator. Only a
; literal format string with a float / number / currency specifier (%f %e %g %n %m,
; any width / non-zero precision; %.0f prints no separator) is flagged; %d / %s / %x formats are locale-neutral, and
; the 3-argument call carries its settings after the array.
((exprCall
  entity: (identifier) @callee
  args: (exprArgs . (literalString) @fmt) @args) @warn
  (#eq? @callee "Format")
  (#match? @fmt "(?i)%[-0-9*:]*([fegnm]|\\.[0-9]*[1-9][0-9]*[fegnm]|\\.[0-9]*[egnm])")
  (#not-match? @args "\\]\\s*,\\s*[A-Za-z]"))
