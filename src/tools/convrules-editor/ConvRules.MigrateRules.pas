unit ConvRules.MigrateRules;

{ A4 #migrate slice 1 -- the PURE classification of one '#migrate' line and the book
  helpers over the lines of a #convert block. No UI, no engine call, no I/O.

  The engine applies a '#migrate Old -> New' inside a #convert block only in its member
  form (engine 1.32.0+, capability migrate_members): no scope prefix, Old and New plain
  identifiers (New may be DL_NONE, a deliberate break), no trailing units. Every other
  form is refused with one sentence (DRagLint.Convert.Apply.MigrateRuleRefusal);
  MigrateRefusal returns that same sentence BEFORE a run. A block runs from its header to
  the next header or EOF (ENGINE contract G5, INBOX-REPLY 2026-10-25); a '#migrate'
  before the first header is not a member migration (G2c). Spec:
  docs\superpowers\specs\2026-10-23-converter-migrate-slice1-design.md sections 4 and 8. }

interface

uses
  ConvRules.Model
  ;

const
  /// <summary>The info --json capability that says convert-apply applies member-form
  /// #migrate lines inside a #convert block (engine 1.32.0-alpha and later).</summary>
  CAPABILITY_MIGRATE_MEMBERS = 'migrate_members';
  /// <summary>The replacement that marks a deliberate break: the engine wraps each site
  /// as DL_NONE(&lt;old&gt;) so the unit stops compiling there until converted by hand.</summary>
  MIGRATE_DL_NONE = 'DL_NONE';
  /// <summary>apply/1 items[] kind: a member site the engine renamed.</summary>
  APPLY_KIND_MIGRATE_APPLIED  = 'migrate-applied';
  /// <summary>apply/1 items[] kind: a member site the engine wrapped in DL_NONE(...).</summary>
  APPLY_KIND_DELIBERATE_BREAK = 'deliberate-break';
  /// <summary>apply/1 items[] kind: a #migrate line (line 0) or one site the engine did
  /// not apply; its text says why.</summary>
  APPLY_KIND_MIGRATE_CHECK    = 'migrate-check';

  // The engine's own refusal sentences, verbatim, in its order.
  /// <summary>Refusal: the line carries a 'Class:' or 'obj.' scope.</summary>
  MIGRATE_REFUSAL_SCOPED   = 'a scoped #migrate (Class: / obj.) is not applied yet';
  /// <summary>Refusal: Old is no plain identifier (a call or assignment form).</summary>
  MIGRATE_REFUSAL_CALL     = 'only a plain member name is migrated; call and assignment forms are not applied yet';
  /// <summary>Refusal: the line names no replacement ('#migrate Foo -> ').</summary>
  MIGRATE_REFUSAL_NO_NEW   = 'it names no replacement';
  /// <summary>Refusal: New is no plain identifier (a replacement template).</summary>
  MIGRATE_REFUSAL_TEMPLATE = 'only a member rename or DL_NONE is applied; replacement templates are not applied yet';
  /// <summary>Refusal: the line carries trailing ', Unit' names.</summary>
  MIGRATE_REFUSAL_UNITS    = 'uses units after a member #migrate are not added by convert-apply';

/// <summary>True when ANode is a '#migrate' line the engine applies: no scope, Old and New
/// plain identifiers, no trailing units.</summary>
/// <param name="ANode">Any node; nil and other kinds answer False.</param>
/// <returns>True for the member form (a rename or DL_NONE).</returns>
function IsMemberMigrate(ANode: TRuleNode): Boolean;

/// <summary>True when ANode is a member-form '#migrate' whose New is DL_NONE (any case).</summary>
/// <param name="ANode">Any node; nil answers False.</param>
/// <returns>True for a deliberate break.</returns>
function IsDeliberateBreak(ANode: TRuleNode): Boolean;

/// <summary>Why the engine will not apply the '#migrate' line ANode, in the engine's own
/// words and order (scope, call form, no replacement, template, units).</summary>
/// <param name="ANode">A node; '' for nil or any other kind.</param>
/// <returns>'' when IsMemberMigrate, else one MIGRATE_REFUSAL_* sentence.</returns>
function MigrateRefusal(ANode: TRuleNode): string;

/// <summary>The member-form line '#migrate AOld -> ANew'.</summary>
/// <param name="AOld">The member replaced.</param>
/// <param name="ANew">Its replacement, or DL_NONE.</param>
/// <returns>The line text, no line break.</returns>
function MigrateLineText(const AOld, ANew: string): string;

/// <summary>Every '#migrate' node in the block of the header at AHeaderIdx, any form.</summary>
/// <param name="ABook">The book; not owned.</param>
/// <param name="AHeaderIdx">Index of a #convert header in ABook.Nodes.</param>
/// <returns>Book order; [] when AHeaderIdx is no header.</returns>
function MigratesForBlock(ABook: TRuleBook; AHeaderIdx: Integer): TArray<TRuleNode>;

/// <summary>The index of the #convert header whose block holds ANode.</summary>
/// <param name="ABook">The book; not owned.</param>
/// <param name="ANode">A node of ABook.</param>
/// <returns>-1 before the first header (the engine's "global, not applied") or when
/// ANode is not in ABook; the node's own index when ANode is a header.</returns>
function HeaderIndexOfNode(ABook: TRuleBook; ANode: TRuleNode): Integer;

