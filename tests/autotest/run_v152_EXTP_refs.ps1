<#
  run_v152_EXTP_refs.ps1 -- 1.52 lane EXTP: the refs and symbols the parser owes (rename refusals, ORM3 batch 3 item 2).

  Fixtures: tests\autotest\fixtures\v152-EXTP\ (uPDefs.pas, uPProbe.pas). Lines are located by text, never by
  number. Rows come from `sql --json` (positional) and are mapped onto columns[].name.

  NEW in 1.52 (RED on the 1.51.1 extractor), each with a positive-control twin:
    W1  `edtF1.DataBinding.DataField := pName`: the root edtF1 and the intermediate DataBinding each carry a
        'write-through' ref (one per token); the final member keeps its member-access row, the root its read.
        Twin: the read row of edtF1 on that line still exists (the query can see the line).
    W2  `Self.edtF2.DataBinding.DataField := pName`: write-through on edtF2 and DataBinding, none on Self.
    W1b the root's write-through is bound to the field, and
    W5  `usages --name edtF1` counts it under writes, not calls: both need an INT HANDOVER hunk (resolver,
        Query.Callers) and print PENDING-HANDOVER in the one state that hunk changes; any other state fails.
    W3  NEGATIVE:`Result := edtF1.DataBinding.DataField` (a read chain) carries no write-through.
        Twin: W1 on the same receiver chain.
    A1  anonymous-method parameters are symbols (kind param, parented to the enclosing routine,
        QName <Routine>.<Param>), and the reads inside the lambda bind to them.
        Twin: a named routine's parameter (pIdx) and its read.
    A2  NEGATIVE: unused-parameter does not report an unused anonymous-method parameter (its signature is
        fixed by the reference type). Twin: it reports the unused named parameter pUnused.
    E1  `on E: EConvertError do` carries a 'write' ref at the E token bound to the handler variable.
        Twin: the E of `E.Message` is a read bound to the same symbol.
    E2  NEGATIVE: write-only-local does not report a handler variable the handler never reads (EUnused).
        Twin: it reports lDead, a local assigned and never read.

    C1  `class constructor TPHolder.Create` / `class destructor TPHolder.Destroy` bodies are matched to the
        class routines (is_class_method = 1), the instance constructor / destructor bodies to theirs; before,
        the shared name sent each body to the other routine. Twin: an ordinary method body (C1+).
    C2  the locals of each body are parented to its own routine.

  HELD (pins; GREEN on base too):
    I1  `FArr[pIdx].Count` is bound to TPItem.Count with receiver_type_text TPItem (E-RENAME-ELEMENT-TYPE). The
        subscript has no ref of its own, so ref_receivers holds no row for it -- by design, see REPORT.
    W4  a bare `edtF2 := nil` is a 'write'.
    P1  no parse error.

  Usage: pwsh -File tests\autotest\run_v152_EXTP_refs.ps1 [-Exe path\to\drag-lint.exe]
