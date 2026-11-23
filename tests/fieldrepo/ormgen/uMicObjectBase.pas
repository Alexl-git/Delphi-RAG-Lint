unit uMicObjectBase;

{ Stub of the ORM3 unit of the same name: only what the generated units reference.
  Reference counting is modelled on the real TMicObjectBase (COMMON\uMicObjectBase.pas): FRefCount starts at 0,
  an object without a component owner is freed by _Release when the count falls back to 0, so a temporary
  interface reference to an object held only by an object reference frees it. MicDestroyCount counts the
  destructors that ran (tests read it). }

interface

uses
  System.Classes,
  IuMicObject,
  MStreams;

var
  MicDestroyCount: Integer = 0;

type
  TMicObjectBase<I: IMicObject> = class(TComponent, IMicObject)
  private
    FRefCount: Integer;
    FOwnerIsComponent: Boolean;
  protected
    FModified: Boolean;
    { protected, as in the real unit: a descendant that re-implements the interface only sees these then }
    function QueryInterface(const IID: TGUID; out Obj): HResult; override; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
    function GetModified: Boolean;
    procedure SetModified(const Value: Boolean);
    procedure Initialize; virtual; abstract;
    function Reader(AStream: TABZMemoryStream): Boolean; virtual; abstract;
    function Writer(AStream: TABZMemoryStream): Boolean; virtual; abstract;
  public
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
    destructor Destroy; override;
    property Modified: Boolean read GetModified write SetModified;
  end;

implementation

procedure TMicObjectBase<I>.AfterConstruction;
begin
  FOwnerIsComponent := Assigned(Owner) and (Owner is TComponent);
  inherited;
  Initialize;
end;

procedure TMicObjectBase<I>.BeforeDestruction;
begin
  if (FRefCount <> 0) and not FOwnerIsComponent then
    System.Error(reInvalidPtr);
  inherited;
end;

destructor TMicObjectBase<I>.Destroy;
begin
  Inc(MicDestroyCount);
  inherited;
end;

function TMicObjectBase<I>.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
    Result := 0
  else
    Result := E_NOINTERFACE;
end;

function TMicObjectBase<I>._AddRef: Integer;
begin
  if FOwnerIsComponent then
    Result := -1
  else
    Result := AtomicIncrement(FRefCount);
end;

function TMicObjectBase<I>._Release: Integer;
begin
  if FOwnerIsComponent then
    Result := -1
  else
  begin
    Result := AtomicDecrement(FRefCount);
    if Result = 0 then
      Destroy;
  end;
end;

function TMicObjectBase<I>.GetModified: Boolean;
begin
  Result := FModified;
end;

procedure TMicObjectBase<I>.SetModified(const Value: Boolean);
begin
  FModified := Value;
end;

end.
