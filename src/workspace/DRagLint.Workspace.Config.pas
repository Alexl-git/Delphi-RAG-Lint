unit DRagLint.Workspace.Config;

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.JSON
  , System.Generics.Collections
  ; { v0.42: lets TJSONArray.GetValue inline (was H2443) }

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoWorkspace (DRagLint.CLI.pas), DRagLint.Workspace.Config.TWorkspaceConfigIO.LoadFromFile (DRagLint.Workspace.Config.pas), DRagLint.Workspace.Config.TWorkspaceConfigIO.SaveToFile (DRagLint.Workspace.Config.pas)
  /// Used in units: DRagLint.CLI, DRagLint.Workspace.Config
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TWorkspaceProject = record
    Path   : string ;
    ScanDir: Boolean;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoWorkspace (DRagLint.CLI.pas), declaration (DRagLint.Workspace.Config.pas), DRagLint.Workspace.Config.TWorkspaceConfigIO.LoadFromFile (DRagLint.Workspace.Config.pas), DRagLint.Workspace.Config.TWorkspaceConfigIO.SaveToFile (DRagLint.Workspace.Config.pas)
  /// Used in units: DRagLint.CLI, DRagLint.Workspace.Config
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TWorkspaceConfig = record
    Name    : string                   ;
    Projects: TArray<TWorkspaceProject>;
    SharedDb: string                   ; // relative to config file dir
    RootDir : string                   ; // populated after Load -- absolute dir containing config
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoWorkspace (DRagLint.CLI.pas)
  /// Used in units: DRagLint.CLI
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TWorkspaceConfigIO = class
    public
      /// <summary><!-- drag-lint:auto -->TWorkspaceConfigIO</summary>
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Observed: Default(TWorkspaceConfig).</returns>
      /// <exception cref="Exception"><!-- drag-lint:auto --></exception>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.DoWorkspace (DRagLint.CLI.pas), DRagLint.CLI.DoCycles (DRagLint.CLI.pas) ?, DRagLint.CLI.DoUsesAudit (DRagLint.CLI.pas) ?, DRagLint.CLI.DoUsesFixSweep (DRagLint.CLI.pas) ?, DRagLint.CLI.DoUsesFix (DRagLint.CLI.pas) ?
      /// Calls: Default, TJSONArray, TJSONObject
      /// Complexity: 11 (cyclomatic, outer body), 47 lines (full implementation)
      /// Touches: file system
      /// <seealso cref="DRagLint.Workspace.Config.TWorkspaceConfigIO.FindWorkspaceRoot"/>
      /// <seealso cref="DRagLint.Workspace.Config.TWorkspaceConfigIO.SaveToFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function LoadFromFile(const APath: string): TWorkspaceConfig; static;
      /// <param name="AConfig"><!-- drag-lint:auto type -->const TWorkspaceConfig</param>
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.DoWorkspace (DRagLint.CLI.pas), DRagLint.CLI.OpenInObsidian (DRagLint.CLI.pas) ?, DRagLint.CLI.DoUsesFix.TryEdit (DRagLint.CLI.pas) ?, DRagLint.CLI.DoUsesFix (DRagLint.CLI.pas) ?
      /// Touches: file system
      /// <seealso cref="DRagLint.Workspace.Config.TWorkspaceConfigIO.FindWorkspaceRoot"/>
      /// <seealso cref="DRagLint.Workspace.Config.TWorkspaceConfigIO.LoadFromFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class procedure SaveToFile(const AConfig: TWorkspaceConfig; const APath: string); static;
      /// <param name="AStartDir"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Observed: ''; Dir.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.DoWorkspace (DRagLint.CLI.pas)
      /// Touches: file system
      /// <seealso cref="DRagLint.Workspace.Config.TWorkspaceConfigIO.LoadFromFile"/>
      /// <seealso cref="DRagLint.Workspace.Config.TWorkspaceConfigIO.SaveToFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function FindWorkspaceRoot(const AStartDir: string): string; static;
  end;

