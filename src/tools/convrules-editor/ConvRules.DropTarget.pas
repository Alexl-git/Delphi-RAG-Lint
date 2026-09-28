unit ConvRules.DropTarget;

{ OLE drop target for the editor's main window: Explorer files (CF_HDROP) and
  dragged text (CF_UNICODETEXT). Registered on the FORM's window, re-registered
  by TConvRulesForm.CreateWnd, because a VCL style switch recreates the handle.
  Windows glue only -- the parsing it feeds lives in ConvRules.UsesHarvest. }

interface

uses
  Winapi.Windows
  , Winapi.ActiveX
  , Winapi.ShellAPI // HDROP: FilesFromHDrop's parameter type
  ;

type
  /// <summary>Receives dropped file paths.</summary>
  TDropFilesProc = reference to procedure(const AFiles: TArray<string>);
  /// <summary>Receives dropped text.</summary>
  TDropTextProc  = reference to procedure(const AText: string);

  /// <summary>IDropTarget accepting files or text and handing them on AFTER the
  /// drop returns (TThread.ForceQueue), so Explorer's drag loop is never held
  /// while the editor reads files or queries the engine.</summary>
  TFormDropTarget = class(TInterfacedObject, IDropTarget)
  private
    FOnFiles: TDropFilesProc;
    FOnText : TDropTextProc;
    FEffect : Longint;
    function CanAccept(const ADataObj: IDataObject): Boolean;
  protected
    function DragEnter(const dataObj: IDataObject; grfKeyState: Longint; pt: TPoint; var dwEffect: Longint): HResult; stdcall;
    function DragOver(grfKeyState: Longint; pt: TPoint; var dwEffect: Longint): HResult; stdcall;
    function DragLeave: HResult; stdcall;
    function Drop(const dataObj: IDataObject; grfKeyState: Longint; pt: TPoint; var dwEffect: Longint): HResult; stdcall;
  public
    /// <summary>Creates the target.</summary>
    /// <param name="AOnFiles">Called with dropped paths.</param>
    /// <param name="AOnText">Called with dropped text.</param>
    constructor Create(const AOnFiles: TDropFilesProc; const AOnText: TDropTextProc);
  end;

/// <summary>The paths held by a CF_HDROP handle.</summary>
/// <param name="ADrop">The handle; not freed here.</param>
/// <returns>The paths, in drop order.</returns>
function FilesFromHDrop(ADrop: HDROP): TArray<string>;

/// <summary>OLE-initialises once, then registers ATarget on AWnd.</summary>
/// <param name="AWnd">The window.</param>
/// <param name="ATarget">The target; the caller keeps a reference.</param>
/// <returns>False when registration failed.</returns>
function RegisterFormDropTarget(AWnd: HWND; const ATarget: IDropTarget): Boolean;

/// <summary>Revokes the target registered on AWnd.</summary>
/// <param name="AWnd">The window.</param>
procedure RevokeFormDropTarget(AWnd: HWND);

implementation

uses
  System.Classes
  ;

const
  ALL_INDEXES = -1;
  ALL_FILES   = $FFFFFFFF;

var
  GOleInitialized: Boolean = False;

function MakeFormatEtc(AFormat: TClipFormat): TFormatEtc;
begin
  Result.cfFormat:= AFormat;
  Result.ptd     := nil;
  Result.dwAspect:= DVASPECT_CONTENT;
  Result.lindex  := ALL_INDEXES;
  Result.tymed   := TYMED_HGLOBAL;
end;

function FilesFromHDrop(ADrop: HDROP): TArray<string>;
var
  Count: Integer;
  i    : Integer;
  Len  : UINT;
  Buf  : string;
begin
  Result:= nil;
  Count:= Integer(DragQueryFile(ADrop, ALL_FILES, nil, 0));
  for i:= 0 to Count - 1 do
  begin
    Len:= DragQueryFile(ADrop, UINT(i), nil, 0);
    SetLength(Buf, Len);
    DragQueryFile(ADrop, UINT(i), PChar(Buf), Len + 1);
    Result:= Result + [Buf];
  end;
