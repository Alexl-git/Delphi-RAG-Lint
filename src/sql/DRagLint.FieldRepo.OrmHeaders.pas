unit DRagLint.FieldRepo.OrmHeaders;

{ drag-lint 1.54 lane TT-GENFIX: one-time upgrade of the code TableTools wrote AROUND the DB-RAD
  regions of an ORM unit (repo update-orm only rewrites the lines inside them):
  * Assign / AssignTo: 'if not (Source is T) then inherited else with Source as T do begin'
    becomes 'if Source is not T then inherited else begin';
  * Reader: the 'var StreamSize: integer; ByteTemp: Byte;' block goes when nothing uses it
    (region 11 declares its own locals since 1.54).
  * AssignI -> Assign (1.54, owner ruling 2026-11-23): the i unit declares 'procedure Assign(const IValue: Imc<T>);',
    the u unit 'procedure Assign(Source: TPersistent); overload; override;' (published) and 'procedure Assign(const
    Value: Imc<T>); reintroduce; overload;' in a public section (only one overload can be published). The i and u
    unit are converted as a PAIR or not at all (half of it does not compile). Calls of AssignI in hand code are only listed (FindAssignICalls), never edited.
  Only the exact generated token sequence is recognised, in any layout and letter case; a comment or
  any other token in it marks the header as hand-edited and it stays as it is. }

interface

uses
  System.Classes;

/// <summary>Returns a u&lt;T&gt;.PAS text with the generated Assign / AssignTo / Reader headers in
/// their 1.54 form. Everything else is kept byte for byte.</summary>
/// <param name="pText">Text of the unit.</param>
/// <param name="pIdent">Table identifier ('$' replaced by '_'); the class is Tmc&lt;pIdent&gt;.</param>
/// <param name="pNotes">Receives one line per header that is neither the generated old form nor the
/// new one, i.e. left alone for a person to look at; not cleared.</param>
/// <returns>The upgraded text; pText itself when there is nothing to upgrade.</returns>
/// <remarks>Pure text function. A second call on its own result changes nothing.</remarks>
function UpgradeOrmHeaderText(const pText, pIdent: string; pNotes: TStrings): string;

/// <summary>Converts the generated AssignI of an i/u unit pair to the overloaded Assign.</summary>
/// <param name="pIntfText">Text of i&lt;T&gt;.PAS; ignored when pHasIntf is False.</param>
/// <param name="pUnitText">Text of u&lt;T&gt;.PAS.</param>
/// <param name="pIdent">Table identifier; the interface is Imc&lt;pIdent&gt;, the class Tmc&lt;pIdent&gt;.</param>
/// <param name="pHasIntf">False when the i unit does not exist.</param>
/// <param name="pNotes">Receives one line when the pair is left as it is because a side is not in the
/// generated form (hand-edited?) or does not match the other side; not cleared.</param>
/// <param name="pNewIntf">The i text after the conversion (pIntfText when nothing changed).</param>
/// <param name="pNewUnit">The u text after the conversion (pUnitText when nothing changed).</param>
/// <remarks>Both sides change or neither does. A pair already converted, or one with no AssignI at all, is
/// not an error and adds no note. A second call on the result changes nothing.</remarks>
procedure UpgradeOrmAssignPair(const pIntfText, pUnitText, pIdent: string; pHasIntf: Boolean; pNotes: TStrings;
  out pNewIntf, pNewUnit: string);

/// <summary>Line numbers (1-based) of the calls of AssignI in a hand-written unit.</summary>
/// <param name="pText">Text of any unit.</param>
/// <returns>One entry per line that calls AssignI; a declaration, an implementation header and a
/// comment line are not calls.</returns>
function FindAssignICalls(const pText: string): TArray<Integer>;

/// <summary>True when the Assign (or AssignTo) of a unit still runs inside 'with pParam as Tmc...'.</summary>
/// <param name="pText">Text of the unit.</param>
/// <param name="pIdent">Table identifier; the class is Tmc&lt;pIdent&gt;.</param>
/// <param name="pParam">'Source' (Assign) or 'Dest' (AssignTo).</param>
/// <returns>True for a unit with that 'with' statement.</returns>
/// <remarks>Inside it a column named like the parameter hides the parameter.</remarks>
function HasOrmWithHeader(const pText, pIdent, pParam: string): Boolean;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.RegularExpressions;

