unit DragLint.Plugin.Settings;

interface

type
  TDragLintSettings = record
    ExePath:              string;
    DbPathTemplate:       string;
    AutoIndex:            Boolean;
    AutoReindexOnSave:    Boolean;
    EnableHover:          Boolean;
    EnableCompletion:     Boolean;
    EnableSignature:      Boolean;
    EnableDiagnostics:    Boolean;
  end;

function LoadSettings: TDragLintSettings;
procedure SaveSettings(const ASettings: TDragLintSettings);
function DefaultSettings: TDragLintSettings;
function ResolveDbPath(const ATemplate, AProjDir: string): string;

implementation

uses
  System.SysUtils, System.Win.Registry, Winapi.Windows;

const
  REG_KEY = 'Software\drag-lint\DelphiPlugin';

function DefaultSettings: TDragLintSettings;
begin
  Result.ExePath        := 'drag-lint.exe';
  Result.DbPathTemplate := '<projdir>\.drag-lint.sqlite';
  Result.AutoIndex            := True;
  Result.AutoReindexOnSave    := True;
  Result.EnableHover          := True;
  Result.EnableCompletion  := True;
  Result.EnableSignature   := True;
  Result.EnableDiagnostics := True;
end;

function LoadSettings: TDragLintSettings;
var
  Reg: TRegistry;
begin
  Result := DefaultSettings;
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(REG_KEY) then
    try
      if Reg.ValueExists('ExePath')        then Result.ExePath        := Reg.ReadString('ExePath');
      if Reg.ValueExists('DbPathTemplate') then Result.DbPathTemplate := Reg.ReadString('DbPathTemplate');
      if Reg.ValueExists('AutoIndex')         then Result.AutoIndex         := Reg.ReadInteger('AutoIndex') <> 0;
      if Reg.ValueExists('AutoReindexOnSave') then Result.AutoReindexOnSave := Reg.ReadInteger('AutoReindexOnSave') <> 0;
      if Reg.ValueExists('EnableHover')       then Result.EnableHover       := Reg.ReadInteger('EnableHover') <> 0;
      if Reg.ValueExists('EnableCompletion')  then Result.EnableCompletion  := Reg.ReadInteger('EnableCompletion') <> 0;
      if Reg.ValueExists('EnableSignature')   then Result.EnableSignature   := Reg.ReadInteger('EnableSignature') <> 0;
      if Reg.ValueExists('EnableDiagnostics') then Result.EnableDiagnostics := Reg.ReadInteger('EnableDiagnostics') <> 0;
    finally
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

procedure SaveSettings(const ASettings: TDragLintSettings);
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create(KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey(REG_KEY, True) then
    try
      Reg.WriteString('ExePath',        ASettings.ExePath);
      Reg.WriteString('DbPathTemplate', ASettings.DbPathTemplate);
      Reg.WriteInteger('AutoIndex',         Ord(ASettings.AutoIndex));
      Reg.WriteInteger('AutoReindexOnSave', Ord(ASettings.AutoReindexOnSave));
      Reg.WriteInteger('EnableHover',       Ord(ASettings.EnableHover));
      Reg.WriteInteger('EnableCompletion',  Ord(ASettings.EnableCompletion));
      Reg.WriteInteger('EnableSignature',   Ord(ASettings.EnableSignature));
      Reg.WriteInteger('EnableDiagnostics', Ord(ASettings.EnableDiagnostics));
    finally
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

function ResolveDbPath(const ATemplate, AProjDir: string): string;
begin
  Result := StringReplace(ATemplate, '<projdir>',
    ExcludeTrailingPathDelimiter(AProjDir), [rfReplaceAll, rfIgnoreCase]);
end;

end.
