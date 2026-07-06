unit params;

interface

type
  TThing = class
    procedure Handle(const AItem: TThing; ACount: Integer);
    procedure Combine(A, B: TThing);
    procedure Fill(var AList: TThing; out ACount: Integer);
    procedure Raw(var E);
  end;

implementation

procedure TThing.Handle(const AItem: TThing; ACount: Integer);
begin
end;

procedure TThing.Combine(A, B: TThing);
begin
end;

procedure TThing.Fill(var AList: TThing; out ACount: Integer);
begin
end;

procedure TThing.Raw(var E);
begin
end;

end.
