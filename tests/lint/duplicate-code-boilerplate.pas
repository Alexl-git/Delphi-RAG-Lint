unit dupboiler;

interface

implementation

function RunCommand(const ACmd: string): Integer;
begin
  Result := 0;
  if      ACmd = 'alpha' then Result := 1
  else if ACmd = 'beta'  then Result := 2
  else if ACmd = 'gamma' then Result := 3
  else if ACmd = 'delta' then Result := 4
  else if ACmd = 'epsil' then Result := 5
  else if ACmd = 'zeta'  then Result := 6;
end;

function RunReport(const AName: string): Integer;
begin
  Result := 0;
  if      AName = 'north' then Result := 7
  else if AName = 'south' then Result := 8
  else if AName = 'east'  then Result := 9
  else if AName = 'west'  then Result := 10
  else if AName = 'up'    then Result := 11
  else if AName = 'down'  then Result := 12;
end;

end.
