unit LargeMagicV1511;

interface

type
  TKind = (kA = 100, kB = 200, kC);
  TLevel = (lvOne, lvTwo = 5000);

  IFoo = interface
    ['{11111111-2222-3333-4444-555555555555}']
    function Get: Integer; dispid 201;
    procedure Put(X: Integer); safecall; dispid 202;
    property Value: Integer dispid 203;
  end;

implementation

procedure P(I: Integer);
begin
  case I of
    7001: I := 1;
    7002, 7003: I := 2;
  end;
  I := 7004;
end;

end.
