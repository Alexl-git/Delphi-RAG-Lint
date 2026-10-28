# Hand-populated data_flows rows for the taint fixture (lane T2, 2026-10-27).
#
# The rows T1's extractor is specified to emit for tests\lint-project\taint\*.pas
# (plan docs\superpowers\plans\2026-10-27-taint-interprocedural-plan.md section 2),
# keyed by REAL ids and REAL ref positions of an index of this folder. Used by
# tests\autotest\run_taint_rules.ps1 -Mode fixture until T1 is merged; a real T1
# index of the same folder must give a SUPERSET of these rows (-Mode real).
#
# usage: python -I fixture_rows.py <db.sqlite> <fixture dir> [taint|minirtl|uselib]
# (the last two are tests\lint-project\taint-lib\lib and \proj, for run_taint_library.ps1)
# Positions: every site is named by an ANCHOR (a substring unique to one line of
# the unit) plus the ref's name_text on that line; the column is the ref's own
# start_col, so the rows join refs exactly as the contract requires.
import os
import sqlite3
import sys

# unit | routine qname | dst_kind | dst anchor | dst_name | dst_index | dst_receiver |
# src_kind | src_index | src anchor | src_name | via_local | cond
ROWS = r"""
uInput|uInput.ReadArg|result|Result := Trim|Result|-1||ref|-1|Result := Trim|Trim|0|0
uInput|uInput.ReadArg|arg|Result := Trim|Trim|0||ref|-1|Result := Trim|ParamStr|0|0
uInput|uInput.TfrmInput.btnRunClick|arg|RunQuery(S)|RunQuery|0||ref|-1|S := Edit1.Text|Text|1|0
uDal|uDal.DoExec|arg|GConn.ExecSQL(ASql)|ExecSQL|0|GConn|param|0||ASql|0|0
uDal|uDal.RunQuery|arg|DoExec('select|DoExec|0||param|0||AName|0|0
uDal|uDal.RunArg|arg|D.Exec(|Exec|0|D|ref|-1|D.Exec(|ReadArg|0|0
uDal2|uDal2.TDal2.Exec|write|Q.SQL.Text := ASql|Text|-1|Q.SQL|param|0||ASql|0|0
uSafe|uSafe.Helper|arg|GConn.ExecSQL(A)|ExecSQL|0|GConn|param|0||A|0|0
uSafe|uSafe.SafeQuoted|arg|QuotedStr(ParamStr|ExecSQL|0|GConn|ref|-1|QuotedStr(ParamStr|QuotedStr|0|0
uSafe|uSafe.SafeQuoted|arg|QuotedStr(ParamStr|QuotedStr|0||ref|-1|QuotedStr(ParamStr|ParamStr|0|0
uSafe|uSafe.SafeParam|write|ParamByName('N').AsString|AsString|-1|Q.ParamByName('N')|ref|-1|ParamByName('N').AsString|ParamStr|0|0
uSafe|uSafe.SafeInt|arg|StrToInt(ParamStr|ExecSQL|0|GConn|ref|-1|StrToInt(ParamStr|Format|0|0
uSafe|uSafe.SafeInt|arg|StrToInt(ParamStr|Format|1||ref|-1|StrToInt(ParamStr|StrToInt|0|0
uSafe|uSafe.SafeInt|arg|StrToInt(ParamStr|StrToInt|0||ref|-1|StrToInt(ParamStr|ParamStr|0|0
uSafe|uSafe.SafeNonSource|arg|Helper(GetConfigName)|Helper|0||ref|-1|Helper(GetConfigName)|GetConfigName|0|0
uCycle|uCycle.CycA|result|Result := S|Result|-1||param|0||S|0|1
uCycle|uCycle.CycA|result|Result := CycB|Result|-1||ref|-1|Result := CycB|CycB|0|1
uCycle|uCycle.CycA|arg|Result := CycB|CycB|0||param|0||S|0|0
uCycle|uCycle.CycB|result|Result := CycA|Result|-1||ref|-1|Result := CycA|CycA|0|0
uCycle|uCycle.CycB|arg|Result := CycA|CycA|0||param|0||S|0|0
uCycle|uCycle.RunCycle|arg|GConn.ExecSQL(CycA|ExecSQL|0|GConn|ref|-1|GConn.ExecSQL(CycA|CycA|0|0
uCycle|uCycle.RunCycle|arg|GConn.ExecSQL(CycA|CycA|0||ref|-1|GConn.ExecSQL(CycA|ParamStr|0|0
uWeak|uWeak.TfrmWeak.Go|arg|edtName.Text|ExecSQL|0|GConn|ref|-1|edtName.Text|Text|0|0
uField|uField.TCfg.Load|field|FSql := ParamStr(2)|FSql|-1||ref|-1|FSql := ParamStr(2)|ParamStr|0|0
uField|uField.TCfg.Run|arg|GConn.ExecSQL(FSql)|ExecSQL|0|GConn|field|-1||FSql|0|0
uField|uField.TCfg2.Run2|arg|'select ' + FSql|ExecSQL|0|GConn|field|-1||FSql|0|0
uFieldUp|uFieldUp.TBase.Exec|arg|GConn.ExecSQL(FCmd)|ExecSQL|0|GConn|field|-1||FCmd|0|0
uFieldUp|uFieldUp.TChild.Load|write|FCmd := ParamStr(4)|FCmd|-1||ref|-1|FCmd := ParamStr(4)|ParamStr|0|0
uGlobal|uGlobal.InitPath|global|GPath := GetEnv|GPath|-1||ref|-1|GPath := GetEnv|GetEnvironmentVariable|0|0
uGlobal|uGlobal.DelPath|arg|DeleteFile(GPath)|DeleteFile|0||global|-1||GPath|0|0
uGlobal|uGlobal.DelPath|arg|Create(ExtractFileName|Create|0|TFileStream|ref|-1|Create(ExtractFileName|ExtractFileName|0|0
uGlobal|uGlobal.DelPath|arg|Create(ExtractFileName|ExtractFileName|0||ref|-1|Create(ExtractFileName|GetEnvironmentVariable|0|0
uGlobal|uGlobal.DelPath|arg|TFileStream.Create(GetEnv|Create|0|TFileStream|ref|-1|TFileStream.Create(GetEnv|GetEnvironmentVariable|0|0
uGlobal|uGlobal.DelPath|arg|TFileStream.Create(ParamStr|Create|0|TFileStream|ref|-1|TFileStream.Create(ParamStr|ParamStr|0|0
uGlobal|uGlobal.DelPath|arg|Create(ExpandFileName|Create|0|TFileStream|ref|-1|Create(ExpandFileName|ExpandFileName|0|0
uGlobal|uGlobal.DelPath|arg|Create(ExpandFileName|ExpandFileName|0||ref|-1|Create(ExpandFileName|ParamStr|0|0
uOut|uOut.GetName|outparam|S := ParamStr(1)|S|0||ref|-1|S := ParamStr(1)|ParamStr|0|0
uOut|uOut.UseOut|arg|WinExec(|WinExec|0||argout|0|GetName(N)|GetName|1|0
uList|uList.UseList|arg|L.Add(ParamStr(1))|Add|0|L|ref|-1|L.Add(ParamStr(1))|ParamStr|0|0
uList|uList.UseList|arg|ExecSQL(L.Text)|ExecSQL|0|GConn|ref|-1|L.Add(ParamStr(1))|ParamStr|1|0
uList|uList.UseList|arg|Q.SQL.Add(ParamStr(2))|Add|0|Q.SQL|ref|-1|Q.SQL.Add(ParamStr(2))|ParamStr|0|0
uShellEx|uShellEx.Launch|arg|ShellExecuteEx(@Info)|ShellExecuteEx|0||ref|-1|PChar(ParamStr(1))|ParamStr|1|0
uLambda|uLambda.RunLambda|arg|GConn.ExecSQL(S)|ExecSQL|0|GConn|ref|-1|S := ParamStr(1)|ParamStr|1|0
uCmd|uCmd.RunCmd|arg|CreateProcess(nil|CreateProcess|1||param|0||ACmd|0|0
uCmd|uCmd.RunCmdFromArg|arg|RunCmd(ParamStr(1))|RunCmd|0||ref|-1|RunCmd(ParamStr(1))|ParamStr|0|0
uSelf|uSelf.SpawnSelf|arg|CreateProcess(nil|CreateProcess|1||param|0||ACmd|0|0
uSelf|uSelf.RunSelf|arg|SpawnSelf(ParamStr(0)|SpawnSelf|0||ref|-1|SpawnSelf(ParamStr(0)|ParamStr|0|0
uSelf|uSelf.RunArgOne|arg|SpawnSelf(ParamStr( 1|SpawnSelf|0||ref|-1|SpawnSelf(ParamStr( 1|ParamStr|0|0
uSelf|uSelf.CacheKnown|arg|('LocalAppData')|DeleteFile|0||ref|-1|('LocalAppData')|GetEnvironmentVariable|0|0
uSelf|uSelf.CacheCustom|arg|('MY_CACHE')|DeleteFile|0||ref|-1|('MY_CACHE')|GetEnvironmentVariable|0|0
"""

