unit RF2Vcl;

interface

uses
  Vcl.Forms;

type
  TRf2Form = class(TForm)
    procedure Go;
  end;

implementation

procedure TRf2Form.Go;
var
  Tmp: Integer;
begin
  try
    Tmp:= 1 div ClientWidth;
  except
    Tmp:= 0;
  end;
end;

end.
