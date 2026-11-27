unit DRagLint.FieldRepo.ZipBackup;

{ drag-lint 1.56 -- lane BK-Z: `repo backup --format zip` (VACUUM INTO a copy, then zip it) and its
  restore. The --format dispatch lives in DRagLint.CLI.RepoBackup (same lane). Text
  (DRagLint.FieldRepo.TextBackup) stays the default format.
  Scaffold created by lane FRAME-1; lane BK-Z owns this unit. }

interface

/// <summary>Writes a consistent copy of the repository file into a zip archive.</summary>
/// <param name="pRepoPath">The repository file; must exist.</param>
/// <param name="pFileName">The archive to write; an existing file is replaced.</param>
/// <exception cref="ENotImplemented">Always, while the unit is a scaffold.</exception>
/// <remarks>Reads the repository only. Not thread-safe.</remarks>
procedure BackupRepositoryZip(const pRepoPath, pFileName: string);

/// <summary>Restores a repository file from an archive written by BackupRepositoryZip.</summary>
/// <param name="pFileName">The archive; must exist.</param>
/// <param name="pRepoPath">The repository file to write.</param>
/// <param name="pReplace">True = an existing repository file is replaced; False = it is refused.</param>
/// <exception cref="ENotImplemented">Always, while the unit is a scaffold.</exception>
/// <remarks>Not thread-safe.</remarks>
procedure RestoreRepositoryZip(const pFileName, pRepoPath: string; pReplace: Boolean);

implementation

uses
  System.SysUtils;

const
  NOT_IMPLEMENTED = 'repo backup --format zip: not implemented';

procedure BackupRepositoryZip(const pRepoPath, pFileName: string);
begin
  raise ENotImplemented.Create(NOT_IMPLEMENTED);
end;

procedure RestoreRepositoryZip(const pFileName, pRepoPath: string; pReplace: Boolean);
begin
  raise ENotImplemented.Create(NOT_IMPLEMENTED);
end;

end.
