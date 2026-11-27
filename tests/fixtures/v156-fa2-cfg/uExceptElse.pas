unit uExceptElse;

{ drag-lint 1.56 lane FA-2 fixture: the ELSE part of an except block is in the flow graph, so the
  data-flow walk emits rows from it. Read by tests\autotest\run_v156_FA2_cfg.ps1 through the M-*
  markers (one per line). Not compiled; 7-bit ASCII, CRLF. }

interface

procedure Sink(const S: string);
procedure ElseP(const P: string);
procedure ElseTwo(const P, Q: string);
function ElseResult(const P: string): string;

implementation

procedure Sink(const S: string);
begin
end;

procedure ElseP(const P: string);
begin
  try
    Sink('x');
  except
    on E: EAbort do
      Sink(P); { M-ON }
    else
      Sink(P); { M-ELSE }
  end;
end;

procedure ElseTwo(const P, Q: string);
begin
  try
    Sink('x');
  except
    on E: EAbort do
      Sink('y');
    else
      Sink(P); { M-ELSE-FIRST }
      Sink(Q); { M-ELSE-SECOND }
  end;
end;

function ElseResult(const P: string): string;
begin
  try
    Result := 'a';
  except
    on E: EAbort do
      Result := 'b';
    else
      Result := P; { M-ELSE-RESULT }
  end;
end;

end.
