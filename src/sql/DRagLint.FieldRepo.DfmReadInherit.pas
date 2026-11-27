unit DRagLint.FieldRepo.DfmReadInherit;

{ drag-lint 1.56 -- lane ANCDFM: follows a dataset name into the ancestor data module or form DFM at read time.
  A DFM whose root is `inherited Name: TClass` holds only what it changes; the rest of a dataset (TableName, SQL, the
  persistent fields) is in the DFM of the ancestor class. The ancestor class comes from the unit beside the DFM
  (`TClass = class(TAncestor)`), the ancestor DFM is the ONE DFM of the same folder whose root class is TAncestor.
  No DFM, two DFMs, no unit or no class declaration = not followed, with a note that names the reason (never a pick).
  Limits: an ancestor form in another folder is not found; a property an inherited field overrides is not applied to
  the ancestor's field; a property the descendant resets to '' reads as the ancestor's value.
  Files are only READ. Lane ANCDFM owns this unit; the stub was created by lane FRAME-1.

  1.56 GCR-2: IDfmrModuleFinder finds the DFM of a module (`dmX` of `dmX.tblY`) that is NOT in the folder of the form.
  The form's unit must use the module's unit; the DFM of that unit is looked for in the project folder (the nearest
  folder, from the form's folder up to MODULE_LEVELS levels above it, that holds a project file; the form's own folder
  when none does) and every folder below it, except folders whose name starts with `__` or `.` (__history,
  __recovery, backups). One DFM with that root object = found; two = a note, nothing picked. A module outside the
  project folder (a search-path folder elsewhere) is not found. }

interface

uses
  DRagLint.FieldRepo.DfmRead;

type
  /// <summary>Loads (or returns from the caller's cache) the parsed DFM of a file.</summary>
  /// <remarks>May raise EDfmReadError; the ancestry catches it and notes the file as not read.</remarks>
  TDfmrFormLoader = reference to function(const pFile: string): TDfmrForm;

  /// <summary>The first object line of a DFM.</summary>
  TDfmrRootHead = record
    /// <summary>object, inherited or inline, lower case; '' = the file has no readable root.</summary>
    Kind: string;
    /// <summary>Root object name.</summary>
    Name: string;
    /// <summary>Root object class.</summary>
    RootClass: string;
  end;

  /// <summary>Resolves datasets through the ancestor DFM chain of a form; caches what it read.</summary>
  /// <remarks>Not thread-safe: one instance per read, used from one thread. Holds no file open.</remarks>
  IDfmrAncestry = interface
    ['{6C0B6C0E-6B5B-4D6F-9A40-2B0F5F4E7C31}']
    /// <summary>The DFM of the ancestor class of a DFM whose root is `inherited`.</summary>
    /// <param name="pFile">Path of a DFM.</param>
    /// <returns>Full path of the ancestor's DFM; '' when the root is not `inherited` or the ancestor is not found
    /// (the reason is then in Notes, once per file).</returns>
    function AncestorFile(const pFile: string): string;
    /// <summary>The dataset of a form as the form has it at run time: declared in its own DFM, or declared in an
    /// ancestor's DFM and completed with what the descendants change.</summary>
    /// <param name="pForm">The form (its FileName finds the ancestors).</param>
    /// <param name="pName">Dataset component name, case-insensitive.</param>
    /// <param name="pDataset">The dataset; an `inherited` one whose ancestor is not found is returned as its own DFM
    /// states it.</param>
    /// <returns>True when the form or one of its ancestors has the dataset.</returns>
    function FindDataset(const pForm: TDfmrForm; const pName: string; out pDataset: TDfmrDataset): Boolean;
    /// <summary>What was followed and what could not be, one line each, in the order found, no line twice.</summary>
    /// <returns>The notes; empty when no inherited form was met.</returns>
    function Notes: TArray<string>;
  end;

  /// <summary>Finds the DFM of a form or data module a form names (`dmX` of `dmX.tblY`) outside the form's own
  /// folder; caches the folders and units it read (1.56 GCR-2).</summary>
  /// <remarks>Not thread-safe: one instance per read, used from one thread. Files are only read; no file is held
  /// open.</remarks>
  IDfmrModuleFinder = interface
    ['{8CA3F4AE-9B5F-431F-A00E-84E3F87FFB93}']
    /// <summary>The DFM whose root object is pRoot, among the DFMs of the units the form's unit uses.</summary>
    /// <param name="pDfm">Path of the form's DFM; the unit of the same name beside it gives the used units.</param>
    /// <param name="pRoot">Root object name of the module, case-insensitive.</param>
    /// <returns>Full path of the one such DFM in the project folder tree (see the unit header); '' when the form has
    /// no unit, uses no unit with such a DFM, or two DFMs qualify (then a note names them: never a pick).</returns>
    function ModuleFile(const pDfm, pRoot: string): string;
    /// <summary>One line per module that was not picked because two DFMs qualify, in the order found, no line
    /// twice.</summary>
    /// <returns>The notes; empty when nothing was ambiguous.</returns>
    function Notes: TArray<string>;
  end;

