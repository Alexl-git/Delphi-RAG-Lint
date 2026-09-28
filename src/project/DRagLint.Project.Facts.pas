unit DRagLint.Project.Facts;

{ What a project's BUILD actually does, read from its .dproj -- the report
  behind `drag-lint project-facts` (owner ruling 2026-09-16, C9 / FIX-6).

  WHY IT EXISTS. A symbol index cannot answer "does this project post-process
  with EurekaLog?", and the answer was costly to discover: DataCopy defines
  EUREKALOG_VER7;EUREKALOG and pulls ExceptionLog7 in under an IFDEF, but
  imports no EurekaLog .targets, so an msbuild exe carries the code without the
  post-processing and dies at start-up. Every fact needed was in the .dproj;
  nothing read it.

  SCOPE. The four PropertyGroups MSBuild applies for one platform + config --
  Base, Base_<Platform>, Cfg_N, Cfg_N_<Platform>, the same set and the same
  Release -> Cfg_2 / Debug -> Cfg_1 indirection DRagLint.Preprocess.Profile
  uses (that unit is on the extractor-hashed surface, so this one reads the file
  itself rather than growing it). A report, not a lint rule: no index, no
  schema, no extractor involvement. }

interface

type
  /// <summary>One define that is ON for the platform + config, with every
  /// place that turns it on.</summary>
  TProjectDefine = record
    /// <summary>The define as the .dproj spells it (case kept).</summary>
    Name   : string;
    /// <summary>Group labels ('Base', 'Base_Win64', 'Cfg_2', 'Cfg_2_Win64'),
    /// 'optset:<file>' for an imported option set, or 'builtin'.</summary>
    Sources: TArray<string>;
  end;

  /// <summary>One `&lt;Import&gt;` of the .dproj.</summary>
  TProjectImport = record
    /// <summary>The Project attribute, verbatim (macros unexpanded).</summary>
    Project  : string;
    /// <summary>The Condition attribute, verbatim; '' when absent.</summary>
    Condition: string;
    /// <summary>'targets' | 'optset' | 'proj' | 'deployproj' | 'other', from
    /// the extension.</summary>
    Kind     : string;
  end;

  /// <summary>Everything `project-facts` reports for one .dproj, platform and
  /// config.</summary>
  TProjectFacts = record
    DprojPath  : string;
    Platform   : string;
    Config     : string;
    /// <summary>The config's Cfg_N alias (Release -> Cfg_2, Debug -> Cfg_1).</summary>
    CfgAlias   : string;
    /// <summary>False when the file is missing or unreadable; every other
    /// field is then empty.</summary>
    Found      : Boolean;
    Defines    : TArray<TProjectDefine>;
    Imports    : TArray<TProjectImport>;
    /// <summary>DCC_ExeOutput / DCC_DcuOutput as the LAST applied group sets
    /// them (MSBuild order), verbatim; '' when no group sets one.</summary>
    ExeOutput  : string;
    DcuOutput  : string;
    /// <summary>DCC_UsePackage of the last applied group that sets it, split,
    /// the $(DCC_UsePackage) recursion token dropped.</summary>
    UsePackages: TArray<string>;
    /// <summary>Human-readable findings, e.g. a post-processor define with no
    /// import that brings in its build step.</summary>
    Notices    : TArray<string>;
  end;

  /// <summary>A build-time post-processor the report knows how to recognise.</summary>
  TPostProcessor = record
    /// <summary>Display name, e.g. 'EurekaLog'.</summary>
    Tool        : string;
    /// <summary>Lowercased define prefix that says the code is compiled in.</summary>
    DefinePrefix: string;
    /// <summary>Lowercased text an `&lt;Import Project&gt;` must contain for the
    /// build step to be imported.</summary>
    ImportNeedle: string;
    /// <summary>Lowercased unit-name prefixes of the tool's runtime units.</summary>
    UnitPrefixes: TArray<string>;
  end;

