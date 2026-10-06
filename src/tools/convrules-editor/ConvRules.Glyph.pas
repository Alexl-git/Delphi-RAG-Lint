unit ConvRules.Glyph;

{ C10 (spec 2026-10-06-c10-split-merge-design.md), editor half of the G[I/N] glyph
  grammar: the decisions behind the Glyph column, the expression dialog, the Convert
  tab's greying and its glyph outcome lines. Pure -- no VCL, no engine process, no
  file system -- so ConvRulesModelTests pins every rule with inline text.

  The expression itself is checked by the ENGINE's parser, DRagLint.Convert.GlyphExpr,
  imported from src\report exactly as DRagLint.Convert.CastLib is: one parser, two
  consumers, no drift. What the pure parser cannot see (other links in the block, the
  To tree) is decided here with the engine's own wording, so a user reads the same
  sentence in the dialog and in convert-validate's output. }

interface

uses
  System.SysUtils
  , ConvRules.Model
  ;

const
  /// <summary>Suffix the Convert tab shows on a checklist book holding a G-link while
  /// the engine lacks glyph_stitch (two leading spaces, as the unit-rules suffix).</summary>
  GLYPH_BOOK_PENDING_SUFFIX = '  (glyph links: engine support pending)';
  /// <summary>apply/1 glyphs[] kind for a realised link; every other kind is a to-do outcome.</summary>
  GLYPH_KIND_STITCHED = 'glyph-stitched';
  /// <summary>The expression that links a target's glyph COUNT.</summary>
  GLYPH_COUNT_EXPR = 'G[count]';

type
  /// <summary>One apply/1 glyphs[] object: what the engine did with one instance's one
  /// G-link (engine ask N3).</summary>
  /// <remarks>Kind is GLYPH_KIND_STITCHED or a to-do kind; an unknown Kind counts as a
  /// to-do (the engine wrote one, whatever it called it). DroppedSlots are the slots the
  /// chosen alternative left out, named by the RULE, never inferred.</remarks>
  TGlyphOutcome = record
    Instance    : string;
    FromPath    : string;
    ToPath      : string;
    Kind        : string;
    Alternative : string;
    Message     : string;
    SourceN     : Integer;
    RuleLine    : Integer;
    DroppedSlots: TArray<Integer>;
  end;

/// <summary>Checks a glyph expression's syntax and static rules through the engine's
/// own parser.</summary>
/// <param name="AText">The expression; '' is valid (no expression).</param>
/// <param name="AError">'' when valid, else 'column C: &lt;message&gt;' for the first problem.</param>
/// <returns>True when valid.</returns>
function CheckGlyphExprText(const AText: string; out AError: string): Boolean;  // dl:ok unused-public-symbol@c654 -- REVIEWED 2026-10-06 editor caller arrives in a later C10 task (GlyphForm / MainForm / ConvertTab); ConvRulesModelTests already calls it

/// <summary>True for a #link whose expression is set and is not G[count].</summary>
/// <param name="ANode">Any node; nil or a non-link gives False.</param>
/// <returns>True for an IMAGE glyph link.</returns>
function IsImageGlyphLink(ANode: TRuleNode): Boolean;

/// <summary>How many image glyph links in ANodes read from AFromPath.</summary>
/// <param name="ANodes">The block's nodes (header included or not; only links count).</param>
/// <param name="AFromPath">Compared case-insensitively with LinkFrom.</param>
/// <returns>The count; 0 when none.</returns>
function ImageGlyphLinksFrom(const ANodes: TArray<TRuleNode>; const AFromPath: string): Integer;

/// <summary>The engine's rule that a G[count] link needs EXACTLY one image link from
/// its FromPath in the same block.</summary>
/// <param name="ANodes">The block's nodes.</param>
/// <param name="AFromPath">The count link's FromPath.</param>
/// <param name="AExpr">The expression being written; anything but G[count] gives ''.</param>
/// <returns>'' when fine, else 'G[count] needs exactly one image link from &lt;From&gt;; found K'.</returns>
function CountLinkIssue(const ANodes: TArray<TRuleNode>; const AFromPath, AExpr: string): string;  // dl:ok unused-public-symbol@dfd3 -- REVIEWED 2026-10-06 editor caller arrives in a later C10 task (GlyphForm / MainForm / ConvertTab); ConvRulesModelTests already calls it

/// <summary>The engine's warning, as a hint: a straight carry of a glyph-count property
/// beside an image G-link in the same block is right only for identity alternatives.</summary>
/// <param name="ANodes">The block's nodes.</param>
/// <returns>'' when the block has no image G-link or no straight count carry; else
/// '#link &lt;To&gt; &lt;- &lt;From&gt; is a straight carry of the source glyph count -- write
/// "#link &lt;To&gt; &lt;- &lt;ImageFrom&gt; G[count]" instead' for the first such carry.</returns>
function StraightCountCarryHint(const ANodes: TArray<TRuleNode>): string;  // dl:ok unused-public-symbol@6d5b -- REVIEWED 2026-10-06 editor caller arrives in a later C10 task (GlyphForm / MainForm / ConvertTab); ConvRulesModelTests already calls it

/// <summary>The one To leaf a G[count] link should target: its last segment is a
/// glyph-count property name and no link in the block targets it.</summary>
/// <param name="AToLeafPaths">The To tree's leaf paths.</param>
/// <param name="ANodes">The block's nodes.</param>
/// <returns>The path, or '' when there is none OR more than one (never guess).</returns>
function SuggestCountTarget(const AToLeafPaths: TArray<string>; const ANodes: TArray<TRuleNode>): string;  // dl:ok unused-public-symbol@d840 -- REVIEWED 2026-10-06 editor caller arrives in a later C10 task (GlyphForm / MainForm / ConvertTab); ConvRulesModelTests already calls it

/// <summary>The text after the last '.' of a dotted path (the whole path when undotted).</summary>
/// <param name="APath">A property path.</param>
/// <returns>The last segment; '' for ''.</returns>
function LastSegment(const APath: string): string;

/// <summary>True when the book text holds at least one #link with a glyph expression.</summary>
/// <param name="ARulesText">A .rules text.</param>
/// <returns>True = the Convert tab must gate this book on glyph_stitch.</returns>
function BookHasGlyphLinks(const ARulesText: string): Boolean;  // dl:ok unused-public-symbol@3796 -- REVIEWED 2026-10-06 editor caller arrives in a later C10 task (GlyphForm / MainForm / ConvertTab); ConvRulesModelTests already calls it

/// <summary>True when the outcome is anything but GLYPH_KIND_STITCHED.</summary>
/// <param name="AOutcome">One glyphs[] object.</param>
/// <returns>True = the engine wrote a to-do marker for it.</returns>
function IsGlyphTodo(const AOutcome: TGlyphOutcome): Boolean;

/// <summary>How many of AOutcomes are to-do outcomes.</summary>
/// <param name="AOutcomes">A unit's glyph outcomes.</param>
/// <returns>The to-do count.</returns>
function GlyphTodoCount(const AOutcomes: TArray<TGlyphOutcome>): Integer;

/// <summary>The converted row's note suffix.</summary>
/// <param name="AOutcomes">A unit's glyph outcomes.</param>
/// <returns>'' when none, else the spec E13 suffix -- N stitched, M slots dropped by rule, K to-do outcomes (exact text pinned by the glyph.note.suffix test).</returns>
function GlyphNoteSuffix(const AOutcomes: TArray<TGlyphOutcome>): string;

/// <summary>One tab-separated run-report line for an outcome.</summary>
/// <param name="AUnitPas">The unit's path as the report names it.</param>
/// <param name="AOutcome">The outcome.</param>
/// <returns>glyph TAB unit TAB instance.from -&gt; to TAB kind TAB N=n TAB alternative TAB
/// 'dropped a,b' or '-' TAB message.</returns>
function GlyphReportLine(const AUnitPas: string; const AOutcome: TGlyphOutcome): string;  // dl:ok unused-public-symbol@b124 -- REVIEWED 2026-10-06 editor caller arrives in a later C10 task (GlyphForm / MainForm / ConvertTab); ConvRulesModelTests already calls it

/// <summary>The red run summary (spec E14).</summary>
/// <param name="ATodoUnits">Units with at least one to-do outcome.</param>
/// <returns>'' for 0, else the sentence.</returns>
function GlyphRunSummary(ATodoUnits: Integer): string;  // dl:ok unused-public-symbol@a92e -- REVIEWED 2026-10-06 editor caller arrives in a later C10 task (GlyphForm / MainForm / ConvertTab); ConvRulesModelTests already calls it

implementation

uses
  DRagLint.Convert.GlyphExpr
  ;

function CheckGlyphExprText(const AText: string; out AError: string): Boolean;
var
  Expr: TGlyphExpr;
  Errs: TArray<TGlyphExprError>;
begin
  AError:= '';
  if Trim(AText) = '' then
    Exit(True);
  Errs:= ParseGlyphExpr(AText, Expr);
  if Length(Errs) = 0 then
    Errs:= ValidateGlyphExpr(Expr);
  Result:= Length(Errs) = 0;
  if not Result then
    AError:= Format('column %d: %s', [Errs[0].Column, Errs[0].Message]);
end;

function IsCountExprText(const AExpr: string): Boolean;
var
  Expr: TGlyphExpr;
begin
  Result:= (Length(ParseGlyphExpr(AExpr, Expr)) = 0) and IsGlyphCountExpr(Expr);
end;

function IsImageGlyphLink(ANode: TRuleNode): Boolean;
begin
  Result:= (ANode <> nil) and (ANode.Kind = rnkLink) and (ANode.GlyphExpr <> '') and not IsCountExprText(ANode.GlyphExpr);
end;

function ImageGlyphLinksFrom(const ANodes: TArray<TRuleNode>; const AFromPath: string): Integer;
var
  N: TRuleNode;
begin
  Result:= 0;
  for N in ANodes do
    if IsImageGlyphLink(N) and SameText(N.LinkFrom, AFromPath) then
      Inc(Result);
end;

function CountLinkIssue(const ANodes: TArray<TRuleNode>; const AFromPath, AExpr: string): string;
var
  K: Integer;
begin
  Result:= '';
  if not IsCountExprText(AExpr) then
    Exit;
  K:= ImageGlyphLinksFrom(ANodes, AFromPath);
  if K <> 1 then
    Result:= Format('G[count] needs exactly one image link from %s; found %d', [AFromPath, K]);
end;

function LastSegment(const APath: string): string;
var
  P: Integer;
begin
  P:= APath.LastIndexOf('.');
  if P < 0 then
    Result:= APath
  else
    Result:= APath.Substring(P + 1);
end;

function FirstImageGlyphLink(const ANodes: TArray<TRuleNode>): TRuleNode;
var
  N: TRuleNode;
begin
  for N in ANodes do
    if IsImageGlyphLink(N) then
      Exit(N);
  Result:= nil;
end;

function StraightCountCarryHint(const ANodes: TArray<TRuleNode>): string;
var
  Img: TRuleNode;
  N  : TRuleNode;
begin
  Result:= '';
  Img:= FirstImageGlyphLink(ANodes);
  if Img = nil then
    Exit;
  for N in ANodes do
    if (N.Kind = rnkLink) and (N.GlyphExpr = '') and IsGlyphCountPropName(LastSegment(N.LinkFrom)) then
      Exit(Format('#link %s <- %s is a straight carry of the source glyph count -- write "#link %s <- %s %s" instead',
        [N.LinkTo, N.LinkFrom, N.LinkTo, Img.LinkFrom, GLYPH_COUNT_EXPR]));
end;

function SuggestCountTarget(const AToLeafPaths: TArray<string>; const ANodes: TArray<TRuleNode>): string;

  function Targeted(const APath: string): Boolean;
  var
    N: TRuleNode;
  begin
    for N in ANodes do
      if (N.Kind = rnkLink) and SameText(N.LinkTo, APath) then
        Exit(True);
    Result:= False;
  end;

var
  P    : string;
  Found: Integer;
begin
  Result:= '';
  Found := 0;
  for P in AToLeafPaths do
    if IsGlyphCountPropName(LastSegment(P)) and not Targeted(P) then
    begin
      Inc(Found);
      Result:= P;
    end;
  if Found <> 1 then
    Result:= '';
end;

function BookHasGlyphLinks(const ARulesText: string): Boolean;
var
  Book: TRuleBook;
  N   : TRuleNode;
begin
  Result:= False;
  if Trim(ARulesText) = '' then
    Exit;
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(ARulesText);
    for N in Book.Nodes do
      if (N.Kind = rnkLink) and (N.GlyphExpr <> '') then
        Exit(True);
  finally
    Book.Free;
  end;
end;

function IsGlyphTodo(const AOutcome: TGlyphOutcome): Boolean;
begin
  Result:= not SameText(AOutcome.Kind, GLYPH_KIND_STITCHED);
end;

function GlyphTodoCount(const AOutcomes: TArray<TGlyphOutcome>): Integer;
var
  O: TGlyphOutcome;
begin
  Result:= 0;
  for O in AOutcomes do
    if IsGlyphTodo(O) then
      Inc(Result);
end;

function GlyphNoteSuffix(const AOutcomes: TArray<TGlyphOutcome>): string;
var
  O       : TGlyphOutcome;
  Stitched: Integer;
  Dropped : Integer;
begin
  if Length(AOutcomes) = 0 then
    Exit('');
  Stitched:= 0;
  Dropped := 0;
  for O in AOutcomes do
    if not IsGlyphTodo(O) then
    begin
      Inc(Stitched);
      Inc(Dropped, Length(O.DroppedSlots));
    end;
  Result:= Format('; glyphs: %d stitched, %d slot(s) dropped by rule, %d TODO(s)', [Stitched, Dropped, GlyphTodoCount(AOutcomes)]);
end;

function GlyphReportLine(const AUnitPas: string; const AOutcome: TGlyphOutcome): string;
var
  Slots: string;
  S    : Integer;
begin
  Slots:= '';
  for S in AOutcome.DroppedSlots do
    Slots:= Slots + (if Slots = '' then '' else ',') + IntToStr(S);
  Slots:= if Slots = '' then '-' else 'dropped ' + Slots;
  Result:= string.Join(#9, ['glyph', AUnitPas, Format('%s.%s -> %s', [AOutcome.Instance, AOutcome.FromPath, AOutcome.ToPath]),
    AOutcome.Kind, 'N=' + IntToStr(AOutcome.SourceN), AOutcome.Alternative, Slots, AOutcome.Message]);
end;

function GlyphRunSummary(ATodoUnits: Integer): string;
begin
  if ATodoUnits <= 0 then
    Result:= ''
  else
    Result:= Format('%d unit(s) have glyph TODOs -- each one''s implementation section starts with the TODO line; see the report', [ATodoUnits]);
end;

end.
