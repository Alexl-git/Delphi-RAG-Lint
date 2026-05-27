; Sample external lint rule loaded from rules/*.scm at startup.
; Matches every bare procedure call whose callee identifier is named "WriteLn".
; Pair this file with writeln-in-source.json for severity / message metadata.
((exprCall
  entity: (identifier) @callee) @warn)
