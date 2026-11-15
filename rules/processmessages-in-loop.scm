; Application.ProcessMessages (or a bare ProcessMessages) inside a loop: re-entrancy hazard,
; the form can be closed or the handler re-entered while the loop is still running.
((exprDot) @warn (#match? @warn "(?i)^(Vcl\\.Forms\\.)?Application\\.ProcessMessages$"))
((exprCall) @warn (#match? @warn "(?i)^(Vcl\\.Forms\\.)?Application\\.ProcessMessages\\s*\\(\\s*\\)$"))
