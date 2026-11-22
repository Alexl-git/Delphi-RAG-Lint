unit DRagLint.CLI.MigrateDbs;

// ---------------------------------------------------------------------------
// The `migrate-dbs` verb (lane v1511 SPLIT T07): move a set of index databases and rewrite the manifest
// pair (dll-win32 / dll-win64). Moved verbatim out of DRagLint.CLI.
// ---------------------------------------------------------------------------

interface

uses
  DRagLint.CLI.Common;

/// <summary>The platform sibling of a manifest that sits directly in a dll-win32 / dll-win64 folder, so a write to one is mirrored to the other.</summary>
/// <param name="ACfgPath">The manifest written.</param>
/// <returns>The sibling manifest path, or '' when ACfgPath is not in such a folder.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.ApplyReconcileToLibrary (DRagLint.CLI.pas), DRagLint.CLI.MigrateDbs.MirrorPairedManifest (DRagLint.CLI.MigrateDbs.pas)</para>
/// <para>Calls: ExcludeTrailingPathDelimiter, ExpandFileName, ExtractFileDir, ExtractFileName, ExtractFilePath, SameText</para>
/// <para>Returns: ''; TPath.Combine(TPath.Combine(ParentDir, Sibling), ExtractFileName(ACfgPath))</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function PairedManifestPath(const ACfgPath: string): string;

/// <summary>Moves every project section's index into that project's _D-RAG home
/// and drops the now-derivable "db" from the manifest.</summary>
/// <param name="AArgs">Parsed args; ConfigPath and the --apply switch are read.</param>
/// <returns>0 = success or nothing to do, 1 = a move failed, 2 = a DB is locked
/// or the manifest could not be read.</returns>
/// <remarks>
/// Dry-run by default: prints every planned move and touches nothing,
/// so the exclusive-open lock probe is skipped entirely for a dry run -- it
/// must always be safe to run even while RAD Studio holds every index open.
/// The manifest entry for a section is corrected and SAVED the INSTANT
/// MoveDbSet physically relocates its database -- before the row-count
/// verification, before the .gitignore write, before anything else that
/// could still fail. That is the instant the on-disk manifest becomes wrong,
/// so it is the instant it must be fixed; a later verification failure does
/// NOT move the file back, so it must not revert this either, only report
/// loudly. A stale entry that names a source which no longer exists, but
/// whose derived destination already holds a database, self-heals on the
/// next --apply -- but only after passing the SAME health check verification
/// uses (PRAGMA quick_check + a non-zero files count), so a database that
/// already failed verification once can never be laundered back to "healthy"
/// by a retry. No reindex is needed -- no table stores the database's own
/// path.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.MigrateDbs.DbIsLocked, DRagLint.CLI.MigrateDbs.DbLooksHealthy, DRagLint.CLI.MigrateDbs.FindHgRoot, DRagLint.CLI.MigrateDbs.MirrorPairedManifest, DRagLint.CLI.MigrateDbs.MoveDbSet, DRagLint.Index.Manifest.ExpandSectionDb, DRagLint.Index.Manifest.SectionProjectFile, DRagLint.Index.Manifest.TInstalledLayout.ManifestLocation, DRagLint.Index.Manifest.TManifestIO.ParseText, DRagLint.Index.Manifest.TManifestIO.SaveEdits (+8 more)</para>
/// <para>Returns: 0; 2; 1</para>
/// <para>Complexity: 22 (cyclomatic, outer body), 208 lines (full implementation)</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>SQL: reads FILES</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.MigrateDbs.DbIsLocked"/>
/// <seealso cref="DRagLint.CLI.MigrateDbs.DbLooksHealthy"/>
/// <seealso cref="DRagLint.CLI.MigrateDbs.FindHgRoot"/>
/// <seealso cref="DRagLint.CLI.MigrateDbs.MirrorPairedManifest"/>
/// <seealso cref="DRagLint.CLI.MigrateDbs.MoveDbSet"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoMigrateDbs(const AArgs: TArgs): Integer;

implementation

uses
  DRagLint.Core.Model, Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, System.NetEncoding,
  System.JSON, System.DateUtils, System.Generics.Collections, System.SyncObjs, FireDAC.Comp.Client,
  FireDAC.Stan.Async, FireDAC.DApt, TreeSitter, DRagLint.Storage.FileMembership, DRagLint.Index.Manifest;

