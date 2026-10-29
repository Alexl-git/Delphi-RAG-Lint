unit uRecvCst;

{ T-11 fixture: the receiver of a qualified call / member access is a PARSE
  fact (refs.receiver_text from the CST), so multi-line fluent chains, a dot at
  line end, a comment inside the receiver and call segments in chain position
  all reach the receiver-typing ladder. Two classes declare K (TLeaf, TOther),
  so a name join cannot pass by accident. Guard:
  tests\callresolve\run_receiver_cst_capture.ps1 }

interface

type
  TLeaf = class
  public
    procedure K;
  end;

  TInner = class
  private
    FL: TLeaf;
  public
    function Mk(const A: string): TInner;
    function Leaf: TLeaf;
    property L: TLeaf read FL;
  end;

  TOther = class
  public
    procedure K;
  end;

  ICopy = interface
    function Run: Boolean;
  end;

  TCaller = class
  public
    procedure Go(const O: TInner; M: ICopy);
  end;

function Twin(const A: TInner): TInner;

implementation

function Twin(const A: TInner): TInner;
begin
  Result:= A;
end;

procedure TLeaf.K;
begin
end;

function TInner.Mk(const A: string): TInner;
begin
  Result:= Self;
end;

function TInner.Leaf: TLeaf;
begin
  Result:= FL;
end;

procedure TOther.K;
begin
end;

procedure TCaller.Go(const O: TInner; M: ICopy);
var
  X: TLeaf;
begin
  O.Mk('a')
    .Mk('b').Leaf.K;
  O.
    Mk('c');
  O.L.K;
  O.Mk('d').L.K;
  (O as TInner) { note } .Leaf.K;
  (O.Mk('e') as TInner).L.K;
  M.Run;
  X:= (O as TInner).L;
  X:= TInner(O).L;
  X:= Twin(O).L;
  X:= Nope(O).L;
  Undeclared.Mk('x').K;
  O.Missing('x').K;
  K;
end;

end.