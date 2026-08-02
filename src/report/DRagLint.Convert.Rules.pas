unit DRagLint.Convert.Rules;

{
  Track 3 (component conversion), Batch 1, Task 2 -- the reFind-SUPERSET
  conversion-rules DSL parser + validator that backs the CLI `convert-validate`
  verb (and, later, the convert-scaffold generator + an apply step in Batch 2+).

  The DSL is a strict superset of RAD Studio's reFind rule language (readme.txt
  section 3.2): it ADOPTS reFind's #unuse / #remove / #migrate directives and the
  raw-PCRE ' -> ' escape hatch verbatim, and ADDS four drag-lint directives that
  reFind lacks -- #convert / #link / #default / #note -- so a whole type-pair
  conversion (grouped deep-property assignments + a target uses-add + defaults +
  human notes) lives in one text file.

  Two totally-pure functions, NO I/O:
    * ParseConversionRules  -- TOTAL: never raises. Every input line is either a
      recognised rule, an ignored comment/blank, or a captured PARSE ERROR
      (unknown '#directive'). Parse errors ride on the ruleset's ParseErrors
      field; the validator surfaces them.
    * ValidateConversionRules -- the "we know the REAL properties" check reFind
      cannot do: #link / #default target/source paths are checked against the
      supplied from/to property trees (TPropTree from Task 1). A literal '???'
      path is an explicit-unfilled STUB marker (the Batch-1 scaffolder emits
      these) and is NOT a hard error.

  READ-ONLY / PURE: no store, no files, no globals. Deterministic.
}

interface

uses
  System.SysUtils,
  DRagLint.Convert.PropTree;