{ Exclusive-open probe. A DB that another process holds -- RAD Studio's LSP is
  the usual one, but a stray index job or an LSP started from a copied exe does
  it too -- must abort the migration BEFORE the first move, not half way through.
  Testing the file beats testing for a process name: it is the lock that would
  actually break the move. }
function DbIsLocked(const APath: string): Boolean;
var
  FS: TFileStream;
begin
  Result:= False;
  if not TFile.Exists(APath) then Exit;
  try
    FS:= TFileStream.Create(APath, fmOpenReadWrite or fmShareExclusive);
    FS.Free;
  except
    on E: EFOpenError do Result:= True;
  end;
end;

{ Move a database and the two WAL sidecars that belong to it. All 27 configured
  indexes have both today. Checkpointing first collapses the WAL into the main
  file, so a sidecar that fails to move costs nothing. }
procedure MoveDbSet(const ASrc, ADst: string);
var
  Suffix: string;
begin
  TFile.Move(ASrc, ADst);
  for Suffix in ['-wal', '-shm'] do
    if TFile.Exists(ASrc + Suffix) then
    begin
      if TFile.Exists(ADst + Suffix) then TFile.Delete(ADst + Suffix);  // dl:ok stat-gated-destructive@2cce -- REVIEWED 2026-11-19 SLZ-MARK: own .dcu, journal or -wal/-shm sidecar inside try/except; a failed stat only leaves a stale file
      TFile.Move(ASrc + Suffix, ADst + Suffix);
    end;
end;

{ Opens APath and confirms it is a USABLE drag-lint index, not merely present.
  Guards the reconciliation branch (review finding 1b): TFile.Exists alone
  would also accept a database that failed the row-count check on an earlier
  run -- the move itself succeeds independently of whether the moved file is
  intact, so "Src missing, Dst present" is also exactly what a section that
  already failed verification looks like. Reconciling that blindly would
  launder a database this tool itself already flagged as broken. }
function DbLooksHealthy(const APath: string): Boolean;
var
  Conn : TFDConnection;
  Check: string       ;
  Rows : Int64        ;
begin
  Result:= False;
  if not TFile.Exists(APath) then Exit;
  Conn:= TFDConnection.Create(nil);
  try
    try
      ConnectReadOnly(Conn, APath); { a reader: never FireDAC's Exclusive/Delete defaults }
      Check:= Conn.ExecSQLScalar('PRAGMA quick_check');
      Rows := Conn.ExecSQLScalar('SELECT COUNT(*) FROM files');
      Result:= SameText(Check, 'ok') and (Rows > 0);
    except  // dl:ok bare-except@79dc -- REVIEWED 2026-11-19 SLZ-MARK: best-effort probe or file read with a documented fallback; the handler assigns that fallback or exits, so no result is lost silently
      Result:= False;   { not a database, or too corrupt to answer either query }
    end;
  finally
    Conn.Close;
    Conn.Free;
  end;
end;

{ Fix 2 (2026-08-11 final review): there are TWO copies of drag-lint.json that
  must stay byte-identical -- third_party\dll-win32\drag-lint.json (the 32-bit
  IDE design-time BPL resolves the manifest beside ITSELF, i.e. this copy --
  DragLint.Plugin.DbResolver.pas:89-92) and dll-win64\drag-lint.json (every
  engine process the plugin spawns is the win64 CLI, which reads its OWN
  sibling copy -- DRagLint.Index.Manifest.pas:546). See
  tests\autotest\run_manifest_parity.ps1's header for the full mechanism.
  DoMigrateDbs resolves and rewrites exactly ONE of the pair (CfgPath); this
  bit the user for real (a live migration desynced them, repaired by hand),
  and nothing stopped the next --apply from doing it again.
  Returns '' when ACfgPath does not sit directly inside a folder literally
  named "dll-win32" or "dll-win64" -- e.g. a test's --config path, or a
  workspace-local manifest -- where there is no platform sibling to keep in
  sync. }
function PairedManifestPath(const ACfgPath: string): string;
var
  Dir, ParentDir, LeafDir, Sibling: string;
begin
  Result := '';
  Dir    := ExcludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(ACfgPath)));
  LeafDir:= ExtractFileName(Dir);
  if SameText(LeafDir, 'dll-win64') then Sibling:= 'dll-win32'
  else if SameText(LeafDir, 'dll-win32') then Sibling:= 'dll-win64'
  else Exit;
  ParentDir:= ExtractFileDir(Dir);
  Result:= TPath.Combine(TPath.Combine(ParentDir, Sibling), ExtractFileName(ACfgPath));
