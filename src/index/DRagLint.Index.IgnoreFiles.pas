unit DRagLint.Index.IgnoreFiles;

// Practical .gitignore / .hgignore engine for the drag-lint index manifest.
// Semantics: per-line glob rules; '#' = comment; trailing '/' = dir-only;
// leading '!' = negation (re-include); last matching rule across all stacked
// layers wins (outermost-first, top-to-bottom within each layer).

interface

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections
  ;

type
  /// <summary>Stack of ignore rules accumulated while descending a directory
  /// tree. Deeper (later-pushed) directories' rules take precedence; a leading
  /// '!' re-includes. Honors .gitignore AND .hgignore (practical subset:
  /// per-line glob, '#' comments, trailing '/' = dir-only, leading '!' =
  /// negation).</summary>
  /// <remarks>
  /// v0.46: .hgignore syntax handling. Mercurial's DEFAULT syntax is
  /// 'regexp', switched to glob by a 'syntax: glob' line. Lines that are in
  /// effect under regexp syntax (i.e. before any 'syntax: glob' switch, or
  /// after a 'syntax: regexp' switch) are NOT valid globs and are SKIPPED --
  /// feeding them to the glob matcher would mis-interpret '/'-, '~'- and
  /// '- '-bearing regexps as globs. Only glob-syntax lines become rules.
  /// .gitignore is always glob. Matching uses TGlob's direct linear matcher,
  /// so no pattern can cause pathological CPU/stack behavior on the walk.
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoSelfTestIgnoreFiles (DRagLint.CLI.pas), declaration (DRagLint.Core.Indexer.pas), DRagLint.Core.Indexer.TIndexer.SetWalkFilter (DRagLint.Core.Indexer.pas)
  /// Used in units: DRagLint.CLI, DRagLint.Core.Indexer
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TIgnoreStack = class
    private
      type
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// Used by: DRagLint.Index.IgnoreFiles.TIgnoreStack.ParseIgnoreFile (DRagLint.Index.IgnoreFiles.pas), DRagLint.Index.IgnoreFiles.TIgnoreStack.PushDir (DRagLint.Index.IgnoreFiles.pas), DRagLint.Index.IgnoreFiles.TIgnoreStack.IsIgnored (DRagLint.Index.IgnoreFiles.pas)
        /// Used in units: DRagLint.Index.IgnoreFiles
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.Create"/>
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.Destroy"/>
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.IsIgnored"/>
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.ParseIgnoreFile"/>
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.PopDir"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        TRule = record
        Pattern: string ; // glob pattern (stripped of leading '!')
        DirOnly: Boolean; // rule applies to directories only (trailing '/')
        Negated: Boolean; // leading '!' -> re-include if matched
        HasSep : Boolean; // pattern contains a path separator (precomputed)
      end;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Used by: declaration (DRagLint.Index.IgnoreFiles.pas), DRagLint.Index.IgnoreFiles.TIgnoreStack.Create (DRagLint.Index.IgnoreFiles.pas), DRagLint.Index.IgnoreFiles.TIgnoreStack.ParseIgnoreFile (DRagLint.Index.IgnoreFiles.pas), DRagLint.Index.IgnoreFiles.TIgnoreStack.PushDir (DRagLint.Index.IgnoreFiles.pas), DRagLint.Index.IgnoreFiles.TIgnoreStack.IsIgnored (DRagLint.Index.IgnoreFiles.pas)
      /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.Create"/>
      /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.Destroy"/>
      /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.IsIgnored"/>
      /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.ParseIgnoreFile"/>
      /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.PopDir"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      TLayer = TList<TRule>;

    var
      FLayers: TObjectList<TLayer>; // index 0 = outermost; last = innermost

      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AIsHg"><!-- drag-lint:auto type -->Boolean</param>
      /// <returns><!-- drag-lint:auto -->Observed: TLayer.Create.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Index.IgnoreFiles.TIgnoreStack.PushDir (DRagLint.Index.IgnoreFiles.pas)
      /// Calls: Copy, Default, Pos, Trim
      /// Complexity: 12 (cyclomatic, outer body), 55 lines (full implementation)
      /// Owns returned: new (caller owns)
      /// Touches: file system
      /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.Create"/>
      /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.Destroy"/>
      /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.IsIgnored"/>
      /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.PopDir"/>
      /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.PushDir"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function ParseIgnoreFile(const APath: string; AIsHg: Boolean): TLayer; static;
      public
        /// <summary><!-- drag-lint:auto -->TIgnoreStack</summary>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// Called from: DRagLint.CLI.DoSelfTestIgnoreFiles (DRagLint.CLI.pas), DRagLint.Core.Indexer.TIndexer.SetWalkFilter (DRagLint.Core.Indexer.pas)
        /// Pure
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.Destroy"/>
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.IsIgnored"/>
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.ParseIgnoreFile"/>
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.PopDir"/>
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.PushDir"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        constructor Create;
        destructor Destroy; override;

        /// <summary>Load .gitignore + .hgignore (if present) from ADir and push
        /// them as the new innermost (highest-precedence) layer.</summary>
        /// <param name="ADir">Directory to load ignore files from.</param>
        /// <remarks>
        /// Each call to PushDir must be balanced by a PopDir call when
        /// leaving the directory. Multiple ignore files in the same directory are
        /// merged into one layer in git-first, hg-second order.
        /// <!-- drag-lint:auto BEGIN -->
        /// Called from: DRagLint.CLI.DoSelfTestIgnoreFiles (DRagLint.CLI.pas), DRagLint.Core.Indexer.TIndexer.WalkAndIndex (DRagLint.Core.Indexer.pas)
        /// Calls: DRagLint.Index.IgnoreFiles.TIgnoreStack.ParseIgnoreFile
        /// Touches: file system
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.ParseIgnoreFile"/>
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.Create"/>
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.Destroy"/>
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.IsIgnored"/>
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.PopDir"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        procedure PushDir(const ADir: string);

        /// <summary>Pop the innermost layer (call when leaving a directory).</summary>
        /// <remarks>
        /// Safe to call when the stack is empty; the call is a no-op in
        /// that case.
        /// <!-- drag-lint:auto BEGIN -->
        /// Called from: DRagLint.CLI.DoSelfTestIgnoreFiles (DRagLint.CLI.pas), DRagLint.Core.Indexer.TIndexer.WalkAndIndex (DRagLint.Core.Indexer.pas)
        /// Pure
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.Create"/>
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.Destroy"/>
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.IsIgnored"/>
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.ParseIgnoreFile"/>
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.PushDir"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        procedure PopDir;

        /// <summary>True if APath (a file or directory) is ignored under the current
        /// stack. AIsDir distinguishes dir-only ('foo/') rules. APath may be a full
        /// path or a name; matching uses the base name and the path tail.</summary>
        /// <param name="APath">Full path, partial path, or bare name to test.</param>
        /// <param name="AIsDir">True when APath refers to a directory.</param>
        /// <returns>True if the last matching rule ignores the candidate; False if
        /// no rule matches or the last match is a negation rule.</returns>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// Called from: DRagLint.CLI.DoSelfTestIgnoreFiles (DRagLint.CLI.pas), DRagLint.Core.Indexer.TIndexer.WalkAndIndex (DRagLint.Core.Indexer.pas)
        /// Calls: DRagLint.Index.Glob.TGlob.Matches, DRagLint.Index.IgnoreFiles.BaseName, DRagLint.Index.IgnoreFiles.NormPath
        /// Returns: False; not Rule.Negated
        /// Pure
        /// <seealso cref="DRagLint.Index.Glob.TGlob.Matches"/>
        /// <seealso cref="DRagLint.Index.IgnoreFiles.BaseName"/>
        /// <seealso cref="DRagLint.Index.IgnoreFiles.NormPath"/>
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.Create"/>
        /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.Destroy"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        function IsIgnored(const APath: string; AIsDir: Boolean): Boolean;
  end;

