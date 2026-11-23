unit DRagLint.FieldRepo.SchemaHook;

{ drag-lint 1.54 -- lane TT-ALTER: the replaceable hook around a per-table ALTER (owner answer FU-2: Firebird- and
  Micronite-specific actions live in a hook others can replace). A hook vetoes tables, blocks changes, adds notes and
  adds statements; everything it adds is in the plan before anything runs, so a dry run shows it. The default hook
  does nothing; the Micronite hook is DRagLint.FieldRepo.SchemaHookMicronite. }

interface

uses
  System.SysUtils,
  DRagLint.FieldRepo.Alter,
  DRagLint.FieldRepo.DbProvider;

const
  /// <summary>Name of the hook that does nothing.</summary>
  HOOK_GENERIC = 'generic';

type
  /// <summary>Raised when a table is vetoed or a hook is not registered.</summary>
  EFrSchemaHookError = class(Exception);

  /// <summary>Site-specific rules of a per-table ALTER.</summary>
  IFrSchemaHook = interface
    ['{5F9B6E6C-3B8E-45B0-9C0A-6C2D1A1B5E03}']
    /// <summary>The hook's name.</summary>
    /// <returns>What --hook takes.</returns>
    function Name: string;
    /// <summary>Refuses a whole table.</summary>
    /// <param name="pTable">Table name.</param>
    /// <returns>The reason; '' = allowed.</returns>
    function TableVeto(const pTable: string): string;
    /// <summary>Refuses one change.</summary>
    /// <param name="pChange">The planned change.</param>
    /// <returns>The reason; '' = allowed.</returns>
    function BlockReason(const pChange: TFrAlterChange): string;
    /// <summary>Remarks for the person who applies the plan.</summary>
    /// <param name="pPlan">The plan.</param>
    /// <returns>One line each.</returns>
    function Notes(const pPlan: TFrAlterPlan): TArray<string>;
    /// <summary>Statements run, in their own transaction, before the first group.</summary>
    /// <param name="pPlan">The plan.</param>
    /// <param name="pDialect">SQL text generator.</param>
    /// <returns>The statements.</returns>
    function BeforeStatements(const pPlan: TFrAlterPlan; const pDialect: IFrDbDialect): TArray<string>;
    /// <summary>Statements run, in their own transaction, after the last group.</summary>
    /// <param name="pPlan">The plan.</param>
    /// <param name="pDialect">SQL text generator.</param>
    /// <returns>The statements.</returns>
    function AfterStatements(const pPlan: TFrAlterPlan; const pDialect: IFrDbDialect): TArray<string>;
  end;

  /// <summary>The do-nothing hook; a site hook overrides what it needs.</summary>
  TFrSchemaHook = class(TInterfacedObject, IFrSchemaHook)
  public
    /// <summary>See IFrSchemaHook.</summary>
    /// <returns>HOOK_GENERIC.</returns>
    function Name: string; virtual;
    /// <summary>See IFrSchemaHook.</summary>
    /// <param name="pTable">Table name.</param>
    /// <returns>'' (allowed).</returns>
    function TableVeto(const pTable: string): string; virtual;
    /// <summary>See IFrSchemaHook.</summary>
    /// <param name="pChange">The planned change.</param>
    /// <returns>'' (allowed).</returns>
    function BlockReason(const pChange: TFrAlterChange): string; virtual;
    /// <summary>See IFrSchemaHook.</summary>
    /// <param name="pPlan">The plan.</param>
    /// <returns>Nothing.</returns>
    function Notes(const pPlan: TFrAlterPlan): TArray<string>; virtual;
    /// <summary>See IFrSchemaHook.</summary>
    /// <param name="pPlan">The plan.</param>
    /// <param name="pDialect">SQL text generator.</param>
    /// <returns>Nothing.</returns>
    function BeforeStatements(const pPlan: TFrAlterPlan; const pDialect: IFrDbDialect): TArray<string>; virtual;
    /// <summary>See IFrSchemaHook.</summary>
    /// <param name="pPlan">The plan.</param>
    /// <param name="pDialect">SQL text generator.</param>
    /// <returns>Nothing.</returns>
    function AfterStatements(const pPlan: TFrAlterPlan; const pDialect: IFrDbDialect): TArray<string>; virtual;
  end;