end;

/// <summary>Mirrors ACfgPath over its platform-paired manifest (see
/// PairedManifestPath) whenever the sibling exists and now differs from what
/// was just saved.</summary>
/// <param name="ACfgPath">The manifest DoMigrateDbs just wrote.</param>
/// <remarks>Chosen over a loud warning: CfgPath is, by construction, the copy
/// this run deliberately just wrote, so there is no ambiguity about which
/// side is "intended" -- mirroring it is exactly the fix
/// run_manifest_parity.ps1's own failure text recommends ("copy the intended
/// file over the other so both are identical"). No-ops (silently) when there
/// is no sibling to pair with, or the sibling already matches
/// byte-for-byte.</remarks>
procedure MirrorPairedManifest(const ACfgPath: string);
var
  Mine, Theirs: TBytes;
  SiblingPath : string;
  Same        : Boolean;
begin
  SiblingPath:= PairedManifestPath(ACfgPath);
  if (SiblingPath = '') or (not TFile.Exists(SiblingPath)) then Exit;
  Mine  := TFile.ReadAllBytes(ACfgPath);
  Theirs:= TFile.ReadAllBytes(SiblingPath);
  Same:= (Length(Mine) = Length(Theirs)) and
    ((Length(Mine) = 0) or CompareMem(@Mine[0], @Theirs[0], Length(Mine)));
  if Same then Exit;
  TFile.Copy(ACfgPath, SiblingPath, True);
  Writeln(Format('  manifest parity: mirrored to %s (the IDE win32 BPL and the win64 CLI must read the same scope)', [SiblingPath]));
end;

{ Nearest ancestor holding a .hg directory, or '' -- used only to tell the user
  which .hgignore to edit. }
function FindHgRoot(const AStartDir: string): string;
var
  Dir, Parent: string;
begin
  Result:= '';
  Dir   := ExcludeTrailingPathDelimiter(ExpandFileName(AStartDir));
  while Dir <> '' do
  begin
    if TDirectory.Exists(TPath.Combine(Dir, '.hg')) then Exit(Dir);
    Parent:= ExtractFileDir(Dir);
    if SameText(Parent, Dir) then Break;
    Dir:= Parent;
  end;
end;

function DoMigrateDbs(const AArgs: TArgs): Integer;
var
  Manifest   : TIndexManifest;
  CfgPath    : string        ;
  I          : Integer       ;
  Src, Dst   : string        ;
  ProjFile   : string        ;
  Moved      : Integer       ;
  Reconciled : Integer       ;
  Planned    : Integer       ;
  Conn       : TFDConnection ;
  RowsBefore, RowsAfter: Int64;
  HgRoots    : TStringList   ;
  OrigText   : string        ;
