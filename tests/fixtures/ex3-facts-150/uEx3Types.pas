unit uEx3Types;

interface

type
  TEx3Rec = record
    Alpha: Integer;
    Beta: Integer;
  end;

  TEx3Base = class
  end;

  TEx3Runner = class(TEx3Base)
  public
    procedure Go;
  end;

implementation

procedure TEx3Runner.Go;
begin
end;

end.