unit LabDirA;

interface

uses
{$IFDEF LAB_EXTRA}
  LabDirB,
{$ENDIF}
  System.SysUtils;

type
  TLabDirA = class
  public
    function Name: string;
  end;

implementation

function TLabDirA.Name: string;
begin
  Result := 'dir-a';
end;

end.
