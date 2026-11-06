unit uLhBase;

{ Fixture types for the lh lane (145): a thread base, a client base, two lock-like classes.
  Every ancestry is closed inside the project, so "does not descend" is provable. }

interface

type
  TThread = class
  public
    procedure Execute; virtual;
    procedure WaitFor;
  end;

  /// <summary>A thread base in ANOTHER unit than the worker below: its name does not say thread.</summary>
  TBaseWorker = class(TThread)
  end;

  /// <summary>Named like a thread, but not one.</summary>
  TLogThread = class
  end;

  TIdHTTP = class
  public
    constructor Create(AOwner: TObject);
  end;

  TMyHttp = class(TIdHTTP)
  end;

  TCriticalSection = class
  public
    procedure Enter;
    procedure Leave;
  end;

  TSemaphore = class
  public
    procedure Acquire;
    procedure Release;
  end;

implementation

procedure TThread.Execute;
begin
end;

procedure TThread.WaitFor;
begin
end;

constructor TIdHTTP.Create(AOwner: TObject);
begin
end;

procedure TCriticalSection.Enter;
begin
end;

procedure TCriticalSection.Leave;
begin
end;

procedure TSemaphore.Acquire;
begin
end;

procedure TSemaphore.Release;
begin
end;

end.
