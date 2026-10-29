unit RaiseInDestructor;

interface

uses
  System.SysUtils;

type
  TBadDtor = class
  public
    destructor Destroy; override;
  end;

  TSwallowDtor = class
  public
    destructor Destroy; override;
  end;

  TRethrowDtor = class
  public
    destructor Destroy; override;
  end;

  TNotDtor = class
  public
    procedure Close;
  end;

implementation

destructor TBadDtor.Destroy;
begin
  raise Exception.Create('cannot close');
  inherited;
end;

destructor TSwallowDtor.Destroy;
begin
  try
    raise Exception.Create('cannot close');
  except
    // swallowed
  end;
  inherited;
end;

destructor TRethrowDtor.Destroy;
begin
  try
    inherited;
  except
    on E: Exception do
      raise;
  end;
end;

procedure TNotDtor.Close;
begin
  raise Exception.Create('fine outside a destructor');
end;

end.