/// <summary>Reads the build facts of ADprojPath for APlatform and AConfig.</summary>
/// <param name="ADprojPath">The .dproj; missing or unreadable -> Found=False.</param>
/// <param name="APlatform">'Win32' or 'Win64' (case-insensitive); anything else
/// is Win64, as DRagLint.Preprocess.Profile treats it.</param>
/// <param name="AConfig">'Debug' selects Cfg_1; anything else is Release (Cfg_2).</param>
/// <returns>The facts. Defines include the platform built-ins as source
/// 'builtin'. Never raises: an unreadable file is Found=False.</returns>
/// <remarks>A group is matched on its exact `'$(X)'!=''` condition, the shape
/// RAD Studio writes for the four definition groups; when a file has no such
/// group for X, the first group whose condition CONTAINS `$(X)` and sets the
/// property is used -- DRagLint.Preprocess.Profile's rule. An optset import is
/// read (relative to the .dproj) for its own DCC_Define when its path carries
/// no macro and its Condition names an active group or none. Macros are never
/// expanded; paths are reported as written.</remarks>
function ReadProjectFacts(const ADprojPath, APlatform, AConfig: string): TProjectFacts;

/// <summary>The post-processors ReadProjectFacts checks for.</summary>
/// <returns>EurekaLog and madExcept.</returns>
function KnownPostProcessors: TArray<TPostProcessor>;

/// <summary>The post-processors whose define is ON in AFacts (whether or not
/// their build step is imported).</summary>
/// <param name="AFacts">A report from ReadProjectFacts.</param>
/// <returns>The matching entries of KnownPostProcessors, in table order.</returns>
function ActivePostProcessors(const AFacts: TProjectFacts): TArray<TPostProcessor>;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  DRagLint.Preprocess.Profile;

const
  RECURSION_DEFINE  = '$(DCC_Define)';
  RECURSION_PACKAGE = '$(DCC_UsePackage)';

function KnownPostProcessors: TArray<TPostProcessor>;
var
  P: TPostProcessor;
begin
  Result:= nil;
  P.Tool        := 'EurekaLog';
  P.DefinePrefix:= 'eurekalog';
  P.ImportNeedle:= 'eurekalog';
  P.UnitPrefixes:= ['exceptionlog', 'eurekalog', 'ebase', 'ecore', 'emodules'];
  Result:= Result + [P];
  P.Tool        := 'madExcept';
  P.DefinePrefix:= 'madexcept';
  P.ImportNeedle:= 'madexcept';
  P.UnitPrefixes:= ['madexcept', 'madlinkdisasm', 'madlisthardware', 'madlistprocesses', 'madlistmodules'];
  Result:= Result + [P];
end;

{ The inner XML of the group for label ALabel: the exact `'$(ALabel)'!=''`
  group first, then Profile's contains-rule restricted to groups that set
  AProperty. '' when neither exists. }
function GroupBody(const AContent, ALabel, AProperty: string): string;
var
  M    : TMatch;
  Cond : string;
  Exact: string;
begin
  Result:= '';
  Exact := '''$(' + ALabel + ')''!=''''';
  for M in TRegEx.Matches(AContent, '<PropertyGroup\b[^>]*Condition="([^"]*)"[^>]*>(.*?)</PropertyGroup>',
                          [roIgnoreCase, roSingleLine]) do
    if SameText(Trim(M.Groups[1].Value), Exact) then Exit(M.Groups[2].Value);
  for M in TRegEx.Matches(AContent, '<PropertyGroup\b[^>]*Condition="([^"]*)"[^>]*>(.*?)</PropertyGroup>',
                          [roIgnoreCase, roSingleLine]) do
  begin
    Cond:= M.Groups[1].Value;
    if ContainsText(Cond, '$(' + ALabel + ')')
       and ContainsText(M.Groups[2].Value, '<' + AProperty + '>') then Exit(M.Groups[2].Value);
  end;
end;

function PropertyIn(const ABody, AProperty: string): string;
var
  M: TMatch;
begin
  M:= TRegEx.Match(ABody, '<' + AProperty + '>(.*?)</' + AProperty + '>', [roIgnoreCase, roSingleLine]);
  if M.Success then Result:= Trim(M.Groups[1].Value) else Result:= '';
