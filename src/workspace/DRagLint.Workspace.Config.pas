unit DRagLint.Workspace.Config;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON;

type
  TWorkspaceProject = record
    Path:    string;
    ScanDir: Boolean;
  end;

  TWorkspaceConfig = record
    Name:     string;
    Projects: TArray<TWorkspaceProject>;
    SharedDb: string;  // relative to config file dir
    RootDir:  string;  // populated after Load -- absolute dir containing config
  end;

  TWorkspaceConfigIO = class
  public
    class function LoadFromFile(const APath: string): TWorkspaceConfig; static;
    class procedure SaveToFile(const AConfig: TWorkspaceConfig;
      const APath: string); static;
    class function FindWorkspaceRoot(const AStartDir: string): string; static;
  end;

const
  WORKSPACE_FILENAME = '.drag-lint-workspace.json';
  DEFAULT_SHARED_DB  = '.drag-lint-workspace.sqlite';

implementation

{ TWorkspaceConfigIO }

class function TWorkspaceConfigIO.LoadFromFile(
  const APath: string): TWorkspaceConfig;
var
  Content: string;
  Root: TJSONObject;
  ProjArr: TJSONArray;
  ProjObj: TJSONObject;
  I: Integer;
  V: TJSONValue;
  B: TJSONBool;
  P: TWorkspaceProject;
begin
  Result := Default(TWorkspaceConfig);
  Result.SharedDb := DEFAULT_SHARED_DB;
  Result.RootDir  := TPath.GetDirectoryName(TPath.GetFullPath(APath));

  Content := TFile.ReadAllText(APath, TEncoding.UTF8);
  Root := TJSONObject.ParseJSONValue(Content) as TJSONObject;
  if Root = nil then
    raise Exception.CreateFmt('Invalid JSON in workspace config: %s', [APath]);
  try
    V := Root.GetValue('name');
    if (V <> nil) and (V.Value <> '') then
      Result.Name := V.Value;

    V := Root.GetValue('shared_db');
    if (V <> nil) and (V.Value <> '') then
      Result.SharedDb := V.Value;

    V := Root.GetValue('projects');
    if V is TJSONArray then
    begin
      ProjArr := TJSONArray(V);
      SetLength(Result.Projects, ProjArr.Count);
      for I := 0 to ProjArr.Count - 1 do
      begin
        P := Default(TWorkspaceProject);
        if ProjArr.Items[I] is TJSONObject then
        begin
          ProjObj := TJSONObject(ProjArr.Items[I]);
          var PathV := ProjObj.GetValue('path');
          if PathV <> nil then
            P.Path := PathV.Value;
          B := ProjObj.GetValue('scan_dir') as TJSONBool;
          if B <> nil then
            P.ScanDir := B.AsBoolean;
        end;
        Result.Projects[I] := P;
      end;
    end;
  finally
    Root.Free;
  end;
end;

class procedure TWorkspaceConfigIO.SaveToFile(const AConfig: TWorkspaceConfig;
  const APath: string);
var
  Root: TJSONObject;
  ProjArr: TJSONArray;
  ProjObj: TJSONObject;
  P: TWorkspaceProject;
  JsonText: string;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('name', AConfig.Name);
    Root.AddPair('shared_db', AConfig.SharedDb);
    ProjArr := TJSONArray.Create;
    Root.AddPair('projects', ProjArr);
    for P in AConfig.Projects do
    begin
      ProjObj := TJSONObject.Create;
      ProjObj.AddPair('path', P.Path);
      if P.ScanDir then
        ProjObj.AddPair('scan_dir', TJSONBool.Create(True));
      ProjArr.AddElement(ProjObj);
    end;
    JsonText := Root.Format(2);
  finally
    Root.Free;
  end;
  TFile.WriteAllText(APath, JsonText, TEncoding.UTF8);
end;

class function TWorkspaceConfigIO.FindWorkspaceRoot(
  const AStartDir: string): string;
var
  Dir, Parent: string;
  Candidate: string;
begin
  Result := '';
  Dir := TPath.GetFullPath(AStartDir);
  while Dir <> '' do
  begin
    Candidate := TPath.Combine(Dir, WORKSPACE_FILENAME);
    if TFile.Exists(Candidate) then
    begin
      Result := Dir;
      Exit;
    end;
    Parent := TPath.GetDirectoryName(Dir);
    // Stop at drive root (Parent = Dir means we're at root)
    if (Parent = '') or (Parent = Dir) then
      Break;
    Dir := Parent;
  end;
end;

end.
