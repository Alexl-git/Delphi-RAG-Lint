unit RaiseHandle;

interface

uses
  System.SysUtils;

type
  EFoo = class(Exception);
  EBare = class(Exception)
  public
    constructor Create;
  end;
  TErrStack = class
  public
    function Pop: Exception;
  end;

procedure SimpleRaise(const S: string);
procedure QualifiedRaise;
procedure RaiseOfCall(AErrors: TErrStack);
procedure HandlerShapes;
procedure ReraiseAt(Addr: Pointer);
procedure BareExcepts;
procedure ElseBranch;
procedure Negatives;
procedure Outer;

implementation

constructor EBare.Create;
begin
  inherited Create('bare');
end;

function TErrStack.Pop: Exception;
begin
  Result := nil;
end;

procedure SimpleRaise(const S: string);
begin
  if S = '' then
    raise EFoo.Create('empty');
  if S = 'x' then
    raise EBare.Create;
  raise EConvertError.CreateFmt('%s', [S]);
end;

procedure QualifiedRaise;
begin
  raise System.SysUtils.EArgumentException.Create('x');
end;

procedure RaiseOfCall(AErrors: TErrStack);
begin
  raise AErrors.Pop;
end;

procedure HandlerShapes;
begin
  try
    SimpleRaise('');
  except
    on E: EConvertError do
      raise;
    on EAbort do ;
    on E: System.SysUtils.EArgumentException do
    begin
      try
        QualifiedRaise;
      except
        on EFoo do ;
      end;
    end;
  end;
end;

procedure ReraiseAt(Addr: Pointer);
var
  E: EFoo;
begin
  E := EFoo.Create('a');
  try
    raise E;
  except
    raise E at Addr;
  end;
end;

procedure BareExcepts;
begin
  try
    SimpleRaise('');
  except
    SimpleRaise('again');
  end;
  try
    SimpleRaise('');
  except
  end;
end;

procedure ElseBranch;
begin
  try
    SimpleRaise('');
  except
    on EFoo do ;
  else
    SimpleRaise('else');
  end;
end;

procedure Negatives;
var
  X: Exception;
begin
  try
    SimpleRaise('');
  finally
    X := Exception.Create('not raised');
    X.Free;
  end;
end;

procedure Outer;

  procedure Inner;
  begin
    try
      SimpleRaise('');
    except
      on E: EFoo do
        SimpleRaise(E.Message);
    end;
  end;

begin
  Inner;
end;

end.
