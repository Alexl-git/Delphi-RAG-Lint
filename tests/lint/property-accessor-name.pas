unit property_accessor_name;

{ Fixture for property-accessor-name (info).
  Hit: a read accessor that is neither F<Prop> nor Get<Prop>, or a write
  accessor that is neither F<Prop> nor Set<Prop> (case-insensitive).
  Silent: conforming names, an indexed property, an accessor shared by several
  properties. }

interface

type
  TFoo = class
  private
    FName: string;
    FSize: Integer;
    function ReadName: string;
    procedure StoreSize(AValue: Integer);
    function GetFlag(Idx: Integer): Boolean;
    function ReadShared: Integer;
  public
    property Name: string read ReadName write FName;
    property Size: Integer read FSize write StoreSize;
    property Ok: string read FName write FName;
    property Good: Integer read FSize write FSize;
    property Flag[Idx: Integer]: Boolean read GetFlag;
    property Same1: Integer read ReadShared;
    property Same2: Integer read ReadShared;
  end;

implementation

end.