/// <summary>Reads the first object line of a text or binary DFM without parsing the file.</summary>
/// <param name="pFile">Path of a DFM.</param>
/// <returns>Kind, name and class of the root; all '' when the file is missing, unreadable or holds no object.</returns>
function ReadDfmRootHead(const pFile: string): TDfmrRootHead;

/// <summary>The ancestor class a unit declares for a class: `TClass = class(TAncestor, ...)`.</summary>
/// <param name="pUnitText">Unit source; comments and strings are not read.</param>
/// <param name="pClass">Class name, case-insensitive.</param>
/// <returns>The ancestor's bare name (unit qualifier and type arguments removed); '' when the unit does not declare
/// the class with an ancestor.</returns>
function AncestorClassOf(const pUnitText, pClass: string): string;

/// <summary>An `inherited` dataset completed from its ancestor's.</summary>
/// <param name="pOwn">The dataset as the descendant DFM states it.</param>
/// <param name="pAncestor">The same dataset of the ancestor.</param>
/// <returns>The ancestor's dataset with pOwn's name, class and kind; UpdateTableName, TableName, Sql, OnCalcFields
/// and AttachedTo are pOwn's where pOwn states one; Fields = the ancestor's, then the fields pOwn adds;
/// InheritedFields = pOwn's overridden fields the ancestor does not have.</returns>
function MergeInherited(const pOwn, pAncestor: TDfmrDataset): TDfmrDataset;

/// <summary>The units a unit names in its uses clauses, interface and implementation.</summary>
/// <param name="pUnitText">Unit source; comments, strings (the path of `in '...'`) and directives are not read, so a
/// unit inside a conditional block counts.</param>
/// <returns>The unit names as written (`System.Classes`, `uMod`), in source order.</returns>
function UsedUnitsOf(const pUnitText: string): TArray<string>;  // dl:ok unused-public-symbol@89f9 -- REVIEWED 2026-11-27 GCR-2: tested on its own by tests/fieldrepo/DfmReadGcr2Tests.dpr (M1, M2), which is outside this project index

/// <summary>A new module finder.</summary>
/// <returns>The finder.</returns>
function NewDfmrModuleFinder: IDfmrModuleFinder;

/// <summary>A new ancestry over a form loader.</summary>
/// <param name="pLoad">Loads a DFM; must not be nil. The ancestry keeps the reference, not the forms.</param>
/// <returns>The ancestry.</returns>
function NewDfmrAncestry(const pLoad: TDfmrFormLoader): IDfmrAncestry;

implementation

uses
  Winapi.Windows, // FileClose is inline: without the unit it is not expanded (H2443)
  System.SysUtils,
  System.IOUtils,
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  DRagLint.FieldRepo.HandlersRegions;

