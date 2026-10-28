unit LabCtorChild;

interface

type
  TLabCtorChild = class
  private
    FOwner: TObject;
  public
    constructor Create(pOwner: TObject);
    procedure Touch;
  end;

implementation

uses
  LabCtorOwner;

constructor TLabCtorChild.Create(pOwner: TObject);
begin
  inherited Create;
  FOwner := pOwner;
end;

procedure TLabCtorChild.Touch;
begin
  Writeln('[ctor] touched by ', TLabCtorOwner(FOwner).Title);
end;

end.
