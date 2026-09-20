program ForwardStubTests;
{$APPTYPE CONSOLE}
{ Pins design section 2 of docs\superpowers\specs\2026-09-17-forward-stub-is-not-a-class-design.md
  at the ROW level, without a database: a stub is a class/interface row with no
  heritage, no children and a later same-name same-kind row in the same file.
  Same recipe as AncestryNameCollisionTests.dpr -- dcc64 with the engine's src
  folders on -U (see tests\autotest\run_forward_stub_pairing.ps1). }
uses
  System.SysUtils,
  DRagLint.Core.Model,
  DRagLint.Core.ForwardStub;

var
  Failed: Integer = 0;

procedure Check(const AName: string; AOk: Boolean; const ADetail: string = '');
begin
  if AOk then Writeln('  [PASS] ', AName)
  else begin Writeln('  [FAIL] ', AName, '  ', ADetail); Inc(Failed); end;
end;

function Row(AId: Int64; AKind: TSymbolKind; const AQName, AHeritage: string; ALine: Integer;
  AParentId: Int64 = -1; AFileId: Int64 = 1): TSymbol;
begin
  Result:= Default(TSymbol);
  Result.Id           := AId;
  Result.FileId       := AFileId;
  Result.ParentId     := AParentId;
  Result.Kind         := AKind;
  Result.QualifiedName:= AQName;
  Result.Name         := Copy(AQName, Pos('.', AQName) + 1, MaxInt);
  Result.Heritage     := AHeritage;
  Result.StartLine    := ALine;
  Result.EndLine      := ALine;
end;

function IndexOfId(const ARows: TArray<TSymbol>; AId: Int64): Integer;
begin
  for var i:= 0 to High(ARows) do if ARows[i].Id = AId then Exit(i);
  Result:= -1;
end;

var
  Rows, Folded: TArray<TSymbol>;
  Pairs: TArray<Integer>;
  I: Integer;
