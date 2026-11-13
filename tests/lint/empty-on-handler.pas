unit EmptyHandler;

interface

uses System.SysUtils;

implementation

procedure P;
begin
  try
    WriteLn('x');
  except
    on E: Exception do ;
  end;
end;

procedure Q;
begin
  try
    WriteLn('y');
  except
    on E: Exception do
      WriteLn('handled');
  end;
end;


{ A comment between `do` and the separating `;` is a node of the handler too;
  it does not give the handler a body, so the rule still fires (v151 RMU). }
procedure R;
begin
  try
    WriteLn('r');
  except
    on E: EAbort do // why it is swallowed
      ;
    on E: EConvertError do { brace comment } ;
    on E: EInOutError do
      // a comment on its own line
      // and a second one
      (* and a third *)
      ;
    on E: Exception do ; // comment after the separator
  end;
end;

procedure S;
begin
  try
    WriteLn('s');
  except
    on E: EAbort do // comment, then a real body
      WriteLn('handled');
    on E: Exception do
      raise;
  end;
end;

end.
