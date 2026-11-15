unit ThreadUiDialogsClean;
{ ui-access-in-thread look-alikes: a dialog inside Synchronize, a qualified
  method that only shares the name, and ShowMessage outside any thread. }
interface

implementation

type
  TQuietWorker = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TQuietWorker.Execute;
begin
  FLog.ShowMessage('x');
  TThread.Synchronize(nil,
    procedure
    begin
      ShowMessage('safe');
      FDialog.ShowModal;
    end);
end;

procedure Plain;
begin
  ShowMessage('main thread');
end;

end.