const
  KIND_INHERITED = 'inherited';
  KIND_INLINE = 'inline';
  KIND_OBJECT = 'object';
  EXT_PAS = '.pas';
  DFM_MASK = '*.dfm';
  { A text root line, a BOM or blank lines before it. }
  PAT_TEXT_HEAD = '^[^A-Za-z]{0,8}(object|inherited|inline)\s+(?:(\w+)\s*:\s*)?(\w+)';
  GROUP_KIND = 1;
  GROUP_NAME = 2;
  GROUP_CLASS = 3;
  { `TClass = class [abstract|sealed] (TAncestor`; %s = the escaped class name. }
  PAT_CLASS_DECL = '(?<![\w.])%s\s*=\s*class\s*(?:abstract\s*|sealed\s*)?\(\s*([\w.]+)';
  SIGNATURE = 'TPF0';
  HEAD_BYTES = 1024; // root line of a text DFM, or resource header + signature + class + name of a binary one
  PREFIX_MASK = $F0; // a binary object starts with this nibble when it carries flags
  FLAG_MASK = $0F;
  FLAG_INHERITED = 1;
  FLAG_CHILD_POS = 2;
  FLAG_INLINE = 4;
  VA_INT8 = 2;  // TValueType of the child position that follows the flags
  VA_INT16 = 3;
  VA_INT32 = 4;
  SIZE_INT8 = 1;
  SIZE_INT16 = 2;
  SIZE_INT32 = 4;
  MAX_CHAIN = 32; // ancestor levels followed; more is a cycle
  EXT_DFM = '.dfm';
  PROJECT_MASKS: array[0..2] of string = ('*.dpr', '*.dproj', '*.dpk');
  MODULE_LEVELS = 3; // folders above the form's that may hold the project file
  SKIP_PREFIXES: array[0..1] of string = ('__', '.'); // __history, __recovery, backups; .git and the like
  { One uses clause of blanked source: the names up to the semicolon. }
  PAT_USES = '(?<![\w.])uses\b([^;]*);';
  PAT_UNIT_NAME = '^\s*([A-Za-z_][\w.]*)';

type
  TRootEntry = record
    FileName: string;
    RootClass: string;
  end;

  TDfmrAncestry = class(TInterfacedObject, IDfmrAncestry)
  private
    FLoad: TDfmrFormLoader;
    FAncestors: TDictionary<string, string>;         // lower DFM path -> ancestor DFM path, '' = none
    FFolders: TDictionary<string, TArray<TRootEntry>>; // lower folder -> root class of each DFM in it
    FNotes: TList<string>;
    procedure Note(const pText: string);
    function Roots(const pFolder: string): TArray<TRootEntry>;
    function ResolveAncestor(const pFile: string): string;
    function LoadForm(const pFile: string; out pForm: TDfmrForm): Boolean;
    function Find(const pForm: TDfmrForm; const pName: string; pDepth: Integer; out pDataset: TDfmrDataset): Boolean;
  public
    constructor Create(const pLoad: TDfmrFormLoader);
    destructor Destroy; override;
    function AncestorFile(const pFile: string): string;
    function FindDataset(const pForm: TDfmrForm; const pName: string; out pDataset: TDfmrDataset): Boolean;
    function Notes: TArray<string>;
  end;

  TDfmrModuleFinder = class(TInterfacedObject, IDfmrModuleFinder)
  private
    FTrees: TDictionary<string, TArray<string>>; // lower project folder -> every DFM in and below it
    FUses: TDictionary<string, TArray<string>>;  // lower DFM path -> units its unit uses
    FNotes: TList<string>;
    function ProjectFolder(const pFolder: string): string;
    procedure Collect(const pFolder: string; var pFiles: TArray<string>);
    function Tree(const pFolder: string): TArray<string>;
    function UsedBy(const pDfm: string): TArray<string>;
  public
    constructor Create;
    destructor Destroy; override;
    function ModuleFile(const pDfm, pRoot: string): string;
    function Notes: TArray<string>;
  end;

{ The first bytes of a file, one Char per byte; '' when it cannot be read. }
function HeadOf(const pFile: string): string;
var
  VHandle: THandle;
  VBytes: TBytes;
  VCount, VI: Integer;
