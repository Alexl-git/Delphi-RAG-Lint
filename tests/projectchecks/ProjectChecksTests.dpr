program ProjectChecksTests;

// v0.65 TDD harness for the project-membership parsing/normalization helpers
// (FP-8 unit-not-in-dpr clause parsing, FP-9 unit-not-in-project dotted-name
// normalization). Pure functions only -- no DB/FireDAC -- so this builds with a
// bare dcc64 against the dep-free DRagLint.Lint.ProjectChecks.Parse unit.

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DRagLint.Lint.ProjectChecks.Parse in '..\..\src\lint\DRagLint.Lint.ProjectChecks.Parse.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then
  begin
    Inc(GPass);
    Writeln('PASS  ', AName);
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL  ', AName);
  end;
end;

function HasName(const AArr: TArray<string>; const AName: string): Boolean;
var
  S: string;
begin
  Result:= False;
  for S in AArr do
    if SameText(S, AName) then Exit(True);
end;

procedure TestNormUnit;
begin
  // FP-9: dotted unit names must normalize consistently on both sides so a
  // unit registered as 'Foo.ViewModel.pas' matches the used 'Foo.ViewModel'.
  Check('NormUnit dotted keeps last segment',
    NormUnit('Foo.ViewModel') = 'viewmodel');
  Check('NormUnit dotted .pas strips only source ext',
    NormUnit('Foo.ViewModel.pas') = 'viewmodel');
  Check('NormUnit dotted name == its .pas file',
    NormUnit('uDefineSerialNumbers.ViewModel') = NormUnit('uDefineSerialNumbers.ViewModel.pas'));
  Check('NormUnit RTL namespaced -> last segment',
    NormUnit('System.SysUtils') = 'sysutils');
  Check('NormUnit plain .pas',
    NormUnit('uMyUnit.pas') = 'umyunit');
  Check('NormUnit bare ident',
    NormUnit('Forms') = 'forms');
end;

procedure TestUsesParse;
const
  DPR =
    'program Demo;'#13#10 +
    'uses'#13#10 +
    '  uMain in ''uMain.pas'' {frmMAIN},'#13#10 +
    '  {$IFDEF EUREKALOG}'#13#10 +
    '  EMapWin32,'#13#10 +
    '  {$ENDIF}'#13#10 +
    '  uStations in ''uStations.pas'' {frmStations: TfrmStations}; // trailing'#13#10 +
    'begin'#13#10 +
    'end.'#13#10;
var
  Names: TArray<string>;
  Line : Integer;
begin
  Names:= ParseUsesFromContent(DPR, Line);
  // FP-8: real units survive...
  Check('uses keeps uMain',        HasName(Names, 'uMain'));
  Check('uses keeps EMapWin32',    HasName(Names, 'EMapWin32'));
  Check('uses keeps uStations',    HasName(Names, 'uStations'));
  // ...but form/type hints and directives are NOT extracted as units.
  Check('uses drops frmMAIN hint',      not HasName(Names, 'frmMAIN'));
  Check('uses drops frmStations hint',  not HasName(Names, 'frmStations'));
  Check('uses drops TfrmStations type', not HasName(Names, 'TfrmStations'));
  Check('uses drops IFDEF directive',   not HasName(Names, 'IFDEF'));
  Check('uses drops ENDIF directive',   not HasName(Names, 'ENDIF'));
  Check('uses drops EUREKALOG token',   not HasName(Names, 'EUREKALOG'));
  Check('uses start line is 2',         Line = 2);
end;

procedure TestStripComments;
begin
  // String literals must survive; brace/line/block comments become blanks of
  // equal length (so byte offsets and line numbers are preserved).
  Check('strip keeps string literal',
    Pos('''keep.pas''', StripPasCommentsKeepLayout('A in ''keep.pas'' {drop}')) > 0);
  Check('strip preserves length',
    Length(StripPasCommentsKeepLayout('X{abc}Y')) = Length('X{abc}Y'));
  Check('strip removes brace body',
    Pos('abc', StripPasCommentsKeepLayout('X{abc}Y')) = 0);
  Check('strip removes line comment',
    Pos('gone', StripPasCommentsKeepLayout('keep // gone'#10'next')) = 0);
  Check('strip keeps newline',
    Pos(#10, StripPasCommentsKeepLayout('keep // gone'#10'next')) > 0);
end;

begin
  GPass:= 0;
  GFail:= 0;
  try
    TestNormUnit;
    TestUsesParse;
    TestStripComments;
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION ', E.ClassName, ': ', E.Message);
      Inc(GFail);
    end;
  end;
  Writeln('');
  Writeln(Format('projectchecks-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
