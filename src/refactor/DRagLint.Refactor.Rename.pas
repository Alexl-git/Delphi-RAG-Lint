unit DRagLint.Refactor.Rename;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  System.Generics.Collections, System.Generics.Defaults,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  TRenameEdit = record
    FilePath:  string;
    Line:      Integer;   // 1-based
    Col:       Integer;   // 1-based
    OldName:   string;
    NewName:   string;
  end;

  TRenameRefactoring = class
  public
    class function Build(const AStore: ISymbolStore;
      const AQName, ANewName: string): TArray<TRenameEdit>;
    class function Apply(const AEdits: TArray<TRenameEdit>;
      AWriteBackups: Boolean): Integer;  // returns files touched
    class function RenderDryRun(const AEdits: TArray<TRenameEdit>): string;
  end;

implementation

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function LastDotSegment(const S: string): string;
var
  DotPos: Integer;
begin
  DotPos := LastDelimiter('.', S);
  if DotPos > 0 then
    Result := Copy(S, DotPos + 1, MaxInt)
  else
    Result := S;
end;

// Compare two TRenameEdit values: FilePath ASC, Line DESC, Col DESC.
// Used to sort edits so we apply them back-to-front within each file,
// preventing earlier column-position shifts from invalidating later edits.
function CompareEdits(const A, B: TRenameEdit): Integer;
begin
  Result := CompareText(A.FilePath, B.FilePath);
  if Result <> 0 then Exit;
  // Same file: sort Line DESC
  Result := B.Line - A.Line;
  if Result <> 0 then Exit;
  // Same line: sort Col DESC
  Result := B.Col - A.Col;
end;

// ---------------------------------------------------------------------------
// TRenameRefactoring
// ---------------------------------------------------------------------------

class function TRenameRefactoring.Build(const AStore: ISymbolStore;
  const AQName, ANewName: string): TArray<TRenameEdit>;
var
  Syms:      TArray<TSymbol>;
  Refs:      TArray<TReference>;
  ShortName: string;
  Sym:       TSymbol;
  Ref:       TReference;
  Edit:      TRenameEdit;
  List:      TList<TRenameEdit>;
  Comparer:  IComparer<TRenameEdit>;
begin
  Result := nil;
  Syms := AStore.FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then Exit;
  Sym := Syms[0];

  ShortName := LastDotSegment(AQName);

  List := TList<TRenameEdit>.Create;
  try
    // Declaration site
    Edit.FilePath := AStore.GetFilePath(Sym.FileId);
    Edit.Line     := Sym.StartLine;
    Edit.Col      := Sym.StartCol;
    Edit.OldName  := ShortName;
    Edit.NewName  := ANewName;
    List.Add(Edit);

    // All reference sites
    Refs := AStore.FindCallersByName(ShortName);
    for Ref in Refs do
    begin
      Edit.FilePath := AStore.GetFilePath(Ref.FileId);
      Edit.Line     := Ref.StartLine;
      Edit.Col      := Ref.StartCol;
      Edit.OldName  := ShortName;
      Edit.NewName  := ANewName;
      List.Add(Edit);
    end;

    // Sort: FilePath ASC, Line DESC, Col DESC
    Comparer := TComparer<TRenameEdit>.Construct(
      function(const A, B: TRenameEdit): Integer
      begin
        Result := CompareEdits(A, B);
      end);
    List.Sort(Comparer);

    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

class function TRenameRefactoring.Apply(const AEdits: TArray<TRenameEdit>;
  AWriteBackups: Boolean): Integer;
var
  FileMap:    TDictionary<string, TList<TRenameEdit>>;
  Edit:       TRenameEdit;
  FilePath:   string;
  Group:      TList<TRenameEdit>;
  Pair:       TPair<string, TList<TRenameEdit>>;
  RawBytes:   TBytes;
  Content:    string;
  Lines:      TStringList;
  LineStr:    string;
  ColIdx:     Integer;  // 0-based index into line string
  OldLen:     Integer;
  FilesTouched: Integer;
