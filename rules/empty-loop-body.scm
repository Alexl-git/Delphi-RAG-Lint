; A loop with an empty body is almost always a bug: a stray ';' detached the
; intended body ('while C do ;' then the real code runs once, unguarded), or it
; is a busy-wait that should sleep/yield instead of spinning the CPU.
; while/for: 'do' is the loop's last child (no body follows).
((while (kDo) @warn .))
((for (kDo) @warn .))
; repeat: 'repeat' is immediately followed by 'until' (no statements between).
((repeat (kRepeat) @warn . (kUntil)))
