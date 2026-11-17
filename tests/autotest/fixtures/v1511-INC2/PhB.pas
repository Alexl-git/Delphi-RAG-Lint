unit PhB;

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

implementation

const
  cLimit = 2;

var
  gTotal: Integer;

procedure TWork.Helper;
begin
end;

procedure Emit;
begin
end;

{$I PhShared.inc}

end.
