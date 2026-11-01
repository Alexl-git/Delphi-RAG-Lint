unit uMethRes;

{ Fixture for tests\callresolve\run_method_resolution_dispatch.ps1.
  A method-resolution clause (`procedure IJob.Execute = RunJob;`) maps an
  interface method to a class method of ANOTHER name. TJob also declares a real
  Execute, so a by-name join picks the wrong implementor and fails the guard. }

interface

type
  IJob = interface
    ['{11111111-2222-3333-4444-555555555555}']
    procedure Execute;
    function Name: string;
  end;

  { MR1/MR2: both interface methods remapped; MR3: a real same-named Execute. }
  TJob = class(TInterfacedObject, IJob)
  public
    procedure IJob.Execute = RunJob;
    function IJob.Name = JobName;
    procedure RunJob;
    function JobName: string;
    procedure Execute;
  end;

  { PC: no clause -- the by-name rule still applies. }
  TPlainJob = class(TInterfacedObject, IJob)
  public
    procedure Execute;
    function Name: string;
  end;

  TBaseJob = class(TInterfacedObject)
  public
    procedure BaseRun;
    function BaseName: string;
  end;

  { MR5: the clause target is INHERITED from the parent class. }
  TSubJob = class(TBaseJob, IJob)
  public
    procedure IJob.Execute = BaseRun;
    function IJob.Name = BaseName;
  end;

procedure UseIt;

implementation

procedure TJob.RunJob;
begin
end;

function TJob.JobName: string;
begin
  Result := 'x';
end;

procedure TJob.Execute;
begin
end;

procedure TPlainJob.Execute;
begin
end;

function TPlainJob.Name: string;
begin
  Result := 'p';
end;

procedure TBaseJob.BaseRun;
begin
end;

function TBaseJob.BaseName: string;
begin
  Result := 'b';
end;

procedure UseIt;
var
  J: IJob;
begin
  J := TJob.Create;
  J.Execute;
end;

end.