# tests\lint-project\taint-lib\lib -- the mini library (indexed into a temp LIBRARY db)
MINIRTL_ROWS = r"""
uMiniRtl|uMiniRtl.MyTrim|result|Result := S;|Result|-1||param|0||S|0|0
uMiniRtl|uMiniRtl.MyQuote|result|Result := ''''|Result|-1||param|0||S|0|0
uMiniRtl|uMiniRtl.GetLine|outparam|S := ParamStr(1)|S|0||ref|-1|S := ParamStr(1)|ParamStr|0|0
"""

# tests\lint-project\taint-lib\proj -- the project that calls it
USELIB_ROWS = r"""
uUseLib|uUseLib.ViaTrim|arg|MyTrim(ParamStr(1))|ExecSQL|0|GDb|ref|-1|MyTrim(ParamStr(1))|MyTrim|0|0
uUseLib|uUseLib.ViaTrim|arg|MyTrim(ParamStr(1))|MyTrim|0||ref|-1|MyTrim(ParamStr(1))|ParamStr|0|0
uUseLib|uUseLib.ViaQuote|arg|MyQuote(ParamStr(1))|ExecSQL|0|GDb|ref|-1|MyQuote(ParamStr(1))|MyQuote|0|0
uUseLib|uUseLib.ViaQuote|arg|MyQuote(ParamStr(1))|MyQuote|0||ref|-1|MyQuote(ParamStr(1))|ParamStr|0|0
uUseLib|uUseLib.ViaLine|arg|GDb.ExecSQL(S)|ExecSQL|0|GDb|argout|0|GetLine(S)|GetLine|1|0
"""

