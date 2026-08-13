unit DRagLint.Lint.SharedUnit;

{ The `dl:shared` unit marker: a unit compiled by more than one project says so
  in its own source.

    unit YADF.Options;   // dl:shared YADF, YADFOT, YADFSetup

  WHY A MARKER AND NOT DERIVATION. `resolve-dbs --in <file>` answers with the
  OWNING database, one path -- measured 2026-08-13, it returns only YADF.sqlite
  for a unit that YADFOT.dproj and YADFSetup.dproj also compile. Deriving the SET
  would mean opening every index in the manifest on every run, to learn a fact
  that changes about once a year.

  WHY THE PROJECT LIST IS IN THE MARKER. It is not needed by the staleness rule,
  which only asks "is this unit shared". It is there so the blast radius is
  readable in the source without running the tool -- the case that motivated the
  whole feature -- and so `check-shared` can verify the claim instead of trusting
  it. A marker nobody checks decays into a lie, and this one decides staleness. }

interface

uses
  System.SysUtils;

type
  TSharedUnit = class
  public
    /// <summary>True when the unit carries a `dl:shared` marker.</summary>
    /// <remarks>Scans the unit's HEADER REGION, not line 1 alone: line 1 of a
    /// unit here is frequently the `{` of a block comment, which is the same
    /// anchoring trap already recorded for unit-too-large and
    /// compiler-magic-comments.</remarks>
    class function IsShared(const AUnitPath: string): Boolean;

    /// <summary>The project names listed on the marker, in written order.</summary>
    /// <remarks>Returns an empty array if the unit is not marked.</remarks>
    class function ProjectsOf(const AUnitPath: string): TArray<string>;

    /// <summary>Adds AProject to the marker, creating the marker when absent.</summary>
    /// <returns>False when AProject is already listed -- an idempotent no-op, so
    /// the IDE menu item is safe to press twice.</returns>
    /// <remarks>Returns the new text with the marker added or updated; caller is
    /// responsible for writing it to disk with --apply.</remarks>
    class function AddProject(const AUnitPath, AProject: string; out ANewText: string): Boolean;
  private
    /// <summary>Scan the header region of the file (from start to first 'interface'
    /// keyword) and find the `dl:shared` marker.</summary>
    /// <returns>The text after 'dl:shared' on the line where it was found, or ''
    /// if not found. This is the part that contains the project list.</returns>
    class function FindMarkerContent(const AFileText: string): string;

    /// <summary>Parse the project list from the marker content.</summary>
    class function ParseProjects(const AMarkerContent: string): TArray<string>;

    /// <summary>Format the marker with a project list.</summary>
    class function FormatMarker(const AProjects: TArray<string>): string;

    /// <summary>Read the entire file as ASCII text.</summary>
    class function ReadFileAsText(const AFilePath: string): string;
  end;

const
  /// <summary>The marker tag that identifies a shared unit.</summary>
  SHARED_MARK = 'dl:shared';

implementation

class function TSharedUnit.ReadFileAsText(const AFilePath: string): string;
begin
  if not FileExists(AFilePath) then
    raise EFileNotFound.CreateFmt('File not found: %s', [AFilePath]);
  Result := TFile.ReadAllText(AFilePath, TEncoding.ASCII);
end;

class function TSharedUnit.FindMarkerContent(const AFileText: string): string;
var
  Lines: TArray<string>;
  I: Integer;
  Line: string;
  MarkerPos: Integer;
  TrimmedLine: string;
