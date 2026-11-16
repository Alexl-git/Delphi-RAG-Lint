unit uUse;

interface

uses
  LibCtl, uTok;

type
  TKind = (kEdit, kCombo, kTok, kOther, kMake, kMy, kTokEx);
  TTokenEx = class(TToken)
  end;
  TMyEdit = class(TEdit)
  end;
  TFrame1 = class
  private
    FControls: TArray<TControl>;
    FKinds: TArray<TKind>;
  public
    procedure Load(const AValue: string);
    procedure Save(var AValue: string);
  end;

implementation

procedure TFrame1.Load(const AValue: string);
var
  i: Integer;
begin
  for i:= 0 to High(FControls) do
    case FKinds[i] of
      kEdit : TEdit(FControls[i]).Text:= AValue;
      kCombo: TComboBox(FControls[i]).Text:= AValue;
      kTok  : TToken(FControls[i]).Text:= AValue;
      kOther: TOther(FControls[i]).Text:= AValue;
      kMake : MakeCtl(FControls[i]).Text:= AValue;
      kMy   : TMyEdit(FControls[i]).Text:= AValue;
      kTokEx: TTokenEx(FControls[i]).Text:= AValue;
    end;
end;

procedure TFrame1.Save(var AValue: string);
var
  i: Integer;
begin
  for i:= 0 to High(FControls) do
    case FKinds[i] of
      kEdit : AValue:= TEdit(FControls[i]).Text;
      kCombo: AValue:= TComboBox(FControls[i]).Text;
      kTok  : AValue:= TToken(FControls[i]).Text;
    end;
end;

end.