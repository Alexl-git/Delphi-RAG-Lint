unit synchronize_in_destructor;

{ synchronize-in-destructor fixture.  HIT marker = rule fires on that line, OK marker = silent. }

interface

uses
  System.Classes;

type
  TWorker = class(TThread)
  private
    procedure Notify;
  protected
    procedure Execute; override;
  public
    destructor Destroy; override;
  end;

  TViaHelper = class(TThread)
  private
    procedure Flush;
  protected
    procedure Execute; override;
  public
    destructor Destroy; override;
  end;

  TQueued = class(TThread)
  private
    procedure Notify;
  protected
    procedure Execute; override;
  public
    destructor Destroy; override;
  end;

  TPlain = class
  public
    destructor Destroy; override;
  end;

implementation

procedure TWorker.Notify;
begin
end;

procedure TWorker.Execute;
begin
  Synchronize(Notify); {OK}
end;

destructor TWorker.Destroy;
begin
  Synchronize(Notify); {HIT}
  inherited;
end;

procedure TViaHelper.Flush;
begin
  Synchronize(nil); {OK}
end;

procedure TViaHelper.Execute;
begin
  Flush; {OK}
end;

destructor TViaHelper.Destroy;
begin
  Flush; {HIT}
  inherited;
end;

procedure TQueued.Notify;
begin
end;

procedure TQueued.Execute;
begin
end;

destructor TQueued.Destroy;
begin
  Queue(Notify); {OK}
  inherited;
end;

destructor TPlain.Destroy;
begin
  TThread.Synchronize(nil, nil); {OK}
  inherited;
end;

end.
