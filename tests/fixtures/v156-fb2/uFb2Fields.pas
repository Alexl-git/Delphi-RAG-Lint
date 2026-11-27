unit uFb2Fields;

{ Fixture of tests\autotest\run_v156_FB2.ps1 (1.56 lane FB-2): check-init reads
  symbol_facts.must_writes for an instance field. TFbBig has more methods than the runner's
  --max-routines budget: FList is proven from the stored fact of Init, FCount is not (its writer
  is conditional), so its answer must stay MAY-BE-UNSET with ctor-misses-field. }

interface

uses
  System.Classes;

type
  TFbBig = class
  private
    FList: TStringList;
    FCount: TStringList;
    procedure Init;
    procedure InitMaybe(pOn: Boolean);
  public
    constructor Create(pOn: Boolean);
    procedure StepA;
    procedure StepB;
    procedure StepC;
    procedure StepD;
    procedure StepE;
    function Size: Integer;
    function Count: Integer;
  end;

implementation

constructor TFbBig.Create(pOn: Boolean);
begin
  inherited Create;
  Init;
  InitMaybe(pOn);
end;

procedure TFbBig.Init;
begin
  FList := TStringList.Create;
end;

procedure TFbBig.InitMaybe(pOn: Boolean);
begin
  if pOn then
    FCount := TStringList.Create;
end;

procedure TFbBig.StepA;
begin
  FList.Add('a');
end;

procedure TFbBig.StepB;
begin
  FList.Add('b');
end;

procedure TFbBig.StepC;
begin
  FList.Add('c');
end;

procedure TFbBig.StepD;
begin
  FList.Add('d');
end;

procedure TFbBig.StepE;
begin
  FList.Add('e');
end;

function TFbBig.Size: Integer;
begin
  Result := FList.Count;
end;

function TFbBig.Count: Integer;
begin
  Result := FCount.Count;
end;

end.