begin
  Result := '';
  VHandle := FileOpen(pFile, fmOpenRead or fmShareDenyNone);
  if VHandle = INVALID_HANDLE_VALUE then
    Exit;
  try
    SetLength(VBytes, HEAD_BYTES);
    VCount := FileRead(VHandle, VBytes[0], HEAD_BYTES);
  finally
    FileClose(VHandle);
  end;
  if VCount <= 0 then
    Exit;
  SetLength(Result, VCount);
  for VI := 0 to VCount - 1 do
    Result[VI + 1] := Char(VBytes[VI]);
end;

{ The length-prefixed string at pPos of a binary DFM head; pPos moves behind it. '' when the head ends first. }
function ShortAt(const pHead: string; var pPos: Integer): string;
var
  VLen: Integer;
begin
  Result := '';
  if pPos > Length(pHead) then
    Exit;
  VLen := Ord(pHead[pPos]);
  if pPos + VLen > Length(pHead) then
    Exit;
  Result := Copy(pHead, pPos + 1, VLen);
  Inc(pPos, VLen + 1);
end;

function BinaryHead(const pHead: string): TDfmrRootHead;
var
  VPos, VFlags, VType: Integer;
begin
  Result := Default(TDfmrRootHead);
  VPos := Pos(SIGNATURE, pHead);
  if VPos = 0 then
    Exit;
  Inc(VPos, Length(SIGNATURE));
  if VPos > Length(pHead) then
    Exit;
  VFlags := 0;
  if Ord(pHead[VPos]) and PREFIX_MASK = PREFIX_MASK then
  begin
    VFlags := Ord(pHead[VPos]) and FLAG_MASK;
    Inc(VPos);
    if (VFlags and FLAG_CHILD_POS <> 0) and (VPos <= Length(pHead)) then
    begin
      VType := Ord(pHead[VPos]);
      Inc(VPos, 1 + (if VType = VA_INT8 then SIZE_INT8 else if VType = VA_INT16 then SIZE_INT16
        else if VType = VA_INT32 then SIZE_INT32 else 0));
    end;
  end;
  Result.RootClass := ShortAt(pHead, VPos);
  Result.Name := ShortAt(pHead, VPos);
  if Result.RootClass = '' then
    Exit(Default(TDfmrRootHead));
  Result.Kind := if VFlags and FLAG_INHERITED <> 0 then KIND_INHERITED
    else if VFlags and FLAG_INLINE <> 0 then KIND_INLINE else KIND_OBJECT;
end;

function ReadDfmRootHead(const pFile: string): TDfmrRootHead;
var
  VHead: string;
  VMatch: TMatch;
begin
  Result := Default(TDfmrRootHead);
  VHead := HeadOf(pFile);
  if VHead = '' then
    Exit;
  VMatch := TRegEx.Match(VHead, PAT_TEXT_HEAD, [roIgnoreCase]);
  if not VMatch.Success then
    Exit(BinaryHead(VHead));
  Result.Kind := LowerCase(VMatch.Groups[GROUP_KIND].Value);
  Result.Name := VMatch.Groups[GROUP_NAME].Value;
  Result.RootClass := VMatch.Groups[GROUP_CLASS].Value;
end;

function AncestorClassOf(const pUnitText, pClass: string): string;
var
  VMatch: TMatch;
begin
  Result := '';
  if (pUnitText = '') or (pClass = '') then
    Exit;
  VMatch := TRegEx.Match(ScanPascal(pUnitText).Code, Format(PAT_CLASS_DECL, [TRegEx.Escape(pClass)]), [roIgnoreCase]);
  if not VMatch.Success then
    Exit;
  Result := VMatch.Groups[1].Value;
  Result := Result.Substring(Result.LastIndexOf('.') + 1);
end;

function HasField(const pFields: TArray<TDfmrField>; const pCompName: string): Boolean;
var
  VField: TDfmrField;
begin
  Result := False;
  for VField in pFields do
    if SameText(VField.CompName, pCompName) then
      Exit(True);
