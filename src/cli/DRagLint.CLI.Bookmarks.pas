unit DRagLint.CLI.Bookmarks;

// ---------------------------------------------------------------------------
// The `bookmarks-strip` / `bookmarks-restore` verbs (E-BOOKMARKS phase 2, wave 147 lane G2):
// file I/O, the sidecar and the output. The text work is TBookmarks.Strip / Restore
// (DRagLint.Lint.Bookmarks). Contract: docs\wiki\bookmarks.md.
// ---------------------------------------------------------------------------

interface

/// <summary>Runs `drag-lint bookmarks-strip --in X --output S [--name C] [--apply] [--json]`.</summary>
/// <param name="pIn">--in: one unit, or a folder (every .pas below it).</param>
/// <param name="pOut">--output: the sidecar to write; required with pApply; never overwritten.</param>
/// <param name="pName">--name: strip only the anchors with this code; '' = all.</param>
/// <param name="pApply">--apply: write the sidecar, then the sources; False = dry run, writes nothing.</param>
/// <param name="pJson">--json: one JSON object on stdout.</param>
/// <returns>0 anchors found, 3 none, 1 usage (or the sidecar exists), 2 path not found.</returns>
/// <remarks>Files are read and written as raw bytes (code page 28591 maps every byte to one
/// character), so line endings, a BOM and non-ASCII bytes are kept. The sidecar is written
/// BEFORE any source, so an interrupted run can lose no anchor.</remarks>
function RunBookmarksStrip(const pIn, pOut, pName: string; pApply, pJson: Boolean): Integer;

/// <summary>Runs `drag-lint bookmarks-restore --from S [--apply] [--json]`.</summary>
/// <param name="pFrom">--from: a sidecar written by bookmarks-strip.</param>
/// <param name="pApply">--apply: write the restored files; False = dry run.</param>
/// <param name="pJson">--json: one JSON object on stdout.</param>
/// <returns>0 every anchor restored / already there, 4 one or more unplaced or a file missing,
/// 1 usage, 2 sidecar not found or unreadable.</returns>
/// <remarks>A file already equal to its original bytes is 'already'. A file with one anchor
/// that cannot be placed is not written at all: that anchor is 'unplaced', its siblings 'held'.
/// The sidecar is never deleted.</remarks>
function RunBookmarksRestore(const pFrom: string; pApply, pJson: Boolean): Integer;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  System.Generics.Collections,
  DRagLint.Lint.Bookmarks;

const
  SIDECAR_FORMAT   = 'drag-lint-bookmarks/1';
  RAW_CODEPAGE     = 28591; // ISO-8859-1: one byte <-> one character, both ways
  EXIT_USAGE       = 1;
  EXIT_NOT_FOUND   = 2;
  EXIT_NONE        = 3;
  EXIT_UNPLACED    = 4;
  ST_RESTORED      = 'restored';
  ST_ALREADY       = 'already';
  ST_UNPLACED      = 'unplaced';
  ST_HELD          = 'held';
  ST_FILE_MISSING  = 'file-missing';

function ReadRaw(const pPath: string; pEnc: TEncoding): string;
begin
  Result:= pEnc.GetString(TFile.ReadAllBytes(pPath));
end;

procedure WriteRaw(const pPath, pText: string; pEnc: TEncoding);
begin
  TFile.WriteAllBytes(pPath, pEnc.GetBytes(pText));
end;

function Sha256Of(const pText: string; pEnc: TEncoding): string;
var
  H: THashSHA2;
begin
  H:= THashSHA2.Create;  // dl:ok object-leak@a45a -- THashSHA2 is a record: Create initialises it, there is nothing to free
  H.Update(pEnc.GetBytes(pText));
  Result:= H.HashAsString;
end;

procedure Fail(pJson: Boolean; const pReason, pMessage: string);
var
  J: TJSONObject;
begin
  if pJson then
  begin
    J:= TJSONObject.Create;
    try
      J.AddPair('error', pReason);
      J.AddPair('message', pMessage);
      Writeln(J.ToJSON);
    finally
      J.Free;
    end;
  end
  else
    Writeln(ErrOutput, pMessage);
