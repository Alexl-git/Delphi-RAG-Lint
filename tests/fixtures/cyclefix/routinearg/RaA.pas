unit RaA;

interface

type
  /// <summary>A plain procedural type.</summary>
  TRaProc = procedure(const pText: string);

  /// <summary>A method-reference type.</summary>
  TRaRef = reference to procedure(const pText: string);

/// <summary>Hands RaBSay over twice.</summary>
procedure RaAShow;

/// <summary>A fixed value; RaB reads it without parentheses, so the edge RaB to RaA cannot be cut.</summary>
/// <returns>5.</returns>
function RaAFive: Integer;

implementation

uses
  RaB;

procedure RaApply(const pText: string; const pProc: TRaProc);
begin
  pProc(pText);
end;

procedure RaApplyRef(const pText: string; const pProc: TRaRef);
begin
  pProc(pText);
end;

procedure RaAShow;
begin
  RaApply('plain', RaBSay);
  RaApplyRef('ref', RaBSay);
  RaBSay('call');
end;

function RaAFive: Integer;
begin
  Result:= 5;
end;

end.