end;

function MergeInherited(const pOwn, pAncestor: TDfmrDataset): TDfmrDataset;
var
  VField: TDfmrField;
  VName: string;
begin
  Result := pAncestor;
  Result.Name := pOwn.Name;
  Result.ObjKind := pOwn.ObjKind;
  if pOwn.DatasetClass <> '' then
    Result.DatasetClass := pOwn.DatasetClass;
  if pOwn.UpdateTableName <> '' then
    Result.UpdateTableName := pOwn.UpdateTableName;
  if pOwn.TableName <> '' then
    Result.TableName := pOwn.TableName;
  if pOwn.Sql <> '' then
    Result.Sql := pOwn.Sql;
  if pOwn.OnCalcFields <> '' then
    Result.OnCalcFields := pOwn.OnCalcFields;
  if pOwn.AttachedTo <> '' then
    Result.AttachedTo := pOwn.AttachedTo;
  for VField in pOwn.Fields do
    if not HasField(pAncestor.Fields, VField.CompName) then
      Result.Fields := Result.Fields + [VField];
  Result.InheritedFields := nil;
  for VName in pOwn.InheritedFields do
    if not HasField(pAncestor.Fields, VName) then
      Result.InheritedFields := Result.InheritedFields + [VName];
end;

function UsedUnitsOf(const pUnitText: string): TArray<string>;
var
  VClause, VName: TMatch;
  VPart: string;
begin
  Result := nil;
  if pUnitText = '' then
    Exit;
  for VClause in TRegEx.Matches(ScanPascal(pUnitText).Code, PAT_USES, [roIgnoreCase]) do
    for VPart in VClause.Groups[1].Value.Split([',']) do
    begin
      VName := TRegEx.Match(VPart, PAT_UNIT_NAME);
      if VName.Success then
        Result := Result + [VName.Groups[1].Value];
    end;
end;

function NewDfmrModuleFinder: IDfmrModuleFinder;
begin
  Result := TDfmrModuleFinder.Create;
end;

{ TDfmrModuleFinder }

constructor TDfmrModuleFinder.Create;
begin
  inherited Create;
  FTrees := TDictionary<string, TArray<string>>.Create;
  FUses := TDictionary<string, TArray<string>>.Create;
  FNotes := TList<string>.Create;
end;

destructor TDfmrModuleFinder.Destroy;
begin
  FNotes.Free;
  FUses.Free;
  FTrees.Free;
  inherited;
end;

function TDfmrModuleFinder.Notes: TArray<string>;
begin
  Result := FNotes.ToArray;
end;

{ The nearest folder, from pFolder up to MODULE_LEVELS levels above it, that holds a project file; pFolder when none. }
function TDfmrModuleFinder.ProjectFolder(const pFolder: string): string;
var
  VFolder, VMask: string;
  VLevel: Integer;
begin
  Result := pFolder;
  VFolder := pFolder;
  for VLevel := 0 to MODULE_LEVELS do
  begin
    if (VFolder = '') or not TDirectory.Exists(VFolder) then
      Exit;
    for VMask in PROJECT_MASKS do
      if Length(TDirectory.GetFiles(VFolder, VMask)) > 0 then
        Exit(VFolder);
    VFolder := TPath.GetDirectoryName(VFolder);
  end;
end;

{ True for a folder that is never searched (SKIP_PREFIXES). }
function IsSkippedFolder(const pName: string): Boolean;
var
  VPrefix: string;
begin
  Result := False;
  for VPrefix in SKIP_PREFIXES do
    if StartsText(VPrefix, pName) then
      Exit(True);
end;

{ Every DFM of pFolder and of the folders below it that are not skipped. }
procedure TDfmrModuleFinder.Collect(const pFolder: string; var pFiles: TArray<string>);
var
  VSub: string;
begin
  pFiles := pFiles + TDirectory.GetFiles(pFolder, DFM_MASK);
  for VSub in TDirectory.GetDirectories(pFolder) do
    if not IsSkippedFolder(ExtractFileName(VSub)) then
      Collect(VSub, pFiles);
