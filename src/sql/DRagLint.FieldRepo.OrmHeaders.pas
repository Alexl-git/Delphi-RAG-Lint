unit DRagLint.FieldRepo.OrmHeaders;

{ drag-lint 1.54 lane TT-GENFIX: one-time upgrade of the code TableTools wrote AROUND the DB-RAD
  regions of an ORM unit (repo update-orm only rewrites the lines inside them):
  * Assign / AssignTo: 'if not (Source is T) then inherited else with Source as T do begin'
    becomes 'if Source is not T then inherited else begin';
  * Reader: the 'var StreamSize: integer; ByteTemp: Byte;' block goes when nothing uses it
    (region 11 declares its own locals since 1.54).
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
  System.RegularExpressions;

const
  { %0 = class name, %1 = method, %2 = parameter, %3 = region id }
  PAT_METHOD = '\bprocedure\s+%0:s\.%1:s\s*\(\s*%2:s\s*:\s*TPersistent\s*\)\s*;\s*begin\s+';
  PAT_OLD = 'if\s+not\s*\(\s*%2:s\s+is\s+%0:s\s*\)\s*then\s+inherited\s+else\s+with\s+%2:s\s+as\s+%0:s\s+do\s+begin' +
    '(?=\s*\{\$REGION\s+''DB-RAD %3:s''\s*\})';
  PAT_NEW = 'if\s+%2:s\s+is\s+not\s+%0:s\s+then\s+inherited\s+else\s+begin(?=\s*\{\$REGION\s+''DB-RAD %3:s''\s*\})';
  PAT_TAIL = '\{\$ENDREGION\s+''DB-RAD %3:s''\s*\}';
  PAT_TAIL_END = '\G\s*end\s*;\s*end\s*;';
  PAT_READER = '\bfunction\s+%0:s\.Reader\s*\(\s*AStream\s*:\s*TABZMemoryStream\s*\)\s*:\s*boolean\s*;\s*';
  PAT_READER_VARS = '\Gvar\s+StreamSize\s*:\s*integer\s*;\s*ByteTemp\s*:\s*Byte\s*;\s*(?=begin\b)';
  PAT_NEXT_METHOD = '^[ \t]*(procedure|function|constructor|destructor)\s+%0:s\.';
  PAT_READER_LOCALS = '\b(StreamSize|ByteTemp)\b';
  CLASS_PREFIX = 'Tmc';

function Rx(const pPattern: string): TRegEx;
begin
  Result:= TRegEx.Create(pPattern, [roIgnoreCase, roMultiLine]);
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

function HasOrmWithHeader(const pText, pIdent, pParam: string): Boolean;
begin
  Result:= Rx(Format('\bwith\s+%s\s+as\s+%s%s\s+do\b', [pParam, CLASS_PREFIX, pIdent])).IsMatch(pText);
end;

end.
