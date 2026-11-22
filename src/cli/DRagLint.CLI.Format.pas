unit DRagLint.CLI.Format;

// ---------------------------------------------------------------------------
// The purge-locals and format (YADF) verbs. Moved verbatim out of DRagLint.CLI (lane v1511 SPLIT, T07).
// ---------------------------------------------------------------------------

interface

uses
  DRagLint.CLI.Common;

/// <summary>v14 (D5 T12): drag-lint purge-locals --db PATH [--json] -- the SIZE
/// ESCAPE HATCH. Deletes every skLocalVar/skParam symbol (kind IN 'local_var',
/// 'param'), then VACUUMs to reclaim the freed pages, and reports how many rows
/// were removed plus the DB file size before/after. Once ResolveCallTargets has
/// populated call_edges, these numerous per-local / per-param symbols have done
/// their job (they let the resolver type call-site receivers), so purging them
/// slims the index. The resolved CALL GRAPH is unchanged: call_edges references
/// call TARGETS (methods) and receiver TYPES (classes), never a local/param, so
/// no edge can cascade-delete. Requires an explicit --db (it MUTATES a specific
/// index -- never purges across an auto-selected DB set). NOT wired into any
/// auto-index path: a reindex re-emits locals/params and rebuilds call_edges, so
/// this is a manual, point-in-time slim only, correctly re-inflated on the next
/// full index. Idempotent: a second run removes 0 rows and still exits 0.</summary>
/// <param name="AArgs">Parsed CLI args; DbPath is the index to purge; AsJson picks JSON output.</param>
/// <returns>0 on success (including the idempotent 0-removed second run); 2 on
/// usage error / missing --db / missing db file.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.Common.AcquireIndexLock, DRagLint.CLI.Common.ConfigDbRedirectsWrite, DRagLint.Core.Interfaces.ISymbolStore.Migrate, DRagLint.Core.Interfaces.ISymbolStore.PurgeLocals, DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create, FileExists, Format, Writeln</para>
/// <para>Returns: 2; 0</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.AcquireIndexLock"/>
/// <seealso cref="DRagLint.CLI.Common.ConfigDbRedirectsWrite"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.Migrate"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.PurgeLocals"/>
/// <seealso cref="DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoPurgeLocals(const AArgs: TArgs): Integer;

/// <summary>drag-lint format FILE [--yadf-path PATH] [--dry-run|--diff]: formats one unit with YADF; --dry-run / --diff never write the file.</summary>
/// <param name="AArgs">The file, --yadf-path, --dry-run, --diff.</param>
/// <returns>0 on success; 2 on a usage error or a missing file; 3 / 4 passed on from the formatter.</returns>
/// <exception cref="EYadfFormatError"><!-- drag-lint:auto exc -->via DRagLint.Format.Yadf.TYadfFormatter.Format: File not found: %s</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Format.Yadf.TYadfFormatter.Format, FileExists, Trim, Writeln</para>
/// <para>Returns: 1; 0</para>
/// <para>Complexity: 16 (cyclomatic, outer body), 48 lines (full implementation)</para>
/// <seealso cref="DRagLint.Format.Yadf.TYadfFormatter.Format"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoFormat(const AArgs: TArgs): Integer;

implementation

uses
  Winapi.Windows, System.SysUtils, System.IOUtils, System.NetEncoding, System.JSON, System.DateUtils,
  System.SyncObjs, FireDAC.Stan.Async, FireDAC.DApt, DRagLint.Core.Interfaces, DRagLint.Storage.SQLite,
  DRagLint.Format.Yadf;

function DoPurgeLocals(const AArgs: TArgs): Integer;
var
  Store     : ISymbolStore;
  Removed   : Int64        ;
  SizeBefore: Int64        ;
  SizeAfter : Int64        ;