end;

function TDfmrModuleFinder.Tree(const pFolder: string): TArray<string>;
begin
  if FTrees.TryGetValue(LowerCase(pFolder), Result) then
    Exit;
  Result := nil;
  if TDirectory.Exists(pFolder) then
    Collect(pFolder, Result);
  FTrees.Add(LowerCase(pFolder), Result);
end;

function TDfmrModuleFinder.UsedBy(const pDfm: string): TArray<string>;
var
  VPas: string;
begin
  if FUses.TryGetValue(LowerCase(pDfm), Result) then
    Exit;
  Result := nil;
  VPas := ChangeFileExt(pDfm, EXT_PAS);
  if TFile.Exists(VPas) then
    Result := UsedUnitsOf(TFile.ReadAllText(VPas));
  FUses.Add(LowerCase(pDfm), Result);
end;

function TDfmrModuleFinder.ModuleFile(const pDfm, pRoot: string): string;
var
  VFull, VRoot, VUnit, VFile, VNote: string;
  VFound, VNames, VUnits: TArray<string>;
begin
  Result := '';
  VFull := TPath.GetFullPath(pDfm);
  VRoot := ProjectFolder(TPath.GetDirectoryName(VFull));
  VFound := nil;
  VUnits := nil;
  for VUnit in UsedBy(VFull) do
    for VFile in Tree(VRoot) do
      if SameText(ExtractFileName(VFile), VUnit + EXT_DFM) and (not SameText(VFile, VFull))
        and SameText(ReadDfmRootHead(VFile).Name, pRoot) and not MatchText(VFile, VFound) then
      begin
        VFound := VFound + [VFile];
        if not MatchText(VUnit, VUnits) then
          VUnits := VUnits + [VUnit];
      end;
  if Length(VFound) = 1 then
    Exit(VFound[0]);
  if Length(VFound) = 0 then
    Exit;
  VNames := nil;
  for VFile in VFound do
    VNames := VNames + [ExtractRelativePath(IncludeTrailingPathDelimiter(VRoot), VFile)];
  VNote := Format('%s: %d DFMs of the used unit %s have the root %s (%s): module not read', [ExtractFileName(VFull),
    Length(VFound), string.Join(', ', VUnits), pRoot, string.Join(', ', VNames)]);
  if not FNotes.Contains(VNote) then
    FNotes.Add(VNote);
end;

function NewDfmrAncestry(const pLoad: TDfmrFormLoader): IDfmrAncestry;
begin
  Result := TDfmrAncestry.Create(pLoad);
end;

{ TDfmrAncestry }

constructor TDfmrAncestry.Create(const pLoad: TDfmrFormLoader);
begin
  inherited Create;
  FLoad := pLoad;
  FAncestors := TDictionary<string, string>.Create;
  FFolders := TDictionary<string, TArray<TRootEntry>>.Create;
  FNotes := TList<string>.Create;
end;

destructor TDfmrAncestry.Destroy;
begin
  FNotes.Free;
  FFolders.Free;
  FAncestors.Free;
  inherited;
end;

procedure TDfmrAncestry.Note(const pText: string);
begin
  if not FNotes.Contains(pText) then
    FNotes.Add(pText);
end;

function TDfmrAncestry.Notes: TArray<string>;
begin
  Result := FNotes.ToArray;
end;

{ Root class of every DFM of a folder, read once. }
function TDfmrAncestry.Roots(const pFolder: string): TArray<TRootEntry>;
var
  VFile: string;
  VEntry: TRootEntry;
begin
  if FFolders.TryGetValue(LowerCase(pFolder), Result) then
    Exit;
  Result := nil;
  if TDirectory.Exists(pFolder) then
    for VFile in TDirectory.GetFiles(pFolder, DFM_MASK) do
    begin
      VEntry.FileName := VFile;
      VEntry.RootClass := ReadDfmRootHead(VFile).RootClass;
      if VEntry.RootClass <> '' then
        Result := Result + [VEntry];
    end;
  FFolders.Add(LowerCase(pFolder), Result);
