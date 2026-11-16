unit PhA;

interface

uses
  PhU;

type
  TWork = class
  private
    FCount: Integer;
  public
    procedure Run;
    procedure Helper;
  end;

procedure Emit;
procedure Clash;

implementation

const
  cLimit = 1;

var
  gTotal: Integer;

procedure TWork.Helper;
begin
end;

procedure Emit;
begin
end;

procedure Clash;
begin
end;

{$I PhShared.inc}

end.
