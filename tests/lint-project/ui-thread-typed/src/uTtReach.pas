unit uTtReach;

{ Fixture of ui-access-in-thread-typed reachability (1.47 lane U1): a thread class that nothing
  in the project names outside its own method headers is never constructed, so its Execute
  never runs -- the finding is labelled "(class never constructed)" and reported as a hint.
  A thread class the project does construct keeps the warning and carries no label. }

interface

uses
  System.Classes, Vcl.Forms, Vcl.StdCtrls;

type
  TTtNeverBuilt = class(TThread)
  public
    FLabel: TLabel;
  protected
    procedure Execute; override;
  end;

  TTtBuilt = class(TThread)
  public
    FLabel: TLabel;
  protected
    procedure Execute; override;
  end;

procedure StartBuilt;

implementation

procedure StartBuilt;
begin
  TTtBuilt.Create;
end;

procedure TTtNeverBuilt.Execute;
begin
  FLabel.Hide; // TRIGGER-UIT-UNBUILT
end;

procedure TTtBuilt.Execute;
begin
  FLabel.Hide; // TRIGGER-UIT-BUILT
end;

end.