end;

function TDfmrAncestry.ResolveAncestor(const pFile: string): string;
var
  VHead: TDfmrRootHead;
  VPas, VAncestor, VFolder, VName: string;
  VEntry: TRootEntry;
  VFound: TArray<string>;
begin
  Result := '';
  VHead := ReadDfmRootHead(pFile);
  if VHead.Kind <> KIND_INHERITED then
    Exit;
  VName := ExtractFileName(pFile);
  VPas := ChangeFileExt(pFile, EXT_PAS);
  if not TFile.Exists(VPas) then
  begin
    Note(Format('%s: inherited from an ancestor form, but no unit beside the DFM names it: ancestor not read', [VName]));
    Exit;
  end;
  VAncestor := AncestorClassOf(TFile.ReadAllText(VPas), VHead.RootClass);
  if VAncestor = '' then
  begin
    Note(Format('%s: %s declares no ancestor class for %s: ancestor not read', [VName, ExtractFileName(VPas),
      VHead.RootClass]));
    Exit;
  end;
  VFolder := TPath.GetDirectoryName(pFile);
  VFound := nil;
  for VEntry in Roots(VFolder) do
    if SameText(VEntry.RootClass, VAncestor) and not SameText(VEntry.FileName, pFile) then
      VFound := VFound + [VEntry.FileName];
  if Length(VFound) = 0 then
  begin
    Note(Format('%s: no DFM of this folder has the ancestor class %s: ancestor not read', [VName, VAncestor]));
    Exit;
  end;
  if Length(VFound) > 1 then
  begin
    Note(Format('%s: %d DFMs of this folder have the ancestor class %s: ancestor not read', [VName, Length(VFound),
      VAncestor]));
    Exit;
  end;
  Result := VFound[0];
end;

function TDfmrAncestry.AncestorFile(const pFile: string): string;
var
  VFull: string;
begin
  VFull := TPath.GetFullPath(pFile);
  if FAncestors.TryGetValue(LowerCase(VFull), Result) then
    Exit;
  Result := ResolveAncestor(VFull);
  FAncestors.Add(LowerCase(VFull), Result);
end;

function TDfmrAncestry.LoadForm(const pFile: string; out pForm: TDfmrForm): Boolean;
begin
  pForm := Default(TDfmrForm);
  try
    pForm := FLoad(pFile);
    Result := True;
  except
    on E: EDfmReadError do
    begin
      Note(Format('%s: ancestor DFM not read: %s', [ExtractFileName(pFile), E.Message]));
      Result := False;
    end;
  end;
end;

function TDfmrAncestry.Find(const pForm: TDfmrForm; const pName: string; pDepth: Integer; out pDataset: TDfmrDataset): Boolean;
var
  VCandidate, VAncestor: TDfmrDataset;
  VFile: string;
  VForm: TDfmrForm;
begin
  pDataset := Default(TDfmrDataset);
  Result := False;
  for VCandidate in pForm.Datasets do
    if SameText(VCandidate.Name, pName) then
    begin
      pDataset := VCandidate;
      Result := True;
      Break;
    end;
  if Result and not SameText(pDataset.ObjKind, KIND_INHERITED) then
    Exit;
  if pDepth >= MAX_CHAIN then
    Exit;
  VFile := AncestorFile(pForm.FileName);
  if (VFile = '') or (not LoadForm(VFile, VForm)) or (not Find(VForm, pName, pDepth + 1, VAncestor)) then
    Exit;
  Note(Format('%s %s: read from the ancestor %s', [ExtractFileName(pForm.FileName), VAncestor.Name,
    ExtractFileName(VFile)]));
  pDataset := if Result then MergeInherited(pDataset, VAncestor) else VAncestor;
  Result := True;
end;

function TDfmrAncestry.FindDataset(const pForm: TDfmrForm; const pName: string; out pDataset: TDfmrDataset): Boolean;
begin
  Result := Find(pForm, pName, 0, pDataset);
end;

end.
