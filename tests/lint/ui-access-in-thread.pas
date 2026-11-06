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

type
  TDeepWorker = class(TWorker)
  protected
    procedure Execute; override;
  end;

  TPlainKid = class(TPlainBase)
  public
    procedure Execute;
  end;

procedure TDeepWorker.Execute;
begin
  Form1.Repaint;
  Application.ProcessMessages;
  Synchronize(Form1.Repaint);
  TThread.Queue(nil, Form1.BringToFront);
end;

procedure TPlainKid.Execute;
begin
  Form1.Repaint;
end;

procedure StartThem;
begin
  Form1.Caption := 'main thread';
  TThread.CreateAnonymousThread(
    procedure
    begin
      Form1.Caption := 'anon';
    end).Start;
  TTask.Run(
    procedure
    begin
      Form1.SetFocus;
      TThread.Synchronize(nil,
        procedure
        begin
          Form1.SetFocus;
        end);
    end);
  TTask.Future<Integer>(
    function: Integer
    begin
      Form1.SendToBack;
      Result := 0;
    end);
  TParallel.For(0, 3,
    procedure(I: Integer)
    begin
      Form1.BringToFront;
    end);
  TOtherPool.Run(
    procedure
    begin
      Form1.Caption := 'not a thread start';
    end);
end;

end.