end;

function AttrOf(const ATag, AName: string): string;
var
  M: TMatch;
begin
  M:= TRegEx.Match(ATag, '\b' + AName + '="([^"]*)"', [roIgnoreCase]);
  if M.Success then Result:= M.Groups[1].Value else Result:= '';
end;

function ImportKind(const AProject: string): string;
var
  Ext: string;
begin
  Ext:= LowerCase(ExtractFileExt(AProject));
  if Ext = '.targets' then Result:= 'targets'
  else if Ext = '.optset' then Result:= 'optset'
  else if Ext = '.deployproj' then Result:= 'deployproj'
  else if Ext = '.proj' then Result:= 'proj'
  else Result:= 'other';
end;

{ Adds every define of a DCC_Define value to AOrder / AIdx with ASource. }
procedure AddDefines(const AValue, ASource: string; AOrder: TList<TProjectDefine>;
  AIdx: TDictionary<string, Integer>);
var
  Part: string;
  Sym : string;
  I   : Integer;
  D   : TProjectDefine;
begin
  for Part in AValue.Split([';']) do
  begin
    Sym:= Trim(Part);
    if (Sym = '') or SameText(Sym, RECURSION_DEFINE) then Continue;
    if AIdx.TryGetValue(LowerCase(Sym), I) then
    begin
      D:= AOrder[I];
      if IndexText(ASource, D.Sources) < 0 then D.Sources:= D.Sources + [ASource];
      AOrder[I]:= D;
    end
    else
    begin
      D.Name   := Sym;
      D.Sources:= [ASource];
      AIdx.Add(LowerCase(Sym), AOrder.Count);
      AOrder.Add(D);
    end;
  end;
end;

function ActivePostProcessors(const AFacts: TProjectFacts): TArray<TPostProcessor>;
var
  P: TPostProcessor;
  D: TProjectDefine;
begin
  Result:= nil;
  for P in KnownPostProcessors do
    for D in AFacts.Defines do
      if StartsText(P.DefinePrefix, D.Name) and (IndexText('builtin', D.Sources) < 0) then
      begin
        Result:= Result + [P];
        Break;
      end;
end;

{ Whether an import's Condition applies to the build ALabels describes. A
  condition naming no group label (`$(Base)`, `$(Base_Win64)`, `$(Cfg_2)`, ...)
  applies always; one that names labels applies when any of them is active --
  an option set attached to Cfg_1 must not colour a Release report. }
function ConditionIsActive(const ACondition: string; const ALabels: TArray<string>): Boolean;
var
  M      : TMatch;
  AnyName: Boolean;
begin
  AnyName:= False;
  for M in TRegEx.Matches(ACondition, '\$\(((?:Base|Cfg_\d+)(?:_\w+)?)\)', [roIgnoreCase]) do
  begin
    AnyName:= True;
    if IndexText(M.Groups[1].Value, ALabels) >= 0 then Exit(True);
  end;
  Result:= not AnyName;
end;

{ One notice per active post-processor whose build step no import brings in. }
function PostProcessorNotices(const AFacts: TProjectFacts): TArray<string>;
var
  P       : TPostProcessor;
  Imp     : TProjectImport;
  D       : TProjectDefine;
  Imported: Boolean;
  Names   : string;
begin
  Result:= nil;
  for P in ActivePostProcessors(AFacts) do
  begin
    Imported:= False;
    for Imp in AFacts.Imports do
      Imported:= Imported or ContainsText(Imp.Project, P.ImportNeedle);
    if Imported then Continue;
    Names:= '';
    for D in AFacts.Defines do
      if StartsText(P.DefinePrefix, D.Name) then Names:= Names + IfThen(Names <> '', ', ', '') + D.Name;
    Result:= Result + [Format('%s is compiled in (%s ON for %s %s) but no <Import> brings in its build ' +
      'step: an msbuild build carries the %s code without its post-processing.',
      [P.Tool, Names, AFacts.Platform, AFacts.Config, P.Tool])];
  end;
end;

