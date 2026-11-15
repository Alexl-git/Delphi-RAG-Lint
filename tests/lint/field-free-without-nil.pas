unit FieldFreeWithoutNilFixture;

{ field-free-without-nil: FField.Free outside the destructor, with a path to the
  end of the method that leaves the dangling reference in the field. HIT lines
  must fire, OK lines must not. }

interface

uses
  System.Classes, System.SysUtils;

type
  TCacheOwner = class
  private
    FCache: TStringList;
    FItems: TStringList;
    FTemp : TStringList;
    FData : TStringList;
    FMore : TStringList;
    procedure InitData;
    procedure ReleaseAll;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Reset;
    procedure Rebuild;
    procedure Replace(AList: TStringList);
    procedure Drop(AFlag: Boolean);
    procedure Renew;
    procedure ResetSafely;
    procedure EarlyOut(AFlag: Boolean);
  end;

  TCloseAction = (caNone, caHide, caFree);

  TClosingForm = class
  private
    FTimer: TStringList;
  public
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  end;

  TCacheTest = class
  private
    FList: TStringList;
  public
    [TearDown]
    procedure TearDown;
  end;

implementation

constructor TCacheOwner.Create;
begin
  inherited Create;
  FCache:= TStringList.Create;
  FItems:= TStringList.Create;
end;

destructor TCacheOwner.Destroy;
begin
  ReleaseAll;
  FCache.Free; {OK}
  inherited Destroy;
end;

procedure TCacheOwner.ReleaseAll;
begin
  FItems.Free; {OK}
  FTemp.Free; {OK}
end;

procedure TCacheOwner.InitData;
begin
  FData:= TStringList.Create;
end;

procedure TCacheOwner.Reset;
begin
  FCache.Free; {HIT}
end;

procedure TCacheOwner.Rebuild;
begin
  FCache.Free; {OK}
  FCache:= TStringList.Create;
end;

procedure TCacheOwner.Replace(AList: TStringList);
begin
  FItems.Free; {OK}
  FItems:= AList;
end;

procedure TCacheOwner.Drop(AFlag: Boolean);
begin
  FTemp.Free; {HIT}
  if AFlag then
    FTemp:= nil;
end;

procedure TCacheOwner.Renew;
begin
  FData.Free; {OK}
  InitData;
end;

procedure TCacheOwner.ResetSafely;
begin
  FreeAndNil(FMore); {OK}
  if FCache.Count > 0 then
  begin
    FCache.Free; {HIT}
    Exit;
  end;
end;

procedure TCacheOwner.EarlyOut(AFlag: Boolean);
begin
  FMore.Free; {HIT}
  if AFlag then
    Exit;
  FMore:= nil;
end;

procedure TClosingForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FTimer.Free; {OK}
  Action:= caFree;
end;

procedure TCacheTest.TearDown;
begin
  FList.Free; {OK}
end;

end.
