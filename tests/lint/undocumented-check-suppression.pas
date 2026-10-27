unit UndocCheckSupp;

interface

implementation

procedure Bad;
begin
  {$R-}
  {$Q-}
  {$OVERFLOWCHECKS OFF}
  {$RANGECHECKS OFF}
end;

procedure Good;
begin
  // hot loop, bounds proven by the caller
  {$R-}
  // hash arithmetic wraps on purpose
  {$Q-}
  {$R+}
  {$Q+}
  {$IFDEF DEBUG}
  {$ENDIF}
end;

end.
