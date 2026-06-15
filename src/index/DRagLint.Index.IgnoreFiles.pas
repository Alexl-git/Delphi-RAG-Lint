unit DRagLint.Index.IgnoreFiles;

// Practical .gitignore / .hgignore engine for the drag-lint index manifest.
// Semantics: per-line glob rules; '#' = comment; trailing '/' = dir-only;
// leading '!' = negation (re-include); last matching rule across all stacked
// layers wins (outermost-first, top-to-bottom within each layer).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

type
  /// <summary>Stack of ignore rules accumulated while descending a directory
  /// tree. Deeper (later-pushed) directories' rules take precedence; a leading
  /// '!' re-includes. Honors .gitignore AND .hgignore (practical subset:
  /// per-line glob, '#' comments, trailing '/' = dir-only, leading '!' =
  /// negation; .hgignore 'syntax:' lines are skipped).</summary>
  TIgnoreStack = class
  private
    type
      TRule = record
        Pattern: string;  // glob pattern (stripped of leading '!')
        DirOnly: Boolean; // rule applies to directories only (trailing '/')
        Negated: Boolean; // leading '!' -> re-include if matched
      end;
      TLayer = TList<TRule>;

    var
      FLayers: TObjectList<TLayer>; // index 0 = outermost; last = innermost

    class function ParseIgnoreFile(const APath: string;
      AIsHg: Boolean): TLayer; static;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Load .gitignore + .hgignore (if present) from ADir and push
    /// them as the new innermost (highest-precedence) layer.</summary>
    /// <param name="ADir">Directory to load ignore files from.</param>
    /// <remarks>Each call to PushDir must be balanced by a PopDir call when
    /// leaving the directory. Multiple ignore files in the same directory are
    /// merged into one layer in git-first, hg-second order.</remarks>
    procedure PushDir(const ADir: string);

    /// <summary>Pop the innermost layer (call when leaving a directory).</summary>
    /// <remarks>Safe to call when the stack is empty; the call is a no-op in
    /// that case.</remarks>
    procedure PopDir;

    /// <summary>True if APath (a file or directory) is ignored under the current
    /// stack. AIsDir distinguishes dir-only ('foo/') rules. APath may be a full
    /// path or a name; matching uses the base name and the path tail.</summary>
    /// <param name="APath">Full path, partial path, or bare name to test.</param>
    /// <param name="AIsDir">True when APath refers to a directory.</param>
    /// <returns>True if the last matching rule ignores the candidate; False if
    /// no rule matches or the last match is a negation rule.</returns>
    function IsIgnored(const APath: string; AIsDir: Boolean): Boolean;
  end;

implementation

uses
  System.IOUtils,
  DRagLint.Index.Glob;

{ ---- helpers ---------------------------------------------------------------- }

// Extract the base name (last component after any path separator).
function BaseName(const APath: string): string;
var
  I: Integer;
begin
  Result := APath;
  for I := Length(APath) downto 1 do
    if (APath[I] = '\') or (APath[I] = '/') then
    begin
      Result := Copy(APath, I + 1, MaxInt);
      Break;
    end;
end;

// Normalize backslashes to forward slashes.
function NormPath(const S: string): string;
begin
  Result := StringReplace(S, '\', '/', [rfReplaceAll]);
end;

{ TIgnoreStack }

constructor TIgnoreStack.Create;
begin
  inherited Create;
  FLayers := TObjectList<TLayer>.Create(True); // owns layers
end;

destructor TIgnoreStack.Destroy;
begin
  FLayers.Free;
  inherited;
end;

class function TIgnoreStack.ParseIgnoreFile(const APath: string;
  AIsHg: Boolean): TLayer;
var
  Lines: TStringList;
  Line:  string;
  Rule:  TRule;
begin
  Result := TLayer.Create;
  if not TFile.Exists(APath) then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(APath);
    for Line in Lines do
    begin
      // Trim leading/trailing whitespace.
      var Trimmed := Trim(Line);
      // Skip blank lines and comments.
      if (Trimmed = '') or (Trimmed[1] = '#') then
        Continue;
      // Skip .hgignore 'syntax:' directive lines.
      if AIsHg and Trimmed.StartsWith('syntax:', True) then
        Continue;
      Rule := Default(TRule);
      // Leading '!' = negation.
      if Trimmed[1] = '!' then
      begin
        Rule.Negated := True;
        Trimmed := Copy(Trimmed, 2, MaxInt);
        if Trimmed = '' then Continue;
      end;
      // Trailing '/' = directory-only rule; strip it.
      if Trimmed[Length(Trimmed)] = '/' then
      begin
        Rule.DirOnly := True;
        Trimmed := Copy(Trimmed, 1, Length(Trimmed) - 1);
        if Trimmed = '' then Continue;
      end;
      Rule.Pattern := Trimmed;
      Result.Add(Rule);
    end;
  finally
    Lines.Free;
  end;
end;

procedure TIgnoreStack.PushDir(const ADir: string);
var
  Layer: TLayer;
  GitLayer, HgLayer: TLayer;
  R: TRule;
begin
  Layer     := TLayer.Create;
  GitLayer  := nil;
  HgLayer   := nil;
  try
    GitLayer := ParseIgnoreFile(TPath.Combine(ADir, '.gitignore'), False);
    HgLayer  := ParseIgnoreFile(TPath.Combine(ADir, '.hgignore'),  True);
    // git rules first, then hg rules (merged into one layer).
    for R in GitLayer do Layer.Add(R);
    for R in HgLayer  do Layer.Add(R);
    FLayers.Add(Layer);
    Layer := nil; // ownership transferred
  finally
    GitLayer.Free;
    HgLayer.Free;
    Layer.Free;   // no-op if ownership was transferred
  end;
end;

procedure TIgnoreStack.PopDir;
begin
  if FLayers.Count > 0 then
    FLayers.Delete(FLayers.Count - 1);
end;

function TIgnoreStack.IsIgnored(const APath: string; AIsDir: Boolean): Boolean;
var
  LayerIdx: Integer;
  RuleIdx:  Integer;
  Layer:    TLayer;
  Rule:     TRule;
  Base:     string;
  Norm:     string;
  Matched:  Boolean;
begin
  Result  := False; // default: not ignored
  Base    := BaseName(APath);
  Norm    := NormPath(APath);

  // Scan outermost layer (index 0) to innermost (index Count-1);
  // last match wins.
  for LayerIdx := 0 to FLayers.Count - 1 do
  begin
    Layer := FLayers[LayerIdx];
    for RuleIdx := 0 to Layer.Count - 1 do
    begin
      Rule := Layer[RuleIdx];
      // Dir-only rules do not apply to plain files.
      if Rule.DirOnly and not AIsDir then
        Continue;
      // Match: try base name first; if pattern contains '/' also try path tail.
      Matched := TGlob.Matches(Base, Rule.Pattern);
      if (not Matched) and
         ((Pos('/', NormPath(Rule.Pattern)) > 0) or
          (Pos('\', Rule.Pattern) > 0)) then
        Matched := TGlob.Matches(Norm, Rule.Pattern);
      if Matched then
        Result := not Rule.Negated; // '!' flips the decision
    end;
  end;
end;

end.
