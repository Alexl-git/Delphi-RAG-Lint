// A fragment included by U1 and U2, both with HOSTON defined.
{$IFDEF HOSTON}
procedure HostOnProc;
begin
  try
    Writeln('on');
  except
  end;
end;
{$ELSE}
procedure HostOffProc;
begin
  try
    Writeln('off');
  except
  end;
end;
{$ENDIF}