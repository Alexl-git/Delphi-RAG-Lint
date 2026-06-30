program BaselineTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils,
  DRagLint.Core.Model in '..\..\src\core\DRagLint.Core.Model.pas',
  DRagLint.Lint.Baseline in '..\..\src\lint\DRagLint.Lint.Baseline.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;

function MkFinding(const ARule, AFile: string; ALine: Integer): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId  := ARule;
  Result.Severity:= 'warning';
  Result.FilePath:= AFile;
  Result.StartLine:= ALine; Result.StartCol:= 1;
  Result.EndLine  := ALine; Result.EndCol  := 5;
  Result.Message := ARule + ' here';
end;

procedure TestBaseline;
var
  SrcPath, BasePath, ShiftedSrc: string;
  Findings, Filtered: TArray<TLintFinding>;
begin
  SrcPath := TPath.Combine(TPath.GetTempPath, 'dl-base-src.pas');
  BasePath:= TPath.Combine(TPath.GetTempPath, 'dl-base.json');

  // Source whose line 3 holds the flagged statement.
  TFile.WriteAllText(SrcPath,
    'unit X;'#13#10 +            // line 1
    'begin'#13#10 +             // line 2
    '  DoTheThing(a, b);'#13#10 + // line 3  <- finding
    'end.'#13#10, TEncoding.UTF8);

  Findings:= [MkFinding('used-before-assignment', SrcPath, 3)];
  TBaseline.Write(BasePath, Findings);
  Check('baseline file written', TFile.Exists(BasePath));

  // Re-run identical -> 0 new.
  Filtered:= TBaseline.Filter(BasePath, Findings);
  Check('identical run => 0 new', Length(Filtered) = 0);

  // Insert an unrelated line ABOVE the finding; the flagged statement is now on
  // line 4. Same line CONTENT => fingerprint stable => still suppressed.
  ShiftedSrc:=
    'unit X;'#13#10 +
    '// a new comment'#13#10 +   // inserted
    'begin'#13#10 +
    '  DoTheThing(a, b);'#13#10 + // line 4 now
    'end.'#13#10;
  TFile.WriteAllText(SrcPath, ShiftedSrc, TEncoding.UTF8);
  Filtered:= TBaseline.Filter(BasePath, [MkFinding('used-before-assignment', SrcPath, 4)]);
  Check('line-shift stable => still 0 new', Length(Filtered) = 0);

  // Two findings on the same (rule, file, line text): both fingerprinted distinctly,
  // both recorded, both suppressed on re-run.
  TBaseline.Write(BasePath, [MkFinding('used-before-assignment', SrcPath, 4),
                             MkFinding('used-before-assignment', SrcPath, 4)]);
  Filtered:= TBaseline.Filter(BasePath, [MkFinding('used-before-assignment', SrcPath, 4),
                                         MkFinding('used-before-assignment', SrcPath, 4)]);
  Check('duplicate identical findings both suppressed', Length(Filtered) = 0);

  // A genuinely new finding (different line content) reports.
  Filtered:= TBaseline.Filter(BasePath, [MkFinding('used-before-assignment', SrcPath, 1)]); // line 1 = 'unit X;'
  Check('new finding (diff line text) reported', Length(Filtered) = 1);

  TFile.Delete(SrcPath);
  TFile.Delete(BasePath);
end;

begin
  GPass:= 0; GFail:= 0;
  try
    TestBaseline;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('baseline-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