implementation

uses
  System.IOUtils
  , DRagLint.Index.Glob
  ;

{ ---- helpers ---------------------------------------------------------------- }

// Extract the base name (last component after any path separator).
function BaseName(const APath: string): string;
var
  I: Integer;
begin
  Result:= APath;
  for I:= Length(APath) downto 1 do
    if (APath[I] = '\') or (APath[I] = '/') then
    begin
      Result:= Copy(APath, I + 1, MaxInt);
      Break;
    end;
end;

// Normalize backslashes to forward slashes.
function NormPath(const S: string): string;
begin
  Result:= StringReplace(S, '\', '/', [rfReplaceAll]);
end;

{ TIgnoreStack }

constructor TIgnoreStack.Create;
begin
  inherited Create;
  FLayers:= TObjectList<TLayer>.Create(True); // owns layers
end;

destructor TIgnoreStack.Destroy;
begin
  FLayers.Free;
  inherited;
end;

class function TIgnoreStack.ParseIgnoreFile(const APath: string; AIsHg: Boolean): TLayer;
var
  Lines     : TStringList;
  Line      : string     ;
  Rule      : TRule      ;
  GlobSyntax: Boolean    ; // hg: current line syntax (False=regexp default, True=glob)
begin
  Result:= TLayer.Create;
  if not TFile.Exists(APath) then Exit;
  // .gitignore is always glob. .hgignore defaults to 'regexp' until a
  // 'syntax: glob' directive switches it; regexp-syntax lines are skipped.
  GlobSyntax:= not AIsHg;
  Lines:= TStringList.Create;
  try
    Lines.LoadFromFile(APath);
    for Line in Lines do
    begin
      // Trim leading/trailing whitespace.
      var Trimmed:= Trim(Line);
      // Skip blank lines and comments.
      if (Trimmed = '') or (Trimmed[1] = '#') then Continue;
      // Handle .hgignore 'syntax:' directive: switch mode, then skip the line.
      if AIsHg and Trimmed.StartsWith('syntax:', True) then
      begin
        var Mode:= Trim(Copy(Trimmed, Length('syntax:') + 1, MaxInt)).ToLower;
        GlobSyntax:= (Mode = 'glob');
        Continue;
      end;
      // Skip lines that are not glob syntax (hg regexp-mode lines): treating a
      // regexp as a glob would feed '/'-, '~'- and '- '-bearing patterns to the
      // matcher with the wrong meaning. Safe, documented choice.
      if not GlobSyntax then Continue;
      Rule:= Default(TRule);
      // Leading '!' = negation.
      if Trimmed[1] = '!' then
      begin
        Rule.Negated:= True;
        Trimmed:= Copy(Trimmed, 2, MaxInt);
        if Trimmed = '' then Continue;
      end;
      // Trailing '/' = directory-only rule; strip it.
      if Trimmed[Length(Trimmed)] = '/' then
      begin
        Rule.DirOnly:= True;
        Trimmed:= Copy(Trimmed, 1, Length(Trimmed) - 1);
        if Trimmed = '' then Continue;
      end;
      Rule.Pattern:= Trimmed;
      // Precompute separator presence so IsIgnored need not re-scan per call.
      Rule.HasSep:= (Pos('/', Trimmed) > 0) or (Pos('\', Trimmed) > 0);
      Result.Add(Rule);
    end; // for
  finally
    Lines.Free;
  end; // try
end; // function

procedure TIgnoreStack.PushDir(const ADir: string);
var
  Layer   : TLayer;
  GitLayer: TLayer;
  HgLayer : TLayer;
  R       : TRule ;
begin
  Layer:= TLayer.Create;
  GitLayer:= nil;
  HgLayer := nil;
  try
    GitLayer:= ParseIgnoreFile(TPath.Combine(ADir, '.gitignore'), False);
    HgLayer := ParseIgnoreFile(TPath.Combine(ADir, '.hgignore' ), True );
    // git rules first, then hg rules (merged into one layer).
    for R in GitLayer do Layer.Add(R);
    for R in HgLayer  do Layer.Add(R);
    FLayers.Add(Layer);
    Layer:= nil; // ownership transferred
  finally
    GitLayer.Free;
    HgLayer.Free;
    Layer.Free; // no-op if ownership was transferred
  end;
end; // procedure

procedure TIgnoreStack.PopDir;
begin
  if FLayers.Count > 0 then FLayers.Delete(FLayers.Count - 1);
end;

function TIgnoreStack.IsIgnored(const APath: string; AIsDir: Boolean): Boolean;
var
  LayerIdx: Integer;
  RuleIdx : Integer;
  Layer   : TLayer ;
  Rule    : TRule  ;
  Base    : string ;
  Norm    : string ;
  Matched : Boolean;
begin
  Result:= False; // default: not ignored
  Base:= BaseName(APath);
  Norm:= NormPath(APath);

  // Scan outermost layer (index 0) to innermost (index Count-1);
  // last match wins.
  for LayerIdx:= 0 to FLayers.Count - 1 do
  begin
    Layer:= FLayers[LayerIdx];
    for RuleIdx:= 0 to Layer.Count - 1 do
    begin
      Rule:= Layer[RuleIdx];
      // Dir-only rules do not apply to plain files.
      if Rule.DirOnly and not AIsDir then Continue;
      // Match: try base name first; if pattern contains a separator also try
      // the full path tail (HasSep precomputed at parse time).
      Matched:= TGlob.Matches(Base, Rule.Pattern);
      if (not Matched) and Rule.HasSep then Matched:= TGlob.Matches(Norm, Rule.Pattern);
      if Matched then Result:= not Rule.Negated; // '!' flips the decision
    end;
  end; // for
end; // function

end.
