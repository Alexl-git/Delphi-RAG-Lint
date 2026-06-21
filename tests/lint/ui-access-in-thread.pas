unit ThreadUI;

interface

implementation

type
  TWorker = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TWorker.Execute;
begin
  Form1.Caption := 'done';
  TThread.Synchronize(nil,
    procedure
    begin
      Form1.Caption := 'safe';
    end);
end;

end.
