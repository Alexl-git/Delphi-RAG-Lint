unit uTtOwn;

{ A project that declares its OWN TControl and TTask, and uses no Forms unit: the leaf
  name proves nothing here, so the rule stays silent. Run in its own DB, because a project
  TControl silences the name for the whole index. }

interface

uses
  System.Classes;

type
  TControl = class
  public
    Caption: string;
  end;

  TOwnLabel = class(TControl)
  end;

  TTask = class
  public
    class procedure Run(const AProc: TThreadProcedure);
  end;

  TOwnWorker = class(TThread)
  public
    FLabel: TOwnLabel;
    Application: TObject;
  protected
    procedure Execute; override;
  end;

implementation

class procedure TTask.Run(const AProc: TThreadProcedure);
begin
  AProc();
end;

procedure TOwnWorker.Execute;
begin
  FLabel.Caption := 'mine'; // CONTROL-UITOWN-OWN-TCONTROL
  Application.ClassName; // CONTROL-UITOWN-BOUND-APPLICATION
  TTask.Run(
    procedure
    begin
      FLabel.Caption := 'mine'; // CONTROL-UITOWN-OWN-TTASK
    end);
end;

end.
