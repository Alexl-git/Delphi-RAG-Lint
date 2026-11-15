; Items/Lines/Nodes.Add inside a loop repaints a visual list on every call.
((exprCall) @warn
  (#match? @warn "(?i)\\.(Items|Lines|Nodes|Strings)\\.(Add|AddObject|Append|Insert)\\s*\\("))
