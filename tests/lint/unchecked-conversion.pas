unit unchecked_conversion;

interface

implementation

uses
  System.SysUtils;

type
  TEdit = class
    Text: string;
  end;

procedure Lesen(edtMenge: TEdit; const S: string);
var
  Menge: Integer;
  Preis: Double;
begin
  Menge := StrToInt(edtMenge.Text);
  Preis := StrToFloat(Trim(edtMenge.Text));
  Menge := StrToInt(ParamStr(1));
end;

procedure Fein(edtMenge: TEdit; const S: string);
var
  Menge: Integer;
begin
  Menge := StrToInt(S);
  Menge := StrToIntDef(edtMenge.Text, 0);
  try
    Menge := StrToInt(edtMenge.Text);
  except
    Menge := 0;
  end;
end;

end.
