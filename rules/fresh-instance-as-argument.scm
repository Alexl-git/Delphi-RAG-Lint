; A freshly created object passed straight into a call: nobody holds a reference, so it leaks unless
; the callee takes ownership or the parameter is an interface. OFF by default (a store-based upgrade
; that reads the callee's parameter type is LATER). The callee is skipped when it is a constructor or
; an ownership-taking name (Add, AddPair, Insert, Register..., ...; AddPair is TJSONObject, which owns the value).
((exprCall
   entity: (identifier) @fn
   args: (exprArgs
     (exprCall entity: (exprDot lhs: (identifier) @t rhs: (identifier) @c))) ) @warn
 (#match? @t "^T[A-Z]\\w*$")
 (#eq? @c "Create")
 (#not-match? @fn "^(Add|AddObject|AddPair|AddElement|AddChild|AddItem|InsertObject|Append|Insert|AddOrSetValue|Push|Enqueue|AddRange|SetValue|RegisterComponent|Register\\w*|Create)$"))

((exprCall
   entity: (identifier) @fn
   args: (exprArgs
     (exprDot lhs: (identifier) @t rhs: (identifier) @c))) @warn
 (#match? @t "^T[A-Z]\\w*$")
 (#eq? @c "Create")
 (#not-match? @fn "^(Add|AddObject|AddPair|AddElement|AddChild|AddItem|InsertObject|Append|Insert|AddOrSetValue|Push|Enqueue|AddRange|SetValue|RegisterComponent|Register\\w*|Create)$"))

((exprCall
   entity: (exprDot rhs: (identifier) @fn)
   args: (exprArgs
     (exprCall entity: (exprDot lhs: (identifier) @t rhs: (identifier) @c)))) @warn
 (#match? @t "^T[A-Z]\\w*$")
 (#eq? @c "Create")
 (#not-match? @fn "^(Add|AddObject|AddPair|AddElement|AddChild|AddItem|InsertObject|Append|Insert|AddOrSetValue|Push|Enqueue|AddRange|SetValue|RegisterComponent|Register\\w*|Create)$"))

((exprCall
   entity: (exprDot rhs: (identifier) @fn)
   args: (exprArgs
     (exprDot lhs: (identifier) @t rhs: (identifier) @c))) @warn
 (#match? @t "^T[A-Z]\\w*$")
 (#eq? @c "Create")
 (#not-match? @fn "^(Add|AddObject|AddPair|AddElement|AddChild|AddItem|InsertObject|Append|Insert|AddOrSetValue|Push|Enqueue|AddRange|SetValue|RegisterComponent|Register\\w*|Create)$"))