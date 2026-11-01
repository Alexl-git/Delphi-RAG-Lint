unit uDeleg;

{ Fixture for tests\callresolve\run_implements_delegation.ps1. TJobHost
  delegates IJob to a property AND declares an unrelated Execute, so a by-name
  join would wrongly call that method the implementor. }

interface

type
  IJob = interface
    ['{11111111-2222-3333-4444-555555555555}']
    procedure Execute;
  end;

  IA = interface
    ['{22222222-2222-3333-4444-555555555555}']
    procedure DoA;
  end;

  IB = interface
    ['{33333333-2222-3333-4444-555555555555}']
    procedure DoB;
  end;

  { PC: an ordinary implementor. }
  TJobImpl = class(TInterfacedObject, IJob)
  public
    procedure Execute;
  end;

  { DL1/DL2: delegation plus a same-named trap method. }
  TJobHost = class(TInterfacedObject, IJob)
  private
    FJob: IJob;
  public
    procedure Execute;
    property Job: IJob read FJob implements IJob;
  end;

  { DL3: one property delegating two interfaces. }
  TBothHost = class(TInterfacedObject, IA, IB)
  private
    FBoth: IInterface;
  public
    property Both: IInterface read FBoth implements IA, IB;
  end;

implementation

procedure TJobImpl.Execute;
begin
end;

procedure TJobHost.Execute;
begin
end;

end.