unit MvHost;

interface

uses
  {$I MvUses.inc}

type
  TMvHost = class
  public
    procedure Run;
  end;

implementation

procedure TMvHost.Run;
var
  B: TMvB;
begin
  B:= TMvB.Create;
  B.Free;
end;

end.