type
  /// <summary>The kind of a single parsed conversion rule.</summary>
  /// <remarks>rkUnuse=#unuse (drop a unit from the uses clause); rkRemove=#remove
  /// (drop a property from PAS+DFM, or DFM-only); rkMigrate=#migrate (replace an
  /// identifier, reFind's ' -&gt; ' form); rkConvert=#convert (declare the
  /// From-&gt;To type pair a block converts, adding target units); rkLink=#link
  /// (deep property assignment, ToPath '&lt;-' FromPath -- note the REVERSED
  /// arrow vs migrate); rkDefault=#default (set a target property to a value when
  /// no source maps); rkNote=#note (a human comment carried in the rule set);
  /// rkPcre=a raw non-'#' line containing ' -&gt; ' (the PCRE find/replace escape
  /// hatch); rkIgnore=#ignore (acknowledge an F property/event is intentionally
  /// NOT mapped -- suppresses the unmapped-non-default WARN for that FromPath).
  /// rkUse=#use (ADD a unit to the uses clause -- companion to #unuse).
  /// rkUseSwap=#useswap (replace Old with one-or-more New units; UnitName=Old,
  /// UnitsAdd=the New list; canonically #unuse Old + #use New...).</remarks>
  TRuleKind = (rkUnuse, rkRemove, rkMigrate, rkConvert, rkLink, rkDefault, rkNote, rkPcre, rkIgnore, rkUse, rkUseSwap);

  /// <summary>One parsed conversion rule. A flat record; only the fields relevant
  /// to <see cref="Kind"/> are populated (the rest stay '').</summary>
  /// <remarks>Field usage by Kind:
  /// rkUnuse -&gt; UnitName.
  /// rkRemove -&gt; PropName + DfmOnly (True for '#remove DFM: X').
  /// rkMigrate -&gt; Scope (optional 'Class:' or 'obj.' receiver prefix -- see
  ///   below), Old (the LHS identifier), New (the RHS identifier), UnitsAdd
  ///   (0+ trailing uses-units).
  /// rkConvert -&gt; FromType, ToType, UnitsAdd (0+ target units to add).
  /// rkLink -&gt; ToPath (LHS of '&lt;-'), FromPath (RHS of '&lt;-').
  /// rkDefault -&gt; ToPath, Value (RHS of '=').
  /// rkNote -&gt; Text.
  /// rkPcre -&gt; Search (LHS of ' -&gt; '), Replace (RHS).
  /// rkIgnore -&gt; FromPath (the F property/event path to leave unmapped, no warn).
  /// LineNo is the 1-based source line the rule was parsed from.
  /// SCOPE-FOLD CHOICE for #migrate: reFind allows an optional '&lt;Class&gt; :'
  /// class-scope and/or an optional '&lt;obj&gt; .' object-scope before the old
  /// identifier. We fold BOTH into a single Scope string kept verbatim (e.g.
  /// 'TForm1:' or 'DataSet.' or 'TForm1: DataSet.'); Old holds only the bare
  /// old identifier after the last such prefix. This preserves the receiver
  /// intent without over-modelling it in Batch 1 (validation ignores Scope).</remarks>
  TConversionRule = record
    Kind: TRuleKind;
    FromType, ToType, ToPath, FromPath, Old, New, Scope, UnitName, PropName, Value, Text, Search, Replace: string;
    UnitsAdd: TArray<string>;
    DfmOnly : Boolean;
    LineNo  : Integer;
  end;

  /// <summary>One parse-or-validation error, anchored to a source line.</summary>
  /// <remarks>LineNo is the 1-based source line; Message is a human-readable,
  /// ASCII-only description (e.g. 'unknown directive: #frobnicate' or
  /// 'link ToPath not found in --to tree: Bogus.Path').</remarks>
  TRuleError = record
    LineNo : Integer;
    Message: string;
  end;

  /// <summary>The full parsed rule set: the recognised rules plus any parse
  /// errors captured while reading them.</summary>
  /// <remarks>Rules holds every RECOGNISED rule in source order. ParseErrors
  /// holds one entry per UNKNOWN '#directive' line (or other total-parser
  /// rejection) -- the parser NEVER raises, so a malformed input still yields a
  /// well-formed ruleset with the problems recorded here. ValidateConversionRules
  /// folds these ParseErrors into its returned error list, so a caller that runs
  /// the validator sees parse + validation problems together. (ADDED FIELD vs the
  /// Task-2 brief's minimal shape -- documented as acceptable there; Task 3 reads
  /// Rules and may inspect ParseErrors but is not broken by its presence.)</remarks>
  TConversionRuleSet = record
    Rules      : TArray<TConversionRule>;
    ParseErrors: TArray<TRuleError>;
  end;

/// <summary>Parses the reFind-superset conversion-rules DSL text into a rule set.
/// TOTAL: never raises -- an unknown '#directive' becomes a captured ParseError,
/// never an exception.</summary>
/// <param name="AText">The raw rules text (CRLF or LF line endings both accepted).
/// Blank lines and lines starting with '//' or ';' are ignored.</param>
/// <returns>A TConversionRuleSet whose Rules are the recognised rules (each with
/// its 1-based LineNo) and whose ParseErrors carry any unknown-directive lines.
/// An empty/whitespace-only input yields empty Rules and empty ParseErrors.</returns>
/// <remarks>Directive grammar (all case-INSENSITIVE on the leading '#word'):
/// '#use &lt;unit&gt;' (add a unit); '#useswap &lt;Old&gt; -&gt; &lt;New1&gt; [, &lt;New2&gt; ...]' (replace a unit with one-or-more units);
/// '#unuse &lt;unit&gt;'; '#remove &lt;prop&gt;' / '#remove DFM: &lt;prop&gt;'
/// (DFM-only); '#migrate [&lt;Class&gt; :] [&lt;obj&gt; .] &lt;old&gt; -&gt;
/// &lt;new&gt; [, &lt;unit&gt; ...]'; '#convert &lt;FromType&gt; -&gt;
/// &lt;ToType&gt; [, &lt;unit&gt; ...]'; '#link &lt;ToPath&gt; &lt;- &lt;FromPath&gt;'
/// (note the '&lt;-' arrow); '#default &lt;ToPath&gt; = &lt;value&gt;';
/// '#note &lt;text&gt;'; '#ignore &lt;FromPath&gt;' (acknowledge an F property is
/// intentionally unmapped -- suppresses its unmapped-non-default warning).
/// A NON-'#' line containing ' -&gt; ' is a raw PCRE
/// rule (Search -&gt; Replace). Any other '#word' is an unknown directive
/// recorded in ParseErrors. Pure; deterministic; no I/O.</remarks>
function ParseConversionRules(const AText: string): TConversionRuleSet;

