unit DRagLint.Core.JsonFile;

{ Writing a JSON file that a HUMAN maintains.

  WHY THIS UNIT EXISTS AT ALL
  ---------------------------
  drag-lint.json is hand-edited, lives in a git repository, and is read by other
  tools. Three properties therefore matter beyond "the keys are correct":

    * PRETTY-PRINTED. Minifying it destroys its readability and every future
      diff of it. Nothing gains from the smaller bytes.
    * NO BYTE-ORDER MARK. jq and strict JSON parsers choke on one;
      TFile.ReadAllText silently SKIPS it, so a tool that writes a BOM can never
      see its own damage.
    * ATOMIC. A plain write truncates the target before writing a byte, so an
      interruption leaves the file empty -- losing every section, not just the
      one being saved.

  Getting any of the three wrong fails silently. That is what happened: the
  correct implementation lived inside TManifestIO.Save, three copies in the IDE
  plugin's options pages did TFile.WriteAllText(Path, Root.ToJSON,
  TEncoding.UTF8) instead, and one of them carried a comment claiming it matched
  Save "byte-for-byte" -- the reverse of the truth. Pressing OK in Tools >
  Options collapsed a 313-line manifest to a single 5 KB line with a BOM on
  2026-08-27. No data was lost, which is exactly why nobody noticed.

  WHY src\core AND NOT src\index
  ------------------------------
  Two reasons, both learned the hard way in one battery run:

    * src\index is inside the extraction surface that
      run_extractor_version_guard.ps1 hashes, so a helper living there makes
      every future edit to it argue about DRAGLINT_EXTRACTOR_VERSION -- for code
      that cannot affect a parse.
    * the IDE plugin's design-time package compiles against src\delphi-plugin,
      src\lint and src\core only (tests\fixtures\T64_lint_options_compile.bat).
      A plugin unit that reached into src\index simply did not build.

  So the shared helper belongs where both halves already look. }

interface

uses
  System.JSON;

/// <summary>Writes ARoot over APath: pretty-printed, UTF-8 with NO byte-order
/// mark, swapped into place with one atomic filesystem operation.</summary>
/// <param name="APath">The file to replace. It need not already exist.</param>
/// <param name="ARoot">The document to write. The CALLER keeps ownership and
/// must free it; nil is a no-op.</param>
/// <exception cref="EOSError">Raised when the atomic swap fails -- loudly, so a
/// caller cannot mistake a failed save for a successful one. The original file
/// is left completely untouched in that case.</exception>
/// <remarks>Not thread-safe against concurrent writers of the same path; the
/// swap is atomic, so the loser simply overwrites rather than interleaving.</remarks>
procedure WriteJsonFileAtomic(const APath: string; ARoot: TJSONObject);

implementation

uses
  System.SysUtils
  , System.IOUtils
  , Winapi.Windows   { MoveFileEx / MOVEFILE_REPLACE_EXISTING -- the atomic swap }
  ;

procedure WriteJsonFileAtomic(const APath: string; ARoot: TJSONObject);
var
  JsonText: string;
  TmpPath : string;
begin
  if ARoot = nil then Exit;

  { Format(2), NOT ToJSON -- see this unit's header for why the shape of the
    file is part of the contract rather than decoration. }
  JsonText:= ARoot.Format(2);

  { Atomic write. migrate-dbs calls this once per section moved -- up to 27
    times in one unattended run -- against the user's real, hand-maintained
    manifest. A plain TFile.WriteAllText TRUNCATES APath before writing a byte
    of the new content, so an interruption mid-write (a crash, a kill, a power
    loss) would leave drag-lint.json truncated or empty, losing every section's
    mapping and not just the one being saved right now. Write the full new
    content to a sibling temp file first (nothing yet depends on it), then swap
    it into place with ONE atomic filesystem operation: a MoveFileEx rename with
    MOVEFILE_REPLACE_EXISTING, which either fully succeeds or leaves the
    ORIGINAL file completely untouched -- there is no observable half-written
    state either way, whether or not APath already exists (the same call handles
    the very first save too).

    NOT TFile.Replace: its Delphi wrapper unconditionally runs its
    backup-filename parameter through TPath.GetFullPath, which raises
    EInOutArgumentException on an empty string -- there is no way to ask it for
    "no backup" even though the underlying Win32 ReplaceFile supports that
    directly (a NULL backup pointer), so the wrapper cannot be used without
    leaving a stray .bak file behind on every single save. MoveFileEx needs no
    backup at all. }

  { GetBytes, not WriteAllText(..., TEncoding.UTF8). TEncoding.UTF8 carries a
    PREAMBLE and WriteAllText emits it, so a hand-maintained drag-lint.json --
    which a real user edits, and which other, non-Delphi tooling (jq, a strict
    JSON parser) reads -- would open with EF BB BF at byte 0. TFile.ReadAllText
    silently skips a BOM on the way back in, which is exactly why this went
    unnoticed from inside drag-lint itself. GetBytes returns the same UTF-8
    WITHOUT the preamble: a manifest that needs a non-ASCII character (an
    accented path) still round-trips as UTF-8, while the ordinary all-ASCII
    manifest stays byte-for-byte plain ASCII, matching the file the user
    started with. }
  TmpPath:= APath + '.tmp';
  TFile.WriteAllBytes(TmpPath, TEncoding.UTF8.GetBytes(JsonText));
  try
    if not MoveFileEx(PChar(TmpPath), PChar(APath),
                      MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
      RaiseLastOSError;
  except
    if TFile.Exists(TmpPath) then TFile.Delete(TmpPath);
    raise;
  end; // try
end;

end.
