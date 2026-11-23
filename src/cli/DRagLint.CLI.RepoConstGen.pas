unit DRagLint.CLI.RepoConstGen;

{ drag-lint 1.53 -- `repo gen-const` (lane FR-CONSTGEN) and `repo check-const` (lane FR-PRELOAD); spec
  docs\superpowers\specs\2026-11-22-field-repository-v2-design.md section 7.
  The CLI adapter of DRagLint.FieldRepo.ConstGen / ConstDataModule / ConstMark: flag reading, argument checks,
  the file writes.
  Writes only to the --output path it is given; there is no default path (FR-1). }

interface

/// <summary>Runs `drag-lint repo gen-const`: writes the registry unit (or, with --datamodule, the pre-filled data
/// module unit and its form) generated from a repository.</summary>
/// <param name="pRepoPath">Resolved repository file (from --repo or --project).</param>
/// <param name="pOutFile">--output value: the unit file to write; required unless --dry-run.</param>
/// <returns>0 = written (or dry run reported); 1 = the repository is missing or unreadable;
/// 2 = bad arguments (unknown or refused --table, --unit / --datamodule not an identifier, no --output, its folder
/// missing, --unit and the --output name different with --datamodule).</returns>
/// <remarks>
/// The other flags are read from the command line here: --unit (default uFieldRegistry), --table (comma list;
/// default the four registry tables), --datamodule (name of the data module; the unit name then defaults to the
/// --output base name and the form is written beside it), --dry-run (prints the row counts, writes nothing).
/// The repository is opened read only. Not thread-safe; main thread only.
/// </remarks>
function RunRepoGenConst(const pRepoPath, pOutFile: string): Integer;

/// <summary>Runs `drag-lint repo check-const`: does a generated unit still match the repository?</summary>
/// <param name="pRepoPath">Resolved repository file (from --repo or --project).</param>
/// <returns>0 = current; 1 = stale (one line per changed table, or the edited / missing form);
/// 2 = the check could not be made (no --unit-file, file or repository missing, no repository mark in the file).</returns>
/// <remarks>--unit-file is read from the command line here. Never writes; every exception is exit 2, so a pre-build
/// step never takes a failed check for a verdict. Not thread-safe; main thread only.</remarks>
function RunRepoCheckConst(const pRepoPath: string): Integer;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.ConstGen,
  DRagLint.FieldRepo.ConstDataModule,
  DRagLint.FieldRepo.ConstMark,
  FireDAC.Comp.Client;

const
  EXIT_OK    = 0;
  EXIT_FAIL  = 1;
  EXIT_USAGE = 2;
  EXIT_STALE = 1;
  VERB       = 'repo gen-const';
  VERB_CHECK = 'repo check-const';
  FORM_EXT   = '.dfm';
  DEFAULT_UNIT = 'uFieldRegistry';

function CommandLineFlag(const pFlag: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), pFlag) then
      Exit(True);
end;