/// <summary>Validates a parsed rule set against the real property trees of the
/// From and To types, catching path typos reFind cannot -- plus folding in any
/// parse errors from ParseConversionRules.</summary>
/// <param name="ARules">The parsed rule set (its ParseErrors are included in the
/// result).</param>
/// <param name="AFromTree">The FromType's flattened property tree (Task 1's
/// BuildPropTree). May be empty (RootType='') to skip source-path checks.</param>
/// <param name="AToTree">The ToType's flattened property tree. May be empty to
/// skip target-path checks.</param>
/// <returns>Zero-length array = valid. Otherwise one TRuleError per problem, in
/// source order (parse errors first, then validation errors).</returns>
/// <remarks>Checks performed: for each rkLink, ToPath must exist as some
/// AToTree.Nodes[].Path and FromPath must exist as some AFromTree.Nodes[].Path;
/// for each rkDefault, ToPath must exist in AToTree. A path equal to the literal
/// '???' is an explicit-unfilled STUB marker (emitted by the Batch-1 scaffolder)
/// and is SKIPPED -- never a hard error -- so scaffolder output validates clean.
/// When a tree is empty (RootType=''), the checks against THAT tree are skipped
/// (parse-only / tree-less mode). rkConvert type pairs are informational and are
/// NEVER hard-failed (a rename mismatch is not a path error). Other kinds
/// (rkUnuse/rkRemove/rkMigrate/rkNote/rkPcre) are not path-checked in Batch 1.
/// rkIgnore is not path-checked either -- a #ignore for a non-existent F path is
/// tolerated (it simply matches nothing), never a hard error.
/// Pure; deterministic; no I/O.</remarks>
function ValidateConversionRules(const ARules: TConversionRuleSet;
  const AFromTree, AToTree: TPropTree): TArray<TRuleError>;

implementation

uses
  System.StrUtils,
  System.Generics.Collections;

const
  ARROW_MIGRATE = ' -> ';  // #migrate / #convert / raw PCRE separator
  ARROW_LINK    = ' <- ';  // #link separator (reversed)
  STUB_MARKER   = '???';   // explicit-unfilled path stub (skip validation)

// Split raw text into lines on CRLF or LF (a total, allocation-light splitter).
function SplitLines(const AText: string): TArray<string>;
var
  Norm: string;
