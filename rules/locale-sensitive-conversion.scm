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
