unit DragLint.Plugin.Fonts;

/// <summary>Read the IDE's configured editor font so drag-lint popups render in
/// the same typeface the user picked (Consolas, Courier, whatever). Guarded --
/// returns False on any failure so callers keep their own default.</summary>

interface

/// <summary>The IDE editor font name + size from Tools > Options > Editor.</summary>
/// <param name="AName">Receives the font family name on success.</param>
/// <param name="ASize">Receives the point size on success.</param>
/// <returns>True if read from the IDE; False if unavailable (caller defaults).</returns>
/// <remarks>Uses the typed ToolsAPI.Editor surface: BorlandIDEServices is queried
/// (via Supports) for INTACodeEditorServices; its Options property (typed
/// INTACodeEditorOptions) exposes GetEditorFont(var Font: TFont), which fills a
/// TFont with the IDE's configured editor font. No string option keys are used.
/// Every step is guarded -- absent service, nil Options, or any exception all
/// degrade to Result:=False so the caller can fall back to its own default.</remarks>
function GetIdeEditorFont(out AName: string; out ASize: Integer): Boolean;

implementation

uses
  System.SysUtils, Vcl.Graphics, ToolsAPI, ToolsAPI.Editor;

function GetIdeEditorFont(out AName: string; out ASize: Integer): Boolean;
var
  Svcs: INTACodeEditorServices;
  Opts: INTACodeEditorOptions ;
  F   : TFont                 ;
begin
  Result:= False;
  AName:= ''; ASize:= 0;
  try
    if not Supports(BorlandIDEServices, INTACodeEditorServices, Svcs) then Exit;
    Opts:= Svcs.Options;
    if Opts = nil then Exit;
    F:= TFont.Create;
    try
      Opts.GetEditorFont(F);
      AName:= F.Name;
      ASize:= F.Size;
      Result:= (AName <> '') and (ASize > 0);
    finally
      F.Free;
    end;
  except
    Result:= False; // any ToolsAPI surprise -> caller default
  end;
end;

end.
