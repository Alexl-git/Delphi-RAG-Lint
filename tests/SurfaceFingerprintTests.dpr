program SurfaceFingerprintTests;
{$APPTYPE CONSOLE}
{ The interface-surface fingerprint changes when, and ONLY when, a dependent
  could care.

  WHAT THIS PINS. lint-tree decides whether to fan out at all by comparing a
  fingerprint of unit B's INTERFACE against an edit-episode baseline. Two
  failures are possible and they are not symmetric:

    a fingerprint that moves when nothing a dependent can see has changed
    (whitespace, a comment, a declaration moved down, an implementation edit)
    makes the feature fire constantly and trains the user to ignore it;

    a fingerprint that does NOT move when a breaking edit was made makes the
    feature silently report all-clear, which is worse, because the whole point
    of lint-tree is that `lint-all` already reports nothing in that case
    (MEASURED 2026-09-10: removing three interface symbols from B produced ZERO
    findings in A, and the finding count went DOWN from 4 to 3).

  So this program is half positive controls and half negative controls, and
  neither half is optional. A fingerprint function that returns a constant
  passes every positive control's inverse; one that hashes the whole file
  passes every negative control's inverse. Only both together pin the shape.

  WHY A CONSOLE TEST AND NOT AN AUTOTEST. SurfaceCanonical is a pure function
  over TArray<TSymbol> / TArray<TUnitUse>, so it links against Core.Model alone
  and needs neither a database nor the CLI. The `lint-tree` verb that will feed
  it real parses does not exist yet (task B2), so an autotest driving the verb
  could not run at all; waiting for B2 would mean writing the fingerprint with
  no test. Same shape as CodeLensCacheLruTests.dpr and JobQueueHoldTests.dpr.

  WHAT THIS DELIBERATELY DOES NOT PROVE. The inputs here are CONSTRUCTED, not
  parsed. This pins the canonicaliser's contract over the record arrays; it says
  nothing about whether the two adapters (parser output for the buffer,
  symbols/unit_uses for the index) actually produce equivalent arrays for the
  same source. That is the B4 guard `run_surface_fingerprint.ps1`, which drives
  real files through the verb, and it is the one that can catch an adapter skew.
  A green run here is necessary and not sufficient. }
uses
  System.SysUtils,
  DRagLint.Core.Model            in '..\src\core\DRagLint.Core.Model.pas',
  DRagLint.Analysis.SurfaceFingerprint
    in '..\src\analysis\DRagLint.Analysis.SurfaceFingerprint.pas';

var
  GPass: Integer = 0;
  GFail: Integer = 0;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  if ACond then
  begin
    Inc(GPass);
    Writeln('PASS  ', AName);
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL  ', AName, sLineBreak, '      ', ADetail);
  end;
end;

{ ---- builders -------------------------------------------------------------- }

function Sym(const AKind: TSymbolKind; const AQName, ASig: string;
  const AModifiers: string = 'public'; const ASection: string = 'interface'):
  TSymbol;
begin
  Result           := Default(TSymbol);
  Result.Kind      := AKind;
  Result.Name      := AQName;
  Result.QualifiedName := AQName;
  Result.Signature := ASig;
  Result.Modifiers := AModifiers;
  Result.Section   := ASection;
  { line numbers are deliberately NON-ZERO and DIFFERENT from any other
    builder call, so a canonicaliser that leaked a line number into the
    string would fail the "declaration moved" negative control below. }
  Result.StartLine := 100 + Length(AQName);
  Result.EndLine   := Result.StartLine + 1;
end;

function UseOf(const AName: string; const ASection: TUnitUseSection):
  TUnitUse;
begin
  Result          := Default(TUnitUse);
  Result.UnitName := AName;
  Result.Section  := ASection;
end;

function BaseSymbols: TArray<TSymbol>;
begin
  Result := [
    Sym(skProcedure, 'uB.FreeProc',       'procedure FreeProc'),
    Sym(skClass,     'uB.TWidget',        'class'),
    Sym(skMethod,    'uB.TWidget.DoThing','procedure DoThing'),
    Sym(skConstDecl,     'uB.BConst',         '42')
  ];
end;

function BaseUses: TArray<TUnitUse>;
begin
  Result := [
    UseOf('System.SysUtils', uusInterface),
    UseOf('System.Classes',  uusInterface),
    UseOf('System.IOUtils',  uusImplementation)
  ];
end;

function FpOf(const ASymbols: TArray<TSymbol>; const AUses: TArray<TUnitUse>;
  const ABodies: TArray<TInlineBody>): string;
begin
  Result := SurfaceFingerprint(ASymbols, AUses, ABodies);
end;

var
  Base    : string;
  S       : TArray<TSymbol>;
  U       : TArray<TUnitUse>;
  B       : TArray<TInlineBody>;
  Tmp     : TSymbol;
  FpBody1 : string;
