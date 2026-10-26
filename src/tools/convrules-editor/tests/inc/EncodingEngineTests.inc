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
  LPlain : string;
  LDir   : string;
  LOldTmp: string;
  LOldTemp: string;
begin
  Check('raise.args.empty', RaiseEncodingArgs(nil) = '');
  Check('raise.args.two', RaiseEncodingArgs(['C:\p\A.pas', 'C:\p\A.dfm'])
    = ' --raise-encoding "C:\p\A.pas=utf8-bom" --raise-encoding "C:\p\A.dfm=utf8-bom"');
  Check('apply.args.raise', ApplyArgs(U, 'B.rules', ' --db "d"', '', RaiseEncodingArgs([U]), '')
    = 'convert-apply --unit "C:\p\A.pas" --rules "B.rules" --db "d" --raise-encoding "C:\p\A.pas=utf8-bom" --apply --no-backup --format json');
  // A space in the path stays inside the quotes: one flag per file, the path intact.
  Check('raise.args.space', RaiseEncodingArgs(['C:\my dir\A b.pas']) = ' --raise-encoding "C:\my dir\A b.pas=utf8-bom"');
  // The plain line is the raise line minus its raise flags, derived (not a second literal).
  LPlain:= ApplyArgs(U, 'B.rules', ' --db "d"', '', '', '');
  Check('apply.args.plain', LPlain = StringReplace(ApplyArgs(U, 'B.rules', ' --db "d"', '', RaiseEncodingArgs([U]), ''), RaiseEncodingArgs([U]), '', []));
  Check('apply.args.only.castlib', ApplyArgs(U, 'B.rules', ' --db "d"', ' --only "x,y"', '', ' --castlib "c"')
    = StringReplace(LPlain, ' --apply', ' --only "x,y" --castlib "c" --apply', []));
  // ValidateTextAt writes its rules file to the temp dir: point TMP/TEMP at a directory of
  // our own so a parallel run's files cannot move the count (and a failed write is caught).
  LDir:= TPath.Combine(TPath.GetTempPath, 'enc-nonexe-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(LDir);
  LOldTmp := GetEnvironmentVariable('TMP');
  LOldTemp:= GetEnvironmentVariable('TEMP');
  try
    SetEnvironmentVariable('TMP', PChar(LDir));
    SetEnvironmentVariable('TEMP', PChar(LDir));
    LBefore:= EncTempRulesCount;
    LEngine:= TEngineAdapter.Create('C:\nowhere\drag-lint.exe', []);
    try
      LRes:= LEngine.ValidateTextAt('#use A' + Chr($0413), tlUtf8, '', '');
    finally
      LEngine.Free;
    end;
    Check('validate.at.nonexe', (not LRes.OK) and (LBefore = 0) and (EncTempRulesCount = 0), IntToStr(EncTempRulesCount));
  finally
    SetEnvironmentVariable('TMP', PChar(LOldTmp));
    SetEnvironmentVariable('TEMP', PChar(LOldTemp));
    TDirectory.Delete(LDir, True);
  end; // try
  Check('validate.level.fn', (NeededLevel('#use A') = tlAscii7) and (NeededLevel('#use A' + Chr($0413)) = tlUtf8));
end;
