unit CvCode;

interface

uses
  System.Classes, CvLib;

type
  TCvCode = class(TObject)
  public
    procedure Run;
  end;

implementation

uses
  System.SysUtils;

procedure TCvCode.Run;
var
  C: TScreenCursorOld;
begin
  C:= scoWait;
  if C = scoDefault then Exit;
end;

end.
