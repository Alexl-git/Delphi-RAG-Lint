unit uFpInj;

{ Fixture for run_v156_FPINJ.ps1. Each private member is named for its role; the runner
  checks which of them unused-private-member reports. }

interface

type
  TService = class
  end;

  TConsumer = class
  private
    [Inject]
    FInjBare: TService;
    [Spring.Container.Common.Inject]
    FInjQual: TService;
    [Inject('name')]
    FInjNamed: TService;
    [Weak]
    FWeakUnused: TService;
    FPlainUnused: TService;
    FUsed: TService;
    [Inject]
    procedure SetDep(pValue: TService);
  public
    function Control: TService;
  end;

implementation

function TConsumer.Control: TService;
begin
  Result:= FUsed;
end;

procedure TConsumer.SetDep(pValue: TService);
begin
end;

end.