unit DRagLint.Charts.Checks;

{ Pure predicates the chart emitters apply to rows they already hold. Each routine is
  a port of the named function in charts\src\Emit-Common.ps1 (line numbers of
  2026-10-13); the PowerShell output is the reference (spec P3/P4). No I/O, no index. }

interface

type
  /// <summary>One uses-edge between two units of a cycle group.</summary>
  TUnitEdge = record
    /// <summary>The using unit.</summary>
    Src    : string;
    /// <summary>The used unit.</summary>
    Dst    : string;
    /// <summary>'interface' or 'implementation' (the uses clause the edge sits in).</summary>
    Section: string;
  end;

/// <summary>Effects' engine-D12 detector: the stored g rests on a write to the routine's own name.</summary>
/// <param name="pName">The routine's own name.</param>
/// <param name="pWitness">The stored witness text.</param>
/// <param name="pEffectKinds">The Kind of every decoded effect row.</param>
/// <returns>True when pName and pWitness are non-empty, pWitness is 'writes &lt;pName&gt;
/// (non-local)' ignoring case, and some kind is 'g' (ignoring case).</returns>
/// <remarks>Port of Test-D12OwnNameWrite (Emit-Common.ps1:1259). PS traps closed:
/// String.Equals(..., OrdinalIgnoreCase) compares upper-invariant chars (not Delphi SameText,
/// which folds ASCII only); `$_.Kind -eq 'g'` is case-insensitive.</remarks>
function TestD12OwnNameWrite(const pName, pWitness: string; const pEffectKinds: TArray<string>): Boolean;

/// <summary>True when the INTERFACE-section edges alone close a loop among the members.</summary>
/// <param name="pEdges">The member edges; the FIRST edge of a src|dst pair counts (Emit-Cycles
/// builds its map with ContainsKey before the set).</param>
/// <param name="pMembers">The group's units.</param>
/// <returns>True when a depth-first walk over interface edges between members meets a unit
/// already on its path (a self-use counts).</returns>
/// <remarks>Port of Test-InterfaceLoop (Emit-Common.ps1:2914). PS traps closed: the edge
/// map and the visit state are @{} hashtables, so unit names match case-insensitively, and
/// `-ne 'interface'` is case-insensitive.</remarks>
function TestInterfaceLoop(const pEdges: TArray<TUnitEdge>; const pMembers: TArray<string>): Boolean;

type
  /// <summary>consumers' reader / writer counts. Port of the Measure-ConsumerKeys result.</summary>
  TConsumerKeys = record
    /// <summary>Distinct keys &gt; 0 (routine ids).</summary>
    Routines: Integer;
    /// <summary>Distinct keys &lt; 0 (minus a file id: one "(unit level)" row per unit).</summary>
    Units   : Integer;
  end;

/// <summary>Counts consumers' rows apart: routines and units.</summary>
/// <param name="pCertKeys">Keys of the certain rows.</param>
/// <param name="pLitKeys">Keys of the literal rows.</param>
/// <returns>Distinct positive keys and distinct negative keys over both lists.</returns>
/// <remarks>Port of Measure-ConsumerKeys (Emit-Common.ps1:1246). A key counts once however
/// many rows carry it; 0 is neither.</remarks>
function MeasureConsumerKeys(const pCertKeys, pLitKeys: TArray<Integer>): TConsumerKeys;

implementation

uses
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults;

const
  INTERFACE_SECTION = 'interface';
  EFFECT_GLOBAL_WRITE = 'g';
  EDGE_KEY_SEP = '|';
  ON_PATH = 1;
  DONE = 2;

function SameOrdinalIgnoreCase(const pA, pB: string): Boolean;
begin
  Result:= pA.ToUpperInvariant = pB.ToUpperInvariant;
end;

function TestD12OwnNameWrite(const pName, pWitness: string; const pEffectKinds: TArray<string>): Boolean;
begin
  if (pName = '') or (pWitness = '') then
    Exit(False);
  if not SameOrdinalIgnoreCase(pWitness, 'writes ' + pName + ' (non-local)') then
    Exit(False);
  for var Kind in pEffectKinds do
    if SameText(Kind, EFFECT_GLOBAL_WRITE) then
      Exit(True);
  Result:= False;
end;

type
  TLoopWalk = class
  private
    FSections: TDictionary<string, string>;
    FState   : TDictionary<string, Integer>;
    FMembers : TArray<string>;
    function StateOf(const pUnit: string): Integer;
  public
    constructor Create(const pEdges: TArray<TUnitEdge>; const pMembers: TArray<string>);
    destructor Destroy; override;
    function Visit(const pUnit: string): Boolean;
    function Run: Boolean;
  end;

constructor TLoopWalk.Create(const pEdges: TArray<TUnitEdge>; const pMembers: TArray<string>);
begin
  inherited Create;
  FSections:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  FState:= TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  FMembers:= pMembers;
  for var E in pEdges do
    FSections.TryAdd(E.Src + EDGE_KEY_SEP + E.Dst, E.Section);
end;

destructor TLoopWalk.Destroy;
begin
  FState.Free;
  FSections.Free;
  inherited Destroy;
end;

function TLoopWalk.StateOf(const pUnit: string): Integer;
begin
  if not FState.TryGetValue(pUnit, Result) then
    Result:= 0;
end;

function TLoopWalk.Visit(const pUnit: string): Boolean;
var
  Section: string;
begin
  FState.AddOrSetValue(pUnit, ON_PATH);
  for var M in FMembers do
  begin
    if not FSections.TryGetValue(pUnit + EDGE_KEY_SEP + M, Section) or not SameText(Section, INTERFACE_SECTION) then
      Continue;
    if StateOf(M) = ON_PATH then
      Exit(True);
    if (StateOf(M) = 0) and Visit(M) then
      Exit(True);
  end;
  FState.AddOrSetValue(pUnit, DONE);
  Result:= False;
end;

function TLoopWalk.Run: Boolean;
begin
  for var U in FMembers do
    if (StateOf(U) = 0) and Visit(U) then
      Exit(True);
  Result:= False;
end;

function TestInterfaceLoop(const pEdges: TArray<TUnitEdge>; const pMembers: TArray<string>): Boolean;
begin
  var Walk:= TLoopWalk.Create(pEdges, pMembers);
  try
    Result:= Walk.Run;
  finally
    Walk.Free;
  end;
end;

function MeasureConsumerKeys(const pCertKeys, pLitKeys: TArray<Integer>): TConsumerKeys;
begin
  Result:= Default(TConsumerKeys);
  var Seen:= TDictionary<Integer, Boolean>.Create;
  try
    for var K in pCertKeys + pLitKeys do
      if Seen.TryAdd(K, True) then
        if K > 0 then
          Inc(Result.Routines)
        else if K < 0 then
          Inc(Result.Units);
  finally
    Seen.Free;
  end;
end;

end.