#>
[CmdletBinding()]
param([string]$Exe = 'src\cli\Win64\Debug\drag-lint.exe')
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $Repo
$exePath = (Resolve-Path $Exe).Path
$fxDir = Join-Path $Repo 'tests\autotest\fixtures\v152-EXTP'
$script:Failed = $false
$script:Passed = 0
$script:FailedCount = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name"; $script:Passed++ }
  else { Write-Host "FAIL  $Name $Detail" -ForegroundColor Red; $script:Failed = $true; $script:FailedCount++ }
}
function Get-Line([string]$File, [string]$Text) {
  $hit = Select-String -Path (Join-Path $fxDir $File) -SimpleMatch -Pattern $Text | Select-Object -First 1
  if (-not $hit) { throw "fixture $File lost the line '$Text'" }
  return $hit.LineNumber
}
function Get-Col([string]$File, [string]$Text, [string]$Token) {
  $hit = Select-String -Path (Join-Path $fxDir $File) -SimpleMatch -Pattern $Text | Select-Object -First 1
  if (-not $hit) { throw "fixture $File lost the line '$Text'" }
  $m = [regex]::Match($hit.Line, '\b' + [regex]::Escape($Token) + '\b')
  if (-not $m.Success) { throw "line '$Text' has no token $Token" }
  return $m.Index + 1
}
function Invoke-Sql([string]$Db, [string]$Query) {
  $txt = (& { $ErrorActionPreference = 'Continue'; & $exePath sql --db $Db --query $Query --json --limit 0 2>$null }) -join "`n"
  $doc = $txt | ConvertFrom-Json | ForEach-Object { $_ }
  $cols = @($doc.columns | ForEach-Object { $_.name })
  $out = foreach ($r in @($doc.rows)) {
    $o = [ordered]@{}
    for ($k = 0; $k -lt $cols.Count; $k++) { $o[$cols[$k]] = $r[$k] }
    [pscustomobject]$o
  }
  return , @($out)
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('v152extp-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($tmp) | Out-Null
$dir = Join-Path $tmp 'fx'
[IO.Directory]::CreateDirectory($dir) | Out-Null
foreach ($f in Get-ChildItem $fxDir -File -Filter *.pas) { [IO.File]::Copy($f.FullName, (Join-Path $dir $f.Name)) }
$db = Join-Path $tmp 'fx.sqlite'
$log = (& { $ErrorActionPreference = 'Continue'; & $exePath index $dir --db $db --library-db none 2>&1 | ForEach-Object { "$_" } }) -join "`n"

$all = Invoke-Sql $db @"
select f.path path, r.id id, r.start_line line, r.start_col col, r.kind kind, r.name_text name,
       s.qualified_name target, r.receiver_text rcv, r.receiver_type_text rcvtype,
       (select mode from member_accesses m where m.ref_id = r.id) mode
from refs r join files f on f.id = r.file_id left join symbols s on s.id = r.symbol_id
"@
$syms = Invoke-Sql $db @"
select s.id id, s.kind kind, s.name name, s.qualified_name qname, p.qualified_name parent, s.start_line line, s.start_col col
from symbols s left join symbols p on p.id = s.parent_id
"@
$probe = 'uPProbe.pas'
function Refs([string]$LineText, [string]$Name, [string]$Kind = '') {
  $ln = Get-Line $probe $LineText
  return , @($all | Where-Object { $_.path -like "*\$probe" -and $_.line -eq $ln -and $_.name -eq $Name -and ($Kind -eq '' -or $_.kind -eq $Kind) })
}
function Show($Rows) { return (@($Rows | ForEach-Object { "$($_.kind)@$($_.line):$($_.col)->$($_.target)" }) -join ' | ') }
function Lint([string]$Rule) {
  $txt = (& { $ErrorActionPreference = 'Continue'; & $exePath lint-all --db $db --enable $Rule --rule $Rule --json 2>$null }) -join "`n"
  $start = $txt.IndexOf('[')
  if ($start -lt 0) { return , @() }
  return , @(($txt.Substring($start) | ConvertFrom-Json | ForEach-Object { $_ }) | Where-Object { $_.rule -eq $Rule })
}

# ---- W: writes through a member chain ----
$wLine = 'edtF1.DataBinding.DataField := pName;'
$w1Root = Refs $wLine 'edtF1' 'write-through'
$w1Mid = Refs $wLine 'DataBinding' 'write-through'
$w1Leaf = Refs $wLine 'DataField' 'write-through'
$w1Read = Refs $wLine 'edtF1' 'read'
$w1Member = Refs $wLine 'DataField' 'member-access'
Check 'W1 root and intermediate of a written member chain carry one write-through each' (($w1Root.Count -eq 1) -and ($w1Mid.Count -eq 1) -and ($w1Leaf.Count -eq 0)) ((Show $w1Root) + ' / ' + (Show $w1Mid) + ' / ' + (Show $w1Leaf))
Check 'W1+ control: the read of the root and the member-access of the leaf are kept' (($w1Read.Count -eq 1) -and ($w1Member.Count -eq 1) -and ($w1Member[0].mode -eq 'write')) ((Show $w1Read) + ' / ' + (Show $w1Member) + " mode=$($w1Member[0].mode)")
function Pending([string]$Name, [string]$Detail) { Write-Host "PENDING-HANDOVER  $Name $Detail" -ForegroundColor Yellow; $script:Pending++ }
$script:Pending = 0
# W1b / W5 need the INT HANDOVER hunks (resolver binding, usages bucket; EXTP REPORT.md H2/H3). Until they land
# the unbound / 'calls' state prints PENDING-HANDOVER; any OTHER state fails. INT makes both hard checks.
if (($w1Root.Count -eq 1) -and ($w1Root[0].target -eq 'uPProbe.TPProbe.edtF1')) { Check 'W1b write-through of the root is bound to the field' $true }
elseif (($w1Root.Count -eq 1) -and ([string]::IsNullOrEmpty($w1Root[0].target))) { Check 'W1b write-through of the root is bound to the field' $false (Show $w1Root) }
else { Check 'W1b write-through of the root is bound to the field' $false (Show $w1Root) }
$uText = (& { $ErrorActionPreference = 'Continue'; & $exePath usages --name edtF1 --db $db 2>$null }) -join "`n"
$uW = [regex]::Match($uText, 'writes: (\d+)'); $uC = [regex]::Match($uText, 'calls: (\d+)')
Write-Host "      raw usages: $(($uText -split "`n" | Where-Object { $_ -match 'reads:' }) -join '')"
if ($uW.Success -and ([int]$uW.Groups[1].Value -ge 1) -and ([int]$uC.Groups[1].Value -eq 0)) { Check 'W5 usages --name edtF1 reports the write through the chain' $true }
elseif ($uW.Success -and ([int]$uW.Groups[1].Value -eq 0) -and ([int]$uC.Groups[1].Value -ge 1)) { Check 'W5 usages --name edtF1 reports the write through the chain' $false 'write-through still in the calls bucket' }
else { Check 'W5 usages --name edtF1 reports the write through the chain' $false $uText }

$w2Line = 'Self.edtF2.DataBinding.DataField := pName;'
$w2Root = Refs $w2Line 'edtF2' 'write-through'
$w2Mid = Refs $w2Line 'DataBinding' 'write-through'
$w2Self = Refs $w2Line 'Self' 'write-through'
Check 'W2 a Self-rooted chain marks its members, not Self' (($w2Root.Count -eq 1) -and ($w2Mid.Count -eq 1) -and ($w2Self.Count -eq 0)) ((Show $w2Root) + ' / ' + (Show $w2Mid) + ' / ' + (Show $w2Self))

$w3 = @((Refs 'Result := edtF1.DataBinding.DataField;' 'edtF1') + (Refs 'Result := edtF1.DataBinding.DataField;' 'DataBinding') | Where-Object { $_.kind -eq 'write-through' })
$w3Read = Refs 'Result := edtF1.DataBinding.DataField;' 'edtF1' 'read'
Check 'W3 a read chain carries no write-through (twin: W1)' (($w3.Count -eq 0) -and ($w3Read.Count -eq 1) -and ($w1Root.Count -eq 1)) ((Show $w3) + ' / read ' + (Show $w3Read))

$w4 = Refs 'edtF2 := nil;' 'edtF2' 'write'
Check 'W4 held: a bare assignment is a write' (($w4.Count -eq 1) -and ($w4[0].target -eq 'uPProbe.TPProbe.edtF2')) (Show $w4)

# ---- A: anonymous-method parameters ----
$pA = @($syms | Where-Object { $_.qname -eq 'uPProbe.TPProbe.AnonUse.pA' })
$pB = @($syms | Where-Object { $_.qname -eq 'uPProbe.TPProbe.AnonUse.pB' })
$pS = @($syms | Where-Object { $_.qname -eq 'uPProbe.TPProbe.AnonUnused.pSender' })
$rA = Refs 'Result := pA + Length(pB);' 'pA' 'read'
$rB = Refs 'Result := pA + Length(pB);' 'pB' 'read'
$okA = ($pA.Count -eq 1) -and ($pA[0].kind -eq 'param') -and ($pA[0].parent -eq 'uPProbe.TPProbe.AnonUse') -and ($pB.Count -eq 1) -and ($pS.Count -eq 1) -and
       ($rA.Count -eq 1) -and ($rA[0].target -eq 'uPProbe.TPProbe.AnonUse.pA') -and ($rB.Count -eq 1) -and ($rB[0].target -eq 'uPProbe.TPProbe.AnonUse.pB')
Check 'A1 anonymous-method parameters are param symbols and their reads bind' $okA ("syms pA=$($pA.Count) pB=$($pB.Count) pSender=$($pS.Count) / " + (Show $rA) + ' / ' + (Show $rB))
$pIdx = @($syms | Where-Object { $_.qname -eq 'uPProbe.TPProbe.ReadIndexed.pIdx' -and $_.kind -eq 'param' })
$rIdx = Refs 'Result := FArr[pIdx].Count;' 'pIdx' 'read'
Check 'A1+ control: a named parameter and its read' (($pIdx.Count -eq 1) -and ($rIdx.Count -eq 1) -and ($rIdx[0].target -eq 'uPProbe.TPProbe.ReadIndexed.pIdx')) (Show $rIdx)

$up = Lint 'unused-parameter'
$upNames = @($up | ForEach-Object { $_.message })
Check 'A2 unused-parameter ignores an unused anonymous-method parameter' (@($upNames | Where-Object { $_ -match 'pSender' }).Count -eq 0) ($upNames -join ' | ')
Check 'A2+ control: unused-parameter reports the unused named parameter' (@($upNames | Where-Object { $_ -match 'pUnused' }).Count -eq 1) ($upNames -join ' | ')

# ---- E: the variable of an exception handler ----
$eCol = Get-Col $probe 'on E: EConvertError do' 'E'
$e1 = @(Refs 'on E: EConvertError do' 'E' | Where-Object { $_.col -eq $eCol })
Check 'E1 the handler variable token is a write bound to the handler variable' (($e1.Count -eq 1) -and ($e1[0].kind -eq 'write') -and ($e1[0].target -eq 'uPProbe.TPProbe.TryIt.E')) (Show $e1)
$e1r = Refs 'raise Exception.Create(E.Message);' 'E' 'read'
Check 'E1+ control: E of E.Message is a read bound to the same symbol' (($e1r.Count -eq 1) -and ($e1r[0].target -eq 'uPProbe.TPProbe.TryIt.E')) (Show $e1r)

$wo = Lint 'write-only-local'
$woMsgs = @($wo | ForEach-Object { $_.message })
Check 'E2 write-only-local ignores an unread handler variable' (@($woMsgs | Where-Object { $_ -match '"(e|eunused)"' }).Count -eq 0) ($woMsgs -join ' | ')
Check 'E2+ control: write-only-local reports a local assigned and never read' (@($woMsgs | Where-Object { $_ -match 'ldead' }).Count -eq 1) ($woMsgs -join ' | ')

# ---- C: class constructor / class destructor bodies ----
$hs = Invoke-Sql $db @"
select s.id id, s.kind kind, s.is_class_method cm, s.impl_start_line impl, s.name name, s.parent_id parent
from symbols s where s.qualified_name in ('uPDefs.TPHolder.Create', 'uPDefs.TPHolder.Destroy', 'uPDefs.TPHolder.Create.lClassSeed', 'uPDefs.TPHolder.Create.lInstSeed', 'uPProbe.TPProbe.WriteChain')
"@
function HolderSym([string]$Kind, [int]$Cm) { return , @($hs | Where-Object { $_.kind -eq $Kind -and $_.cm -eq $Cm }) }
$cc = HolderSym 'constructor' 1; $ic = HolderSym 'constructor' 0; $cd = HolderSym 'destructor' 1; $id = HolderSym 'destructor' 0
$lnCC = Get-Line 'uPDefs.pas' 'class constructor TPHolder.Create;'; $lnIC = Get-Line 'uPDefs.pas' 'constructor TPHolder.Create(pA: Integer);'
$lnCD = Get-Line 'uPDefs.pas' 'class destructor TPHolder.Destroy;'; $lnID = Get-Line 'uPDefs.pas' 'destructor TPHolder.Destroy;'
if ($lnID -eq $lnCD) { $lnID = (Select-String -Path (Join-Path $fxDir 'uPDefs.pas') -Pattern '^destructor TPHolder\.Destroy;' | Select-Object -First 1).LineNumber }
$showH = (@($hs | ForEach-Object { "$($_.name)/$($_.kind)/cm=$($_.cm)/impl=$($_.impl)/id=$($_.id)/parent=$($_.parent)" }) -join ' | ')
$okC = ($cc.Count -eq 1) -and ($ic.Count -eq 1) -and ($cd.Count -eq 1) -and ($id.Count -eq 1) -and
       ($cc[0].impl -eq $lnCC) -and ($ic[0].impl -eq $lnIC) -and ($cd[0].impl -eq $lnCD) -and ($id[0].impl -eq $lnID)
Check 'C1 a class constructor / destructor body goes to the class routine, not the instance one' $okC ($showH + " want cc=$lnCC ic=$lnIC cd=$lnCD id=$lnID")
$lcs = @($hs | Where-Object { $_.name -eq 'lClassSeed' }); $lis = @($hs | Where-Object { $_.name -eq 'lInstSeed' })
Check 'C2 locals of each body are parented to their own routine' (($lcs.Count -eq 1) -and ($lis.Count -eq 1) -and ($cc.Count -eq 1) -and ($ic.Count -eq 1) -and ($lcs[0].parent -eq $cc[0].id) -and ($lis[0].parent -eq $ic[0].id)) $showH
$wc = @($hs | Where-Object { $_.name -eq 'WriteChain' })
Check 'C1+ control: an ordinary method body is matched' (($wc.Count -eq 1) -and ($wc[0].impl -eq (Get-Line $probe 'procedure TPProbe.WriteChain(const pName: string);'))) $showH

# ---- held ----
$i1 = Refs 'Result := FArr[pIdx].Count;' 'Count'
Check 'I1 held: a member of a subscripted receiver binds through the element type' (($i1.Count -eq 1) -and ($i1[0].target -eq 'uPDefs.TPItem.Count') -and ($i1[0].rcvtype -eq 'TPItem')) ((Show $i1) + " rcvtype=$($i1[0].rcvtype)")
$diag = @($log -split "`n" | Where-Object { $_ -match 'parse error|parse-errors=[1-9]' })
Check 'P1 no parse error in any fixture' ($diag.Count -eq 0) ($diag -join ' | ')

Write-Host "run_v152_EXTP_refs: $($script:Passed) passed, $($script:FailedCount) failed, $($script:Pending) pending-handover"
if ($script:Failed) { exit 1 } else { exit 0 }