begin
  Result    := 0;
  Moved     := 0;
  Reconciled:= 0;
  Planned   := 0;
  { Deliberately NOT TManifestIO.Load: that MERGES a global and a local manifest
    and does not report which file it read, so saving the merged result back
    would inline one manifest into the other. Resolve exactly one file and
    rewrite exactly that file. --config wins; else the drag-lint.json beside the
    exe, which is where the real one lives (third_party\dll-win64). }
  CfgPath:= AArgs.WorkspaceConfig;
  if CfgPath = '' then CfgPath:= TInstalledLayout.ManifestLocation(ExtractFilePath(ParamStr(0))).Path;
  if not TFile.Exists(CfgPath) then
  begin
    Writeln('ERROR: manifest not found: ', CfgPath);
    Writeln('       Pass --config <drag-lint.json> naming the file to rewrite.');
    Exit(2);
  end;
  { OrigText is what each save patches: only the moved sections' "db" keys
    change, every other byte of the user's manifest is kept (SaveEdits). }
  OrigText:= TFile.ReadAllText(CfgPath);
  Manifest:= TManifestIO.ParseText(OrigText, ExtractFilePath(TPath.GetFullPath(CfgPath)));

  { Probe EVERY lock before moving ANY file -- but only when actually
    APPLYING. A plain dry run only prints the plan and touches nothing, so it
    must always be safe to run, even while RAD Studio holds every index open
    (review finding 4: the probe used to run unconditionally, so a harmless
    dry run would abort with exit 2 for no reason). A half-done APPLY is
    still the one outcome worth engineering against. }
  if AArgs.Apply then
    for I:= 0 to High(Manifest.Sections) do
    begin
      if SectionProjectFile(Manifest, Manifest.Sections[I]) = '' then Continue;
      Src:= ExpandSectionDb(Manifest, Manifest.Sections[I]);
      if DbIsLocked(Src) then
      begin
        Writeln('ERROR: in use, cannot migrate: ', Src);
        Writeln('       Close RAD Studio (its LSP holds project indexes open) and retry.');
        Exit(2);
      end;
    end;

  HgRoots:= TStringList.Create;
  HgRoots.Sorted:= True;
  HgRoots.Duplicates:= dupIgnore;
  try
    for I:= 0 to High(Manifest.Sections) do
    begin
      ProjFile:= SectionProjectFile(Manifest, Manifest.Sections[I]);
      if ProjFile = '' then Continue;                    { folder scan: stays put }
      Src:= ExpandSectionDb(Manifest, Manifest.Sections[I]);
      Dst:= TPath.Combine(TPath.Combine(ExtractFilePath(ProjFile), DRAG_HOME_DIR),
                          TPath.GetFileNameWithoutExtension(ProjFile) + '.sqlite');
      if SameText(Src, Dst) then Continue;               { already home }
      Inc(Planned);
      Writeln(Format('%s  %s -> %s', [Manifest.Sections[I].Name, Src, Dst]));
      if not AArgs.Apply then Continue;
      if not TFile.Exists(Src) then
      begin
        { Review finding 2: a stale manifest entry (a hand-edited config, or a
          retry after a batch that failed partway through, before this
          function persisted after every move) must not be reported as
          "never built" when the database plainly already exists at its
          derived home -- reconcile the entry instead. Only reconcile when
          the destination is real AND HEALTHY (review finding 1b): the move
          itself can succeed independently of whether the moved database is
          intact, so "Src missing, Dst present" is also exactly what a
          section that already failed the row-count check looks like on a
          retry -- TFile.Exists alone would launder it back to "healthy"
          with no verification at all. A source and destination BOTH missing
          is still a project that was never indexed. }
        if TFile.Exists(Dst) and DbLooksHealthy(Dst) then
        begin
          Manifest.Sections[I].Db:= '';   { now derivable }
          TManifestIO.SaveEdits(OrigText, Manifest, CfgPath);
          MirrorPairedManifest(CfgPath);   { Fix 2: keep the win32/win64 pair in sync }
          Inc(Reconciled);
          Writeln('  RECONCILED: already at ', Dst, ' -- manifest entry updated');
        end
        else if TFile.Exists(Dst) then
        begin
          Writeln('  ERROR: found ', Dst, ' but it failed an integrity check -- ' +
            'NOT reconciling. Rebuild it (index --rebuild) before retrying.');
          Exit(1);
        end
        else
          Writeln('  SKIP: source does not exist (never built)');
        Continue;
      end;

      try
        { Checkpoint so the moved file is self-contained, and count rows so the
          move can be verified rather than assumed -- but the count is only
          CONSULTED after the manifest is already fixed (below); it can no
          longer gate whether the manifest gets fixed at all. }
        Conn:= TFDConnection.Create(nil);
        try
          { A writer (the checkpoint), so ConnectWriter: FireDAC's defaults
            converted the index to a rollback journal before it was moved. }
          ConnectWriter(Conn, Src);
          Conn.ExecSQL('PRAGMA wal_checkpoint(TRUNCATE)');
          RowsBefore:= Conn.ExecSQLScalar('SELECT COUNT(*) FROM files');
        finally
          Conn.Close;
          Conn.Free;
        end;

        TDirectory.CreateDirectory(ExtractFileDir(Dst));
        MoveDbSet(Src, Dst);

        { Review finding 1 (critical, round 2): the database IS at Dst the
          instant MoveDbSet returns -- whatever happens in the rest of this
          try block, that fact does not change. The on-disk manifest becomes
          WRONG at that same instant (it still names Src), so it must be
          corrected in that same instant: HERE, before the row-count
          verification below, before the .gitignore write, before anything
          else that could throw and Exit(1) with the entry still naming a
          path that no longer exists. A verification failure a few lines
          down does NOT move the file back, so it must not revert this. }
        Manifest.Sections[I].Db:= '';   { now derivable }
        TManifestIO.SaveEdits(OrigText, Manifest, CfgPath);
        MirrorPairedManifest(CfgPath);   { Fix 2: keep the win32/win64 pair in sync }
        Inc(Moved);

        { Verify AFTER persisting the move, not instead of it: a mismatch
          here is a loud integrity failure on a database that is ALREADY
          migrated, not proof that the move can be undone. The manifest
          keeps naming Dst either way -- see DbLooksHealthy above, which is
          what stops a retry from treating this failure as fine. }
        Conn:= TFDConnection.Create(nil);
        try
          ConnectReadOnly(Conn, Dst); { a reader: never FireDAC's Exclusive/Delete defaults }
          RowsAfter:= Conn.ExecSQLScalar('SELECT COUNT(*) FROM files');
        finally
          Conn.Close;
          Conn.Free;
        end;
        if RowsAfter <> RowsBefore then
        begin
          Writeln(Format('  ERROR: %d files before, %d after -- the database ' +
            'IS at %s but FAILED VERIFICATION -- STOPPING. The manifest entry ' +
            'already points here (correctly, since the file really is there); ' +
            'investigate before trusting it.', [RowsBefore, RowsAfter, Dst]));
          Exit(1);
        end;

        { Self-ignoring for git. Mercurial cannot self-ignore, so collect the
          repo roots and print instructions at the end instead of editing a
          repository's ignore file behind its owner's back. }
        TFile.WriteAllText(TPath.Combine(ExtractFileDir(Dst), '.gitignore'), '*'#13#10);
        var HgRoot: string:= FindHgRoot(ExtractFilePath(ProjFile));
        if HgRoot <> '' then HgRoots.Add(HgRoot);

        Writeln(Format('  OK (%d files)', [RowsAfter]));
      except
        on E: Exception do
        begin
          { Fix 3 (2026-08-11 review): MoveDbSet (above) relocates the main
            .sqlite FIRST via TFile.Move, then the -wal/-shm sidecars
            separately -- so a sidecar move that raises (locked file, etc.)
            leaves the .sqlite already sitting at Dst while this handler's
            plain "ERROR: <class>: <message>" reads as "the move failed".
            Say where the database actually is when that is the case, so the
            operator does not start hunting for it at Src. }
          if TFile.Exists(Dst) then
            Writeln(Format('  ERROR: %s: %s -- the database has ALREADY MOVED to %s; do not re-copy or undo, investigate this failure in place',
              [E.ClassName, E.Message, Dst]))
          else
            Writeln('  ERROR: ', E.ClassName, ': ', E.Message);
          Exit(1);
        end;
      end;
    end;

    if AArgs.Apply and (Moved + Reconciled > 0) then
    begin
      { Already saved per-move (finding 1) or per-reconciliation (finding 2)
        above -- this is a summary line, not the save. Moved and Reconciled
        are reported separately (review: minor) -- a reconciliation is a
        manifest-only fix for a database that was already sitting at its
        home, not a new physical move, and folding the two counts together
        would misreport how many databases actually moved this run. }
      Writeln(Format('migrate-dbs: %d database(s) moved, %d reconciled; manifest updated (%s)',
        [Moved, Reconciled, CfgPath]));
      if HgRoots.Count > 0 then
      begin
        Writeln('');
        Writeln('Mercurial cannot self-ignore. Add this line to each .hgignore:');
        Writeln('    ' + DRAG_HOME_DIR);
        for var R: string in HgRoots do Writeln('  ' + TPath.Combine(R, '.hgignore'));
      end;
    end
    else if not AArgs.Apply then
      Writeln(Format('migrate-dbs: %d database(s) would move. Re-run with --apply.', [Planned]));
  finally
    HgRoots.Free;
  end;
end; // function

end.
