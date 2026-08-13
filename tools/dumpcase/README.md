# dumpcase -- print the named children of every `case` node

A four-line diagnostic that exists because assuming the parse tree's shape cost
two real defects (2026-08-12, `DRagLint.Analysis.Cfg.pas`, the `K = 'case'`
handler):

* the ELSE ARM was assumed to be reachable as `ChildByField('else')`, the way
  `ifElse` exposes it. It is not -- it is a run of bare siblings after `kElse`.
* the SELECTOR was assumed to be "the first named child that is not a
  `caseCase`". It is not -- **keywords are named nodes in this grammar**, so
  that expression names the `case` keyword itself.

Both read plausibly. Neither survives thirty seconds of looking at the tree:

    > dumpcase caseelse.pas
    case node: NamedChildCount=8 ChildCount=10
      named[0] type=kCase
      named[1] type=identifier      <-- the selector
      named[2] type=kOf
      named[3] type=caseCase
      named[4] type=caseCase
      named[5] type=kElse
      named[6] type=assignment      <-- the else body, a bare sibling
      named[7] type=kEnd

## Build

Needs the DCUs from a Win64 build of the CLI (`build\build_draglint_win64.bat`
produces them), and the tree-sitter DLLs on PATH at run time:

    call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
    cd /d <repo>\tools\dumpcase
    dcc64 -B -NU"<repo>\src\cli\Win64\Debug" -U"<repo>\src\cli\Win64\Debug" ^
          -E"<repo>\src\cli\Win64\Debug" dumpcase.dpr

Then run it with `<repo>\third_party\dll-win64` on PATH.

To inspect a different construct, change the `ANode.NodeType = 'case'` test in
`Walk`. `scratchpad\dumptree.dpr` prints the whole tree instead, which is the
better starting point when you do not yet know what you are looking for.
