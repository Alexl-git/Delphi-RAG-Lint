unit uX4RUnit;

{ X4-r (wave 151) unit leg: a bare call inside a FREE unit routine has no
  receiver either (the implicit-Self rung typed it as the unit symbol). }

interface

procedure X4RUnitPub;

implementation

procedure X4RUnitPriv;
begin
end;

procedure X4RUnitPub;
begin
  X4RUnitPriv;
end;

end.