begin
  { DbPaths, not DbPath: Run defaults DbPath from --project, and a DESTRUCTIVE
    verb must not act on a database the user did not name. }
  if Length(AArgs.DbPaths) = 0 then
  begin
    Writeln('ERROR: purge-locals needs an explicit --db <db>');
    Exit(2);
  end;
  if not FileExists(AArgs.DbPath) then
  begin
    Writeln(Format('Database not found: %s', [AArgs.DbPath]));
    Exit(2);
  end;

  { 1.40 IDX-LOCK: purge MUTATES the index -- take <db>.indexing.lock like `index` does. }
  if ConfigDbRedirectsWrite('purge-locals', AArgs, '') then Exit(2);
  if not AcquireIndexLock(AArgs.DbPath, {AQuiet=}False, 'purge-locals') then Exit(2);
  SizeBefore:= TFile.GetSize(AArgs.DbPath);
  { Read-WRITE open (purge MUTATES) -- same path as index/rename/safe-delete, NOT
    the query_only OpenReadOnlyStore used by read verbs. Migrate ensures the
    schema (incl. the symbols.kind values) is current before we touch it. }
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  Removed:= Store.PurgeLocals;
  Store:= nil; { close the connection so the VACUUM's file resize is flushed before we stat }
  SizeAfter:= TFile.GetSize(AArgs.DbPath);

  if AArgs.AsJson then
  begin
    var JO: TJSONObject:= TJSONObject.Create;
    try
      JO.AddPair('db'         , AArgs.DbPath                      );
      JO.AddPair('removed'    , TJSONNumber.Create(Removed   )    );
      JO.AddPair('size_before', TJSONNumber.Create(SizeBefore)    );
      JO.AddPair('size_after' , TJSONNumber.Create(SizeAfter )    );
      Writeln(JO.Format(2));
    finally JO.Free; end;
  end
  else
    Writeln(Format('purge-locals: removed %d local/param symbol(s); db size %d -> %d bytes',
      [Removed, SizeBefore, SizeAfter]));
  Result:= 0;
end; // function

// v0.27: drag-lint format <file> [--yadf-path PATH]
// Runs YADF formatter on the given file (YADF rewrites in place).
// Exit 2 on usage error, 1 on formatter failure, 0 on success.
{ `drag-lint format <file> [--yadf-path PATH] [--dry-run | --diff]`

  THE EXIT CODES ARE DISTINCT ON PURPOSE. This verb REWRITES THE USER'S SOURCE,
  so "it did not format" is not an actionable answer -- a script (or a person)
  has to be able to tell "no formatter" from "the formatter is too old" from
  "the formatter corrupted the file and I put it back":

    0  formatted (or dry-run/diff completed), or YADF DECLINED the file (its
       exit 3: content guard refused, file unchanged -- B-36; not a failure)
    2  usage: no target, or the target does not exist
    3  no usable YADF resolved            (TFormatResult -3)
    4  resolved YADF is BELOW the floor   (TFormatResult -4) -- nothing written
    5  post-format verification FAILED    (TFormatResult -5) -- file RESTORED
    1  any other formatter failure

  `--dry-run` USED TO BE A SILENT LIE. The flag parsed (it is global) and this
  routine ignored it, so a user who typed it specifically to avoid touching the
  file had the file rewritten anyway. Measured 2026-09-16 and pinned by
  tests\autotest\run_format_verb_guard.ps1 (A3b). }
function DoFormat(const AArgs: TArgs): Integer;
var
  Res   : TFormatResult;
  Target: string       ;
  Mode  : TFormatMode  ;
begin
  Target:= AArgs.Target;
  if Target = '' then Target:= AArgs.QName; // fallback: reuse qname slot
  if Target = '' then
  begin
    Writeln('Usage: drag-lint format <file> [--yadf-path PATH] [--dry-run|--diff]');
    Exit (2 );
  end;
  if not FileExists(Target) then
  begin
    Writeln(Format('File not found: %s', [Target]));
    Exit(2);
  end;

  if AArgs.ShowDiff then Mode:= fmDiff
  else if AArgs.DryRun then Mode:= fmDryRun
  else Mode:= fmApply;

  Res:= TYadfFormatter.Format(Target, AArgs.YadfPath, Mode);

  if not Res.Success then
  begin
    Writeln(Format('YADF format failed (exit %d):'#13#10'%s', [Res.ExitCode, Res.StdoutText]));
    case Res.ExitCode of
      -3: Exit(3);
      -4: Exit(4);
      -5: Exit(5);
    else
      Exit(1);
    end;
  end;

  if Res.Declined then
  begin
    if Trim(Res.StdoutText) <> '' then Writeln(Res.StdoutText);
    Writeln(Format('Declined: %s  (YADF''s content guard left it unchanged; not a failure)', [Target]));
    Exit(0);
  end;

  case Mode of
    fmDryRun: Writeln(Res.StdoutText);
    fmDiff  : Writeln(Res.DiffText  );
  else
    begin
      if Trim(Res.StdoutText) <> '' then Writeln(Res.StdoutText);
      Writeln(Format('Formatted: %s  (via %s%s)',
        [Target, Res.ResolvedPath,
         (if Res.YadfVersion <> '' then ' ' + Res.YadfVersion else '')]));
    end;
  end;
  Result:= 0;
end; // function

end.
