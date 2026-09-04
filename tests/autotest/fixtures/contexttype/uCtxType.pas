unit uCtxType;

{ Fixture for run_context_type_surface.ps1.

  Three shapes in one unit, because the bug and its controls are about WHICH
  qname the bundler asks for a class surface:
    TWidget  -- a class, the target that used to get no surface at all
    TPayload -- a record, the same code path
    Helper   -- a top-level routine, whose "parent" is the UNIT and must NOT
                start producing a surface just because the type branch was
                added. }

interface

type
  TPayload = record
    Ident : Integer;
    Weight: Double ;
    function Describe: string;
  end;

  TWidget = class
  private
    FCount: Integer;
  public
    constructor Create(const ACount: Integer);
    procedure Spin(const ATurns: Integer);
    function Measure: Double;
    property Count: Integer read FCount;
  end;

function Helper(const AText: string): string;

implementation

function TPayload.Describe: string;
begin
  Result:= IntToStr(Ident);
end;

constructor TWidget.Create(const ACount: Integer);
begin
  inherited Create;
  FCount:= ACount;
end;

procedure TWidget.Spin(const ATurns: Integer);
begin
  FCount:= FCount + ATurns;
end;

function TWidget.Measure: Double;
begin
  Result:= FCount * 1.5;
end;

function Helper(const AText: string): string;
begin
  Result:= AText;
end;

end.
