unit DRagLint.Project.OwnRoots;

/// <summary>One question, asked of a project rather than of an index: is this
/// source file part of the code this project OWNS?</summary>
/// <remarks>Exists because INDEXING scope and LINTING scope are different
/// questions. A project index is the compile closure, which correctly contains
/// vendored third-party source -- 768 of YADF's 1,072 findings were in
/// C:\Projects\DelphiAST, a parser YADF neither owns nor can fix. Lint was
/// inheriting the indexer's answer.
///
/// Ownership CANNOT be inferred here and must be declared. Measured against
/// every configured index: "under the project folder" and "under the VCS root"
/// both drop 295 of ORM3-Micronite2027's own business objects, because
/// Mercurial repositories on this machine are per-folder (CLIENT, SERVER,
/// COMMON and OBJECTS are four repositories of one codebase); and "a different
/// repository means third-party" additionally counts PDFlibPas, which has no
/// repository at all, as ours.
///
/// Deliberately standalone, for the reason DRagLint.Storage.FileMembership
/// gives: the LSP and the IDE plugin need this one answer and must not drag in
/// the lint configuration machinery to get it.
///
/// All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.</remarks>

interface

type
  /// <summary>The directory roots whose files a lint run treats as the project's
  /// own code, plus the answer to "is this file one of them?".</summary>
  /// <remarks>
  /// Value type; copy freely. Immutable after Load. Thread-safe to
  /// share for reading.
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestOwnRoots (DRagLint.CLI.pas), DRagLint.Doc.Batch.FilterToOwnRoots (DRagLint.Doc.Batch.pas), declaration (DRagLint.Project.OwnRoots.pas)
  /// Used in units: DRagLint.CLI, DRagLint.Doc.Batch, DRagLint.Project.OwnRoots
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TOwnRoots = record
  strict private
    FRoots   : TArray<string>;
    FAnchor  : string        ;
    FDeclared: Boolean       ;
    FError   : string        ;
    FActive  : Boolean       ;
  public
    /// <summary>Reads &lt;AAnchorDir&gt;\_D-RAG\drag-lint-project.json and resolves
    /// its "ownRoots", or falls back to the anchor directory itself.</summary>
    /// <param name="AAnchorDir">The project file's folder. Pass '' when no anchor
    /// could be determined; the result then treats EVERY file as ours, so an
    /// unanchored run behaves exactly as it did before this unit existed.</param>
    /// <returns>A populated record. Check Error before use: a non-empty Error
    /// means the declaration was present but unusable and the caller must refuse
    /// to lint rather than silently scope to something unintended.</returns>
    /// <remarks>
    /// An entry may be absolute or relative to AAnchorDir; a relative
    /// entry keeps a declaration portable ("[..]" from ORM3\CLIENT). A missing,
    /// unreadable or malformed file is NOT an error -- it defaults. An explicit
    /// empty "ownRoots": [] IS an error, because scoping to nothing would report
    /// a clean project, the same reasoning as the empty --project refusal.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestOwnRoots (DRagLint.CLI.pas), DRagLint.Doc.Batch.FilterToOwnRoots (DRagLint.Doc.Batch.pas)
    /// Calls: Default, DRagLint.Project.OwnRoots.NormalizeDir, ExcludeTrailingPathDelimiter, ExpandFileName, Format, TJSONObject, Trim
    /// Returns: Default(TOwnRoots)
    /// Touches: file system
    /// <seealso cref="DRagLint.Project.OwnRoots.NormalizeDir"/>
    /// <seealso cref="DRagLint.Project.OwnRoots.TOwnRoots.IsOurs"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Load(const AAnchorDir: string): TOwnRoots; static;
    /// <summary>True when AFilePath sits under one of the roots.</summary>
    /// <param name="AFilePath">Absolute or relative source path.</param>
    /// <returns>True for our code; always True when the record is inactive
    /// (no anchor).</returns>
    /// <remarks>
    /// Path comparison mirrors
    /// DRagLint.Storage.FileMembership.NormalizeForLookup: forward slashes
    /// folded to backslashes, compared case-insensitively.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoSelfTestOwnRoots (DRagLint.CLI.pas), DRagLint.Doc.Batch.FilterToOwnRoots (DRagLint.Doc.Batch.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas) ?
    /// Calls: ExpandFileName, StartsText, StringReplace
    /// Returns: True; False
    /// Reads: FActive, FRoots
    /// Pure
    /// <seealso cref="DRagLint.Project.OwnRoots.TOwnRoots.Load"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsOurs(const AFilePath: string): Boolean;
    /// <summary>Resolved roots, each with a trailing path delimiter.</summary>
    property Roots: TArray<string> read FRoots;
    /// <summary>The project folder this was loaded for.</summary>
    property Anchor: string read FAnchor;
    /// <summary>True when a drag-lint-project.json supplied the roots; False
    /// when they were defaulted to the anchor.</summary>
    property Declared: Boolean read FDeclared;
    /// <summary>Non-empty when the declaration was present but unusable.</summary>
    property Error: string read FError;
    /// <summary>False when there is no anchor and IsOurs always answers True.</summary>
    property Active: Boolean read FActive;
  end;

