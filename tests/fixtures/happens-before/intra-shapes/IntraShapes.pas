unit IntraShapes;

{ check-init lane HBINTRA fixture: one routine per CFG shape, as twins (the mark dominates the
  query / it does not). Markers for the driver (tests\fixtures\happens-before\intra-driver):
  a MARK comment right before a token makes that token a MARK site, a QUERY comment makes it a
  QUERY site (line + 1-based column of the token that follows the comment). The expected truth
  table lives in tests\autotest\run_check_init_intra.ps1. }

interface

procedure Use(pValue: Integer);

implementation

uses
  System.SysUtils;

type
  THbRec = record
    GX: Integer;
  end;

var
  GX    : Integer;
  GCond : Boolean;
  GCount: Integer;
  GRec  : THbRec;
  GProc : TProc;

procedure Use(pValue: Integer);
begin
  GCount:= GCount + pValue;
end;

function Init(var pValue: Integer): Integer;
begin
  pValue:= 1;
  Result:= pValue;
end;

procedure StraightDom;
begin
  {M}GX:= 1;
  Use({Q}GX);
end;

procedure StraightNoDom;
begin
  Use({Q}GX);
  {M}GX:= 1;
end;

procedure IfElseDom;
begin
  if GCond then
    {M}GX:= 1
  else
    {M}GX:= 2;
  Use({Q}GX);
end;

procedure IfNoElseNoDom;
begin
  if GCond then
    {M}GX:= 1;
  Use({Q}GX);
end;

procedure CaseElseDom;
begin
  case GCount of
    0: {M}GX:= 1;
    1: {M}GX:= 2;
  else
    {M}GX:= 3;
  end;
  Use({Q}GX);
end;

procedure CaseNoElseNoDom;
begin
  case GCount of
    0: {M}GX:= 1;
    1: {M}GX:= 2;
  end;
  Use({Q}GX);
end;

procedure WhileDom;
begin
  while GCond do
  begin
    {M}GX:= 1;
    Use({Q}GX);
  end;
end;

procedure WhileNoDom;
begin
  while GCond do
    {M}GX:= 1;
  Use({Q}GX);
end;

procedure RepeatDom;
begin
  repeat
    {M}GX:= 1;
  until GCond;
  Use({Q}GX);
end;

procedure RepeatNoDom;
begin
  repeat
    if GCond then
      {M}GX:= 1;
  until GCond;
  Use({Q}GX);
end;

procedure ForLiteralDom;
var
  I: Integer;
begin
  for I:= 1 to 3 do
    {M}GX:= I;
  Use({Q}GX);
end;

procedure ForNoDom;
var
  I: Integer;
begin
  for I:= 1 to GCount do
    {M}GX:= I;
  Use({Q}GX);
end;

procedure TryFinallyAfterDom;
begin
  try
    {M}GX:= 1;
  finally
    Use(0);
  end;
  Use({Q}GX);
end;

procedure TryFinallyInFinallyNoDom;
begin
  try
    {M}GX:= 1;
  finally
    Use({Q}GX);
  end;
end;

procedure TryFinallyInFinallyDom;
begin
  {M}GX:= 1;
  try
    Use(0);
  finally
    Use({Q}GX);
  end;
end;

procedure TryExceptAfterNoDom;
begin
  try
    {M}GX:= 1;
  except
    Use(0);
  end;
  Use({Q}GX);
end;

procedure TryExceptAfterDom;
begin
  try
    {M}GX:= 1;
  except
    raise;
  end;
  Use({Q}GX);
end;

procedure TryExceptInHandlerNoDom;
begin
  try
    {M}GX:= 1;
  except
    Use({Q}GX);
  end;
end;

procedure TryExceptInHandlerDom;
begin
  {M}GX:= 1;
  try
    Use(0);
  except
    Use({Q}GX);
  end;
end;

procedure ExitBeforeMark;
begin
  if GCond then
    Exit;
  {M}GX:= 1;
  Use({Q}GX);
end;

procedure RaiseBeforeMark;
begin
  if GCond then
    raise Exception.Create('no');
  {M}GX:= 1;
  Use({Q}GX);
end;

procedure AnonMarkInside;
begin
  GProc:= procedure
    begin
      {M}GX:= 1;
    end;
  Use({Q}GX);
end;

procedure AnonMarkOutside;
begin
  {M}GX:= 1;
  GProc:= procedure
    begin
      Use({Q}GX);
    end;
  Use({Q}GX);
end;

procedure GotoRoutine;
label
  L1;
begin
  {M}GX:= 1;
  goto L1;
L1:
  Use({Q}GX);
end;

procedure ShortCircuitNoDom;
begin
  if GCond and (Init({M}GX) > 0) then
    Use(0);
  Use({Q}GX);
end;

procedure ShortCircuitDom;
begin
  if (Init({M}GX) > 0) and GCond then
    Use(0);
  Use({Q}GX);
end;

procedure TernaryNoDom;
begin
  GCount:= if GCond then Init({M}GX) else 0;
  Use({Q}GX);
end;

procedure TernaryCondDom;
begin
  GCount:= if Init({M}GX) > 0 then 1 else 0;
  Use({Q}GX);
end;

procedure WithOpaqueNoDom;
begin
  with GRec do
    {M}GX:= 1;
  Use({Q}GX);
end;

procedure SameItemNoDom;
begin
  {M}GX:= {Q}GX + 1;
end;

end.
