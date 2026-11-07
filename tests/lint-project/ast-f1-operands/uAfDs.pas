unit uAfDs;

{ Fixture of run_ast_f1_operands.ps1, row 10 (dataset-open-without-close). Stand-in classes only.
  CONTROL-DSOPEN: a receiver whose whole ancestry is known and holds no TDataSet; with the F1
  fact the rule drops it, without it the rule still reports it. TRIGGER-DSOPEN: a TDataSet
  descendant, and a class on an ancestor this project does not declare (unfollowable): the rule
  reports both in every run. }

interface

type
  TDataSet = class
  public
    procedure Open;
    procedure Close;
  end;

  TAfQuery = class(TDataSet)
  end;

  TAfPort = class
  public
    procedure Open;
  end;

  TAfLibLike = class(TAfNowhere)
  end;

  TAfDsHolder = class
  public
    procedure Go;
  end;

implementation

procedure TDataSet.Open;
begin
end;

procedure TDataSet.Close;
begin
end;

procedure TAfPort.Open;
begin
end;

procedure TAfDsHolder.Go;
var
  Port: TAfPort;
  Qry : TAfQuery;
  Lib : TAfLibLike;
begin
  Port.Open; // CONTROL-DSOPEN-1
  Qry.Open; // TRIGGER-DSOPEN-1
  Lib.Open; // TRIGGER-DSOPEN-2
end;

end.
