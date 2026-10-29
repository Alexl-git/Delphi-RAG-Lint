unit uUiThreadFx;

{ Fixture for the `ui-access-in-thread-transitive` project lint rule (backlog
  1.37.0 lane B-EFFECT; INBOX-lint-rules-from-new-facts-2026-09-23 rule 7).

  A TThread.Execute that CALLS (directly or through other project routines)
  a routine whose stored ui_affinity is non-empty touches the UI off the main
  thread. A call marshalled through Synchronize / Queue is the fix, a routine
  that marshals inside itself is safe, and a method named Execute on a class
  that is not a thread is not a thread body. The runner reads each line
  number from its UT-TRIGGER-n / UT-CONTROL-n marker. }

interface

uses
  System.Classes, Vcl.Controls, Vcl.Forms;

type
  TView = class
  public
    FCtl: TControl;
    procedure ShowText(const S: string);
    procedure Relay(const S: string);
    procedure SafeShow(const S: string);
    procedure Calc;
  end;

  TWorker = class(TThread)
  private
    FView: TView;
    procedure DoShow;
  protected
    procedure Execute; override;
  end;

  TDeepWorker = class(TWorker)
  protected
    procedure Execute; override;
  end;

  TPlain = class
  private
    FView: TView;
  public
    procedure Execute;
  end;

implementation

procedure TView.ShowText(const S: string);
begin
  FCtl.Hint:= S;
  Application.Title:= S;
end;

procedure TView.Relay(const S: string);
begin
  ShowText(S);
end;

procedure TView.SafeShow(const S: string);
begin
  TThread.Synchronize(nil,
    procedure
    begin
      ShowText(S);
    end);
end;

procedure TView.Calc;
begin
end;

procedure TWorker.DoShow;
begin
  FView.ShowText('x');
end;

procedure TWorker.Execute;
begin
  FView.ShowText('a');                         { UT-TRIGGER-1: direct callee touches UI }
  FView.Relay('b');                            { UT-TRIGGER-2: two hops }
  FView.Calc;                                  { UT-CONTROL-1: no UI below }
  Synchronize(DoShow);                         { UT-CONTROL-2: marshalled method pointer }
  Queue(
    procedure
    begin
      FView.Relay('c');                        { UT-CONTROL-3: inside a Queue lambda }
    end);
  FView.SafeShow('d');                         { UT-CONTROL-4: callee marshals itself }
end;

procedure TDeepWorker.Execute;
begin
  FView.Relay('e');                            { UT-TRIGGER-3: grandchild of TThread }
end;

procedure TPlain.Execute;
begin
  FView.ShowText('f');                         { UT-CONTROL-5: not a thread class }
end;

end.
