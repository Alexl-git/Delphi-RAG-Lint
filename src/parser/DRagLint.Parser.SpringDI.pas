unit DRagLint.Parser.SpringDI;

/// <summary>
///   Pure recognizer for the Spring4D dependency-injection fluent idiom. Given a
///   method-access chain captured from the Delphi AST (one link per
///   '.Method&lt;TypeArgs&gt;' segment, in source order), classifies it as a DI
///   registration, a resolution, an unresolved DI call, or none.
/// </summary>
/// <remarks>
///   No tree-sitter or database dependency: the caller (DRagLint.Parser.Delphi13)
///   extracts the chain links and feeds them here, then persists the result. This
///   keeps the pattern rules in one small, independently testable unit.
///   Recognized real-world idioms (from ORM3):
///     GlobalContainer.RegisterType&lt;TImpl&gt;.Implements&lt;IIntf&gt;.AsSingleton;
///     GlobalContainer.RegisterType&lt;TImpl&gt;.Implements&lt;IDataService&lt;IFoo&gt;&gt;.AsSingletonPerThread;
///     GlobalContainer.RegisterType&lt;TImpl&gt;.Implements&lt;IIntf&gt;;   // transient
///     GlobalContainer.RegisterType&lt;TImpl&gt;.As&lt;IIntf&gt;.AsSingleton;  // legacy .As
///     GlobalContainer.Resolve&lt;IIntf&gt;;
///   Type-argument text is taken verbatim, so nested generics
///   ('IDataService&lt;ImcCAUSFAIL&gt;') are preserved.
/// </remarks>
interface

uses
  System.SysUtils;

type
  /// <summary>One '.Method&lt;TypeArg&gt;' link of a captured access chain.</summary>
  /// <remarks>
  /// TypeArg is the inner text of the generic argument list with the
  /// surrounding angle brackets already stripped, or '' when the link has no
  /// type argument (e.g. '.AsSingleton').
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Parser.Delphi13.TryEmitSpringDI (DRagLint.Parser.Delphi13.pas), declaration (DRagLint.Parser.SpringDI.pas), DRagLint.Parser.SpringDI.FindLink (DRagLint.Parser.SpringDI.pas), DRagLint.Parser.SpringDI.HasLink (DRagLint.Parser.SpringDI.pas), DRagLint.Parser.SpringDI.FirstDiRegistrationVerb (DRagLint.Parser.SpringDI.pas) (+1 more)</para>
  /// <para>Used in units: DRagLint.Parser.Delphi13, DRagLint.Parser.SpringDI</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDiChainLink = record
    MethodName: string;
    TypeArg:    string;
  end;

  /// <summary>Classification of a captured method-access chain.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Parser.Delphi13.TryEmitSpringDI (DRagLint.Parser.Delphi13.pas), declaration (DRagLint.Parser.SpringDI.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDiOutcome = (
    /// <summary>Not a Spring4D DI chain.</summary>
    dioNone,
    /// <summary>A resolved registration (interface -> implementation + lifetime).</summary>
    dioRegister,
    /// <summary>A resolution site (Resolve/TryResolve of an interface).</summary>
    dioResolve,
    /// <summary>A DI registration we deliberately do not resolve into an I->T
    /// edge yet (named / instance / factory / delegate / bare Register).</summary>
    dioUnresolved
  );

  /// <summary>A resolved Spring4D DI binding: InterfaceName implemented by
  /// ImplName with the given Lifetime. Endpoint names are verbatim, incl. nested
  /// generics.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Parser.Delphi13.TryEmitSpringDI (DRagLint.Parser.Delphi13.pas), declaration (DRagLint.Parser.SpringDI.pas), DRagLint.Parser.SpringDI.ClassifyDiChain (DRagLint.Parser.SpringDI.pas)</para>
  /// <para>Used in units: DRagLint.Parser.Delphi13, DRagLint.Parser.SpringDI</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDiBinding = record
    InterfaceName: string;
    ImplName:      string;
    Lifetime:      string;
  end;

const
  /// <summary>Lifetime tokens written into di_bindings.lifetime.</summary>
  DI_LIFETIME_SINGLETON            = 'singleton';
  DI_LIFETIME_SINGLETON_PER_THREAD = 'singleton-per-thread';
  DI_LIFETIME_TRANSIENT            = 'transient';