begin
  try
    B    := [];
    Base := FpOf(BaseSymbols, BaseUses, B);

    Check('a fingerprint is produced at all', Base <> '', 'empty fingerprint');
    Check('the fingerprint is stable across two identical calls',
      FpOf(BaseSymbols, BaseUses, B) = Base, 'same input gave a different hash');

    { ---- POSITIVE controls: each of these MUST move the fingerprint ---- }

    S := BaseSymbols; S[0].QualifiedName := 'uB.FreeProcRenamed';
    Check('POS renaming an interface routine changes it',
      FpOf(S, BaseUses, B) <> Base);

    S := BaseSymbols; S[3].Signature := '43';
    Check('POS changing a const VALUE changes it',
      FpOf(S, BaseUses, B) <> Base, 'const value is not in the surface');

    S := BaseSymbols; S[2].Signature := 'procedure DoThing(const A: Integer)';
    Check('POS changing a method signature changes it',
      FpOf(S, BaseUses, B) <> Base);

    S := BaseSymbols; S[1].Heritage := 'TObject';
    Check('POS changing heritage changes it', FpOf(S, BaseUses, B) <> Base);

    S := BaseSymbols; S[2].PropAccess := 'ro';
    Check('POS changing a property accessor changes it',
      FpOf(S, BaseUses, B) <> Base);

    S := BaseSymbols; S[1].IsHelper := True;
    Check('POS flipping is_helper changes it', FpOf(S, BaseUses, B) <> Base);

    S := BaseSymbols; S[2].Directives := 'virtual';
    Check('POS adding a routine directive changes it',
      FpOf(S, BaseUses, B) <> Base, 'directives are not in the surface');

    U := [UseOf('System.Classes',  uusInterface),
          UseOf('System.SysUtils', uusInterface),
          UseOf('System.IOUtils',  uusImplementation)];
    Check('POS reordering INTERFACE uses changes it', FpOf(BaseSymbols, U, B) <> Base,
      'interface uses order is not preserved');

    U := [UseOf('System.SysUtils', uusInterface),
          UseOf('System.IOUtils',  uusImplementation)];
    Check('POS removing an interface uses entry changes it',
      FpOf(BaseSymbols, U, B) <> Base);

    S := BaseSymbols;
    S := S + [Sym(skProcedure, 'uB.NewProc', 'procedure NewProc')];
    Check('POS adding an interface routine changes it',
      FpOf(S, BaseUses, B) <> Base);

    B := [Default(TInlineBody)];
    B[0].QualifiedName := 'uB.TWidget.DoThing';
    B[0].BodyText      := 'begin Result := 1; end;';
    FpBody1 := FpOf(BaseSymbols, BaseUses, B);
    Check('POS an inline body hash participates', FpBody1 <> Base,
      'inline bodies do not affect the surface');

    { The ONLY difference from FpBody1 is the body TEXT -- same qualified
      name, same symbols, same uses. Comparing against a differently-NAMED
      body would pass even if the text were never hashed. }
    B[0].BodyText := 'begin Result := 2; end;';
    Check('POS editing an inline body changes it',
      FpOf(BaseSymbols, BaseUses, B) <> FpBody1,
      'inline body text is not hashed');
    B := [];

    { ---- NEGATIVE controls: each of these MUST NOT move it ---- }

    S := BaseSymbols;
    S[0].StartLine := 9000; S[0].EndLine := 9001;
    S[2].StartLine := 9100; S[2].EndLine := 9101;
    Check('NEG moving declarations (line numbers only) does not change it',
      FpOf(S, BaseUses, B) = Base, 'a line number leaked into the surface');

    S := [BaseSymbols[3], BaseSymbols[2], BaseSymbols[1], BaseSymbols[0]];
    Check('NEG the input order of symbols does not change it',
      FpOf(S, BaseUses, B) = Base, 'symbols are not sorted canonically');

    U := [UseOf('System.SysUtils', uusInterface),
          UseOf('System.Classes',  uusInterface),
          UseOf('System.Types',    uusImplementation),
          UseOf('System.IOUtils',  uusImplementation)];
    Check('NEG changing IMPLEMENTATION uses does not change it',
      FpOf(BaseSymbols, U, B) = Base, 'implementation uses leaked in');

    S := BaseSymbols;
    S := S + [Sym(skProcedure, 'uB.HelperProc', 'procedure HelperProc',
                  'public', 'implementation')];
    Check('NEG adding an IMPLEMENTATION symbol does not change it',
      FpOf(S, BaseUses, B) = Base, 'implementation section leaked in');

    S := BaseSymbols;
    Tmp := Sym(skUnit, 'uB', 'unit uB');
    S := [Tmp] + S;
    Check('NEG the skUnit symbol is excluded',
      FpOf(S, BaseUses, B) = Base, 'skUnit is not excluded');

    S := BaseSymbols;
    S := S + [Sym(skParam, 'uB.TWidget.DoThing.A', 'const A: Integer')];
    Check('NEG params are excluded',
      FpOf(S, BaseUses, B) = Base, 'skParam is not excluded');

    S := BaseSymbols;
    S[0].ImplStartLine := 500; S[0].ImplEndLine := 520;
    Check('NEG a non-inline implementation edit does not change it',
      FpOf(S, BaseUses, B) = Base, 'impl span leaked into the surface');
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL  unhandled ', E.ClassName, ': ', E.Message);
    end;
  end;

  Writeln;
  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  if GFail > 0 then Halt(1);
end.
