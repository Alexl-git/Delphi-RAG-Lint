unit DragLint.Plugin.RegistryColors;

interface

uses
  System.SysUtils, Vcl.Graphics;

type
  TDragLintColors = record
    ErrorColor:   TColor;
    WarningColor: TColor;
    HintColor:    TColor;
    InfoColor:    TColor;
  end;

function LoadEditorColors: TDragLintColors;

implementation

uses
  System.Win.Registry, Winapi.Windows;

const
  REG_HL = 'Software\Embarcadero\BDS\37.0\Editor\Highlight\';

function ReadColor(const AName: string; ADefault: TColor): TColor;
var
  Reg: TRegistry;
  S: string;
begin
  Result := ADefault;
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(REG_HL + AName) then
    try
      if Reg.ValueExists('Foreground Color') then
      begin
        S := Reg.ReadString('Foreground Color');
        if not IdentToColor(S, Integer(Result)) then
          if S.StartsWith('$') then
            Result := TColor(StrToIntDef(S, ADefault))
          else
            Result := TColor(StrToIntDef(S, ADefault));
      end;
    finally
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

function LoadEditorColors: TDragLintColors;
begin
  Result.ErrorColor   := ReadColor('Syntax Error', clRed);
  Result.WarningColor := ReadColor('Warning',      clOlive);
  Result.HintColor    := ReadColor('Hint',         clTeal);
  Result.InfoColor    := ReadColor('Information',  clNavy);
end;

end.
