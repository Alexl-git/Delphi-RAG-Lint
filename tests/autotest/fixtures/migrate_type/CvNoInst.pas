unit CvNoInst;

interface

uses
  System.Classes, CvLib;

type
  TCvNoInst = class(TComponent)
  public
    procedure Run;
  end;

implementation

uses
  System.SysUtils;

procedure TCvNoInst.Run;
var
  C: TScreenCursorOld;
begin
  C:= scoWait;
  if C = scoDefault then Exit;
end;

end.
