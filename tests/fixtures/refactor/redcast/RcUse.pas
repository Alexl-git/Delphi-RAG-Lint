unit RcUse;

// Every line that holds a cast says what the planner must do with it:
//   FIX = removed; REFUSE <kind> = named refusal; NONE = a real conversion, in neither list.
// A line with two casts names both, in the order the guard expects them.
// RcTypes.TDup(Dup) is NONE: a qualified cast has no via=cast row, so it is neither seen nor touched.
// TBox(BX): TBox has a generic twin; since 150 the resolver names both (cast TBox vs BX TBox<T>): not identical.

interface

uses
  System.Classes, RcTypes;

type
  THolder = class
    FItem: TBase;
    FArr: array of TBase;
    function GetItem: TBase;
    function GetAt(pAt: Integer): TBase;
    function GetOv(pAt: Integer): TBase; overload;
    function GetOv(const pAt: string): TDer; overload;
    property Item: TBase read FItem;
    procedure Run;
    procedure RunWith;
    procedure RunAfter;
  end;

  TUnknownChain = class(TStringList)
    procedure Run;
  end;

procedure RunAll;

implementation

function THolder.GetItem: TBase;
begin
  Result:= TBase(FItem); // FIX
end;

function THolder.GetAt(pAt: Integer): TBase;
begin
  Result:= TBase(Result); // FIX
end;

function THolder.GetOv(pAt: Integer): TBase;
begin
  Result:= nil;
end;

function THolder.GetOv(const pAt: string): TDer;
begin
  Result:= nil;
end;

procedure THolder.Run;
var
  B: TBase;
  D: TDer;
  R: TRec;
  PR: PRecP;
  I: IFoo;
  E: TEn;
  A: TAlias;
  PV: TProc1;
  BX: TBox<Integer>;
  Hold: THolder;
  Dup: RcTypes.TDup;
  Named: RcTypes.TNamed;
  N: Integer;
  {$IFDEF MSWINDOWS}
  Cnd: TBase;
  {$ELSE}
  Cnd: TDer;
  {$ENDIF}
begin
  B:= nil; D:= nil; I:= nil; E:= eA; A:= nil; PV:= nil; BX:= nil; Hold:= Self; Dup:= nil; Named:= nil; N:= 0; Cnd:= nil; PR:= nil;
  R.V:= 0;
  E:= TEn(R.V); // NONE
  N:= TCnt(R.V); // REFUSE operand-type-unresolved
  B:= TBase(B); // FIX
  R:= TRec(R); // FIX
  I:= IFoo(I); // FIX
  PR:= PRecP(PR); // FIX
  E:= TEn(E); // FIX
  E:= TEn(eB); // FIX
  A:= TAlias(A); // FIX
  B:= TBase(FItem); // FIX
  B:= TBase(Item); // FIX
  B:= TBase(Hold.FItem); // FIX
  B:= TBase(GetItem); // FIX
  B:= TBase(GetAt(1)); // FIX
  TBase(B).Foo; // FIX
  B:= TBase(Hold.GetAt(N + 1)); // FIX
  B:= TBase(TBase(B)); // REFUSE nested-cast FIX
  A:= TAlias(B); // REFUSE alias-not-identical
  B:= TBase(A); // REFUSE alias-not-identical
  B:= TBase(D); // NONE
  D:= TDer(B); // NONE
  B:= TBase(FArr[0]); // REFUSE operand-shape
  B:= TBase(FArr); // REFUSE operand-untyped
  R:= TRec(PR^); // REFUSE operand-shape
  B:= TBase(nil); // REFUSE operand-shape
  E:= TEn(Ord(E) + 1); // REFUSE operand-shape
  Hold:= THolder(Self); // REFUSE operand-untyped
  PV:= TProc1(PV); // REFUSE procedural-type
  B:= TBox(BX); // NONE
  B:= TBase(GetOv(1)); // REFUSE overloaded-operand
  B:= TBase(B) {$IFDEF NEVER_SET_X} {$ENDIF}; // REFUSE ifdef-line
  B:= TBase({c} B); // REFUSE comment-in-cast
  B:= TBase( // REFUSE multi-line
    B);
  Dup:= RcTypes.TDup(Dup); // NONE
  Dup:= TDup(Dup); // REFUSE ambiguous-type-name
  Named:= TNamed(Named); // REFUSE ambiguous-type-name
  N:= Integer(N); // REFUSE type-not-indexed
  B:= TBase(Cnd); // REFUSE conditional-decl
end;

procedure THolder.RunWith;
var
  B: TBase;
begin
  B:= nil;
  with Self do
    B:= TBase(B); // REFUSE with-body
  FItem:= B;
end;

// A with ended above in ANOTHER routine: it must not reach this one.
procedure THolder.RunAfter;
var
  B: TBase;
begin
  B:= FItem;
  FItem:= TBase(B); // FIX
end;

procedure TUnknownChain.Run;
var
  B: TBase;
begin
  B:= nil;
  B:= TBase(B); // REFUSE unresolved-ancestor
  B.Foo;
end;

procedure RunAll;
var
  H: THolder;
begin
  H:= THolder.Create;
  try
    H.Run;
    H.RunWith;
    H.RunAfter;
  finally
    H.Free;
  end;
end;

end.