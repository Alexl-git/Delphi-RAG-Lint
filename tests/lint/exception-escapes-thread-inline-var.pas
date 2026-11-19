unit ExceptionEscapesThreadInlineVar;

{ v152 FPS: an inline `var T := TTask.Run(..)` whose task is later Waited / Result-read / passed to
  TTask.WaitForAll is observed -- the exception surfaces in the caller. Un-waited twins still fire. }

interface

implementation

uses
  System.Threading;

procedure DoWork;
begin
end;

procedure InlineWaited;
begin
  var T := TTask.Run(
    procedure
    begin
      DoWork;
    end);
  T.Wait;
end;

procedure InlineTypedWaitAll;
begin
  var A: ITask := TTask.Run(
    procedure
    begin
      DoWork;
    end);
  TTask.WaitForAll([A]);
end;

procedure InlineNotWaited;
begin
  var T := TTask.Run(
    procedure
    begin
      DoWork;
    end);
  DoWork;
end;

procedure InlineTypedNotWaited;
begin
  var U: ITask := TTask.Run(
    procedure
    begin
      DoWork;
    end);
  DoWork;
end;

end.