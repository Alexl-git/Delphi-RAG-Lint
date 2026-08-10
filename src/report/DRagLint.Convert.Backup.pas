unit DRagLint.Convert.Backup;

{
  Track 3 (component conversion), sub-project B, Task 4 -- the convert-apply
  backup/recovery layer. This unit implements the user's EXACT protocol for
  making --apply safe to run against real source trees:

    1. Every file about to be overwritten is copied to the next-free
       "NAME.EXT.BCK<n>" sibling (NextBackupName / BackupFiles) -- a
       per-file counter, so MyForm.pas and MyForm.dfm can land on different
       n's the first time they diverge (e.g. one already has a stray .BCK1
       from a previous manual copy).
    2. A recovery record is APPENDED to "recovery.txt" in the unit's folder
       BEFORE any conversion write happens (WriteRecoveryRecord). Writing
       the recovery map first means a crash mid-conversion still leaves a
       complete "here is what was touched and where the originals went"
       trail alongside the untouched .BCK files -- recovery never depends on
       the conversion step having completed.
    3. After the real conversion write, PrependConvertComment stamps a short
       provenance comment atop the converted .pas so a reader who opens the
       file later (no recovery.txt in hand) can still see it was machine-
       converted, when, from what backup, and under which rules file.

  All I/O here is plain ANSI + CRLF (matching the project-wide Delphi source
  convention and TTextEditApplier's own encoding discipline) -- BackupFiles
  copies raw bytes (encoding-agnostic), recovery.txt and the prepended
  comment are written explicitly as ANSI/CRLF text.
}

interface

uses
  System.SysUtils,
  System.Generics.Collections;

/// <summary>Returns the next free backup path for APath, of the form
/// "APath.BCK&lt;n&gt;" -- the lowest positive integer n for which that path
/// does not already exist on disk.</summary>
/// <param name="APath">The file to compute a backup name for (the file itself
/// need not exist; only the candidate backup paths are probed).</param>
/// <returns>"APath.BCK1" if unused, else "APath.BCK2", etc. -- the first n
/// (starting at 1) whose backup path is not already occupied.</returns>
/// <remarks>
/// Pure with respect to its inputs but reads the filesystem (FileExists
/// probes); not atomic -- a concurrent writer could race this, which is
/// acceptable for drag-lint's single-user CLI usage.
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Convert.Backup.BackupFiles (DRagLint.Convert.Backup.pas)
/// Calls: IntToStr
/// Touches: file system
/// <!-- drag-lint:auto END -->
/// </remarks>
function NextBackupName(const APath: string): string;

/// <summary>Copies each file in APaths to its own NextBackupName sibling.</summary>
/// <param name="APaths">The distinct file paths about to be overwritten by the
/// conversion write.</param>
/// <param name="AMappings">Receives one "orig -> backup" string per file in
/// APaths, in the same order, suitable for WriteRecoveryRecord and for the
/// human-readable report.</param>
/// <remarks>
/// Each file gets its OWN next-free n via NextBackupName -- the .pas
/// and .dfm of the same unit may end up with different n's if one of them
/// already has stray .BCK files from an earlier run. Raises if a source file
/// does not exist or the copy fails (TFile.Copy); callers should backup BEFORE
/// any conversion write so a failed backup aborts before anything is touched.
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.CLI.DoConvertApply (DRagLint.CLI.pas)
/// Calls: DRagLint.Convert.Backup.NextBackupName, Format
/// Mutates: AMappings (out)
/// Touches: file system
/// <seealso cref="DRagLint.Convert.Backup.NextBackupName"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure BackupFiles(const APaths: TArray<string>; out AMappings: TArray<string>);

/// <summary>Appends a timestamped recovery block to "recovery.txt" in
/// AUnitFolder, creating the file if it does not yet exist.</summary>
/// <param name="AUnitFolder">The folder to write/append recovery.txt in
/// (normally the folder containing the converted unit's .pas/.dfm).</param>
/// <param name="ATimestamp">A pre-formatted timestamp string (see the CLI verb
/// for FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) -- this unit does not read
/// the clock itself, keeping it a pure string-in/file-out routine).</param>
/// <param name="ARulesFile">Path to the conversion rules file used for this
/// run, recorded in the block header.</param>
/// <param name="AMappings">The "orig -> backup" lines from BackupFiles, one
/// per touched file, recorded under the header line.</param>
/// <remarks>
/// Block format:
/// <code>
/// [&lt;timestamp&gt;] convert-apply --rules &lt;rulesfile&gt;
/// &lt;origPas&gt; -&gt; &lt;backupPas&gt;
/// &lt;origDfm&gt; -&gt; &lt;backupDfm&gt;
/// </code>
/// MUST be called BEFORE the conversion write -- see this unit's header remarks:
/// a crash between this call and the actual write still leaves a complete
/// recovery map pointing at the (untouched) .BCK backups.
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.CLI.DoConvertApply (DRagLint.CLI.pas)
/// Calls: Format
/// Touches: file system
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure WriteRecoveryRecord(const AUnitFolder, ATimestamp, ARulesFile: string;
  const AMappings: TArray<string>);