def anchor_line(lines, anchor, unit):
    hits = [i + 1 for i, t in enumerate(lines) if anchor in t]
    if len(hits) != 1:
        raise SystemExit('anchor %r in %s matches %d lines' % (anchor, unit, len(hits)))
    return hits[0]


def ref_col(c, file_id, line, name, fallback):
    row = c.execute('SELECT MIN(start_col) FROM refs WHERE file_id = ? AND start_line = ? '
                    'AND name_text = ? COLLATE NOCASE', (file_id, line, name)).fetchone()
    if row is None or row[0] is None:
        if fallback is None:
            raise SystemExit('no ref %r at %d' % (name, line))
        return fallback
    return row[0]


def main():
    db, fx = sys.argv[1], sys.argv[2]
    which = sys.argv[3] if len(sys.argv) > 3 else 'taint'
    rows = {'taint': ROWS, 'minirtl': MINIRTL_ROWS, 'uselib': USELIB_ROWS}[which]
    c = sqlite3.connect(db)
    n = 0
    for raw in rows.strip().splitlines():
        (unit, routine, dk, danchor, dname, didx, drcv,
         sk, sidx, sanchor, sname, via, cond) = raw.split('|')
        path = os.path.join(fx, unit + '.pas')
        with open(path, 'r', encoding='ascii') as fh:
            lines = fh.read().splitlines()
        frow = c.execute('SELECT id FROM files WHERE path = ? COLLATE NOCASE', (path,)).fetchone()
        if frow is None:
            raise SystemExit('file not indexed: ' + path)
        fid = frow[0]
        srow = c.execute('SELECT id, parent_id FROM symbols WHERE qualified_name = ? '
                         'AND impl_start_line > 0', (routine,)).fetchone()
        if srow is None:
            raise SystemExit('routine not indexed: ' + routine)
        sid, parent = srow[0], srow[1]
        owner = parent if '.' in routine[len(unit) + 1:] else 0
        dline = anchor_line(lines, danchor, unit)
        # an 'arg' site is a call ref; a write after a call (`Q.ParamByName('N').AsString`)
        # and result/field/global/outparam sites may have no ref of that name
        dcol = ref_col(c, fid, dline, dname, None if dk == 'arg' else 3)
        sline, scol = 0, 0
        if sk in ('ref', 'argout'):
            sline = anchor_line(lines, sanchor, unit)
            scol = ref_col(c, fid, sline, sname, None)
        if dk == 'result':
            dname = ''
        c.execute('INSERT INTO data_flows(file_id, symbol_id, owner_id, dst_kind, dst_line, dst_col, '
                  'dst_index, dst_name, dst_receiver, src_kind, src_index, src_line, src_col, src_name, '
                  'via_local, cond) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
                  (fid, sid, owner, dk, dline, dcol, int(didx), dname, drcv, sk, int(sidx),
                   sline, scol, sname, int(via), int(cond)))
        n += 1
    c.commit()
    c.close()
    print(n)


if __name__ == '__main__':
    main()