/// <summary>Registers (or replaces) a hook.</summary>
/// <param name="pHook">The hook; stateless, shared.</param>
/// <remarks>Not thread-safe: call from unit initialization.</remarks>
procedure RegisterSchemaHook(const pHook: IFrSchemaHook);

/// <summary>Finds a hook by name (case-insensitive).</summary>
/// <param name="pName">The name; '' = HOOK_GENERIC.</param>
/// <returns>The hook.</returns>
/// <exception cref="EFrSchemaHookError">No such hook; the message lists the registered names.</exception>
function SchemaHook(const pName: string): IFrSchemaHook;

/// <summary>Lets a hook look at a plan: blocks changes, adds notes and statements.</summary>
/// <param name="pHook">The hook.</param>
/// <param name="pDialect">SQL text generator.</param>
/// <param name="pPlan">The plan, changed in place.</param>
/// <exception cref="EFrSchemaHookError">The hook vetoes the table.</exception>
procedure ApplySchemaHook(const pHook: IFrSchemaHook; const pDialect: IFrDbDialect; var pPlan: TFrAlterPlan);

implementation

var
  GHooks: TArray<IFrSchemaHook>;

function TFrSchemaHook.Name: string;
begin
  Result := HOOK_GENERIC;
end;

function TFrSchemaHook.TableVeto(const pTable: string): string;
begin
  Result := '';
end;

function TFrSchemaHook.BlockReason(const pChange: TFrAlterChange): string;
begin
  Result := '';
end;

function TFrSchemaHook.Notes(const pPlan: TFrAlterPlan): TArray<string>;
begin
  Result := nil;
end;

function TFrSchemaHook.BeforeStatements(const pPlan: TFrAlterPlan; const pDialect: IFrDbDialect): TArray<string>;
begin
  Result := nil;
end;

function TFrSchemaHook.AfterStatements(const pPlan: TFrAlterPlan; const pDialect: IFrDbDialect): TArray<string>;
begin
  Result := nil;
end;

procedure RegisterSchemaHook(const pHook: IFrSchemaHook);
var
  i: Integer;
begin
  for i := 0 to High(GHooks) do
    if SameText(GHooks[i].Name, pHook.Name) then
    begin
      GHooks[i] := pHook;
      Exit;
    end;
  GHooks := GHooks + [pHook];
end;

function SchemaHook(const pName: string): IFrSchemaHook;
var
  VHook: IFrSchemaHook;
  VNames, VWanted: string;
begin
  VWanted := if pName = '' then HOOK_GENERIC else pName;
  VNames := '';
  for VHook in GHooks do
  begin
    if SameText(VHook.Name, VWanted) then
      Exit(VHook);
    VNames := VNames + (if VNames = '' then '' else ', ') + VHook.Name;
  end;
  raise EFrSchemaHookError.CreateFmt('unknown hook "%s"; use one of: %s', [pName, VNames]);
end;

procedure ApplySchemaHook(const pHook: IFrSchemaHook; const pDialect: IFrDbDialect; var pPlan: TFrAlterPlan);
var
  VReason: string;
  i: Integer;
begin
  VReason := pHook.TableVeto(pPlan.TableName);
  if VReason <> '' then
    raise EFrSchemaHookError.CreateFmt('hook %s refuses table %s: %s', [pHook.Name, pPlan.TableName, VReason]);
  for i := 0 to High(pPlan.Changes) do
  begin
    VReason := pHook.BlockReason(pPlan.Changes[i]);
    if VReason = '' then
      Continue;
    VReason := (if pPlan.Changes[i].Change.Blocked = '' then '' else pPlan.Changes[i].Change.Blocked + '; ') + BLOCK_HOOK + ': ' + VReason;
    pPlan.Changes[i].Change.Blocked := VReason;
    pPlan.Changes[i].Change.Checked := False;
  end;
  pPlan.HookBefore := pHook.BeforeStatements(pPlan, pDialect);
  pPlan.HookAfter := pHook.AfterStatements(pPlan, pDialect);
  pPlan.Notes := pPlan.Notes + pHook.Notes(pPlan);
end;

initialization
  RegisterSchemaHook(TFrSchemaHook.Create);

end.
