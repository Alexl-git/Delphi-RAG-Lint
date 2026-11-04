unit uDmfModule;

interface

uses
  System.Classes, Data.DB, uDmfForm;

type
  TAppModule = class(TDataModule)
  private
    ShadowedForm: Integer;
  public
    procedure Touch;
    function ReadShadow: Integer;
  end;

implementation

procedure TAppModule.Touch;
var
  NotUsedForm: Integer;
begin
  MainForm.Caption2 := 'x'; // TRIGGER-MAIN
  MainForm.Caption2 := 'y';
  if PlainForm <> nil then // TRIGGER-PLAIN
    OtherThing.Tag := 1; // CONTROL-NOTAFORM
  if ViaLibForm <> nil then // TRIGGER-LIB
    NotUsedForm := 3;
  NotUsedForm := 2; // CONTROL-NOTINUSES
  ShadowedForm := NotUsedForm; // CONTROL-SHADOWED
end;

function TAppModule.ReadShadow: Integer;
begin
  Result := ShadowedForm;
end;

end.