/// <summary>The member-form '#migrate' for AOld in the block at AHeaderIdx.</summary>
/// <param name="ABook">The book; not owned.</param>
/// <param name="AHeaderIdx">Index of a #convert header.</param>
/// <param name="AOld">The member, case-insensitive.</param>
/// <returns>The first such node (borrowed), or nil; a legacy line is never returned.</returns>
function FindMigrateInBlock(ABook: TRuleBook; AHeaderIdx: Integer; const AOld: string): TRuleNode;

/// <summary>Appends a Dirty member-form '#migrate AOld -> ANew' to the block at AHeaderIdx.</summary>
/// <param name="ABook">The book; owns the new node.</param>
/// <param name="AHeaderIdx">Index of a #convert header, taken AFTER any earlier insert
/// (re-find the header by NODE: an insert above it shifts every index).</param>
/// <param name="AOld">The member.</param>
/// <param name="ANew">The replacement or DL_NONE.</param>
/// <returns>The new node (borrowed), or nil when AHeaderIdx is no header.</returns>
/// <remarks>The line goes after the block's last line that is neither blank nor a
/// comment, so a separator before the next header stays where it is.</remarks>
function AddMigrate(ABook: TRuleBook; AHeaderIdx: Integer; const AOld, ANew: string): TRuleNode;

/// <summary>Changes the New of a '#migrate' node in place: Dirty, and its own Marks cleared
/// (a mark on another node is left alone).</summary>
/// <param name="ANode">A rnkMigrate node; any other node is left untouched.</param>
/// <param name="ANew">The new replacement.</param>
procedure SetMigrateNew(ANode: TRuleNode; const ANew: string);

implementation

uses
  System.SysUtils
  ;

function MigrateRefusal(ANode: TRuleNode): string;
begin
  // The engine's order (DRagLint.Convert.Apply.MigrateRuleRefusal); the sentences are copied verbatim.
  if (ANode = nil) or (ANode.Kind <> rnkMigrate) then
    Result:= ''
  else if ANode.MigScope <> '' then
    Result:= MIGRATE_REFUSAL_SCOPED
  else if not IsValidIdent(ANode.MigOld) then
    Result:= MIGRATE_REFUSAL_CALL
  else if ANode.MigNew = '' then
    Result:= MIGRATE_REFUSAL_NO_NEW
  else if not IsValidIdent(ANode.MigNew) then
    Result:= MIGRATE_REFUSAL_TEMPLATE
  else if ANode.MigUnits <> '' then
    Result:= MIGRATE_REFUSAL_UNITS
  else
    Result:= '';
end;

function IsMemberMigrate(ANode: TRuleNode): Boolean;
begin
  Result:= (ANode <> nil) and (ANode.Kind = rnkMigrate) and (MigrateRefusal(ANode) = '');
end;

function IsDeliberateBreak(ANode: TRuleNode): Boolean;
begin
  Result:= IsMemberMigrate(ANode) and SameText(ANode.MigNew, MIGRATE_DL_NONE);
end;

function MigrateLineText(const AOld, ANew: string): string;
begin
  Result:= Format('#migrate %s -> %s', [AOld, ANew]);
end;

function MigratesForBlock(ABook: TRuleBook; AHeaderIdx: Integer): TArray<TRuleNode>;
begin
  Result:= nil;
  for var LNode: TRuleNode in ABook.NodesInBlock(AHeaderIdx) do
    if LNode.Kind = rnkMigrate then
      Result:= Result + [LNode];
end;

function HeaderIndexOfNode(ABook: TRuleBook; ANode: TRuleNode): Integer;
begin
  for var I: Integer:= ABook.Nodes.IndexOf(ANode) downto 0 do
    if ABook.Nodes[I].Kind = rnkConvert then
      Exit(I);
  Result:= -1;
end;

function FindMigrateInBlock(ABook: TRuleBook; AHeaderIdx: Integer; const AOld: string): TRuleNode;
begin
  for var LNode: TRuleNode in MigratesForBlock(ABook, AHeaderIdx) do
    if IsMemberMigrate(LNode) and SameText(LNode.MigOld, AOld) then
      Exit(LNode);
  Result:= nil;
end;

function AddMigrate(ABook: TRuleBook; AHeaderIdx: Integer; const AOld, ANew: string): TRuleNode;
var
  LAt: Integer;
begin
  if (AHeaderIdx < 0) or (AHeaderIdx >= ABook.Nodes.Count) or (ABook.Nodes[AHeaderIdx].Kind <> rnkConvert) then
    Exit(nil);
  // After the block's last line that is neither blank nor a comment.
  LAt:= AHeaderIdx + 1;
  for var I: Integer:= AHeaderIdx + 1 to ABook.Nodes.Count - 1 do
  begin
    if ABook.Nodes[I].Kind = rnkConvert then
      Break;
    if not (ABook.Nodes[I].Kind in [rnkBlank, rnkComment]) then
      LAt:= I + 1;
  end;
  Result:= TRuleNode.Create;
  Result.Kind  := rnkMigrate;
  Result.MigOld:= AOld;
  Result.MigNew:= ANew;
  Result.Dirty := True;
  Result.Raw   := Result.Emit;
  ABook.Nodes.Insert(LAt, Result);
end;

procedure SetMigrateNew(ANode: TRuleNode; const ANew: string);
begin
  if (ANode = nil) or (ANode.Kind <> rnkMigrate) then
    Exit;
  ANode.MigNew:= ANew;
  ANode.Dirty := True;
  ANode.Marks := nil;
end;

end.
