unit DRagLint.FieldRepo.ZipBackup;

{ drag-lint 1.56 -- lane BK-Z: `repo backup --format zip` (VACUUM INTO a copy, then zip it) and its
  restore. The --format dispatch lives in DRagLint.CLI.RepoBackup (same lane). Text
  (DRagLint.FieldRepo.TextBackup) stays the default format.

  Archive shape: two entries, DLREPO-ZIP.txt ("DLREPO-ZIP 1", then "schema <n>") and repository.sqlite
  (the VACUUMed copy, a complete repository file). A restore validates the archive, extracts the
  copy beside the target, opens it as a repository (so a corrupt or foreign file is caught) and only
  then replaces the target; any failure leaves the target untouched. }

interface

/// <summary>Writes a consistent copy of the repository file into a zip archive.</summary>
/// <param name="pRepoPath">The repository file; must exist.</param>
/// <param name="pFileName">The archive to write; an existing file is replaced.</param>
/// <exception cref="ERepoError">The repository file does not exist or is not a repository.</exception>
/// <remarks>Reads the repository only. The archive is written beside the target and renamed over it, so a
/// failed backup leaves an existing archive intact. Not thread-safe.</remarks>
procedure BackupRepositoryZip(const pRepoPath, pFileName: string);

/// <summary>Restores a repository file from an archive written by BackupRepositoryZip.</summary>
/// <param name="pFileName">The archive; must exist.</param>
/// <param name="pRepoPath">The repository file to write.</param>
/// <param name="pReplace">True = an existing repository file is replaced; False = it is refused.</param>
/// <exception cref="ERepoBackupFormatError">The file is not a zip, lacks the entries, or holds no valid repository;
/// nothing was changed.</exception>
/// <exception cref="ERepoError">The archive does not exist, or the repository exists and pReplace is False.</exception>
/// <remarks>Not thread-safe. The repository is rebuilt from the archive as a whole file: no row migration happens,
/// an older archive gives an older-schema repository (open it with `repo migrate`).</remarks>
procedure RestoreRepositoryZip(const pFileName, pRepoPath: string; pReplace: Boolean);

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Zip,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.TextBackup;

const
  ENTRY_MARKER = 'DLREPO-ZIP.txt';
  ENTRY_REPO = 'repository.sqlite';
  MARKER_HEAD = 'DLREPO-ZIP 1';
  TMP_SUFFIX = '.zip-tmp';

procedure DeleteIfThere(const pFile: string);
begin
  DeleteFile(pFile); // dl:ok ignored-must-use-result@ae9f -- REVIEWED 2026-11-27 BK-Z: best-effort removal of a temp file; a target that cannot be replaced fails in the move that follows
end;

procedure BackupRepositoryZip(const pRepoPath, pFileName: string);
var
  VConn: TFDConnection;
  VCopy, VTmp: string;
  VZip: TZipFile;
  VVersion: Integer;
begin
  if not TFile.Exists(pRepoPath) then
    raise ERepoError.Create('the repository does not exist: ' + pRepoPath);
  VCopy := pFileName + '.copy' + TMP_SUFFIX;
  VTmp := pFileName + TMP_SUFFIX;
  DeleteIfThere(VCopy);
  DeleteIfThere(VTmp);
  VConn := OpenRepository(pRepoPath, True);
  try
    VVersion := RepoSchemaVersion(VConn);
    VConn.ExecSQL('VACUUM INTO ' + QuotedStr(VCopy));
  finally
    VConn.Free;
  end;
  try
    VZip := TZipFile.Create;
    try
      VZip.Open(VTmp, zmWrite);
      VZip.Add(TEncoding.ASCII.GetBytes(MARKER_HEAD + #13#10 + 'schema ' + IntToStr(VVersion) + #13#10), ENTRY_MARKER);
      VZip.Add(VCopy, ENTRY_REPO);
      VZip.Close;
    finally
      VZip.Free;
    end;
    DeleteIfThere(pFileName);
    TFile.Move(VTmp, pFileName);
  finally
    DeleteIfThere(VCopy);
    DeleteIfThere(VTmp);
  end;
end;

{ Raises ERepoBackupFormatError unless pFile (an extracted copy) opens as a repository. }
procedure CheckExtractedRepository(const pFile: string);
var
  VConn: TFDConnection;
begin
  try
    VConn := OpenRepository(pFile, True);
    try
      VConn.ExecSQL('PRAGMA quick_check');
    finally
      VConn.Free;
    end;
  except
    on E: Exception do
      raise ERepoBackupFormatError.Create('the archive does not hold a valid repository: ' + E.Message);
  end;
end;

procedure RestoreRepositoryZip(const pFileName, pRepoPath: string; pReplace: Boolean);
var
  VZip: TZipFile;
  VWork, VText: string;
  VBytes: TBytes;
begin
  if not TFile.Exists(pFileName) then
    raise ERepoError.Create('the backup file does not exist: ' + pFileName);
  if TFile.Exists(pRepoPath) and not pReplace then
    raise ERepoError.Create('the repository exists: ' + pRepoPath + ' (use --replace to overwrite it)');
  if not TZipFile.IsValid(pFileName) then
    raise ERepoBackupFormatError.Create('not a zip archive (or damaged): ' + pFileName);
  VWork := pRepoPath + '.restoring' + TMP_SUFFIX;
  DeleteIfThere(VWork);
  try
    VZip := TZipFile.Create;
    try
      try
        VZip.Open(pFileName, zmRead);
        VZip.Read(ENTRY_MARKER, VBytes);
        VText := TEncoding.ASCII.GetString(VBytes);
        if not VText.StartsWith(MARKER_HEAD) then
          raise ERepoBackupFormatError.Create('not a repository backup archive (bad ' + ENTRY_MARKER + ')');
        VZip.Read(ENTRY_REPO, VBytes);
        TFile.WriteAllBytes(VWork, VBytes);
        VZip.Close;
      except
        on E: ERepoBackupFormatError do
          raise;
        on E: Exception do
          raise ERepoBackupFormatError.Create('the archive is damaged or not a repository backup: ' + E.Message);
      end;
    finally
      VZip.Free;
    end;
    CheckExtractedRepository(VWork);
    DeleteIfThere(pRepoPath);
    TFile.Move(VWork, pRepoPath);
  finally
    DeleteIfThere(VWork);
  end;
end;

end.
