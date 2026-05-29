program T59_workspace_config;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.IOUtils,
  DRagLint.Workspace.Config;
var
  C, C2: TWorkspaceConfig;
  TmpPath: string;
begin
  C.Name := 'TestWorkspace';
  SetLength(C.Projects, 2);
  C.Projects[0].Path := 'sub1/foo.dproj';
  C.Projects[0].ScanDir := False;
  C.Projects[1].Path := 'sub2';
  C.Projects[1].ScanDir := True;
  C.SharedDb := 'shared.sqlite';

  TmpPath := TPath.Combine(TPath.GetTempPath, 'ws-test.json');
  TWorkspaceConfigIO.SaveToFile(C, TmpPath);
  C2 := TWorkspaceConfigIO.LoadFromFile(TmpPath);

  Assert(C2.Name = 'TestWorkspace', 'name roundtrip');
  Assert(Length(C2.Projects) = 2, 'project count');
  Assert(C2.Projects[0].Path = 'sub1/foo.dproj', 'project 0 path');
  Assert(C2.Projects[1].ScanDir, 'project 1 scan dir');
  Assert(C2.SharedDb = 'shared.sqlite', 'shared db');

  TFile.Delete(TmpPath);
  WriteLn('OK');
end.
