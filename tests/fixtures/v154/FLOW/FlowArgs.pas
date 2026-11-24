unit FlowArgs;

// same-variable-two-var-params (G-09)

interface

uses
  FlowOther;

type
  TPoint2 = record
    X, Y: Integer;
  end;
  TWorker = class
  private
    FText: string;
    FList: array[0..3] of Integer;
  public
    procedure Run;
    procedure Both(var A, B: Integer);
  end;

procedure Local;
procedure Swap2(var A, B: Integer);
procedure Parse(const AText: string; out ARest: string);
procedure Add3(var A: Integer; B: Integer; const C: Integer);
procedure Raw(var A; var B);
procedure Half(const A: Integer; out B: Integer);
procedure Join(const A: string; var B: string);
procedure Over(var A, B: Integer); overload;
procedure Over(var A: Integer; B: string); overload;

implementation

procedure Swap2(var A, B: Integer);
var
  T: Integer;
begin
  T := A;
  A := B;
  B := T;
end;

procedure Parse(const AText: string; out ARest: string);
begin
  ARest := Copy(AText, 2, MaxInt);
end;

procedure Add3(var A: Integer; B: Integer; const C: Integer);
begin
  A := A + B + C;
end;

procedure Raw(var A; var B);
begin
  Integer(A) := Integer(B);
end;

procedure Half(const A: Integer; out B: Integer);
begin
  B := A div 2;
end;

procedure Join(const A: string; var B: string);
begin
  B := B + A;
end;

procedure Over(var A, B: Integer);
begin
  A := B;
  B := 0;
end;

procedure Over(var A: Integer; B: string);
begin
  A := Length(B);
end;

procedure TWorker.Both(var A, B: Integer);
begin
  A := B;
  B := 0;
end;

procedure TWorker.Run;
var
  I, J: Integer;
begin
  I := 1;
  J := 2;
  Both(I, I); // FIRE same-variable-two-var-params
  Both(FList[I], FList[I]); // FIRE same-variable-two-var-params
  Both(FList[I], FList[J]);
  Both(FList[0], FList[1]);
  Parse(FText, FText); // FIRE same-variable-two-var-params
  Parse(Self.FText, FText); // FIRE same-variable-two-var-params
end;

procedure Local;
var
  N, M: Integer;
  S, T: string;
  P: TPoint2;
  A: array[0..7] of Byte;
begin
  N := 1;
  M := 2;
  S := 'a';
  T := 'b';
  P.X := 1;
  P.Y := 2;
  A[0] := 1;
  Swap2(N, N); // FIRE same-variable-two-var-params
  Swap2(n, N); // FIRE same-variable-two-var-params
  Parse(S, S); // FIRE same-variable-two-var-params
  Exchange(N, N); // FIRE same-variable-two-var-params
  Swap2(P.X, P.X); // FIRE same-variable-two-var-params
  Swap2(N, M);
  Swap2(P.X, P.Y);
  Parse(S, T);
  Parse(S + '', S);
  Add3(N, N, N);
  Raw(N, N);
  Half(N, N);
  Join(S, S);
  Over(N, M);
  Move(A[0], A[0], 4);
  Parse(T, S);
end;

end.