unit UBaseComp;

{ v151 lane CMP store fixture: the classes the other units of this folder use
  across a unit boundary, so that the rules have to ask the index. }

interface

uses
  Classes;

type
  IGreeter = interface
    ['{4A1B2C3D-5E6F-4071-8293-A4B5C6D7E8F9}']
    procedure Greet;
  end;

  TBaseComp = class(TComponent, IGreeter)
  public
    constructor Create(AOwner: TComponent); override;
    procedure Greet;
  end;

  TCountedObj = class(TInterfacedObject, IGreeter)
  public
    procedure Greet;
  end;

implementation

constructor TBaseComp.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
end;

procedure TBaseComp.Greet;
begin
end;

procedure TCountedObj.Greet;
begin
end;

end.
