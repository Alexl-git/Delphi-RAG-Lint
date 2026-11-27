unit DRagLint.FieldRepo.SqlBackup;

{ drag-lint 1.56 -- lane BK-Q: `repo backup --format sql` (DDL + INSERT statements) and its restore.
  The --format dispatch lives in DRagLint.CLI.RepoBackup (lane BK-Z), which calls the two routines
  below. Text (DRagLint.FieldRepo.TextBackup) stays the default format.
  Scaffold created by lane FRAME-1; lane BK-Q owns this unit. }

interface

uses
  FireDAC.Comp.Client;

/// <summary>Writes the repository as an SQL script: the DDL of every table, then one INSERT per row.</summary>
/// <param name="pConnection">An open repository connection; not nil. The caller owns it.</param>
/// <param name="pFileName">The script file to write; an existing file is replaced.</param>
/// <exception cref="ENotImplemented">Always, while the unit is a scaffold.</exception>
/// <remarks>Reads the repository only. Not thread-safe.</remarks>
procedure BackupRepositorySql(pConnection: TFDConnection; const pFileName: string);

/// <summary>Restores a repository from a script written by BackupRepositorySql.</summary>
/// <param name="pConnection">An open, writable repository connection; not nil. The caller owns it.</param>
/// <param name="pFileName">The script file; must exist.</param>
/// <param name="pReplace">True = existing rows are replaced; False = a non-empty repository is refused.</param>
/// <exception cref="ENotImplemented">Always, while the unit is a scaffold.</exception>
/// <remarks>Not thread-safe.</remarks>
procedure RestoreRepositorySql(pConnection: TFDConnection; const pFileName: string; pReplace: Boolean);

implementation

uses
  System.SysUtils;

const
  NOT_IMPLEMENTED = 'repo backup --format sql: not implemented';

procedure BackupRepositorySql(pConnection: TFDConnection; const pFileName: string);
begin
  raise ENotImplemented.Create(NOT_IMPLEMENTED);
end;

procedure RestoreRepositorySql(pConnection: TFDConnection; const pFileName: string; pReplace: Boolean);
begin
  raise ENotImplemented.Create(NOT_IMPLEMENTED);
end;

end.
