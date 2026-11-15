unit ThreadUiDialogs;
{ ui-access-in-thread, v151 widening: a dialog helper, a modal form and a window
  invalidation inside TThread.Execute; the same calls inside Synchronize and a
  qualified look-alike stay quiet. }
interface

implementation

type
  TReporter = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TReporter.Execute;
begin
  ShowMessage('done');
  MessageDlg('done', mtInformation, [mbOK], 0);
  FDialog.ShowModal;
  FPanel.Invalidate;
  FLog.ShowMessageText('x');
  TThread.Synchronize(nil,
    procedure
    begin
      ShowMessage('safe');
    end);
end;

end.