/// <summary>Prepends a short provenance comment block atop the converted
/// .pas file at APasPath.</summary>
/// <param name="APasPath">The already-converted .pas file to stamp (the write
/// happens in place: read the current content, prepend, write back).</param>
/// <param name="ATimestamp">Pre-formatted timestamp string, same convention as
/// WriteRecoveryRecord.</param>
/// <param name="ARulesFile">Path to the conversion rules file used for this run.</param>
/// <param name="AMappings">The "orig -> backup" lines from BackupFiles; only the
/// .pas/.dfm backup targets are rendered into the comment's "backup:" line (in
/// the order given).</param>
/// <remarks>
/// Comment format:
/// <code>
/// drag-lint convert-apply &lt;timestamp&gt;
/// backup: &lt;backupPas&gt; / &lt;backupDfm&gt; ; rules: &lt;rulesfile&gt;
/// </code>
/// Reads and rewrites APasPath as ANSI text with CRLF line endings, matching
/// the rest of the codebase's strict-ASCII/CRLF source-file convention -- this
/// must run AFTER the conversion write (it stamps the already-converted file).
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.CLI.DoConvertApply (DRagLint.CLI.pas)
/// Calls: ExtractFileExt, Format, SameText
/// Touches: file system
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure PrependConvertComment(const APasPath, ATimestamp, ARulesFile: string;
  const AMappings: TArray<string>);

implementation

uses
  System.IOUtils;

function NextBackupName(const APath: string): string;
var
  N: Integer;
  Cand: string;
begin
  N:= 1;
  repeat
    Cand:= APath + '.BCK' + IntToStr(N);
    if not TFile.Exists(Cand) then Exit(Cand);
    Inc(N);
  until False;
end;

procedure BackupFiles(const APaths: TArray<string>; out AMappings: TArray<string>);
var
  List: TList<string>;
  P, Backup: string;
begin
  List:= TList<string>.Create;
  try
    for P in APaths do
    begin
      Backup:= NextBackupName(P);
      TFile.Copy(P, Backup);
      List.Add(Format('%s -> %s', [P, Backup]));
    end;
    AMappings:= List.ToArray;
  finally
    List.Free;
  end;
end;

procedure WriteRecoveryRecord(const AUnitFolder, ATimestamp, ARulesFile: string;
  const AMappings: TArray<string>);
var
  RecoveryPath: string;
  SB: TStringBuilder;
  M: string;
  Existing: TBytes;
begin
  RecoveryPath:= TPath.Combine(AUnitFolder, 'recovery.txt');
  SB:= TStringBuilder.Create;
  try
    SB.Append(Format('[%s] convert-apply --rules %s', [ATimestamp, ARulesFile])).Append(#13#10);
    for M in AMappings do
      SB.Append('  ').Append(M).Append(#13#10);

    if TFile.Exists(RecoveryPath) then
    begin
      Existing:= TFile.ReadAllBytes(RecoveryPath);
      TFile.WriteAllBytes(RecoveryPath, Existing + TEncoding.ANSI.GetBytes(SB.ToString));
    end
    else
      TFile.WriteAllBytes(RecoveryPath, TEncoding.ANSI.GetBytes(SB.ToString));
  finally
    SB.Free;
  end;
end;

procedure PrependConvertComment(const APasPath, ATimestamp, ARulesFile: string;
  const AMappings: TArray<string>);
var
  Existing: TBytes;
  ExistingText, BackupPas, BackupDfm, M, Header: string;
  Parts: TArray<string>;
begin
  BackupPas:= ''; BackupDfm:= '';
  for M in AMappings do
  begin
    Parts:= M.Split([' -> ']);
    if Length(Parts) < 2 then Continue;
    if SameText(ExtractFileExt(Parts[0]), '.pas') and (BackupPas = '') then BackupPas:= Parts[1]
    else if SameText(ExtractFileExt(Parts[0]), '.dfm') and (BackupDfm = '') then BackupDfm:= Parts[1];
  end;

  Header:= Format('// drag-lint convert-apply %s', [ATimestamp]) + #13#10 +
    Format('//   backup: %s / %s ; rules: %s', [BackupPas, BackupDfm, ARulesFile]) + #13#10;

  Existing:= TFile.ReadAllBytes(APasPath);
  ExistingText:= TEncoding.ANSI.GetString(Existing);
  TFile.WriteAllBytes(APasPath, TEncoding.ANSI.GetBytes(Header + ExistingText));
end;

end.
