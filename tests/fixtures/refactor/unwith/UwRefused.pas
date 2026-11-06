unit UwRefused;

{ Every `with` here must REFUSE, each under its own named reason (the comment before it names the kind). None of them
  is reached at run time except through RunRefused, whose output must not change: nothing here is rewritten. }

interface

uses
  System.SysUtils, System.Classes, UwTypes;

procedure RunRefused;

implementation

function MakePoint: TPoint3;
begin
  Result.X:= 1;
  Result.Y:= 2;
  Result.Z:= 3;
end;

function MakeMid: TMid;
begin
  Result:= TMid.Create;
end;

var
  GArr: array[0..1] of TPoint3;
  GMid: TMid;

{ target-property-getter: Computed's read names a method. }
procedure RefGetter(pOwner: TOwner);
begin
  with pOwner.Computed do
    Value:= 1;
end;

{ target-indexer }
procedure RefIndexer;
begin
  with GArr[0] do
    X:= 1;
end;

{ target-call: a call, evaluated once by with and N times after. }
procedure RefCall;
begin
  with MakePoint do
    Writeln(X);
end;

{ target-call: bare function name, no parentheses (the AST cannot tell; the bound symbol can). }
procedure RefBareCall;
var
  Keep: TMid;
begin
  Keep:= MakeMid;
  try
    with Keep.Identity do
      Writeln(Count);
  finally
    Keep.Free;
  end;
end;

{ target-constructor }
procedure RefCtor;
begin
  with TMid.Create do
    Free;
end;

{ multiple-targets }
procedure RefMulti(pA, pB: TMid);
begin
  with pA, pB do
    Value:= 1;
end;

{ target-cast: a hard cast. }
procedure RefCast(pO: TObject);
begin
  with TMid(pO) do
    Value:= 1;
end;

{ cast-after-side-effect: a failing `as` raises before Writeln today, after it once rewritten. }
procedure RefCastOrder(pO: TObject);
begin
  with pO as TMid do
  begin
    Writeln('first');
    Value:= 1;
  end;
end;

{ null-type: an `as` to a type outside this index. }
procedure RefCastLibrary(pO: TObject);
begin
  with pO as TStringList do
    Clear;
end;

{ null-type: TStringList is not in this project's index: F1 gives no symbol id. }
procedure RefNullType;
var
  L: TStringList;
begin
  L:= TStringList.Create;
  try
    with L do
      Add('x');
  finally
    L.Free;
  end;
end;

{ unresolved-ancestor: THiddenBase is not indexed, it may declare anything. The local named Secret IS what the
  closure would miss: `Secret` binds to THiddenBase.Secret here, and a rewrite that left it bare would compile
  and read the local. }
procedure RefUnresolvedAncestor;
var
  F: TFromHidden;
  Secret: Integer;
begin
  Secret:= -1;
  F:= TFromHidden.Create;
  try
    with F do
      Writeln('unresolved-ancestor ', Secret);
  finally
    F.Free;
  end;
end;

{ target-used-bare: `with` read N once; the rewrite would follow the reassignment. }
procedure RefReassigned(pA, pB: TMid);
var
  N: TMid;
begin
  N:= pA;
  with N do
  begin
    N:= pB;
    Value:= 1;
  end;
end;

{ target-used-bare: passed along (a var parameter could change it). }
procedure Touch(var pM: TMid);
begin
  pM:= nil;
end;

procedure RefPassedVar(pA: TMid);
var
  N: TMid;
begin
  N:= pA;
  with N do
  begin
    Touch(N);
    Value:= 1;
  end;
end;

{ target-field-reassigned: TOwner.Advance writes FCursor, and any call in the body might reach it. }
procedure RefFieldReassigned(pOwner: TOwner);
begin
  with pOwner.Cursor do
  begin
    pOwner.Advance;
    Value:= 2;
  end;
end;

{ target-field-reassigned: a global with a writer in a routine. }
procedure SetG(pM: TMid);
begin
  GMid:= pM;
end;

procedure RefGlobalReassigned;
begin
  with GMid do
    Value:= 3;
end;

{ conditional-in-body: only one branch is visible, the other could use any name. }
procedure RefIfdef(pM: TMid);
begin
  with pM do
  begin
    {$IFDEF NEVER_DEFINED}
    Count:= 1;
    {$ENDIF}
    Value:= 1;
  end;
end;

{ closure-conditional: a member behind a directive may exist in another configuration. }
procedure RefClosureIfdef(pH: THasIfdefMember);
begin
  with pH do
    A:= 1;
end;

{ anonymous-method: E would be evaluated when the closure runs, not when with ran. }
procedure RefAnon(pM: TMid);
var
  P: TProc;
begin
  with pM do
    P:= procedure begin Value:= 1; end;
  P();
end;

{ inline-decl: a declaration in the body can shadow E's root or a member. }
procedure RefInlineVar(pM: TMid);
begin
  with pM do
  begin
    var Count: Integer:= 1;
    Value:= Count;
  end;
end;

{ invisible-member: private of another unit, and a local of the name: does the compiler see the member? Not proved. }
procedure RefPrivateName(pB: TBase);
var
  PrivateName: Integer;
begin
  PrivateName:= 1;
  with pB do
    Count:= PrivateName;
end;

{ nested-type-member: kOne is a nested type's value: `E.kOne` is not a rewrite of it. }
procedure RefNested(pH: TNestedHolder);
begin
  with pH do
    Kind:= kOne;
end;

{ inner-with-first: the outer waits; the inner one has its own verdict. }
procedure RefOuterOfRefused(pM: TMid);
begin
  with pM do
    with MakePoint do
      Value:= X;
end;

procedure RunRefused;
begin
  RefUnresolvedAncestor;
  Writeln('refused done');
end;

end.