end;

constructor TFormDropTarget.Create(const AOnFiles: TDropFilesProc; const AOnText: TDropTextProc);
begin
  inherited Create;
  FOnFiles:= AOnFiles;
  FOnText := AOnText;
end;

function TFormDropTarget.CanAccept(const ADataObj: IDataObject): Boolean;
var
  F: TFormatEtc;
begin
  F:= MakeFormatEtc(CF_HDROP);
  Result:= ADataObj.QueryGetData(F) = S_OK;
  if not Result then
  begin
    F:= MakeFormatEtc(CF_UNICODETEXT);
    Result:= ADataObj.QueryGetData(F) = S_OK;
  end;
end;

function TFormDropTarget.DragEnter(const dataObj: IDataObject; grfKeyState: Longint; pt: TPoint; var dwEffect: Longint): HResult;  // dl:ok unused-parameter@b10b -- IDropTarget fixes this signature; the target accepts anywhere on the form, so key state and point are not needed
begin
  if CanAccept(dataObj) then
    FEffect:= DROPEFFECT_COPY
  else
    FEffect:= DROPEFFECT_NONE;
  dwEffect:= FEffect;
  Result:= S_OK;
end;

function TFormDropTarget.DragOver(grfKeyState: Longint; pt: TPoint; var dwEffect: Longint): HResult;  // dl:ok unused-parameter@964e -- IDropTarget fixes this signature; the target accepts anywhere on the form, so key state and point are not needed
begin
  dwEffect:= FEffect;
  Result:= S_OK;
end;

function TFormDropTarget.DragLeave: HResult;
begin
  Result:= S_OK;
end;

function TFormDropTarget.Drop(const dataObj: IDataObject; grfKeyState: Longint; pt: TPoint; var dwEffect: Longint): HResult;  // dl:ok unused-parameter@1685 -- IDropTarget fixes this signature; the target accepts anywhere on the form, so key state and point are not needed
var
  F     : TFormatEtc;
  Medium: TStgMedium;
  Files : TArray<string>;
  Text  : string;
  OnF   : TDropFilesProc;
  OnT   : TDropTextProc;
begin
  Result  := S_OK;
  dwEffect:= DROPEFFECT_NONE;
  F:= MakeFormatEtc(CF_HDROP);
  if dataObj.GetData(F, Medium) = S_OK then
  begin
    try
      Files:= FilesFromHDrop(HDROP(Medium.hGlobal));
    finally
      ReleaseStgMedium(Medium);
    end;
    OnF:= FOnFiles;
    TThread.ForceQueue(nil, procedure begin OnF(Files); end);
    dwEffect:= DROPEFFECT_COPY;
    Exit;
  end;
  F:= MakeFormatEtc(CF_UNICODETEXT);
  if dataObj.GetData(F, Medium) = S_OK then
  begin
    try
      Text:= PChar(GlobalLock(Medium.hGlobal));
      GlobalUnlock(Medium.hGlobal);
    finally
      ReleaseStgMedium(Medium);
    end;
    OnT:= FOnText;
    TThread.ForceQueue(nil, procedure begin OnT(Text); end);
    dwEffect:= DROPEFFECT_COPY;
  end;
end;

function RegisterFormDropTarget(AWnd: HWND; const ATarget: IDropTarget): Boolean;
begin
  if not GOleInitialized then
    GOleInitialized:= Succeeded(OleInitialize(nil));
  Result:= RegisterDragDrop(AWnd, ATarget) = S_OK;
end;

procedure RevokeFormDropTarget(AWnd: HWND);
begin
  RevokeDragDrop(AWnd);
end;

initialization

finalization
  if GOleInitialized then
    OleUninitialize;

end.