begin
  { The probe from spec section 1, plus an interface pair, a lone stub, an empty
    class and a member on the real TFoo. Row ids are deliberately NOT in line
    order so nothing passes by accident of array position. }
  Rows:= [
    Row(5, skClass    , 'fw.TFoo'     , 'TObject', 8),          { real class }
    Row(2, skClass    , 'fw.TFoo'     , ''       , 4),          { stub }
    Row(9, skMethod   , 'fw.TFoo.Bump', ''       , 10, 5),      { member of the REAL TFoo }
    Row(3, skInterface, 'fw.IFoo'     , ''       , 5),          { interface stub }
    Row(7, skInterface, 'fw.IFoo'     , ''       , 14),         { real interface (no heritage!) }
    Row(11, skMethod  , 'fw.IFoo.Ping', ''       , 15, 7),      { member of the REAL IFoo }
    Row(8, skClass    , 'fw.TOnlyStub', ''       , 12),         { lone stub -- stays a class }
    Row(6, skClass    , 'fw.TEmpty'   , ''       , 13)          { empty class -- not a stub }
  ];

  Writeln('CASE 1: PairForwardStubs over the probe set');
  Pairs:= PairForwardStubs(Rows, HasChildInSet(Rows));
  Check('one index per row', Length(Pairs) = Length(Rows));
  Check('S1: class stub (id 2) pairs with the real TFoo (id 5)', Pairs[IndexOfId(Rows, 2)] = IndexOfId(Rows, 5));
  Check('S7: interface stub (id 3) pairs with the real IFoo (id 7)', Pairs[IndexOfId(Rows, 3)] = IndexOfId(Rows, 7));
  Check('the real TFoo is not itself a stub', Pairs[IndexOfId(Rows, 5)] = -1);
  Check('the real IFoo (heritage-less but WITH a member) is not a stub', Pairs[IndexOfId(Rows, 7)] = -1);
  Check('S2: lone TOnlyStub is not a stub', Pairs[IndexOfId(Rows, 8)] = -1);
  Check('S3: empty TEmpty is not a stub', Pairs[IndexOfId(Rows, 6)] = -1);
  Check('members are never stubs', (Pairs[IndexOfId(Rows, 9)] = -1) and (Pairs[IndexOfId(Rows, 11)] = -1));

  Writeln('CASE 2: FoldForwardStubs drops the stubs and stamps the targets');
  Folded:= FoldForwardStubs(Rows, HasChildInSet(Rows));
  Check('two rows fewer', Length(Folded) = Length(Rows) - 2, Format('%d', [Length(Folded)]));
  Check('stub id 2 is gone', IndexOfId(Folded, 2) = -1);
  Check('stub id 3 is gone', IndexOfId(Folded, 3) = -1);
  I:= IndexOfId(Folded, 5);
  Check('real TFoo survives', I >= 0);
  if I >= 0 then Check('S1: real TFoo carries ForwardLine = 4', Folded[I].ForwardLine = 4, Format('%d', [Folded[I].ForwardLine]));
  I:= IndexOfId(Folded, 7);
  if I >= 0 then Check('S7: real IFoo carries ForwardLine = 5', Folded[I].ForwardLine = 5, Format('%d', [Folded[I].ForwardLine]));
  I:= IndexOfId(Folded, 8);
  Check('S2: lone stub survives with ForwardLine 0', (I >= 0) and (Folded[I].ForwardLine = 0));
  I:= IndexOfId(Folded, 6);
  Check('S3: empty class survives with ForwardLine 0', (I >= 0) and (Folded[I].ForwardLine = 0));
  Check('input array untouched (fold returns a copy)', Rows[IndexOfId(Rows, 5)].ForwardLine = 0);

  Writeln('CASE 3: the fold is a no-op on sets without a pair');
  Folded:= FoldForwardStubs([Rows[0]], HasChildInSet([Rows[0]]));
  Check('single row returned as is', (Length(Folded) = 1) and (Folded[0].Id = 5) and (Folded[0].ForwardLine = 0));
  Folded:= FoldForwardStubs(nil, HasChildInSet(nil));
  Check('nil in, nil out', Length(Folded) = 0);

  Writeln('CASE 4: the children question is asked through the callback');
  { Same two rows as the TFoo pair, but the callback says the EARLIER row has
    children: then it is a class with members, not a stub, whatever its line. }
  Folded:= FoldForwardStubs([Rows[0], Rows[1]],
    function(const ASym: TSymbol): Boolean begin Result:= ASym.Id = 2; end);
  Check('a row the callback calls parented is never folded', Length(Folded) = 2);
  Folded:= FoldForwardStubs([Rows[0], Rows[1]], nil);
  Check('nil callback = no children known = fold happens', (Length(Folded) = 1) and (Folded[0].ForwardLine = 4));

  Writeln('CASE 5: the target is the NEAREST later twin, and files never mix');
  Rows:= [
    Row(1, skClass, 'u.TA', '', 3),
    Row(2, skClass, 'u.TA', 'TObject', 20),
    Row(3, skClass, 'u.TA', 'TObject', 9),
    Row(4, skClass, 'u.TA', 'TObject', 5, -1, 2)   { other file, earliest line -- must be ignored }
  ];
  Pairs:= PairForwardStubs(Rows, HasChildInSet(Rows));
  Check('nearest later twin in the SAME file wins (line 9, id 3)', Pairs[0] = 2, Format('%d', [Pairs[0]]));
  Check('a twin in another file is not a target', Pairs[3] = -1);

  Writeln('CASE 6: qualified-name match is case-insensitive (Delphi is)');
  Rows:= [ Row(1, skClass, 'u.TFoo', '', 3), Row(2, skClass, 'u.tfoo', 'TObject', 6) ];
  Pairs:= PairForwardStubs(Rows, HasChildInSet(Rows));
  Check('tfoo completes TFoo', Pairs[0] = 1);

  Writeln;
  if Failed = 0 then begin Writeln('PASS'); ExitCode:= 0; end
  else begin Writeln(Format('FAIL (%d)', [Failed])); ExitCode:= 1; end;
end.