end;

function EditToJson(const pEdit: TBookmarkEdit): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('line', TJSONNumber.Create(pEdit.Line));
  Result.AddPair('strippedLine', TJSONNumber.Create(pEdit.StrippedLine));
  Result.AddPair('col', TJSONNumber.Create(pEdit.Col));
  Result.AddPair('mode', pEdit.Mode);
  Result.AddPair('text', pEdit.Text);
  Result.AddPair('anchor', pEdit.Anchor);
  Result.AddPair('anchorEof', TJSONBool.Create(pEdit.AnchorEof));
  Result.AddPair('kind', pEdit.Bookmark.Kind);
  Result.AddPair('code', pEdit.Bookmark.Code);
  Result.AddPair('hash', pEdit.Bookmark.Hash);
  Result.AddPair('reason', pEdit.Bookmark.Reason);
end;

function EditFromJson(const pObj: TJSONObject): TBookmarkEdit;
begin
  Result:= Default(TBookmarkEdit);
  Result.Line           := pObj.GetValue<Integer>('line');
  Result.StrippedLine   := pObj.GetValue<Integer>('strippedLine');
  Result.Col            := pObj.GetValue<Integer>('col');
  Result.Mode           := pObj.GetValue<string>('mode');
  Result.Text           := pObj.GetValue<string>('text');
  Result.Anchor         := pObj.GetValue<string>('anchor');
  Result.AnchorEof      := pObj.GetValue<Boolean>('anchorEof');
  Result.Bookmark.Line  := Result.Line;
  Result.Bookmark.Kind  := pObj.GetValue<string>('kind');
  Result.Bookmark.Code  := pObj.GetValue<string>('code');
  Result.Bookmark.Hash  := pObj.GetValue<string>('hash');
  Result.Bookmark.Reason:= pObj.GetValue<string>('reason');
end;

function RunBookmarksStrip(const pIn, pOut, pName: string; pApply, pJson: Boolean): Integer;
var
  Enc: TEncoding;
  Files: TArray<string>;
  F, FullPath, Txt, Stripped: string;
  Edits: TArray<TBookmarkEdit>;
  E: TBookmarkEdit;
  Changed: TDictionary<string, string>;
  Side, FileObj, Row, Report: TJSONObject;
  SideFiles, EditArr, Rows: TJSONArray;
  FileCount, Count: Integer;
