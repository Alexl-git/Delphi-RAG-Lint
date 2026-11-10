unit RG_149b;

// Lane 150-RG2: a named-argument NAME is a parameter label, not a read of a same-named local.
interface

uses
  System.SysUtils, System.Variants;

procedure Rg149bRun(const pSheet: OleVariant; pFormat: Integer; pUnusedParam: Integer);
function Rg149bRead(const pSheet: OleVariant): Integer;

implementation

procedure Rg149bRun(const pSheet: OleVariant; pFormat: Integer; pUnusedParam: Integer);
var
  FileName: string;
  Format: Integer;
  lTmp: Integer;
begin
  pSheet.AutoFormat(FileName := 'x', Format := pFormat);
  lTmp := 1;
  pSheet.Other(Format := lTmp);
end;

function Rg149bRead(const pSheet: OleVariant): Integer;
var
  Count: Integer;
begin
  pSheet.Do(Count := 3);
  Result := Count;
end;

end.