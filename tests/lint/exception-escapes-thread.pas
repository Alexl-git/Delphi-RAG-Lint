unit ExceptionEscapesThread;

interface

uses
  System.Classes, System.SysUtils, System.Threading;

type
  TBadThread = class(TThread)
  protected
    procedure Execute; override;
  end;

  TGoodThread = class(TThread)
  protected
    procedure Execute; override;
  end;

  TNotAThread = class
  public
    procedure Execute;
  end;

implementation

procedure DoWork; forward;

procedure TBadThread.Execute;
begin
  DoWork;
end;

procedure TGoodThread.Execute;
begin
  try
    DoWork;
  except
    on E: Exception do
      DoWork;
  end;
end;

procedure TNotAThread.Execute;
begin
  DoWork;
end;

procedure DoWork;
begin
end;

procedure Starters;
begin
  TThread.CreateAnonymousThread(
    procedure
    begin
      DoWork;
    end).Start;
  TThread.CreateAnonymousThread(
    procedure
    begin
      try
        DoWork;
      except
        DoWork;
      end;
    end).Start;
  TTask.Run(
    procedure
    begin
      DoWork;
    end);
  TTask.Run(
    procedure
    begin
      try
        DoWork;
      except
        DoWork;
      end;
    end);
end;

end.
