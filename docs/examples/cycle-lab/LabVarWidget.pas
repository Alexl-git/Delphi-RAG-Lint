unit LabVarWidget;

interface

type
  TLabVarWidget = class
  public
    procedure Hello;
    procedure Reload;
  end;

implementation

uses
  LabVarHost;

procedure TLabVarWidget.Hello;
begin
  Writeln('[var] hello');
end;

procedure TLabVarWidget.Reload;
var
  H: TLabVarHost;
  Me: TLabVarWidget;
begin
  H := TLabVarHost.Create;
  try
    Me := Self;
    H.Fill(Me);
  finally
    H.Free;
  end;
end;

end.
