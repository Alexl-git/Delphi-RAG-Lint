unit CvPlain;

interface

uses
  System.Classes, CvLib;

type
  TCvPlain = class(TObject)
  public
    procedure Run;
  end;

implementation

uses
  System.SysUtils;

procedure TCvPlain.Run;
var
  C: Integer;
begin
  C:= 1;
  if C = 2 then Exit;
end;

end.
