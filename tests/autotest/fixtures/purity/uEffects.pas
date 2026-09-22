unit uEffects;
{ Purity v2 stage fixture (plan C6.1 Task 3). Each routine encodes one
  acceptance number of tests\autotest\run_purity_stage.ps1; the expected
  verdict is in the comment beside its declaration. }
interface
type
  TBase = class
  protected
    FInherited: Integer;
  end;
  TThing = class(TBase)
  private
    FBuffer: TArray<Integer>;
    FCount: Integer;
  public
    procedure SetCount(AValue: Integer);           { s }
    procedure GrowField;                            { SetLength(FBuffer): s via translation }
    procedure GrowLocal;                            { SetLength(LocalArr): proven }
    procedure WriteAncestor;                        { writes FInherited: s, witness names TBase }
    procedure UseWith;                              { with -> ?; the body calls only a proven method so `with` is the ONLY blocker }
    procedure DoVirtual; virtual;
    procedure CallsVirtual;                         { virtual callee -> ? }
    procedure MemberWrite(AOther: TThing);          { AOther.FCount := 1 -> bound member write on a parameter -> p0 }
    procedure UnboundMember(AList: TObject);        { AList.Free -> unbound -> ? }
    procedure Nested;                               { outer: judged through Inner (g); Inner: its own var block HAS local_var rows -> judged, not gated }
  end;
var
  GCounter: Integer;
procedure WriteGlobal;                               { g }
procedure CallsWriteGlobal(A: Integer);              { g via callee, regardless of arguments }
procedure FillOut(out AValue: Integer);              { p0 }
procedure CallsFillOutLocal;                         { proven }
procedure CallsFillOutGlobal;                        { FillOut(GCounter) -> ? (global root not classified) -> not proven }
function AddUp(A, B: Integer): Integer;              { proven, empty summary }
procedure FreeIt(P: Pointer);                        { Dispose -> h }
procedure NewLocal;                                  { New(LocalP) and nothing else -> proven }
function OnlyIntrinsics(const S: string): Integer;   { Exit/Length/Ord only -> proven }
function Ident(P: Pointer): Pointer;                 { proven, empty summary }
procedure AddrEscape;                                { Addr(L) lets L escape (T2-ii), so FillOut(L) is NOT a local write -> ? }
implementation
procedure TThing.SetCount(AValue: Integer);
begin
  FCount := AValue;
end;
procedure TThing.GrowField;
begin
  SetLength(FBuffer, 4);
end;
procedure TThing.GrowLocal;
var
  LocalArr: TArray<Integer>;
begin
  SetLength(LocalArr, 4);
end;
procedure TThing.WriteAncestor;
begin
  FInherited := 1;
end;
procedure TThing.UseWith;
begin
  with Self do GrowLocal;
end;
procedure TThing.DoVirtual;
begin
end;
procedure TThing.CallsVirtual;
begin
  DoVirtual;
end;
procedure TThing.MemberWrite(AOther: TThing);
begin
  AOther.FCount := 1;
end;
procedure TThing.UnboundMember(AList: TObject);
begin
  AList.Free;
end;
procedure TThing.Nested;
  procedure Inner;
  var
    I: Integer;
  begin
    I := 0;
    GCounter := I;
  end;
begin
  Inner;
end;
procedure WriteGlobal;
begin
  GCounter := 1;
end;
procedure CallsWriteGlobal(A: Integer);
begin
  WriteGlobal;
end;
procedure FillOut(out AValue: Integer);
begin
  AValue := 1;
end;
procedure CallsFillOutLocal;
var
  L: Integer;
begin
  FillOut(L);
end;
procedure CallsFillOutGlobal;
begin
  FillOut(GCounter);
end;
function AddUp(A, B: Integer): Integer;
begin
  Result := A + B;
end;
procedure FreeIt(P: Pointer);
begin
  Dispose(P);
end;
procedure NewLocal;
var
  LocalP: PInteger;
begin
  New(LocalP);
end;
function OnlyIntrinsics(const S: string): Integer;
begin
  if Length(S) = 0 then Exit(0);
  Result := Ord(S[1]);
end;
function Ident(P: Pointer): Pointer;
begin
  Result := P;
end;
procedure AddrEscape;
var
  L: Integer;
begin
  Ident(Addr(L));
  FillOut(L);
end;
end.