begin
  FilesTouched := 0;
  FileMap := TDictionary<string, TList<TRenameEdit>>.Create;
  try
    // Group edits by FilePath (edits are already sorted FilePath ASC,
    // Line DESC, Col DESC, so same-file edits are consecutive).
    for Edit in AEdits do
    begin
      if not FileMap.TryGetValue(Edit.FilePath, Group) then
      begin
        Group := TList<TRenameEdit>.Create;
        FileMap.Add(Edit.FilePath, Group);
      end;
      Group.Add(Edit);
    end;

    for Pair in FileMap do
    begin
      FilePath := Pair.Key;
      Group    := Pair.Value;
      if not TFile.Exists(FilePath) then Continue;

      // Read as raw bytes, decode as ANSI.
      RawBytes := TFile.ReadAllBytes(FilePath);
      Content  := TEncoding.ANSI.GetString(RawBytes);

      // Backup before modifying if requested.
      if AWriteBackups then
        TFile.WriteAllBytes(FilePath + '.bak', RawBytes);

      // Split into lines. We preserve original line endings by splitting
      // on #10 after stripping #13, then re-joining with CRLF.
      Lines := TStringList.Create;
      try
        Lines.Text := Content;
        // Lines.Text splits on CR/LF/CRLF automatically.

        // Apply each edit in this file. They are sorted Line DESC / Col DESC
        // so later positions in the file come first, avoiding offset drift.
        for Edit in Group do
        begin
          // Convert 1-based Line to 0-based Lines index.
          if (Edit.Line < 1) or (Edit.Line > Lines.Count) then Continue;
          LineStr := Lines[Edit.Line - 1];
          // Convert 1-based Col to 0-based string index.
          ColIdx  := Edit.Col - 1;
          OldLen  := Length(Edit.OldName);
          if ColIdx < 0 then ColIdx := 0;
          // Verify the token at the expected position matches (case-insensitive).
          // If it doesn't, the parser may have stored the keyword position
          // (e.g. "function" before "Compute"). In that case, scan forward
          // on the same line for the first occurrence of OldName as a token.
          if (ColIdx + OldLen > Length(LineStr)) or
             (not SameText(Copy(LineStr, ColIdx + 1, OldLen), Edit.OldName)) then
          begin
            // Linear scan from ColIdx forward.
            var ScanPos := ColIdx;
            var Found := False;
            while ScanPos + OldLen <= Length(LineStr) do
            begin
              if SameText(Copy(LineStr, ScanPos + 1, OldLen), Edit.OldName) then
              begin
                ColIdx := ScanPos;
                Found := True;
                Break;
              end;
              Inc(ScanPos);
            end;
            if not Found then Continue;
          end;
          Lines[Edit.Line - 1] :=
            Copy(LineStr, 1, ColIdx) +
            Edit.NewName +
            Copy(LineStr, ColIdx + OldLen + 1, MaxInt);
        end;

        // Re-encode as ANSI bytes preserving CRLF.
        // TStringList.Text uses system line ending; force CRLF explicitly.
        var SB := TStringBuilder.Create;
        try
          var I: Integer;
          for I := 0 to Lines.Count - 1 do
          begin
            SB.Append(Lines[I]);
            if I < Lines.Count - 1 then
              SB.Append(#13#10);
          end;
          // Preserve trailing newline if original had one.
          if (Length(Content) > 0) and
             (Content[Length(Content)] = #10) then
            SB.Append(#13#10);
          TFile.WriteAllBytes(FilePath,
            TEncoding.ANSI.GetBytes(SB.ToString));
        finally
          SB.Free;
        end;
        Inc(FilesTouched);
      finally
        Lines.Free;
      end;
    end;
  finally
    for Pair in FileMap do
      Pair.Value.Free;
    FileMap.Free;
  end;
  Result := FilesTouched;
end;

class function TRenameRefactoring.RenderDryRun(
  const AEdits: TArray<TRenameEdit>): string;
var
  SB:       TStringBuilder;
  Edit:     TRenameEdit;
  LastFile: string;
begin
  SB := TStringBuilder.Create;
  try
    LastFile := '';
    for Edit in AEdits do
    begin
      if Edit.FilePath <> LastFile then
      begin
        SB.AppendLine('File: ' + Edit.FilePath);
        LastFile := Edit.FilePath;
      end;
      SB.AppendLine(Format('  L%d:C%d  %s -> %s',
        [Edit.Line, Edit.Col, Edit.OldName, Edit.NewName]));
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
