unit LabCtorOwner;

interface

uses
  LabCtorChild;

type
  TLabCtorOwner = class
  private
    FChild: TLabCtorChild;
  public
    constructor Create;
    destructor Destroy; override;
    function Title: string;
    procedure Poke;
  end;

implementation

constructor TLabCtorOwner.Create;
begin
  inherited Create;
  FChild := TLabCtorChild.Create(Self);
end;

destructor TLabCtorOwner.Destroy;
begin
  FChild.Free;
  inherited;
end;

function TLabCtorOwner.Title: string;
begin
  Result := 'owner';
end;

procedure TLabCtorOwner.Poke;
begin
  FChild.Touch;
end;

end.
