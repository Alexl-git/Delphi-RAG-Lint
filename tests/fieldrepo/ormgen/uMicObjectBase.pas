unit uMicObjectBase;

{ Stub of the ORM3 unit of the same name: only what the generated units reference. }

interface

uses
  System.Classes,
  IuMicObject,
  MStreams;

type
  TMicObjectBase<I: IMicObject> = class(TComponent, IMicObject)
  protected
    FModified: Boolean;
    function GetModified: Boolean;
    procedure SetModified(const Value: Boolean);
    procedure Initialize; virtual; abstract;
    function Reader(AStream: TABZMemoryStream): Boolean; virtual; abstract;
    function Writer(AStream: TABZMemoryStream): Boolean; virtual; abstract;
  public
    procedure AfterConstruction; override;
    property Modified: Boolean read GetModified write SetModified;
  end;

implementation

procedure TMicObjectBase<I>.AfterConstruction;
begin
  inherited;
  Initialize;
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
