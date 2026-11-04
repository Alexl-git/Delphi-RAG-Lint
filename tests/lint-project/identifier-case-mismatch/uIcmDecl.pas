unit uIcmDecl;

interface

type
  TIcmThing = class
  private
    FCount: Integer;
  public
    procedure DoWork;
    property Count: Integer read FCount;
  end;

procedure GlobalRoutine;

implementation

procedure TIcmThing.DoWork;
begin
  FCount := 1;
end;

procedure GlobalRoutine;
begin
end;

end.