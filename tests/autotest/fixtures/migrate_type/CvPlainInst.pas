unit CvPlainInst;

interface

uses
  System.Classes, CvLib;

type
  TCvPlainInst = class(TComponent)
  public
    procedure Run;
  end;

implementation

uses
  System.SysUtils;

procedure TCvPlainInst.Run;
var
  C: Integer;
begin
  C:= 1;
  if C = 2 then Exit;
end;

end.
