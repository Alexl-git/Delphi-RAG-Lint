unit CvImpl;

interface

uses
  System.Classes, CvLib;

type
  TCvImpl = class(TComponent)
  public
    procedure Run;
  end;

implementation

uses
  System.SysUtils;

procedure TCvImpl.Run;
var
  C: TScreenCursorOld;
begin
  C:= scoWait;
  if C = scoDefault then Exit;
end;

end.
