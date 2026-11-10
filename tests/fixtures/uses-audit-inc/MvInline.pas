unit MvInline;

interface

uses
  SysUtils, MvB;

type
  TMvInline = class
  public
    procedure Run;
  end;

implementation

procedure TMvInline.Run;
var
  B: TMvB;
begin
  B:= TMvB.Create;
  B.Free;
end;

end.