begin
  Result := '';
  Lines := AFileText.Split([#13#10]);

  for I := 0 to High(Lines) do
  begin
    Line := Lines[I];
    TrimmedLine := Trim(Line);

    { Stop at the 'interface' keyword (case-insensitive) }
    if UpCase(TrimmedLine).StartsWith('INTERFACE') then
      Exit;

    { Look for the marker in a line comment }
    MarkerPos := Pos('//', Line);
    if MarkerPos > 0 then
    begin
      Line := Copy(Line, MarkerPos + 2, MaxInt);
      MarkerPos := Pos(SHARED_MARK, UpCase(Line));
      if MarkerPos > 0 then
      begin
        Result := Trim(Copy(Line, MarkerPos + Length(SHARED_MARK), MaxInt));
        Exit;
      end;
    end;
  end;
end;

class function TSharedUnit.ParseProjects(const AMarkerContent: string): TArray<string>;
var
  Parts: TArray<string>;
  I: Integer;
begin
  Result := nil;
  if AMarkerContent = '' then Exit;

  { Split on ',' to get project list (before any '--' separator for reasons) }
  Parts := AMarkerContent.Split([',', '-']);
  for I := 0 to High(Parts) do
  begin
    { Stop at the '--' separator }
    if Parts[I].Trim.StartsWith('-') then
      Break;

    Parts[I] := Parts[I].Trim;
    if Parts[I] <> '' then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Parts[I];
    end;
  end;
end;

class function TSharedUnit.FormatMarker(const AProjects: TArray<string>): string;
var
  I: Integer;
begin
  Result := SHARED_MARK + ' ';
  for I := 0 to High(AProjects) do
  begin
    if I > 0 then Result := Result + ', ';
    Result := Result + AProjects[I];
  end;
end;

class function TSharedUnit.IsShared(const AUnitPath: string): Boolean;
begin
  Result := FindMarkerContent(ReadFileAsText(AUnitPath)) <> '';
end;

class function TSharedUnit.ProjectsOf(const AUnitPath: string): TArray<string>;
begin
  Result := ParseProjects(FindMarkerContent(ReadFileAsText(AUnitPath)));
end;

class function TSharedUnit.AddProject(const AUnitPath, AProject: string;
  out ANewText: string): Boolean;
var
  Content: string;
  MarkerContent: string;
  Projects: TArray<string>;
  AlreadyExists: Boolean;
  I: Integer;
  NewProjects: TArray<string>;
  Lines: TArray<string>;
  J: Integer;
  Line: string;
  MarkerPos: Integer;
  NewLine: string;
begin
  { Result = True means the project was added (not already there)
    Result = False means the project was already listed (idempotent no-op) }

  Content := ReadFileAsText(AUnitPath);
  MarkerContent := FindMarkerContent(Content);
  Projects := ParseProjects(MarkerContent);

  { Check if project already exists }
  AlreadyExists := False;
  for I := 0 to High(Projects) do
  begin
    if SameText(Projects[I], AProject) then
    begin
      AlreadyExists := True;
      Break;
    end;
  end;

  if AlreadyExists then
  begin
    Result := False;
    ANewText := Content;
    Exit;
  end;

  { Add the project to the list }
  SetLength(NewProjects, Length(Projects) + 1);
  for I := 0 to High(Projects) do
    NewProjects[I] := Projects[I];
  NewProjects[High(NewProjects)] := AProject;

  { Replace the marker in the file }
  Lines := Content.Split([#13#10]);
  for J := 0 to High(Lines) do
  begin
    Line := Lines[J];
    if Pos('//', Line) > 0 then
    begin
      MarkerPos := Pos(UpCase(SHARED_MARK), UpCase(Line));
      if MarkerPos > 0 then
      begin
        { Found the marker line, replace it }
        NewLine := Copy(Line, 1, Pos('//', Line) + 1) + ' ' + FormatMarker(NewProjects);
        Lines[J] := NewLine;
        Break;
      end;
    end;

    { If no marker found yet and we reached 'interface', we need to insert before it }
    if UpCase(Trim(Line)).StartsWith('INTERFACE') then
    begin
      if MarkerPos = 0 then
      begin
        { Insert marker before interface }
        NewLine := 'unit' + Trim(Copy(Line, 1, Pos(' ', Line) - 1));
        { Find the unit line and add marker there }
        for var K := 0 to J - 1 do
        begin
          if UpCase(Trim(Lines[K])).StartsWith('UNIT ') then
          begin
            Lines[K] := TrimRight(Lines[K]) + '   // ' + FormatMarker(NewProjects);
            Break;
          end;
        end;
      end;
      Break;
    end;
  end;

  ANewText := string.Join(#13#10, Lines);
  Result := True;
end;

end.