program CoherenceHarness;
{$APPTYPE CONSOLE}

// Standalone DB-backed harness for DRagLint.Project.Coherence (project-
// coherence reconcile, Task 2). Seeds a temp SQLite store with two real
// on-disk fixture .pas files given as args, then runs ComputeCoherence over
// three TProjectMember records: one fully coherent (indexed, index-fresh,
// compile-fresh), one compile-stale (indexed, index-fresh, but
// last_compiled_unix left NULL), and one never indexed at all (absent).
// Prints one PASS/FAIL line per assertion; exits nonzero if any FAIL.
//
// args: <dbPath> <freshPas> <staleCompilePas> <absentPas>

uses
  System.SysUtils
  , System.IOUtils
  , System.DateUtils
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Storage.SQLite
  , DRagLint.Project.Members
  , DRagLint.Project.Coherence
  ;

var
  DbPath         : string;
  FreshPas       : string;
  StaleCompilePas: string;
  AbsentPas      : string;
  Store          : ISymbolStore;
  Tok            : TFileTxToken;
  Mtime          : Int64;
  Members        : TArray<TProjectMember>;
  Cs             : TArray<TMemberCoherence>;
  Failed         : Boolean;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  if ACond then Writeln('PASS  ', AName)
  else begin
    Writeln('FAIL  ', AName, '  ', ADetail);
    Failed:= True;
  end;
end;

begin
  Failed:= False;
  DbPath         := ParamStr(1);
  FreshPas       := ParamStr(2);
  StaleCompilePas:= ParamStr(3);
  AbsentPas      := ParamStr(4);

  if FileExists(DbPath) then DeleteFile(DbPath);
  Store:= TSQLiteSymbolStore.Create(DbPath);
  Store.Migrate;

  // Fresh member: real disk mtime stored, and last_compiled_unix stamped
  // AFTER that mtime -> Indexed, IndexFresh, CompiledFresh all True.
  Mtime:= DateTimeToUnix(TFile.GetLastWriteTime(FreshPas), False);
  Tok:= Store.OpenFileTx(FreshPas, Mtime, 'sha-fresh', 'delphi13');
  Store.CommitFileTx(Tok);
  Store.SetFileCompiledAt(Tok.FileId, Mtime + 5);

  // Compile-stale member: real disk mtime stored (IndexFresh True), but
  // last_compiled_unix is NEVER stamped -> stays NULL -> CompiledFresh False.
  Mtime:= DateTimeToUnix(TFile.GetLastWriteTime(StaleCompilePas), False);
  Tok:= Store.OpenFileTx(StaleCompilePas, Mtime, 'sha-stale', 'delphi13');
  Store.CommitFileTx(Tok);

  // AbsentPas is never indexed at all.

  SetLength(Members, 3);
  Members[0].UnitPath:= FreshPas;
  Members[1].UnitPath:= StaleCompilePas;
  Members[2].UnitPath:= AbsentPas;

  Cs:= ComputeCoherence(Store, Members);

  Check('3 results returned', Length(Cs) = 3, Format('got %d', [Length(Cs)]));
  if Length(Cs) = 3 then
  begin
    Check('fresh member Indexed',              Cs[0].Indexed);
    Check('fresh member IndexFresh',           Cs[0].IndexFresh);
    Check('fresh member CompiledFresh',        Cs[0].CompiledFresh);
    Check('fresh member NOT incoherent',       not IsIncoherent(Cs[0]));

    Check('stale-compile member Indexed',            Cs[1].Indexed);
    Check('stale-compile member IndexFresh',         Cs[1].IndexFresh);
    Check('stale-compile member CompiledFresh=False', not Cs[1].CompiledFresh);
    Check('stale-compile member IS incoherent',      IsIncoherent(Cs[1]));

    Check('absent member NOT Indexed',   not Cs[2].Indexed);
    Check('absent member IS incoherent', IsIncoherent(Cs[2]));
  end;

  if Failed then begin Writeln('FAIL'); Halt(1); end
  else begin Writeln('PASS'); Halt(0); end;
end.
