; A string-to-number/date conversion applied straight to user input. StrToInt(edtMenge.Text) raises
; EConvertError for anything that is not a number, and user text is exactly where that happens.
; Fires for StrToInt, StrToInt64, StrToFloat, StrToCurr, StrToDate, StrToDateTime and StrToTime with
; ONE argument (no format settings) that is a control's Text, a grid cell / memo line / list entry
; (Cells[..], Lines[..], Strings[..]) or ParamStr(..), optionally wrapped in Trim. A call inside any
; try block is not reported. OFF by default: legacy form code is full of guarded-by-validator cases.
((exprCall
   entity: (identifier) @fn
   args: (exprArgs) @args) @warn
  (#match? @fn "(?i)^(StrToInt|StrToInt64|StrToFloat|StrToCurr|StrToDate|StrToDateTime|StrToTime)$")
  (#match? @args "(?i)^\\(?\\s*(Trim\\(\\s*)?(ParamStr\\([^,]*\\)|[A-Za-z_][\\w.]*[.](Text|(Cells|Lines|Strings)\\[[^\\]]*\\]))\\s*\\)*\\s*$")
  (#not-in? @warn "try"))