/// <summary>The project folder for an index that lives in a _D-RAG home.</summary>
/// <param name="ADbPath">Path to a .sqlite index.</param>
/// <returns>The parent of the _D-RAG folder, without a trailing delimiter, or
/// '' when the DB is not inside one.</returns>
/// <remarks>
/// This is why the index moved next to its project: the anchor is a
/// property of the path, so no manifest lookup and no CWD-sensitive config
/// discovery is needed to find a project's declaration.
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.CLI.DoSelfTestOwnRoots (DRagLint.CLI.pas), DRagLint.CLI.LintAnchorDir (DRagLint.CLI.pas)
/// Calls: ExpandFileName, ExtractFileDir, ExtractFileName, SameText, StringReplace
/// Returns: ''; ExtractFileDir(Dir)
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function AnchorDirForDb(const ADbPath: string): string;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.IOUtils
  , System.JSON
  , DRagLint.Core.Model
  ;

function NormalizeDir(const APath: string): string;
begin
  Result:= '';
  if APath = '' then Exit;
  Result:= IncludeTrailingPathDelimiter(
             ExpandFileName(StringReplace(APath, '/', '\', [rfReplaceAll])));
end;

function AnchorDirForDb(const ADbPath: string): string;
var
  Dir: string;
begin
  Result:= '';
  if ADbPath = '' then Exit;
  Dir:= ExtractFileDir(ExpandFileName(StringReplace(ADbPath, '/', '\', [rfReplaceAll])));
  if not SameText(ExtractFileName(Dir), DRAG_HOME_DIR) then Exit;
  Result:= ExtractFileDir(Dir);
end;

class function TOwnRoots.Load(const AAnchorDir: string): TOwnRoots;
var
  CfgPath: string     ;
  JVal   : TJSONValue ;
  Root   : TJSONObject;
  Arr    : TJSONArray ;
  V      : TJSONValue ;
  Entry  : string     ;
begin
  Result         := Default(TOwnRoots);
  Result.FActive := AAnchorDir <> '';
  if not Result.FActive then Exit;

  Result.FAnchor:= ExcludeTrailingPathDelimiter(ExpandFileName(AAnchorDir));
  CfgPath       := TPath.Combine(TPath.Combine(Result.FAnchor, DRAG_HOME_DIR), 'drag-lint-project.json');

  if TFile.Exists(CfgPath) then
  try
    { Parse into the base TJSONValue FIRST and free it in a finally that covers
      every exit from this block. The earlier `... as TJSONObject` cast raised
      EInvalidCast (on a root that parses but is not an object, e.g. `["a"]`)
      BEFORE the assignment to Root completed -- the parsed value was still
      live but never reachable to free, so it leaked on every malformed file.
      This unit serves the LSP, a long-running process that reloads this file
      repeatedly, so that leak was not academic. }
    JVal:= TJSONObject.ParseJSONValue(TFile.ReadAllText(CfgPath));
    try
      if JVal is TJSONObject then
      begin
        Root:= TJSONObject(JVal);
        if Root.GetValue('ownRoots') is TJSONArray then
        begin
          Arr:= Root.GetValue('ownRoots') as TJSONArray;
          if Arr.Count = 0 then
          begin
            Result.FError:= Format('%s declares an empty "ownRoots". Remove the key to ' +
              'default to the project folder, or list the roots -- scoping to nothing ' +
              'would report a clean project.', [CfgPath]);
            Exit;
          end;
          for V in Arr do
          begin
            Entry:= Trim(V.Value);
            if Entry = '' then Continue;
            if TPath.IsRelativePath(Entry) then Entry:= TPath.Combine(Result.FAnchor, Entry);
            Result.FRoots:= Result.FRoots + [NormalizeDir(Entry)];
          end;
          Result.FDeclared:= Length(Result.FRoots) > 0;
        end;
      end;
    finally
      JVal.Free;
    end;
  except
    { A malformed declaration defaults rather than throws: the fallback is the
      project's own folder, which is never WRONG, only narrow. The parse
      failure itself is swallowed HERE -- E.Message is not captured onto this
      record anywhere, so from TOwnRoots' properties alone a malformed
      drag-lint-project.json is indistinguishable from no declaration at all;
      Declared = False is the only signal this record gives. A caller that
      needs to report WHY defaulting happened must re-read/re-parse the file
      itself. }
    on E: Exception do Result.FDeclared:= False;
  end;

  if not Result.FDeclared then Result.FRoots:= [NormalizeDir(Result.FAnchor)];
end;

function TOwnRoots.IsOurs(const AFilePath: string): Boolean;
var
  P: string;
  R: string;
begin
  Result:= True;
  if not FActive then Exit;
  if AFilePath = '' then Exit;
  P:= ExpandFileName(StringReplace(AFilePath, '/', '\', [rfReplaceAll]));
  for R in FRoots do
    if (R <> '') and StartsText(R, P) then Exit(True);
  Result:= False;
end;

end.
