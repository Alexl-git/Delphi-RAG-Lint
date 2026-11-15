unit Cfg;

{ Shares its name with a local variable in UMain; UMain's `Cfg.Value` is that
  variable, never this unit. Must not be reported. }

interface

var
  Value: Integer;

implementation

end.
