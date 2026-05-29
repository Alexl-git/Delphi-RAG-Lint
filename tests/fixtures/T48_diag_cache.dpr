program T48_diag_cache;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.JSON,
  DragLint.Plugin.DiagnosticCache;
var
  Params: TJSONObject;
  DiagsArr: TJSONArray;
  D: TJSONObject;
  R, S, E: TJSONObject;
  Out: TArray<TDragLintDiagnostic>;
begin
  { Build a minimal publishDiagnostics params object }
  Params   := TJSONObject.Create;
  DiagsArr := TJSONArray.Create;
  D := TJSONObject.Create;
  R := TJSONObject.Create;
  S := TJSONObject.Create;
  S.AddPair('line',      TJSONNumber.Create(5));
  S.AddPair('character', TJSONNumber.Create(2));
  E := TJSONObject.Create;
  E.AddPair('character', TJSONNumber.Create(10));
  R.AddPair('start', S);
  R.AddPair('end',   E);
  D.AddPair('range',    R);
  D.AddPair('severity', TJSONNumber.Create(1));
  D.AddPair('message',  'test error');
  D.AddPair('code',     'W1002');
  DiagsArr.AddElement(D);
  Params.AddPair('diagnostics', DiagsArr);

  Cache.Update('C:\test\foo.pas', Params);

  Out := Cache.GetForLine('C:\test\foo.pas', 5);
  Assert(Length(Out) = 1,           'one diagnostic on line 5');
  Assert(Out[0].Severity = dlsError,'severity is error');
  Assert(Out[0].StartCol = 2,       'start col');
  Assert(Out[0].EndCol   = 10,      'end col');
  Assert(Out[0].Code     = 'W1002', 'code');
  Assert(Out[0].Message  = 'test error', 'message');

  { Line 4 should return nothing }
  Out := Cache.GetForLine('C:\test\foo.pas', 4);
  Assert(Length(Out) = 0, 'no diagnostics on line 4');

  { Case-insensitive path lookup }
  Out := Cache.GetForLine('C:\TEST\FOO.PAS', 5);
  Assert(Length(Out) = 1, 'case-insensitive lookup');

  Params.Free;
  WriteLn('OK');
end.
