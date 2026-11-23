unit DRagLint.V154.ParamModes;

{ Wave v154 (1.54.0-alpha) shared helper S5: the parameter modes of one routine, read from the stored
  signature text (the index has no mode on a kind='param' symbol) and cross-checked with
  symbol_facts.mutates_params. Used by same-variable-two-var-params, fresh-instance arguments,
  var-param-never-written and value-param-assigned. Owned by FRAME / INT; a rule lane only calls it. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Analysis.Flow.Lattices
  ;

type
  /// <summary>What symbol_facts.mutates_params says about one parameter.</summary>
  /// <remarks>
  /// vmUnknown: no facts row, no body, or the list is capped and the name is not in the shown part.
  /// vmNotListed is NOT "never written": the fact does not see a write through another routine's var
  /// argument (SetLength(AList, N)), nor `AParam.Field := X`.
  /// </remarks>
  TV154Mutated = (vmUnknown, vmNotListed, vmListed);

  /// <summary>One parameter of a routine.</summary>
  TV154Param = record
    Name      : string;        // as written, without a leading '&'
    TypeText  : string;        // declared type without the default value; '' = untyped
    Mode      : TParamMode;    // pmValue, pmConst, pmVar or pmOut; never pmUnknown inside a Known list
    HasDefault: Boolean;       // a call may leave it out
    Mutated   : TV154Mutated;
    /// <summary>True for var and out: the callee can change the caller's variable.</summary>
    /// <returns>Mode in [pmVar, pmOut].</returns>
    function ByReference: Boolean;
    /// <summary>True for an untyped `const X` / `var X` / `out X`.</summary>
    /// <returns>True when no type is written.</returns>
    function IsUntyped: Boolean;
  end;

  /// <summary>The parameters of one routine, or the reason they are not known.</summary>
  /// <remarks>A consumer must do nothing when Known is False; Params is empty then.</remarks>
  TV154ParamList = record
    Known : Boolean;
    Reason: string;               // why Known is False; '' otherwise
    Params: TArray<TV154Param>;   // declaration order
    /// <summary>The mode at a 0-based argument position.</summary>
    /// <param name="AIndex">Argument position.</param>
    /// <returns>pmUnknown when the list is not known or has no such position.</returns>
    function ModeAt(AIndex: Integer): TParamMode;
    /// <summary>Finds a parameter by name, case-insensitive.</summary>
    /// <param name="AName">The name, with or without a leading '&amp;'.</param>
    /// <returns>Its position, or -1.</returns>
    function IndexOf(const AName: string): Integer;
  end;

/// <summary>Reads the modes from a signature text.</summary>
/// <param name="ASignature">A routine's stored signature, e.g. '(const A: string; out B): Boolean'; '' = no parameters.</param>
/// <param name="AMutatesParams">symbol_facts.mutates_params, e.g. 'B (out)'.</param>
/// <param name="AFactsKnown">False when the routine has no facts row or no body: AMutatesParams says nothing then.</param>
/// <returns>Known = False with a Reason when the text is cut or unbalanced, holds a conditional directive,
/// when a name is not an identifier, or when AMutatesParams names a parameter the signature does not
/// declare with that mode.</returns>
/// <remarks>Pure; safe from any thread.</remarks>
function V154ParamsOf(const ASignature, AMutatesParams: string; AFactsKnown: Boolean): TV154ParamList;

/// <summary>Reads the modes of an indexed routine and cross-checks them with its facts.</summary>
/// <param name="AStore">The index ARoutine comes from; nil = no cross-check.</param>
/// <param name="ARoutine">A procedure, function, method, constructor or destructor symbol.</param>
/// <returns>See V154ParamsOf; Known = False for any other symbol kind.</returns>
/// <remarks>Reads one facts row.</remarks>
function V154RoutineParams(const AStore: ISymbolStore; const ARoutine: TSymbol): TV154ParamList;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , DRagLint.Analysis.Purity  // dl:unit DRagLint.Analysis.Purity accepted -- ParseMutatedParamNames is the one reader of the stored mutates_params text
  , DRagLint.Hover.Renderer   // dl:unit DRagLint.Hover.Renderer accepted -- ParseSignatureParams is the one parameter-list parser (the flow checks use it too)
  ;

type
  { One pass over a signature that leaves what ParseSignatureParams can read: comments, attributes and
    string contents are gone, line breaks are spaces, a '<' in a default value is no bracket. }
  TSignatureText = record
  strict private
    FSrc   : string;
    FPos   : Integer;
    FDepth : Integer;
    FInName: Boolean;   // between '(' or ';' and the ':'
    FInDef : Boolean;   // between '=' and the ';'
    function At(const AText: string): Boolean;
    function SkipPast(const AClose: string): Boolean;
    procedure Bracket(AChar: Char);
    function Emit: Boolean;
  public
    Text  : string;
    Reason: string;
    function Scan(const ASignature: string): Boolean;
  end;

function BareName(const AName: string): string;
begin
  Result:= Trim(AName);
  if Result.StartsWith('&') then Result:= Copy(Result, Length('&') + 1, MaxInt);
end;

function TSignatureText.At(const AText: string): Boolean;
begin
  Result:= Copy(FSrc, FPos, Length(AText)) = AText;
end;

{ Moves FPos to the last character of AClose; False when it never comes. }
function TSignatureText.SkipPast(const AClose: string): Boolean;
begin
  var P: Integer:= PosEx(AClose, FSrc, FPos + 1);
  Result:= P > 0;
  if Result then FPos:= P + Length(AClose) - 1
  else Reason:= 'no closing ' + AClose;
end;

procedure TSignatureText.Bracket(AChar: Char);
begin
  case AChar of
    '(': Inc(FDepth);
    ')': Dec(FDepth);
  end;
  if FDepth <> 1 then Exit;
  case AChar of
    '(', ';':
    begin
      FInName:= True;
      FInDef := False;
    end;
    ':': FInName:= False;
    '=': FInDef := True;
  end;
end;

{ Copies or drops what starts at FPos; False = Reason is set. }
function TSignatureText.Emit: Boolean;
begin
  Result:= True;
  if At('{$') or At('(*$') then
  begin
    Reason:= 'a conditional directive in the parameter list';
    Exit(False);
  end;
  if At('{') then Exit(SkipPast('}'));
  if At('(*') then Exit(SkipPast('*)'));
  if At('''') then
  begin
    Text:= Text + '_';
    Exit(SkipPast(''''));
  end;
  if FInName and At('[') then Exit(SkipPast(']'));
  var C: Char:= FSrc[FPos];
  Bracket(C);
  if (C < ' ') or (FInDef and CharInSet(C, ['<', '>'])) then C:= ' ';
  Text:= Text + C;
end;

function TSignatureText.Scan(const ASignature: string): Boolean;
begin
  FSrc:= Trim(ASignature);
  FPos:= 1;
  while FPos <= Length(FSrc) do
  begin
    if not Emit then Exit(False);
    if (Text <> '') and (FDepth = 0) then Exit(True); // the list is closed, or there is none
    Inc(FPos);
  end;
  Result:= FDepth = 0;
  if not Result then Reason:= 'the parameter list is not closed';
end;

function TV154Param.ByReference: Boolean;
begin
  Result:= Mode in [pmVar, pmOut];
end;

function TV154Param.IsUntyped: Boolean;
begin
  Result:= TypeText = '';
end;

function TV154ParamList.ModeAt(AIndex: Integer): TParamMode;
begin
  Result:= if (AIndex >= 0) and (AIndex < Length(Params)) then Params[AIndex].Mode else pmUnknown;
end;

function TV154ParamList.IndexOf(const AName: string): Integer;
begin
  for var I: Integer:= 0 to High(Params) do
    if SameText(Params[I].Name, BareName(AName)) then Exit(I);
  Result:= -1;
end;

function ModeOfModifier(const AModifier: string): TParamMode;
begin
  if AModifier = '' then Exit(pmValue);
  if SameText(AModifier, 'const') then Exit(pmConst);
  Result:= if SameText(AModifier, 'var') then pmVar else pmOut;
end;

function Refuse(const AReason: string): TV154ParamList;
begin
  Result:= Default(TV154ParamList);
  Result.Reason:= AReason;
end;

{ Folds mutates_params in; '' or why the two texts do not describe the same routine. }
function ApplyMutates(var AList: TV154ParamList; const AMutates: string): string;
var
  Capped: Boolean;
begin
  Result:= '';
  var Names: TArray<string>:= ParseMutatedParamNames(AMutates, Capped);
  for var I: Integer:= 0 to High(AList.Params) do
    AList.Params[I].Mutated:= if Capped then vmUnknown else vmNotListed;
  for var N: string in Names do
  begin
    var At: Integer:= AList.IndexOf(N);
    if At < 0 then Exit('mutates_params names ' + N + ', the signature does not');
    var Tag: string:= if AList.Params[At].Mode = pmOut then ' (out)' else ' (var)';
    if (not AList.Params[At].ByReference) or not ContainsText(', ' + AMutates, ', ' + N + Tag) then
      Exit('mutates_params and the signature give ' + N + ' another mode');
    AList.Params[At].Mutated:= vmListed;
  end;
end;

function V154ParamsOf(const ASignature, AMutatesParams: string; AFactsKnown: Boolean): TV154ParamList;
var
  Scan: TSignatureText;
begin
  Scan:= Default(TSignatureText);
  if not Scan.Scan(ASignature) then Exit(Refuse(Scan.Reason));
  Result:= Default(TV154ParamList);
  for var P: TParamPart in ParseSignatureParams(Scan.Text) do
  begin
    var V: TV154Param:= Default(TV154Param);
    V.Name:= BareName(P.Name);
    V.Mode:= ModeOfModifier(P.Modifier);
    if not IsValidIdent(V.Name) then Exit(Refuse('not a parameter name: ' + V.Name));
    if P.TypeText.Contains('...') then Exit(Refuse('the signature text is cut'));
    var Eq: Integer:= Pos('=', P.TypeText);
    V.HasDefault:= Eq > 0;
    V.TypeText:= if V.HasDefault then Trim(Copy(P.TypeText, 1, Eq - 1)) else Trim(P.TypeText);
    Result.Params:= Result.Params + [V];
  end;
  Result.Known:= True;
  if not AFactsKnown then Exit;
  var Conflict: string:= ApplyMutates(Result, AMutatesParams);
  if Conflict <> '' then Result:= Refuse(Conflict);
end;

function V154RoutineParams(const AStore: ISymbolStore; const ARoutine: TSymbol): TV154ParamList;
begin
  if ARoutine.Kind not in [skProcedure, skFunction, skMethod, skConstructor, skDestructor] then
    Exit(Refuse('not a routine'));
  var F: TSymbolFacts:= Default(TSymbolFacts);
  if AStore <> nil then F:= AStore.GetSymbolFacts(ARoutine.Id);
  Result:= V154ParamsOf(ARoutine.Signature, F.MutatesParams, F.Present and (F.BodyLoc > 0));
end;

end.
