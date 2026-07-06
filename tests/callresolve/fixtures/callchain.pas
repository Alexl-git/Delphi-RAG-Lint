unit callchain;

// D5 Task 11 fixture: a RESOLVABLE call chain A -> B -> C -> D via typed
// fields, so call-path / callgraph traversal is checkable end-to-end.
//   TChain.StepA -> FB.StepB   (FB: TChainB) -> certain callchain.TChainB.StepB
//   TChainB.StepB -> FC.StepC  (FC: TChainC) -> certain callchain.TChainC.StepC
//   TChainC.StepC -> FD.StepD  (FD: TChainD) -> certain callchain.TChainD.StepD
//   TChainD.StepD -> (empty)   -- the leaf, no outgoing calls
// StepA has no caller of its own; TLoner.Lonely is unreachable from StepA.

interface

type
  TChainD = class
    procedure StepD;
  end;

  TChainC = class
  private
    FD: TChainD;
  public
    procedure StepC;
  end;

  TChainB = class
  private
    FC: TChainC;
  public
    procedure StepB;
  end;

  TChain = class
  private
    FB: TChainB;
  public
    procedure StepA;
  end;

  TLoner = class
    procedure Lonely;
  end;

implementation

procedure TChainD.StepD;
begin
end;

procedure TChainC.StepC;
begin
  FD.StepD;          // field receiver TChainD -> certain TChainD.StepD
end;

procedure TChainB.StepB;
begin
  FC.StepC;          // field receiver TChainC -> certain TChainC.StepC
end;

procedure TChain.StepA;
begin
  FB.StepB;          // field receiver TChainB -> certain TChainB.StepB
end;

procedure TLoner.Lonely;
begin
end;

end.