const
  WORKSPACE_FILENAME = '.drag-lint-workspace.json';
  DEFAULT_SHARED_DB  = '.drag-lint-workspace.sqlite';

implementation

{ TWorkspaceConfigIO }

class function TWorkspaceConfigIO.LoadFromFile( const APath: string): TWorkspaceConfig;
var
  Content: string           ;
  Root   : TJSONObject      ;
  ProjArr: TJSONArray       ;
  ProjObj: TJSONObject      ;
  I      : Integer          ;
  V      : TJSONValue       ;
  B      : TJSONBool        ;
  P      : TWorkspaceProject;
begin
  Result:= Default(TWorkspaceConfig);
  Result.SharedDb:= DEFAULT_SHARED_DB;
  Result.RootDir:= TPath.GetDirectoryName(TPath.GetFullPath(APath));

  Content:= TFile.ReadAllText(APath, TEncoding.UTF8);
  Root:= TJSONObject.ParseJSONValue(Content) as TJSONObject;
  if Root = nil then raise Exception.CreateFmt('Invalid JSON in workspace config: %s', [APath]);
  try
    V:= Root.GetValue('name');
    if (V <> nil) and (V.Value <> '') then Result.Name:= V.Value;

    V:= Root.GetValue('shared_db');
    if (V <> nil) and (V.Value <> '') then Result.SharedDb:= V.Value;

    V:= Root.GetValue('projects');
    if V is TJSONArray then
    begin
      ProjArr:= TJSONArray(V);
      SetLength(Result.Projects, ProjArr.Count);
      for I:= 0 to ProjArr.Count - 1 do
      begin
        P:= Default(TWorkspaceProject);
        if ProjArr.Items[I] is TJSONObject then
        begin
          ProjObj:= TJSONObject(ProjArr.Items[I]);
          var PathV:= ProjObj.GetValue('path');
          if PathV <> nil then P.Path:= PathV.Value;
          B:= ProjObj.GetValue('scan_dir') as TJSONBool;
          if B <> nil then P.ScanDir:= B.AsBoolean;
        end;
        Result.Projects[I]:= P;
      end;
    end; // if
  finally
    Root.Free;
  end; // try
end; // function

class procedure TWorkspaceConfigIO.SaveToFile(const AConfig: TWorkspaceConfig; const APath: string);
var
  Root    : TJSONObject      ;
  ProjArr : TJSONArray       ;
  ProjObj : TJSONObject      ;
  P       : TWorkspaceProject;
  JsonText: string           ;
begin
  Root:= TJSONObject.Create;
  try
    Root.AddPair('name'     , AConfig.Name    );
    Root.AddPair('shared_db', AConfig.SharedDb);
    ProjArr:= TJSONArray.Create;
    Root.AddPair('projects', ProjArr);
    for P in AConfig.Projects do
    begin
      ProjObj:= TJSONObject.Create;
      ProjObj.AddPair('path', P.Path);
      if P.ScanDir then ProjObj.AddPair('scan_dir', TJSONBool.Create(True));
      ProjArr.AddElement(ProjObj);
    end;
    JsonText:= Root.Format(2);
  finally
    Root.Free;
  end; // try
  TFile.WriteAllText(APath, JsonText, TEncoding.UTF8);
end; // procedure

class function TWorkspaceConfigIO.FindWorkspaceRoot( const AStartDir: string): string;
var
  Dir      : string;
  Parent   : string;
  Candidate: string;
begin
  Result:= '';
  Dir:= TPath.GetFullPath(AStartDir);
  while Dir <> '' do
  begin
    Candidate:= TPath.Combine(Dir, WORKSPACE_FILENAME);
    if TFile.Exists(Candidate) then
    begin
      Result:= Dir;
      Exit;
    end;
    Parent:= TPath.GetDirectoryName(Dir);
    // Stop at drive root (Parent = Dir means we're at root)
    if (Parent = '') or (Parent = Dir) then Break;
    Dir:= Parent;
  end;
end; // function

end.
