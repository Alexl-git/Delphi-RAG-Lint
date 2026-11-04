unit uDmfPlain;

interface

uses
  uDmfForm;

procedure Touch;

implementation

{ not a data module: the same read says nothing here }
procedure Touch;
begin
  MainForm.Caption2 := 'x'; // CONTROL-NOTMODULE
end;

end.