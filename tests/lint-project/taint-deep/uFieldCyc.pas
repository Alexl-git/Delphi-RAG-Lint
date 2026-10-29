unit uFieldCyc;

interface

type
  TFA = class
  protected
    FX: string;
  public
    procedure Grow;
  end;

  TFB = class(TFA)
  public
    procedure Run;
  end;

implementation

uses
  System.SysUtils, uDeepConn;

{ the field's writer reads the field: a cycle through FieldSummary }
procedure TFA.Grow;
begin
  FX := StringReplace(FX, 'a', 'b', []);
end;

{ a descendant writes the INHERITED field from a source, then reads it }
procedure TFB.Run;
begin
  FX := FX + ParamStr(4);
  GConn.ExecSQL(FX);
end;

end.