function ReadProjectFacts(const ADprojPath, APlatform, AConfig: string): TProjectFacts;
var
  Content: string;
  Labels : TArray<string>;
  Lbl    : string;
  Body   : string;
  Value  : string;
  Order  : TList<TProjectDefine>;
  Idx    : TDictionary<string, Integer>;
  M      : TMatch;
  Imp    : TProjectImport;
  Sym    : string;
  OptPath: string;
  Part   : string;
begin
  Result:= Default(TProjectFacts);
  Result.DprojPath:= ADprojPath;
  Result.Platform := IfThen(SameText(APlatform, 'Win32'), 'Win32', 'Win64');
  Result.Config   := IfThen(SameText(AConfig, 'Debug'), 'Debug', 'Release');
  Result.CfgAlias := IfThen(Result.Config = 'Debug', 'Cfg_1', 'Cfg_2');
  if (ADprojPath = '') or not TFile.Exists(ADprojPath) then Exit;
  try
    Content:= TFile.ReadAllText(ADprojPath);
  except
    on E: EInOutError do
    begin
      Result.Notices:= ['the .dproj could not be read: ' + E.Message];
      Exit;
    end;
  end;
  Result.Found:= True;
  { MSBuild's order for one platform + config -- the later group wins a scalar. }
  Labels:= ['Base', 'Base_' + Result.Platform, Result.CfgAlias, Result.CfgAlias + '_' + Result.Platform];

  Order:= TList<TProjectDefine>.Create;
  Idx  := TDictionary<string, Integer>.Create;
  try
    for Sym in PlatformBuiltins(Result.Platform) do AddDefines(Sym, 'builtin', Order, Idx);
    for Lbl in Labels do
    begin
      AddDefines(PropertyIn(GroupBody(Content, Lbl, 'DCC_Define'), 'DCC_Define'), Lbl, Order, Idx);
      Body:= GroupBody(Content, Lbl, 'DCC_ExeOutput');
      Value:= PropertyIn(Body, 'DCC_ExeOutput');
      if Value <> '' then Result.ExeOutput:= Value;
      Body:= GroupBody(Content, Lbl, 'DCC_DcuOutput');
      Value:= PropertyIn(Body, 'DCC_DcuOutput');
      if Value <> '' then Result.DcuOutput:= Value;
      Body:= GroupBody(Content, Lbl, 'DCC_UsePackage');
      Value:= PropertyIn(Body, 'DCC_UsePackage');
      if Value <> '' then
      begin
        Result.UsePackages:= nil;
        for Part in Value.Split([';']) do
          if (Trim(Part) <> '') and not SameText(Trim(Part), RECURSION_PACKAGE) then
            Result.UsePackages:= Result.UsePackages + [Trim(Part)];
      end;
    end;

    for M in TRegEx.Matches(Content, '<Import\b[^>]*/?>', [roIgnoreCase]) do
    begin
      Imp.Project  := AttrOf(M.Value, 'Project');
      Imp.Condition:= AttrOf(M.Value, 'Condition');
      Imp.Kind     := ImportKind(Imp.Project);
      Result.Imports:= Result.Imports + [Imp];
      { An option set contributes defines of its own; read it when the path is
        literal (a macro would need MSBuild to evaluate). }
      if (Imp.Kind = 'optset') and (Pos('$(', Imp.Project) = 0) and ConditionIsActive(Imp.Condition, Labels) then
      begin
        OptPath:= TPath.Combine(ExtractFilePath(ADprojPath), Imp.Project);
        if TFile.Exists(OptPath) then
          try
            AddDefines(PropertyIn(TFile.ReadAllText(OptPath), 'DCC_Define'),
                       'optset:' + ExtractFileName(Imp.Project), Order, Idx);
          except
            on E: EInOutError do
              Result.Notices:= Result.Notices + ['option set ' + Imp.Project + ' could not be read, so its defines are missing here: ' + E.Message];
          end;
      end;
    end;
    Result.Defines:= Order.ToArray;
  finally
    Idx.Free;
    Order.Free;
  end;
  Result.Notices:= Result.Notices + PostProcessorNotices(Result);
end;

end.
