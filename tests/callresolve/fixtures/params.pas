unit params;

interface

type
  TThing = class
    procedure Handle(const AItem: TThing; ACount: Integer);
  end;

implementation

procedure TThing.Handle(const AItem: TThing; ACount: Integer);
begin
end;

end.