const
  { %0 = class name, %1 = method, %2 = parameter, %3 = region id; a start marker may carry the hash of its body (1.55 UPDORM) }
  PAT_METHOD = '\bprocedure\s+%0:s\.%1:s\s*\(\s*%2:s\s*:\s*TPersistent\s*\)\s*;\s*begin\s+';
  PAT_OLD = 'if\s+not\s*\(\s*%2:s\s+is\s+%0:s\s*\)\s*then\s+inherited\s+else\s+with\s+%2:s\s+as\s+%0:s\s+do\s+begin' +
    '(?=\s*\{\$REGION\s+''(?:DB-RAD|DLFR) %3:s(?: hash=[0-9a-f]{16})?''\s*\})';
  PAT_NEW = 'if\s+%2:s\s+is\s+not\s+%0:s\s+then\s+inherited\s+else\s+begin(?=\s*\{\$REGION\s+''(?:DB-RAD|DLFR) %3:s(?: hash=[0-9a-f]{16})?''\s*\})';
  PAT_TAIL = '\{\$ENDREGION\s+''(?:DB-RAD|DLFR) %3:s''\s*\}';
  { '// else' is what the YADF formatter writes behind the generated 'end;' of a long block }
  PAT_TAIL_END = '\G\s*end\s*;([ \t]*//[ \t]*else[ \t]*(?=[\r\n]))?\s*end\s*;';
  PAT_READER = '\bfunction\s+%0:s\.Reader\s*\(\s*AStream\s*:\s*TABZMemoryStream\s*\)\s*:\s*boolean\s*;\s*';
  PAT_READER_VARS = '\Gvar\s+StreamSize\s*:\s*integer\s*;\s*ByteTemp\s*:\s*Byte\s*;\s*(?=begin\b)';
  PAT_NEXT_METHOD = '^[ \t]*(procedure|function|constructor|destructor)\s+%0:s\.';
  PAT_READER_LOCALS = '\b(StreamSize|ByteTemp)\b';
  CLASS_PREFIX = 'Tmc';
  { %0 = table identifier, %1 = class name }
  PAT_I_OLD = '\bprocedure\s+AssignI\s*\(\s*const\s+IValue\s*:\s*Imc%0:s\s*\)\s*;';
  PAT_I_NEW = '\bprocedure\s+Assign\s*\(\s*const\s+IValue\s*:\s*Imc%0:s\s*\)\s*;';
  PAT_U_DECL_OLD = '^[ \t]*procedure\s+AssignI\s*\(\s*const\s+Value\s*:\s*Imc%0:s\s*\)\s*;';
  PAT_U_DECL_NEW = '^[ \t]*public\s+procedure\s+Assign\s*\(\s*const\s+Value\s*:\s*Imc%0:s\s*\)\s*;\s*reintroduce\s*;\s*overload\s*;\s*published\b';
  PAT_U_IMPL_REGION = '\s*\(\s*const\s+Value\s*:\s*Imc%0:s\s*\)\s*;\s*begin\s*\{\$REGION\s+''(?:DB-RAD|DLFR) 5(?: hash=[0-9a-f]{16})?''\s*\}';
  PAT_U_IMPL_OLD = '(\bprocedure\s+%1:s\.)AssignI(' + PAT_U_IMPL_REGION + ')';
  PAT_U_IMPL_NEW = '\bprocedure\s+%1:s\.Assign' + PAT_U_IMPL_REGION;
  PAT_SRC_OLD = '(\bprocedure\s+Assign\s*\(\s*Source\s*:\s*TPersistent\s*\)\s*;\s*)(override\s*;)';
  PAT_SRC_NEW = '\bprocedure\s+Assign\s*\(\s*Source\s*:\s*TPersistent\s*\)\s*;\s*overload\s*;\s*override\s*;';
  PAT_ASSIGNI = '\bAssignI\b';
  PAT_LINE_COMMENT = '//[^\r\n]*';
  PAT_ASSIGNI_CALL = '\bAssignI\s*\(';
  PAT_DECL_LINE = '\b(procedure|function)\b';

type
  TAssignIState = (aiNone, aiOld, aiNew, aiOther);

function Rx(const pPattern: string): TRegEx;
begin
  Result:= TRegEx.Create(pPattern, [roIgnoreCase, roMultiLine]);
end;

function Splice(const pText: string; const pM: TMatch; const pNew: string): string;
begin
  Result:= Copy(pText, 1, pM.Index - 1) + pNew + Copy(pText, pM.Index + pM.Length, MaxInt);
end;

