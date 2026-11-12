unit dcrns;

{ wave 152b lane DC: referenced-never-set must credit a field write whose
  receiver is a HARD CAST to the field's class, `TGreet(LOld).FReplaced :=`,
  written from another class's method in the same unit. TRIGGER-* must fire,
  CONTROL-* must stay silent. }

interface

type
  TGreet = class
  private
    FReplaced: Boolean;   // CONTROL-CASTWRITE
    FOnlyRead: Boolean;   // TRIGGER-ONLYREAD
    FOtherCast: Boolean;  // TRIGGER-OTHERCAST
  public
    function State: Integer;
  end;

  TOther = class
  private
    FOtherCast: Boolean;  // CONTROL-OTHERCLASS
  public
    function Has: Boolean;
  end;

  TCtrl = class
  public
    procedure Register(LOld: TObject);
  end;

implementation

function TGreet.State: Integer;
begin
  Result := 0;
  if FReplaced then Inc(Result);
  if FOnlyRead then Inc(Result);
  if FOtherCast then Inc(Result);
end;

function TOther.Has: Boolean;
begin
  Result := FOtherCast;
end;

procedure TCtrl.Register(LOld: TObject);
begin
  TGreet(LOld).FReplaced := True;
  TOther(LOld).FOtherCast := True;
end;

end.
