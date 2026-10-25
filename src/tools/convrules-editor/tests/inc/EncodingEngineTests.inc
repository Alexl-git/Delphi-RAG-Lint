{ ConvRules.Engine: raise-encoding args, the shared apply line, ValidateTextAt (Task 4). }

function EncTempRulesCount: Integer;
begin
  Result:= Length(TDirectory.GetFiles(TPath.GetTempPath, 'convrules-validate-*.rules'));
end;

procedure TestEncodingEngine;
const
  U = 'C:\p\A.pas';
var
  LEngine: TEngineAdapter;
  LRes   : TValidateResult;
  LBefore: Integer;
begin
  Check('raise.args.empty', RaiseEncodingArgs(nil) = '');
  Check('raise.args.two', RaiseEncodingArgs(['C:\p\A.pas', 'C:\p\A.dfm'])
    = ' --raise-encoding "C:\p\A.pas=utf8-bom" --raise-encoding "C:\p\A.dfm=utf8-bom"');
  Check('apply.args.raise', ApplyArgs(U, 'B.rules', ' --db "d"', '', RaiseEncodingArgs([U]), '')
    = 'convert-apply --unit "C:\p\A.pas" --rules "B.rules" --db "d" --raise-encoding "C:\p\A.pas=utf8-bom" --apply --no-backup --format json');
  Check('apply.args.plain', ApplyArgs(U, 'B.rules', ' --db "d"', ' --only "x,y"', '', ' --castlib "c"')
    = 'convert-apply --unit "C:\p\A.pas" --rules "B.rules" --db "d" --only "x,y" --castlib "c" --apply --no-backup --format json');
  LBefore:= EncTempRulesCount;
  LEngine:= TEngineAdapter.Create('C:\nowhere\drag-lint.exe', []);
  try
    LRes:= LEngine.ValidateTextAt('#use A' + Chr($0413), tlUtf8, '', '');
  finally
    LEngine.Free;
  end;
  Check('validate.at.nonexe', (not LRes.OK) and (EncTempRulesCount = LBefore));
  Check('validate.level.fn', (NeededLevel('#use A') = tlAscii7) and (NeededLevel('#use A' + Chr($0413)) = tlUtf8));
end;
