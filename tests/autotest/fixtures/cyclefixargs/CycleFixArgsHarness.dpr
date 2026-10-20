program CycleFixArgsHarness;

{ Console harness for DragLint.Plugin.CycleFix (pure, no ToolsAPI). Prints
  key=value lines that tests\autotest\run_plugin_cyclefix_args.ps1 asserts.
  ParamStr(1) is the fixture folder (tests\fixtures\cyclefix). }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  DragLint.Plugin.CycleFix in '..\..\..\..\src\delphi-plugin\DragLint.Plugin.CycleFix.pas';

const
  BANNER = '(loaded defaults from C:\Projects\.drag-lint.json)' + sLineBreak;
  NOTE   = sLineBreak + 'drag-lint: note: cycles --plan reads no platform library (--library-db none)' + sLineBreak;

var
  Dir : string;
  Rows: TArray<TCycleRow>;

function Fixture(const AName: string): string;
begin
  Result:= TFile.ReadAllText(TPath.Combine(Dir, AName), TEncoding.ASCII);
end;

function B(AValue: Boolean): string;
begin
  Result:= if AValue then 'TRUE' else 'FALSE';
end;

procedure Emit(const AKey, AValue: string);
begin
  Writeln(AKey + '=' + AValue);
end;

procedure EmitOutcome(const APrefix, AText: string);
var
  O: TCycleFixOutcome;
begin
  O:= ParseCycleFixOutcome(AText);
  Emit(APrefix + '.readable', B(O.Readable));
  Emit(APrefix + '.mode'    , O.Mode);
  Emit(APrefix + '.verdict' , O.Verdict);
  Emit(APrefix + '.baseline', O.Baseline);
  Emit(APrefix + '.refusals', IntToStr(Length(O.Refusals)));
  Emit(APrefix + '.verified', B(O.Verified));
  Emit(APrefix + '.written' , IntToStr(Length(O.Written)));
  Emit(APrefix + '.wrote'   , B(CycleFixWroteFiles(O)));
  Emit(APrefix + '.text'    , DescribeCycleFixOutcome(O));
end;

begin
  try
    Dir:= ParamStr(1);

    Emit('args.dry'  , CycleFixDryRunArgs('<P>', '<D>', 2));
    Emit('args.apply', CycleFixApplyArgs ('<P>', '<D>', 2));
    Emit('args.menu' , CycleFixMenuArgs  ('<P>', '<D>'));
    Emit('args.list' , CycleListArgs     ('<P>', '<D>'));

    Rows:= ParseCycleRows(BANNER + Fixture('causes.json') + NOTE);
    Emit('rows.count', IntToStr(Length(Rows)));
    if Length(Rows) = 3 then
    begin
      Emit('rows.0.cycle'  , IntToStr(Rows[0].Cycle));
      Emit('rows.0.units'  , Rows[0].Units);
      Emit('rows.0.fixable', B(Rows[0].Fixable));
      Emit('rows.0.part'   , Rows[0].Part);
      Emit('rows.0.caption', CycleRowCaption(Rows[0]));
      Emit('rows.1.cycle'  , IntToStr(Rows[1].Cycle));
      Emit('rows.1.fixable', B(Rows[1].Fixable));
      Emit('rows.1.reason' , Rows[1].Reason);
      Emit('rows.1.caption', CycleRowCaption(Rows[1]));
      Emit('rows.2.cycle'  , IntToStr(Rows[2].Cycle));
    end;
    Emit('rows.empty'  , IntToStr(Length(ParseCycleRows(BANNER + '[]'))));
    Emit('rows.garbage', IntToStr(Length(ParseCycleRows('drag-lint: error: no such project'))));

    EmitOutcome('refused', BANNER + Fixture('outcome-refused.json')       + NOTE);
    EmitOutcome('cycle'  , BANNER + Fixture('outcome-cycle-refused.json') + NOTE);
    EmitOutcome('dry'    , BANNER + Fixture('outcome-dryrun.json')        + NOTE);
    EmitOutcome('applied', BANNER + Fixture('outcome-applied.json')       + NOTE);
    EmitOutcome('garbage', 'drag-lint: error: something broke');
    EmitOutcome('other'  , '{"schema":"uses-fix/1","applied":true}');

    Writeln('DONE');
  except
    on E: Exception do Writeln('EXCEPTION=' + E.ClassName + ': ' + E.Message);
  end;
end.
