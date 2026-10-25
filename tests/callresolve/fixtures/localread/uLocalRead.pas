unit uLocalRead;

{ Fixture for tests\callresolve\run_local_read_chain_bind.ps1 -- reads of a
  local / parameter and the member chain hanging off it, through an array
  element (`A[0].K`) and a pointer (`P^.K`, `p.K`). Three types declare a K
  (TInner, TRec, TFix) and two routines are named Ping (TInner.Ping and
  TFix.Ping), so a name join or a receiver lost to the enclosing class
  cannot pass by accident. Each statement is on its own line: the guard
  locates lines by their trimmed text. }

interface

type
  TInner = record
    K: Integer;
    procedure Ping;
  end;
  PInner = ^TInner;
  TRec = record
    K: Integer;
    Inner: TInner;
    Arr: array[0..1] of TInner;
  end;
  TMsg = record
    Sev: Integer;
  end;
  TMsgs = TArray<TMsg>;
  TDynRecs = array of TRec;

  TFix = class
  public
    K: Integer;
    procedure Ping;
    procedure Run(pA: Integer; const pM: TMsgs);
  end;

procedure Use(pV: Integer);

implementation

procedure Use(pV: Integer);
begin
end;

procedure TInner.Ping;
begin
end;

procedure TFix.Ping;
begin
end;

procedure TFix.Run(pA: Integer; const pM: TMsgs);
var
  X, Y: Integer;
  R: TRec;
  A: array[0..1] of TRec;
  D: TDynRecs;
  P: PInner;
begin
  X := pA;
  Y := X;
  R.K := Y;
  A[0].K := 2;
  Use(A[0].Inner.K);
  R.Arr[1].K := 3;
  Use(pM[X].Sev);
  Use(D[1].K);
  P := @R.Inner;
  P^.K := 4;
  Use(p.K);
  P^.Ping;
  A [1].K := 5;
  R.Inner.K := 6;
  Use(Undecl[0].K);
  Use(Undecl);
end;

end.