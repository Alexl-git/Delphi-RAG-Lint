; Member access straight off a call whose RTL routine returns nil when nothing is found:
; FindComponent('X').Name raises an access violation when the component is absent. Store the result
; and test it (or use the raising twin: FieldByName / ParamByName / a cast with 'as'-checked lookup).
; Pruned from the candidate list on purpose: GetValue / GetType / GetProcAddress (TRttiProperty.GetValue
; returns a TValue record, never nil; GetProcAddress returns a pointer that cannot be dotted).
; Shape 1: Call(..).Member
((exprDot
  lhs: (exprCall
    entity: [(identifier) @fn (exprDot rhs: (identifier) @fn)])) @warn
 (#any-of? @fn "FindComponent" "FindChildControl" "FindGlobalComponent" "FindControl" "FindVCLWindow" "FindDragTarget" "FindField" "FindParam" "FindNode" "FindItem"))
; Shape 2: (Call(..) as TFoo).Member
((exprDot
  lhs: (exprParens
    (exprBinary
      lhs: (exprCall
        entity: [(identifier) @fn (exprDot rhs: (identifier) @fn)])
      operator: (kAs)))) @warn
 (#any-of? @fn "FindComponent" "FindChildControl" "FindGlobalComponent" "FindControl" "FindVCLWindow" "FindDragTarget" "FindField" "FindParam" "FindNode" "FindItem"))