{ the text without its // and /// comments: autodoc blocks name AssignI in cref / seealso lines }
function CodeOf(const pText: string): string;
begin
  Result:= TRegEx.Replace(pText, PAT_LINE_COMMENT, '');
end;

function CountOf(const pText, pPattern: string): Integer;
begin
  Result:= Rx(pPattern).Matches(pText).Count;
end;

function IntfState(const pText, pIdent: string): TAssignIState;
var
  Total: Integer;
  Code: string;
begin
  Code:= CodeOf(pText);
  { calls in the unit itself are hand code: listed by the verb, not part of the generated shape }
  Total:= CountOf(Code, PAT_ASSIGNI) - Length(FindAssignICalls(Code));
  if (Total = 0) and (CountOf(Code, Format(PAT_I_NEW, [pIdent])) = 0) then
    Exit(aiNone);
  if (Total = 1) and (CountOf(Code, Format(PAT_I_OLD, [pIdent])) = 1) then
    Exit(aiOld);
  if (Total = 0) and (CountOf(Code, Format(PAT_I_NEW, [pIdent])) = 1) then
    Exit(aiNew);
  Result:= aiOther;
end;

function UnitState(const pText, pIdent, pClass: string): TAssignIState;
var
  Total, Sources: Integer;
  Code: string;
begin
  Code:= CodeOf(pText);
  { calls in the unit itself are hand code: listed by the verb, not part of the generated shape }
  Total:= CountOf(Code, PAT_ASSIGNI) - Length(FindAssignICalls(Code));
  Sources:= CountOf(Code, Format(PAT_SRC_NEW, [pIdent])) + CountOf(Code, Format(PAT_SRC_OLD, [pIdent]));
  if (Total = 0) and (CountOf(Code, Format(PAT_U_DECL_NEW, [pIdent])) = 0) then
    Exit(aiNone);
  if (Total = 2) and (Sources = 1) and (CountOf(Code, Format(PAT_U_DECL_OLD, [pIdent])) = 1) and
    (CountOf(Code, Format(PAT_U_IMPL_OLD, [pIdent, pClass])) = 1) then
    Exit(aiOld);
  if (Total = 0) and (CountOf(Code, Format(PAT_SRC_NEW, [pIdent])) = 1) and
    (CountOf(Code, Format(PAT_U_DECL_NEW, [pIdent])) = 1) and (CountOf(Code, Format(PAT_U_IMPL_NEW, [pIdent, pClass])) = 1) then
    Exit(aiNew);
  Result:= aiOther;
end;

{ the rest of the method after the header: the region, then 'end; end;' and nothing else }
function TailIsGenerated(const pText, pTailPattern: string; pFrom: Integer): Boolean;
var
  M: TMatch;
begin
  M:= Rx(pTailPattern).Match(pText, pFrom);
  Result:= M.Success and Rx(PAT_TAIL_END).Match(pText, M.Index + M.Length).Success;
end;

function UpgradeAssign(const pText, pClass, pMethod, pParam, pRegion: string; pNotes: TStrings): string;
var
  M: TMatch;
  Eol: string;

  function Pat(const pTemplate: string): string;
  begin
    Result:= Format(pTemplate, [pClass, pMethod, pParam, pRegion]);
  end;

begin
  Result:= pText;
  if Rx(Pat(PAT_METHOD + PAT_NEW)).IsMatch(pText) then
    Exit;
  M:= Rx('(' + Pat(PAT_METHOD) + ')' + Pat(PAT_OLD)).Match(pText);
  if not (M.Success and TailIsGenerated(pText, Pat(PAT_TAIL), M.Index + M.Length)) then
  begin
    pNotes.Add(pMethod + ' is not in the generated form (hand-edited?): left unchanged');
    Exit;
  end;
  Eol:= if pText.Contains(#13#10) then #13#10 else #10;
  Result:= Copy(pText, 1, M.Index - 1) + M.Groups[1].Value +
    'if ' + pParam + ' is not ' + pClass + ' then' + Eol + '    inherited' + Eol + '  else' + Eol + '  begin' +
    Copy(pText, M.Index + M.Length, MaxInt);
end;

function UpgradeReader(const pText, pClass: string; pNotes: TStrings): string;
var
  H, V, N: TMatch;
  First, Last: Integer;
  Body: string;
begin
  Result:= pText;
  H:= Rx(Format(PAT_READER, [pClass])).Match(pText);
  if not H.Success then
    Exit;
  First:= H.Index + H.Length;
  N:= Rx(Format(PAT_NEXT_METHOD, [pClass])).Match(pText, First);
  Last:= if N.Success then N.Index else Length(pText) + 1;
  Body:= Copy(pText, First, Last - First);
  if not TRegEx.IsMatch(Body, PAT_READER_LOCALS, [roIgnoreCase]) then
    Exit;
  V:= Rx(PAT_READER_VARS).Match(pText, First);
  if V.Success and not TRegEx.IsMatch(Copy(Body, V.Length + 1, MaxInt), PAT_READER_LOCALS, [roIgnoreCase]) then
    Result:= Copy(pText, 1, First - 1) + Copy(pText, First + V.Length, MaxInt)
  else
    pNotes.Add('Reader uses StreamSize / ByteTemp, or its var block is hand-edited: left unchanged (run repo update-orm first)');
end;

function UpgradeOrmHeaderText(const pText, pIdent: string; pNotes: TStrings): string;
var
  Cls: string;
begin
  Cls:= CLASS_PREFIX + pIdent;
  Result:= UpgradeAssign(pText, Cls, 'Assign', 'Source', '4', pNotes);
  Result:= UpgradeAssign(Result, Cls, 'AssignTo', 'Dest', '6', pNotes);
  Result:= UpgradeReader(Result, Cls, pNotes);
end;

procedure UpgradeOrmAssignPair(const pIntfText, pUnitText, pIdent: string; pHasIntf: Boolean; pNotes: TStrings;
  out pNewIntf, pNewUnit: string);
var
  Cls, Work, Eol: string;
  M: TMatch;
  IntfS, UnitS: TAssignIState;
begin
  pNewIntf:= pIntfText;
  pNewUnit:= pUnitText;
  Cls:= CLASS_PREFIX + pIdent;
  UnitS:= UnitState(pUnitText, pIdent, Cls);
  IntfS:= if pHasIntf then IntfState(pIntfText, pIdent) else aiNone;
  if (UnitS = aiNone) and (IntfS = aiNone) then
    Exit;
  if (UnitS = aiNew) and (IntfS = aiNew) then
    Exit;
  if (UnitS not in [aiOld, aiNew]) or (IntfS not in [aiOld, aiNew]) then
  begin
    pNotes.Add('AssignI is not in the generated form on both sides (i and u unit; hand-edited, missing or half converted?): ' +
      'i and u left unchanged');
    Exit;
  end;
  if IntfS = aiOld then
  begin
    M:= Rx(Format(PAT_I_OLD, [pIdent])).Match(pIntfText);
    pNewIntf:= Splice(pIntfText, M, M.Value.Replace('AssignI', 'Assign', [rfIgnoreCase]));
  end;
  if UnitS = aiOld then
  begin
    M:= Rx(Format(PAT_U_DECL_OLD, [pIdent])).Match(pUnitText);
    Eol:= if pUnitText.Contains(#13#10) then #13#10 else #10;
    { only one of a set of overloaded methods can be published (E2266): Assign(Imc) goes into a public section }
    Work:= Splice(pUnitText, M, '  public' + Eol + '     procedure Assign(const Value: Imc' + pIdent + '); reintroduce; overload;' + Eol + '  published');
    M:= Rx(Format(PAT_U_IMPL_OLD, [pIdent, Cls])).Match(Work);
    Work:= Splice(Work, M, M.Groups[1].Value + 'Assign' + M.Groups[2].Value);
    M:= Rx(Format(PAT_SRC_OLD, [pIdent])).Match(Work);
    pNewUnit:= if M.Success then Splice(Work, M, M.Groups[1].Value + 'overload; ' + M.Groups[2].Value) else Work;
  end;
  { the states ignore // comments, the edits do not: a commented-out copy above the real declaration takes the edit }
  if (IntfState(pNewIntf, pIdent) <> aiNew) or (UnitState(pNewUnit, pIdent, Cls) <> aiNew) then
  begin
    pNewIntf:= pIntfText;
    pNewUnit:= pUnitText;
    pNotes.Add('AssignI: a commented-out copy of a generated declaration is in the way: i and u left unchanged');
  end;
end;

function FindAssignICalls(const pText: string): TArray<Integer>;
var
  Lines: TArray<string>;
  Hits: TList<Integer>;
  I: Integer;
  Line: string;
begin
  Hits:= TList<Integer>.Create;
  try
    Lines:= pText.Replace(#13#10, #10).Split([#10]);
    for I:= 0 to High(Lines) do
    begin
      Line:= Lines[I].Trim;
      if Rx(PAT_ASSIGNI_CALL).IsMatch(Line) and not Line.StartsWith('//') and not Rx(PAT_DECL_LINE).IsMatch(Line) then
        Hits.Add(I + 1);
    end;
    Result:= Hits.ToArray;
  finally
    Hits.Free;
  end;
end;

function HasOrmWithHeader(const pText, pIdent, pParam: string): Boolean;
begin
  Result:= Rx(Format('\bwith\s+%s\s+as\s+%s%s\s+do\b', [pParam, CLASS_PREFIX, pIdent])).IsMatch(pText);
end;

end.
