unit MissingInheritedCtorDelegating;

interface

type
  TFoo = class
    constructor Create(A: Integer); overload;
    constructor Create(A, B: Integer); overload;
    constructor CreateSelf(A: Integer);
    constructor CreateBare(A: Integer);
    constructor CreateNone(A: Integer);
  end;

implementation

constructor TFoo.Create(A: Integer);
begin
  Create(A, 0);
end;

constructor TFoo.Create(A, B: Integer);
begin
  inherited Create;
end;

constructor TFoo.CreateSelf(A: Integer);
begin
  Self.Create(A, 0);
end;

constructor TFoo.CreateBare(A: Integer);
begin
  inherited Create;
end;

constructor TFoo.CreateNone(A: Integer);
begin
  WriteLn('no call at all');
end;

end.
