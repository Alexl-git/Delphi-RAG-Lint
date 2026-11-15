unit FieldOwnershipUnclearFixture;

{ field-ownership-unclear: a field the constructor creates, that no method of the
  class frees, but that the class hands out (returns it, passes it to an Add /
  Insert / Register ... call, stores it in another object). HIT lines must fire,
  OK lines must not. }

interface

uses
  System.Classes, System.Generics.Collections;

type
  TRegistry = class
  public
    procedure RegisterList(AList: TStringList);
    procedure Show(AList: TStringList);
    procedure RegisterHook(const AHook: IInterface);
  end;

  TCache = class
  private
    FList   : TStringList;
    FShared : TStringList;
    FGiven  : TStringList;
    FKept   : TStringList;
    FOwned  : TObjectList<TStringList>;
    FChild  : TStringList;
    FShown  : TStringList;
    FReg    : TRegistry;
    FHook   : IInterface;
  public
    constructor Create(AReg: TRegistry);
    destructor Destroy; override;
    function Take: TStringList;
    procedure Publish(AReg: TRegistry);
    procedure Expose(ATarget: TCache);
  end;

implementation

procedure TRegistry.RegisterList(AList: TStringList);
begin
end;

procedure TRegistry.Show(AList: TStringList);
begin
end;

procedure TRegistry.RegisterHook(const AHook: IInterface);
begin
end;

constructor TCache.Create(AReg: TRegistry);
begin
  inherited Create;
  FReg   := AReg;
  FList  := TStringList.Create; {HIT}
  FShared:= TStringList.Create; {HIT}
  FGiven := TStringList.Create; {HIT}
  FKept  := TStringList.Create; {OK}
  FOwned := TObjectList<TStringList>.Create;
  FChild := TStringList.Create; {OK}
  FShown := TStringList.Create; {OK}
  FHook  := TInterfacedObject.Create; {OK}
  FReg.RegisterHook(FHook);
  FOwned.Add(FChild);
  FReg.Show(FShown);
end;

destructor TCache.Destroy;
begin
  FKept.Free;
  FOwned.Free;
  FShown.Free;
  inherited Destroy;
end;

function TCache.Take: TStringList;
begin
  Result:= FList;
end;

procedure TCache.Publish(AReg: TRegistry);
begin
  AReg.RegisterList(FShared);
  FReg.RegisterList(FKept);
end;

procedure TCache.Expose(ATarget: TCache);
begin
  ATarget.FGiven:= FGiven;
end;

end.