/// <summary>Classifies a captured Spring4D method-access chain.</summary>
/// <param name="AChain">Links in source order, e.g.
/// [('RegisterType','TFoo'),('Implements','IFoo'),('AsSingleton','')].</param>
/// <param name="ABinding">Filled when the result is dioRegister; otherwise reset.</param>
/// <param name="AResolveInterface">Interface name when the result is dioResolve;
/// otherwise ''.</param>
/// <param name="AUnresolvedMethod">The DI method name when the result is
/// dioUnresolved; otherwise ''.</param>
/// <returns>The classification outcome.</returns>
/// <remarks>
/// Pure and side-effect free. Method-name matching is case-insensitive.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Parser.Delphi13.TryEmitSpringDI (DRagLint.Parser.Delphi13.pas)</para>
/// <para>Calls: Default, DRagLint.Parser.SpringDI.FindLink, DRagLint.Parser.SpringDI.FirstDiRegistrationVerb, DRagLint.Parser.SpringDI.HasLink</para>
/// <para>Returns: dioNone; dioRegister; dioResolve; dioUnresolved</para>
/// <para>Complexity: 13 (cyclomatic, outer body), 52 lines (full implementation)</para>
/// <para>Mutates: ABinding (out), AResolveInterface (out), AUnresolvedMethod (out)</para>
/// <seealso cref="DRagLint.Parser.SpringDI.FindLink"/>
/// <seealso cref="DRagLint.Parser.SpringDI.FirstDiRegistrationVerb"/>
/// <seealso cref="DRagLint.Parser.SpringDI.HasLink"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ClassifyDiChain(const AChain: TArray<TDiChainLink>;
  out ABinding: TDiBinding; out AResolveInterface: string;
  out AUnresolvedMethod: string): TDiOutcome;

implementation

// Returns the first link whose method name matches AName (case-insensitive).
function FindLink(const AChain: TArray<TDiChainLink>; const AName: string;
  out ALink: TDiChainLink): Boolean;
var
  L: TDiChainLink;
begin
  for L in AChain do
    if SameText(L.MethodName, AName) then
    begin
      ALink := L;
      Exit(True);
    end;
  ALink := Default(TDiChainLink);
  Result := False;
end;

function HasLink(const AChain: TArray<TDiChainLink>; const AName: string): Boolean;
var
  Dummy: TDiChainLink;
begin
  Result := FindLink(AChain, AName, Dummy);
end;

// True if the chain contains any DI registration verb at all (used to decide
// dioUnresolved for forms we do not fully resolve).
function FirstDiRegistrationVerb(const AChain: TArray<TDiChainLink>): string;
const
  // Registration-family verbs. 'Resolve'/'TryResolve' are handled separately.
  VERBS: array[0..5] of string = (
    'RegisterType', 'RegisterInstance', 'RegisterFactory',
    'RegisterDecorator', 'Register', 'DelegateTo');
var
  L: TDiChainLink;
  V: string;
begin
  for L in AChain do
    for V in VERBS do
      if SameText(L.MethodName, V) then
        Exit(L.MethodName);
  Result := '';
end;

function ClassifyDiChain(const AChain: TArray<TDiChainLink>;
  out ABinding: TDiBinding; out AResolveInterface: string;
  out AUnresolvedMethod: string): TDiOutcome;
var
  RegLink, IntfLink, ResLink: TDiChainLink;
  Verb: string;
begin
  ABinding := Default(TDiBinding);
  AResolveInterface := '';
  AUnresolvedMethod := '';
  Result := dioNone;
  if Length(AChain) = 0 then
    Exit;

  // (1) Registration: RegisterType<TImpl> + (Implements<IIntf> | legacy As<IIntf>).
  if FindLink(AChain, 'RegisterType', RegLink) and (RegLink.TypeArg <> '') then
  begin
    if (not (FindLink(AChain, 'Implements', IntfLink) and (IntfLink.TypeArg <> ''))) then
      FindLink(AChain, 'As', IntfLink);
    if IntfLink.TypeArg <> '' then
    begin
      ABinding.ImplName := RegLink.TypeArg;
      ABinding.InterfaceName := IntfLink.TypeArg;
      if HasLink(AChain, 'AsSingletonPerThread') then
        ABinding.Lifetime := DI_LIFETIME_SINGLETON_PER_THREAD
      else if HasLink(AChain, 'AsSingleton') then
        ABinding.Lifetime := DI_LIFETIME_SINGLETON
      else
        ABinding.Lifetime := DI_LIFETIME_TRANSIENT;
      Exit(dioRegister);
    end;
  end;

  // (2) Resolution: Resolve<IIntf> / TryResolve<IIntf>.
  if (FindLink(AChain, 'Resolve', ResLink) or FindLink(AChain, 'TryResolve', ResLink))
     and (ResLink.TypeArg <> '') then
  begin
    AResolveInterface := ResLink.TypeArg;
    Exit(dioResolve);
  end;

  // (3) A DI registration we do not resolve into an I->T edge (RegisterInstance,
  // RegisterFactory, DelegateTo, bare Register, or RegisterType with no
  // Implements/As). Flagged so coverage gaps are measurable, not silently lost.
  Verb := FirstDiRegistrationVerb(AChain);
  if Verb <> '' then
  begin
    AUnresolvedMethod := Verb;
    Exit(dioUnresolved);
  end;

  Result := dioNone;
end;

end.
