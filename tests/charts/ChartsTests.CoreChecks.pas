unit ChartsTests.CoreChecks;

{ Cases for DRagLint.Charts.Checks, the pure predicates ported from
  charts\src\Emit-Common.ps1. The cases are the gate's own synthetic inputs
  (Test-Emitters.ps1 A-FX12-DETECT and A-CY-ILOOP) with the answers the PS gives. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCoreChecksTests = class
  public
    [Test] procedure D12NeedsOwnNameWitnessAndG;
    [Test] procedure InterfaceLoopOnSyntheticGraphs;
    [Test] procedure InterfaceLoopKeysAreCaseBlind;
    [Test] procedure ConsumerKeysCountRoutinesAndUnits;
  end;

implementation

uses
  System.SysUtils, DRagLint.Charts.Checks;

const
  ROUTINE_FIVE = 5;
  ROUTINE_SEVEN = 7;
  UNIT_THREE = -3;
  INTF = 'interface';
  IMPL = 'implementation';

function E(const pSrc, pDst, pSection: string): TUnitEdge;
begin
  Result.Src:= pSrc;
  Result.Dst:= pDst;
  Result.Section:= pSection;
end;

procedure TCoreChecksTests.D12NeedsOwnNameWitnessAndG;
begin
  { A-FX12-DETECT: 'True/True/False/False/False' }
  Assert.IsTrue(TestD12OwnNameWrite('F', 'writes F (non-local)', ['g', '?']));
  Assert.IsTrue(TestD12OwnNameWrite('F', 'WRITES f (NON-LOCAL)', ['g', '?']), 'OrdinalIgnoreCase');
  Assert.IsFalse(TestD12OwnNameWrite('F', 'writes G (non-local)', ['g', '?']));
  Assert.IsFalse(TestD12OwnNameWrite('F', 'writes F (non-local)', ['s']));
  Assert.IsFalse(TestD12OwnNameWrite('F', '', ['g']));
  { $_.Kind -eq 'g' is case-insensitive; a blank name is falsy }
  Assert.IsTrue(TestD12OwnNameWrite('F', 'writes F (non-local)', ['G']));
  Assert.IsFalse(TestD12OwnNameWrite('', 'writes  (non-local)', ['g']));
end;

procedure TCoreChecksTests.InterfaceLoopOnSyntheticGraphs;
begin
  { A-CY-ILOOP: 'True/True/False' }
  Assert.IsTrue(TestInterfaceLoop([E('a', 'b', INTF), E('b', 'c', INTF), E('c', 'a', INTF)], ['a', 'b', 'c']), 'ring');
  Assert.IsTrue(TestInterfaceLoop([E('a', 'b', INTF), E('b', 'a', IMPL), E('b', 'c', INTF), E('c', 'b', INTF)], ['a', 'b', 'c']),
    'an SCC whose b<->c sub-loop is all-interface');
  Assert.IsFalse(TestInterfaceLoop([E('a', 'b', INTF), E('b', 'c', INTF), E('c', 'a', IMPL)], ['a', 'b', 'c']),
    'every loop crosses an implementation use');
  Assert.IsTrue(TestInterfaceLoop([E('a', 'a', INTF)], ['a']), 'a self-use');
  Assert.IsFalse(TestInterfaceLoop([], []), 'no members');
end;

procedure TCoreChecksTests.InterfaceLoopKeysAreCaseBlind;
begin
  { a PS hashtable literal is case-insensitive, and so is -ne 'interface' }
  Assert.IsTrue(TestInterfaceLoop([E('A', 'b', 'INTERFACE'), E('B', 'a', INTF)], ['a', 'b']));
  { the FIRST edge of a key wins, as Emit-Cycles builds the map (ContainsKey before set) }
  Assert.IsFalse(TestInterfaceLoop([E('a', 'b', IMPL), E('a', 'b', INTF), E('b', 'a', INTF)], ['a', 'b']));
end;

procedure TCoreChecksTests.ConsumerKeysCountRoutinesAndUnits;
begin
  { the gate's case: routine 5 by fact AND literal is ONE routine; -3 is one unit, however many literals }
  var K:= MeasureConsumerKeys([ROUTINE_FIVE], [ROUTINE_FIVE, ROUTINE_SEVEN, UNIT_THREE, UNIT_THREE]);
  Assert.AreEqual('2/1', Format('%d/%d', [K.Routines, K.Units]));
  K:= MeasureConsumerKeys([], []);
  Assert.AreEqual('0/0', Format('%d/%d', [K.Routines, K.Units]));
  { a 0 key is neither a routine nor a unit }
  K:= MeasureConsumerKeys([0], []);
  Assert.AreEqual('0/0', Format('%d/%d', [K.Routines, K.Units]));
end;

end.