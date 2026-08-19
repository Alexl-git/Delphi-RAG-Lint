program CallerFilterHarness;

{ Console harness for DragLint.Plugin.CallerFilter (pure, no ToolsAPI), in the
  shape of DbProbeHarness.

  It runs each fixture through BOTH policies:

    NEW = SelectCallers          -- the unit under test
    OLD = OldPolicy below        -- a faithful re-implementation of the code
                                    that shipped: class-qualified filter, and
                                    on zero matches, return EVERYTHING

  Both are printed so the .ps1 can assert that the guard DISCRIMINATES. A test
  that only checked NEW would pass just as happily against a policy that always
  returns nothing, and "always empty" is a different bug wearing the same green
  tick. Case D exists to catch exactly that. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DragLint.Plugin.CallerFilter in '..\..\..\..\src\delphi-plugin\DragLint.Plugin.CallerFilter.pas';

function Row(const AFile: string; ALine: Integer; const ACode, ATarget: string): TDLCallerRow;
begin
  Result.FilePath   := AFile;
  Result.Line       := ALine;
  Result.CodeText   := ACode;
  Result.TargetQName:= ATarget;
end;

{ The policy that shipped before 2026-08-18, reproduced exactly: keep rows whose
  source line contains the class qualifier; if that keeps none, keep them ALL. }
function OldPolicy(const ANameRows: TDLCallerRows; const AClassQual: string): TDLCallerRows;
var
  I, K: Integer;
  Dup : Boolean;
begin
  SetLength(Result, 0);
  for I:= 0 to High(ANameRows) do
    if Pos(AClassQual, ANameRows[I].CodeText) > 0 then
    begin
      Dup:= False;
      for K:= 0 to High(Result) do
        if (Result[K].Line = ANameRows[I].Line) and SameText(Result[K].FilePath, ANameRows[I].FilePath) then Dup:= True;
      if not Dup then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)]:= ANameRows[I];
      end;
    end;
  if Length(Result) > 0 then Exit;
  for I:= 0 to High(ANameRows) do
  begin
    Dup:= False;
    for K:= 0 to High(Result) do
      if (Result[K].Line = ANameRows[I].Line) and SameText(Result[K].FilePath, ANameRows[I].FilePath) then Dup:= True;
    if not Dup then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)]:= ANameRows[I];
    end;
  end;
end;

function SourceName(ASrc: TDLCallerSource): string;
begin
  case ASrc of
    csResolved      : Result:= 'resolved';
    csClassQualified: Result:= 'classqual';
    csNoneResolved  : Result:= 'noneresolved';
  else                Result:= 'unresolvedall';
  end;
end;

procedure Emit(const ACase: string; const AResolved, ANameRows: TDLCallerRows; const AQName: string);
var
  Src : TDLCallerSource;
  New_: TDLCallerRows  ;
  Old_: TDLCallerRows  ;
  CQ  : string         ;
begin
  CQ  := ClassQualifierOf(AQName);
  New_:= SelectCallers(AResolved, ANameRows, AQName, CQ, Src);
  Old_:= OldPolicy(ANameRows, CQ);
  Writeln(Format('%s.classqual=%s', [ACase, CQ]));
  Writeln(Format('%s.new.count=%d', [ACase, Length(New_)]));
  Writeln(Format('%s.new.source=%s', [ACase, SourceName(Src)]));
  Writeln(Format('%s.old.count=%d', [ACase, Length(Old_)]));
  { The path of the first surviving row. A resolved row carries only a bare
    file name, so this is what proves the selection kept the NAME-INDEX row
    (full path, clickable) rather than the resolved one. }
  if Length(New_) > 0 then Writeln(Format('%s.new.path=%s', [ACase, New_[0].FilePath]));
end;

var
  Resolved, NameRows: TDLCallerRows;
begin
  try
    { --- A: the reported defect. The name resolves to OTHER Creates; none is
          ours; the project never constructs our class. --- }
    Resolved:= [
      Row('uMain.pas', 2343, '', 'System.Classes.TTimer.Create'),
      Row('uMain.pas', 3366, '', 'System.Classes.TStringList.Create'),
      Row('uConf.pas',  867, '', 'System.IniFiles.TMemIniFile.Create')
    ];
    NameRows:= [
      Row('uMain.pas', 2343, 'LTimer := TTimer.Create(LDlg);'          , ''),
      Row('uMain.pas', 3366, 'HeaderFields := TStringList.Create;'     , ''),
      Row('uConf.pas',  867, 'FINIFile := TMemIniFile.Create(FININame);', '')
    ];
    Emit('A', Resolved, NameRows, 'EException.TEurekaExceptionInfo.Create');

    { --- B: a genuine resolved hit for our exact symbol.
          Note the ASYMMETRY, which is how the real queries behave and which the
          first draft of this fixture got wrong: `find-callers --resolved`
          reports a BARE file name, while the name index reports a FULL PATH and
          the source line. The selection must match them on base name + line and
          return the FULL-PATH row, or the popup's rows are not clickable. --- }
    Resolved:= [
      Row('uMain.pas', 2343, '', 'System.Classes.TTimer.Create'),
      Row('uUse.pas' ,  120, '', 'MyUnit.TFoo.Create')
    ];
    NameRows:= [
      Row('C:\Proj\uMain.pas', 2343, 'LTimer := TTimer.Create(LDlg);', ''),
      Row('C:\Proj\uUse.pas' ,  120, 'F := TFoo.Create;'             , '')
    ];
    Emit('B', Resolved, NameRows, 'MyUnit.TFoo.Create');

    { --- C: resolver blind (no rows at all), but the source line carries the
          class qualifier. The text filter must still find it. --- }
    SetLength(Resolved, 0);
    NameRows:= [
      Row('uMain.pas', 2343, 'LTimer := TTimer.Create(LDlg);', ''),
      Row('uUse.pas' ,  120, 'F := TFoo.Create;'             , '')
    ];
    Emit('C', Resolved, NameRows, 'MyUnit.TFoo.Create');

    { --- D: POSITIVE CONTROL. Resolver blind AND no class-qualified line: an
          instance-variable call. The permissive fallback must survive, or the
          "fix" is just "always return nothing". --- }
    SetLength(Resolved, 0);
    NameRows:= [
      Row('uUse.pas', 55, 'Thing.DoStuff(1);', ''),
      Row('uUse.pas', 61, 'Other.DoStuff(2);', '')
    ];
    Emit('D', Resolved, NameRows, 'MyUnit.TThing.DoStuff');

    { --- E: de-duplication -- one call site emits a call ref AND a member ref. --- }
    Resolved:= [
      Row('uUse.pas', 120, '', 'MyUnit.TFoo.Create'),
      Row('uUse.pas', 120, '', 'MyUnit.TFoo.Create')
    ];
    SetLength(NameRows, 0);
    Emit('E', Resolved, NameRows, 'MyUnit.TFoo.Create');

    { --- F: a dotted UNIT name must not confuse the class qualifier. --- }
    Writeln('F.classqual=' + ClassQualifierOf('DRagLint.LSP.Server.TLSPServer.HandleHover'));
    Writeln('F.free=' + ClassQualifierOf('MyUnit.SomeFreeRoutine'));
    Writeln('DONE');
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ' + E.ClassName + ': ' + E.Message);
      ExitCode:= 1;
    end;
  end;
end.