begin
  if pIn = '' then
  begin
    Fail(pJson, 'usage', 'Usage: drag-lint bookmarks-strip --in <file.pas|dir> --output <sidecar.json> [--name <code>] [--apply] [--json]');
    Exit(EXIT_USAGE);
  end;
  if pApply and (pOut = '') then
  begin
    Fail(pJson, 'usage', 'error: --apply needs --output <sidecar.json>: the sidecar is what bookmarks-restore reads');
    Exit(EXIT_USAGE);
  end;
  if (pOut <> '') and FileExists(pOut) then
  begin
    Fail(pJson, 'sidecar-exists', 'error: sidecar exists, never overwritten (restore or move it first): ' + pOut);
    Exit(EXIT_USAGE);
  end;
  if TDirectory.Exists(pIn) then
    Files:= TDirectory.GetFiles(pIn, '*.pas', TSearchOption.soAllDirectories)
  else if FileExists(pIn) then
    Files:= [pIn]
  else
  begin
    Fail(pJson, 'not-found', 'error: path not found: ' + pIn);
    Exit(EXIT_NOT_FOUND);
  end;
  Enc    := TEncoding.GetEncoding(RAW_CODEPAGE);
  Changed:= TDictionary<string, string>.Create;
  Side   := TJSONObject.Create;
  Report := TJSONObject.Create;
  Rows   := TJSONArray.Create;
  try
    SideFiles:= TJSONArray.Create;
    Side.AddPair('format', SIDECAR_FORMAT);
    Side.AddPair('created', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));
    Side.AddPair('files', SideFiles);
    FileCount:= 0;
    Count    := 0;
    for F in Files do
    begin
      FullPath:= TPath.GetFullPath(F);
      Txt     := ReadRaw(FullPath, Enc);
      Stripped:= TBookmarks.Strip(Txt, pName, Edits);
      if Length(Edits) = 0 then Continue;
      Inc(FileCount);
      Changed.Add(FullPath, Stripped);
      FileObj:= TJSONObject.Create;
      FileObj.AddPair('path', FullPath);
      FileObj.AddPair('originalSha256', Sha256Of(Txt, Enc));
      FileObj.AddPair('strippedSha256', Sha256Of(Stripped, Enc));
      EditArr:= TJSONArray.Create;
      for E in Edits do
      begin
        Inc(Count);
        EditArr.AddElement(EditToJson(E));
        Row:= TJSONObject.Create;
        Row.AddPair('file', FullPath);
        Row.AddPair('line', TJSONNumber.Create(E.Line));
        Row.AddPair('kind', E.Bookmark.Kind);
        Row.AddPair('code', E.Bookmark.Code);
        Row.AddPair('hash', E.Bookmark.Hash);
        Row.AddPair('reason', E.Bookmark.Reason);
        Row.AddPair('mode', E.Mode);
        Rows.AddElement(Row);
        if not pJson then
          Writeln(Format('%s:%d  %s  %s  %s  %s', [FullPath, E.Line, E.Bookmark.Kind, E.Bookmark.Code, E.Mode,
            if pApply then 'stripped' else 'would strip']));
      end;
      FileObj.AddPair('edits', EditArr);
      SideFiles.AddElement(FileObj);
    end;
    if pApply and (Count > 0) then
    begin
      { the sidecar first: once it is on disk no source write can lose an anchor }
      TFile.WriteAllBytes(pOut, TEncoding.UTF8.GetBytes(Side.ToJSON));
      for F in Changed.Keys do WriteRaw(F, Changed[F], Enc);
    end;
    if pJson then
    begin
      Report.AddPair('verb', 'bookmarks-strip');
      Report.AddPair('apply', TJSONBool.Create(pApply));
      Report.AddPair('sidecar', if pApply and (Count > 0) then TPath.GetFullPath(pOut) else '');
      Report.AddPair('files', TJSONNumber.Create(FileCount));
      Report.AddPair('count', TJSONNumber.Create(Count));
      Report.AddPair('bookmarks', Rows);
      Rows:= nil;
      Writeln(Report.ToJSON);
    end
    else
      Writeln(Format('%d anchor(s) in %d file(s)%s', [Count, FileCount,
        if pApply then (if Count > 0 then '; sidecar ' + pOut else '') else ' (dry run, pass --apply to write)']));
    Result:= if Count > 0 then 0 else EXIT_NONE;
  finally
    Rows.Free;
    Report.Free;
    Side.Free;
    Changed.Free;
    Enc.Free;
  end;
end;

function RunBookmarksRestore(const pFrom: string; pApply, pJson: Boolean): Integer;
var
  Enc: TEncoding;
  Root: TJSONValue;
  FileVal, EditVal: TJSONValue;
  FileObj, Row, Report: TJSONObject;
  Rows: TJSONArray;
  Edits: TArray<TBookmarkEdit>;
  Lines: TArray<Integer>;
  Path, Cur, Restored, Status: string;
  K, Placed, NRestored, NAlready, NUnplaced: Integer;
  Missing, Already, AllPlaced: Boolean;
