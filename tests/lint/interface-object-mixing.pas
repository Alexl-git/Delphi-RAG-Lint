unit InterfaceObjectMixing;

interface

type
  IFoo = interface
    ['{00000000-0000-0000-0000-000000000001}']
    procedure DoIt;
  end;

  TFoo = class(TInterfacedObject, IFoo)
    procedure DoIt;
  end;

implementation

uses System.SysUtils;

procedure TFoo.DoIt;
begin
end;

{ BadDualHandle: an object local X is created, aliased into an interface-typed
  variable I in the SAME routine, then X is manually freed -- the ARC/manual
  dual-handle double-free. The manual free (X.Free) must fire. }
procedure BadDualHandle;
var
  X: TFoo;
  I: IFoo;
begin
  X := TFoo.Create;
  I := X;
  I.DoIt;
  X.Free;
end;

{ SafeObject: a plain object create + free with NO interface alias -- must NOT
  fire (that is the whole point of the narrow slice). }
procedure SafeObject;
var
  X: TFoo;
begin
  X := TFoo.Create;
  try
    X.DoIt;
  finally
    X.Free;
  end;
end;

{ SafeInterface: an interface-typed variable is assigned but there is NO manual
  free of an object -- must NOT fire. }
procedure SafeInterface;
var
  I: IFoo;
begin
  I := TFoo.Create;
  I.DoIt;
end;

procedure UseFoo(pFoo: IFoo);
begin
  pFoo.DoIt;
end;

procedure UseObj(pFoo: TFoo);
begin
  pFoo.DoIt;
end;

{ BadPassed (INBOX W534): the object local is passed to a same-file routine whose
  parameter is an INTERFACE, then freed manually -- the callee's interface
  reference counts the object and frees it. The X.Free must fire. }
procedure BadPassed;
var
  lImpl: TFoo;
begin
  lImpl := TFoo.Create;
  UseFoo(lImpl);
  lImpl.Free;
end;

{ BadPassedFreeAndNil: same, released with FreeAndNil. }
procedure BadPassedFreeAndNil;
var
  lImpl: TFoo;
begin
  lImpl := TFoo.Create;
  UseFoo(lImpl);
  FreeAndNil(lImpl);
end;

{ SafePassedObj: the callee takes a CLASS-typed parameter -- no interface
  reference exists, the manual free is correct. Must NOT fire. }
procedure SafePassedObj;
var
  lImpl: TFoo;
begin
  lImpl := TFoo.Create;
  try
    UseObj(lImpl);
  finally
    lImpl.Free;
  end;
end;

end.