function CommandLineValue(const pFlag: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to ParamCount - 1 do
    if SameText(ParamStr(I), pFlag) then
      Exit(ParamStr(I + 1));
end;

function ReadOptions(const pRepoPath, pOutFile, pModule: string): TConstGenOptions;
var
  VTables, VName: string;
begin
  Result := Default(TConstGenOptions);
  Result.UnitName := CommandLineValue('--unit');
  if Result.UnitName = '' then
    Result.UnitName := if (pModule <> '') and (pOutFile <> '') then ChangeFileExt(ExtractFileName(pOutFile), '') else DEFAULT_UNIT;
  Result.SourceName := ChangeFileExt(ExtractFileName(pRepoPath), '');
  VTables := CommandLineValue('--table');
  if VTables <> '' then
    for VName in VTables.Split([',']) do
      if Trim(VName) <> '' then
        Result.Tables := Result.Tables + [UpperCase(Trim(VName))];
end;

{ Writes pText as ASCII bytes (no BOM), replacing the file. }
procedure WriteUnitFile(const pFile, pText: string);
begin
  TFile.WriteAllBytes(pFile, TEncoding.ASCII.GetBytes(pText));
end;

{ Writes the unit, and with pModule the form beside it. }
procedure WriteSources(pConn: TFDConnection; const pOutFile, pModule: string; const pOptions: TConstGenOptions);
var
  VSource: TConstDataModuleSource;
begin
  if pModule = '' then
    WriteUnitFile(pOutFile, GenRepoConstUnit(pConn, pOptions))
  else
  begin
    VSource := GenRepoDataModule(pConn, pOptions, pModule);
    WriteUnitFile(pOutFile, VSource.Pas);
    WriteUnitFile(ChangeFileExt(pOutFile, FORM_EXT), VSource.Dfm);
  end;
end;

function Generate(const pRepoPath, pOutFile, pModule: string; const pOptions: TConstGenOptions; pDry: Boolean): Integer;
var
  VConn: TFDConnection;
  VCount: TConstGenCount;
  VCounts: TArray<TConstGenCount>;
  VTotal: Integer;
begin
  VConn := OpenRepository(pRepoPath, True);
  try
    VCounts := CountConstRows(VConn, pOptions);
    VTotal := 0;
    for VCount in VCounts do
    begin
      Inc(VTotal, VCount.Rows);
      Writeln(VCount.Table, ': ', VCount.Rows, ' rows');
    end;
    if pDry then
    begin
      Writeln('dry run: ', Length(VCounts), ' tables, ', VTotal, ' rows; nothing written');
      Exit(EXIT_OK);
    end;
    WriteSources(VConn, pOutFile, pModule, pOptions);
  finally
    VConn.Free;
  end;
  Writeln('wrote ', pOutFile, ': unit ', pOptions.UnitName, ', ', Length(VCounts), ' tables, ', VTotal, ' rows');
  Result := EXIT_OK;
end;

{ '' when the arguments of gen-const are usable, else what is wrong with them. }
function UsageError(const pOutFile, pModule: string; const pOptions: TConstGenOptions; pDry: Boolean): string;
begin
  Result := '';
  if (not pDry) and (pOutFile = '') then
    Result := 'give --output <file.pas> (there is no default path)'
  else if (not pDry) and (not TDirectory.Exists(ExtractFilePath(ExpandFileName(pOutFile)))) then
    Result := 'the output folder does not exist: ' + ExtractFilePath(ExpandFileName(pOutFile))
  else if not IsPasIdent(pOptions.UnitName) then
    Result := '--unit "' + pOptions.UnitName + '" is not an identifier'
  else if (pModule <> '') and not IsPasIdent(pModule) then
    Result := '--datamodule "' + pModule + '" is not an identifier'
  else if (pModule <> '') and (pOutFile <> '') and not SameText(ChangeFileExt(ExtractFileName(pOutFile), ''), pOptions.UnitName) then
    Result := '--unit "' + pOptions.UnitName + '" and --output "' + ExtractFileName(pOutFile)
      + '" must have the same name (the form is found by it)';
end;

function RunRepoGenConst(const pRepoPath, pOutFile: string): Integer;
var
  VOpt: TConstGenOptions;
  VModule, VError: string;
  VDry: Boolean;
begin
  VDry := CommandLineFlag('--dry-run');
  if not TFile.Exists(pRepoPath) then
  begin
    Writeln(ErrOutput, VERB, ': the repository does not exist: ', pRepoPath);
    Exit(EXIT_FAIL);
  end;
  VModule := CommandLineValue('--datamodule');
  VOpt := ReadOptions(pRepoPath, pOutFile, VModule);
  VError := UsageError(pOutFile, VModule, VOpt, VDry);
  if VError <> '' then
  begin
    Writeln(ErrOutput, VERB, ': ', VError);
    Exit(EXIT_USAGE);
  end;
  try
    Result := Generate(pRepoPath, if pOutFile = '' then '' else ExpandFileName(pOutFile), VModule, VOpt, VDry);
  except
    on E: EConstGenError do
    begin
      Writeln(ErrOutput, VERB, ': ', E.Message);
      Result := EXIT_USAGE;
    end;
  end;
end;

function CheckUnitFile(const pRepoPath, pUnitFile: string): Integer;
var
  VConn: TFDConnection;
  VCheck: TConstCheck;
  VReason: string;
begin
  VConn := OpenRepository(pRepoPath, True);
  try
    VCheck := CheckConstUnit(VConn, pUnitFile);
  finally
    VConn.Free;
  end;
  case VCheck.State of
    ccsCurrent:
      begin
        Writeln('current: ', pUnitFile);
        Result := EXIT_OK;
      end;
    ccsStale:
      begin
        Writeln('STALE: ', pUnitFile, ' -- regenerate it with ', VERB);
        for VReason in VCheck.Reasons do
          Writeln('  ', VReason);
        Result := EXIT_STALE;
      end;
  else
    for VReason in VCheck.Reasons do
      Writeln(ErrOutput, VERB_CHECK, ': ', VReason);
    Result := EXIT_USAGE;
  end;
end;

function RunRepoCheckConst(const pRepoPath: string): Integer;
var
  VFile: string;
begin
  Result := EXIT_USAGE;
  VFile := CommandLineValue('--unit-file');
  if VFile = '' then
    Writeln(ErrOutput, VERB_CHECK, ': give --unit-file <file.pas>')
  else if not TFile.Exists(pRepoPath) then
    Writeln(ErrOutput, VERB_CHECK, ': the repository does not exist: ', pRepoPath)
  else
  try
    Result := CheckUnitFile(pRepoPath, ExpandFileName(VFile));
  except
    on E: Exception do
      Writeln(ErrOutput, VERB_CHECK, ': ', E.Message);
  end;
end;

end.