begin
  if pFrom = '' then
  begin
    Fail(pJson, 'usage', 'Usage: drag-lint bookmarks-restore --from <sidecar.json> [--apply] [--json]');
    Exit(EXIT_USAGE);
  end;
  if not FileExists(pFrom) then
  begin
    Fail(pJson, 'not-found', 'error: sidecar not found: ' + pFrom);
    Exit(EXIT_NOT_FOUND);
  end;
  Root:= TJSONObject.ParseJSONValue(TFile.ReadAllText(pFrom, TEncoding.UTF8));
  if (Root is not TJSONObject) or (TJSONObject(Root).GetValue<string>('format', '') <> SIDECAR_FORMAT) then
  begin
    Root.Free;
    Fail(pJson, 'bad-sidecar', 'error: not a ' + SIDECAR_FORMAT + ' sidecar: ' + pFrom);
    Exit(EXIT_NOT_FOUND);
  end;
  Enc   := TEncoding.GetEncoding(RAW_CODEPAGE);
  Report:= TJSONObject.Create;
  Rows  := TJSONArray.Create;
  try
    NRestored:= 0;
    NAlready := 0;
    NUnplaced:= 0;
    for FileVal in TJSONObject(Root).GetValue<TJSONArray>('files') do
    begin
      FileObj:= FileVal as TJSONObject;
      Path   := FileObj.GetValue<string>('path');
      Edits  := [];
      for EditVal in FileObj.GetValue<TJSONArray>('edits') do Edits:= Edits + [EditFromJson(EditVal as TJSONObject)];
      Missing  := not FileExists(Path);
      Already  := False;
      AllPlaced:= False;
      Lines    := [];
      if not Missing then
      begin
        Cur:= ReadRaw(Path, Enc);
        Already:= Sha256Of(Cur, Enc) = FileObj.GetValue<string>('originalSha256');
        if not Already then
        begin
          Restored := TBookmarks.Restore(Cur, Edits, Lines);
          Placed   := 0;
          for K:= 0 to High(Lines) do
            if Lines[K] > 0 then Inc(Placed);
          AllPlaced:= Placed = Length(Edits);
          if AllPlaced and pApply then WriteRaw(Path, Restored, Enc);
        end;
      end;
      for K:= 0 to High(Edits) do
      begin
        Status:= if Missing then ST_FILE_MISSING
          else if Already then ST_ALREADY
          else if AllPlaced then ST_RESTORED
          else if Lines[K] = 0 then ST_UNPLACED
          else ST_HELD;
        if Status = ST_RESTORED then Inc(NRestored)
        else if Status = ST_ALREADY then Inc(NAlready)
        else if Status <> ST_HELD then Inc(NUnplaced);
        Row:= TJSONObject.Create;
        Row.AddPair('file', Path);
        Row.AddPair('line', TJSONNumber.Create(if Status = ST_RESTORED then Lines[K] else if Status = ST_ALREADY then Edits[K].Line else 0));
        Row.AddPair('kind', Edits[K].Bookmark.Kind);
        Row.AddPair('code', Edits[K].Bookmark.Code);
        Row.AddPair('mode', Edits[K].Mode);
        Row.AddPair('status', Status);
        Rows.AddElement(Row);
        if not pJson then
          Writeln(Format('%s:%d  %s  %s  %s', [Path, Row.GetValue<Integer>('line'), Edits[K].Bookmark.Kind,
            Edits[K].Bookmark.Code, if (Status = ST_RESTORED) and not pApply then 'would restore' else Status]));
      end;
    end;
    if pJson then
    begin
      Report.AddPair('verb', 'bookmarks-restore');
      Report.AddPair('apply', TJSONBool.Create(pApply));
      Report.AddPair('sidecar', TPath.GetFullPath(pFrom));
      Report.AddPair('restored', TJSONNumber.Create(NRestored));
      Report.AddPair('already', TJSONNumber.Create(NAlready));
      Report.AddPair('unplaced', TJSONNumber.Create(NUnplaced));
      Report.AddPair('bookmarks', Rows);
      Rows:= nil;
      Writeln(Report.ToJSON);
    end
    else
      Writeln(Format('%d restored, %d already, %d unplaced%s', [NRestored, NAlready, NUnplaced,
        if pApply then '' else ' (dry run, pass --apply to write)']));
    Result:= if NUnplaced > 0 then EXIT_UNPLACED else 0;
  finally
    Rows.Free;
    Report.Free;
    Enc.Free;
    Root.Free;
  end;
end;

end.