begin
  Norm:= StringReplace(AText, #13#10, #10, [rfReplaceAll]);
  Norm:= StringReplace(Norm , #13   , #10, [rfReplaceAll]);
  Result:= Norm.Split([#10]);
end;

// Parse a trailing ', U [, U ...]' unit list from the RHS of a migrate/convert
// rule. AInput is the whole RHS (e.g. 'TFDTable, FireDAC.Comp.Client'); the head
// (first comma-separated element, trimmed) is returned via AHead, and every
// remaining non-empty trimmed element becomes a UnitsAdd entry.
procedure SplitHeadAndUnits(const AInput: string; out AHead: string;
  out AUnits: TArray<string>);
var
  Parts: TArray<string>;
  i    : Integer       ;
  U    : TList<string> ;
  T    : string        ;
begin
  AHead := '';
  AUnits:= nil;
  Parts := AInput.Split([',']);
  if Length(Parts) = 0 then Exit;
  AHead:= Trim(Parts[0]);
  U:= TList<string>.Create;
  try
    for i:= 1 to High(Parts) do
    begin
      T:= Trim(Parts[i]);
      if T <> '' then U.Add(T);
    end;
    AUnits:= U.ToArray;
  finally
    U.Free;
  end;
end;

// For #migrate: peel any leading 'Class :' and/or 'obj .' scope prefixes off the
// LHS, folding what we peel (verbatim, whitespace-normalised) into AScope and
// leaving the bare old identifier in AOld. Pragmatic: we recognise a ' : '
// class-scope and a '.' object-scope; anything before the last such marker is
// scope, the remainder is Old.
procedure SplitMigrateLhs(const ALhs: string; out AScope, AOld: string);
var
  S      : string ;
  ColonAt: Integer;
  DotAt  : Integer;
begin
  AScope:= '';
  S     := Trim(ALhs);
  // Class-scope: '<Class> :' -- take up to and including the last ' :'.
  ColonAt:= S.LastIndexOf(':') + 1; // 1-based position, 0 if absent
  if ColonAt > 0 then
  begin
    AScope:= Trim(Copy(S, 1, ColonAt)); // includes the ':'
    S     := Trim(Copy(S, ColonAt + 1, MaxInt));
  end;
  // Object-scope: '<obj> .<old>' -- fold the receiver+'.' into Scope too.
  DotAt:= S.LastIndexOf('.') + 1; // 1-based, 0 if absent
  if DotAt > 0 then
  begin
    if AScope <> '' then AScope:= AScope + ' ' + Trim(Copy(S, 1, DotAt))
    else                 AScope:= Trim(Copy(S, 1, DotAt)); // includes the '.'
    S:= Trim(Copy(S, DotAt + 1, MaxInt));
  end;
  AOld:= Trim(S);
end;

function ParseConversionRules(const AText: string): TConversionRuleSet;
var
  Lines : TArray<string>       ;
  Rules : TList<TConversionRule>;
  Errs  : TList<TRuleError>    ;
  LineNo: Integer              ;
  Raw   : string               ;
  Line  : string               ;
  Low   : string               ;

  procedure AddError(const AMsg: string);
  var
    E: TRuleError;
  begin
    E.LineNo := LineNo;
    E.Message:= AMsg;
    Errs.Add(E);
  end;

  // Returns True + the argument text if Line starts with the (case-insensitive)
  // directive keyword AKey ('#unuse' etc.) followed by whitespace or end.
  function Directive(const AKey: string; out AArg: string): Boolean;
  var
    KLen: Integer;
  begin
    AArg := '';
    KLen := Length(AKey);
    Result:= (Length(Line) >= KLen) and
             SameText(Copy(Line, 1, KLen), AKey) and
             ((Length(Line) = KLen) or CharInSet(Line[KLen + 1], [' ', #9]));
    if Result then AArg:= Trim(Copy(Line, KLen + 1, MaxInt));
  end;

  procedure AddRule(const ARule: TConversionRule);
  var
    R: TConversionRule;
  begin
    R:= ARule;
    R.LineNo:= LineNo;
    Rules.Add(R);
  end;

var
  Arg  : string        ;
  Head : string        ;
  Units: TArray<string>;
  ArrPos: Integer      ;
  Lhs, Rhs: string     ;
  R    : TConversionRule;
begin
  Rules:= TList<TConversionRule>.Create;
  Errs := TList<TRuleError>.Create;
  try
    Lines:= SplitLines(AText);
    for LineNo:= 1 to Length(Lines) do
    begin
      Raw := Lines[LineNo - 1];
      Line:= Trim(Raw);
      if Line = '' then Continue;                                // blank
      if Line.StartsWith('//') or Line.StartsWith(';') then Continue; // comment

      R:= Default(TConversionRule);

      if Directive('#unuse', Arg) then
      begin
        R.Kind    := rkUnuse;
        R.UnitName:= Arg;
        AddRule(R);
      end
      else if Directive('#useswap', Arg) then
      begin
        // #useswap <Old> -> <New1>[, <New2> ...]  -- UnitName=Old, UnitsAdd=News.
        R.Kind:= rkUseSwap;
        ArrPos:= Pos(ARROW_MIGRATE, Arg);
        if ArrPos > 0 then
        begin
          R.UnitName:= Trim(Copy(Arg, 1, ArrPos - 1));
          Rhs       := Trim(Copy(Arg, ArrPos + Length(ARROW_MIGRATE), MaxInt));
        end
        else begin R.UnitName:= Trim(Arg); Rhs:= ''; end;
        // Rhs is a pure comma list of New units; fold Head + rest into UnitsAdd.
        SplitHeadAndUnits(Rhs, Head, Units);
        if Head <> '' then Insert(Head, Units, 0);
        R.UnitsAdd:= Units;
        AddRule(R);
      end
      else if Directive('#use', Arg) then
      begin
        R.Kind    := rkUse;
        R.UnitName:= Arg;
        AddRule(R);
      end
      else if Directive('#remove', Arg) then
      begin
        R.Kind:= rkRemove;
        // '#remove DFM: <prop>' -> DFM-only. Match a leading 'DFM:' (any case).
        if SameText(Copy(Arg, 1, 4), 'DFM:') then
        begin
          R.DfmOnly := True;
          R.PropName:= Trim(Copy(Arg, 5, MaxInt));
        end
        else
        begin
          R.DfmOnly := False;
          R.PropName:= Arg;
        end;
        AddRule(R);
      end
      else if Directive('#migrate', Arg) then
      begin
        R.Kind:= rkMigrate;
        ArrPos:= Pos(ARROW_MIGRATE, Arg);
        if ArrPos > 0 then
        begin
          Lhs:= Trim(Copy(Arg, 1, ArrPos - 1));
          Rhs:= Trim(Copy(Arg, ArrPos + Length(ARROW_MIGRATE), MaxInt));
        end
        else begin Lhs:= Trim(Arg); Rhs:= ''; end;
        SplitMigrateLhs(Lhs, R.Scope, R.Old);
        SplitHeadAndUnits(Rhs, Head, Units);
        R.New     := Head;
        R.UnitsAdd:= Units;
        AddRule(R);
      end
      else if Directive('#convert', Arg) then
      begin
        R.Kind:= rkConvert;
        ArrPos:= Pos(ARROW_MIGRATE, Arg);
        if ArrPos > 0 then
        begin
          R.FromType:= Trim(Copy(Arg, 1, ArrPos - 1));
          Rhs       := Trim(Copy(Arg, ArrPos + Length(ARROW_MIGRATE), MaxInt));
        end
        else begin R.FromType:= Trim(Arg); Rhs:= ''; end;
        SplitHeadAndUnits(Rhs, Head, Units);
        R.ToType  := Head;
        R.UnitsAdd:= Units;
        AddRule(R);
      end
      else if Directive('#link', Arg) then
      begin
        R.Kind:= rkLink;
        ArrPos:= Pos(ARROW_LINK, Arg);
        if ArrPos > 0 then
        begin
          R.ToPath  := Trim(Copy(Arg, 1, ArrPos - 1));
          R.FromPath:= Trim(Copy(Arg, ArrPos + Length(ARROW_LINK), MaxInt));
        end
        else
        begin
          // Malformed link (no '<-') -- keep the LHS as ToPath, empty FromPath.
          R.ToPath  := Trim(Arg);
          R.FromPath:= '';
        end;
        AddRule(R);
      end
      else if Directive('#default', Arg) then
      begin
        R.Kind:= rkDefault;
        ArrPos:= Pos('=', Arg);
        if ArrPos > 0 then
        begin
          R.ToPath:= Trim(Copy(Arg, 1, ArrPos - 1));
          R.Value := Trim(Copy(Arg, ArrPos + 1, MaxInt));
        end
        else
        begin
          R.ToPath:= Trim(Arg);
          R.Value := '';
        end;
        AddRule(R);
      end
      else if Directive('#ignore', Arg) then
      begin
        R.Kind    := rkIgnore;
        R.FromPath:= Arg;
        AddRule(R);
      end
      else if Directive('#note', Arg) then
      begin
        R.Kind:= rkNote;
        R.Text:= Arg;
        AddRule(R);
      end
      else if Line.StartsWith('#') then
      begin
        // An unknown '#directive' -- capture a parse error, never raise.
        Low:= Line;
        ArrPos:= Pos(' ', Low);
        if ArrPos > 0 then Low:= Copy(Low, 1, ArrPos - 1);
        AddError('unknown directive: ' + Low);
      end
      else if Pos(ARROW_MIGRATE, Line) > 0 then
      begin
        // A non-'#' line with ' -> ' -- the raw PCRE find/replace escape hatch.
        R.Kind := rkPcre;
        ArrPos := Pos(ARROW_MIGRATE, Line);
        R.Search := Trim(Copy(Line, 1, ArrPos - 1));
        R.Replace:= Trim(Copy(Line, ArrPos + Length(ARROW_MIGRATE), MaxInt));
        AddRule(R);
      end
      else
      begin
        // A non-blank, non-comment, non-directive line without ' -> ' cannot be
        // interpreted -- record it so nothing is silently swallowed.
        AddError('unrecognised line (no directive and no '' -> '' pattern)');
      end;
    end;

    Result.Rules      := Rules.ToArray;
    Result.ParseErrors:= Errs.ToArray;
  finally
    Rules.Free;
    Errs.Free;
  end;
end;

// True when APath exists as some node's Path in ATree.
function PathExists(const ATree: TPropTree; const APath: string): Boolean;
var
  N: TPropNode;
begin
  Result:= False;
  for N in ATree.Nodes do
    if SameText(N.Path, APath) then Exit(True);
end;

function ValidateConversionRules(const ARules: TConversionRuleSet;
  const AFromTree, AToTree: TPropTree): TArray<TRuleError>;
var
  Errs   : TList<TRuleError>;
  R      : TConversionRule ;
  PE     : TRuleError      ;
  HaveTo : Boolean         ;
  HaveFrom: Boolean        ;

  procedure Add(ALineNo: Integer; const AMsg: string);
  var
    E: TRuleError;
  begin
    E.LineNo := ALineNo;
    E.Message:= AMsg;
    Errs.Add(E);
  end;

  function IsStub(const APath: string): Boolean;
  begin
    Result:= Trim(APath) = STUB_MARKER;
  end;

begin
  Errs:= TList<TRuleError>.Create;
  try
    // 1. Fold in any parse errors first (source order preserved by LineNo).
    for PE in ARules.ParseErrors do
      Errs.Add(PE);

    // A tree with an empty RootType means "no tree supplied" -> skip its checks.
    HaveTo  := AToTree.RootType   <> '';
    HaveFrom:= AFromTree.RootType <> '';

    // 2. Path checks for #link and #default.
    for R in ARules.Rules do
    begin
      case R.Kind of
        rkLink:
        begin
          if HaveTo and (not IsStub(R.ToPath)) and (R.ToPath <> '') and
             (not PathExists(AToTree, R.ToPath)) then
            Add(R.LineNo, Format('link ToPath not found in --to tree: %s', [R.ToPath]));
          if HaveFrom and (not IsStub(R.FromPath)) and (R.FromPath <> '') and
             (not PathExists(AFromTree, R.FromPath)) then
            Add(R.LineNo, Format('link FromPath not found in --from tree: %s', [R.FromPath]));
        end;
        rkDefault:
        begin
          if HaveTo and (not IsStub(R.ToPath)) and (R.ToPath <> '') and
             (not PathExists(AToTree, R.ToPath)) then
            Add(R.LineNo, Format('default ToPath not found in --to tree: %s', [R.ToPath]));
        end;
        // rkConvert is informational; rkUnuse/rkRemove/rkMigrate/rkNote/rkPcre
        // carry no index-checkable paths in Batch 1 -- no checks.
      end;
    end;

    Result:= Errs.ToArray;
  finally
    Errs.Free;
  end;
end;

end.
