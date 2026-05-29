"""
lsp_send.py  --  generate Content-Length framed LSP message sequences.

Usage:
    python lsp_send.py <TEST_ID> <output_file>

Writes binary LSP frames to <output_file>, ready to pipe into drag-lint.exe lsp.
"""
import sys
import json

def frame(msg):
    s = json.dumps(msg, separators=(',', ':'))
    b = s.encode('utf-8')
    header = ('Content-Length: %d\r\n\r\n' % len(b)).encode('utf-8')
    return header + b

def write_frames(msgs, path):
    with open(path, 'wb') as f:
        for m in msgs:
            f.write(frame(m))

test_id  = sys.argv[1]
out_path = sys.argv[2]

if test_id == 'T24':
    # Completion: position inside "GetBaz" on line 14 (0-based 13), col 15 (0-based).
    # 1-based: line 14, col 16.  SubLine = "    function GetBa" -> prefix "GetBa"
    # -> FindSymbolsByPrefix("GetBa") should include GetBaz.
    msgs = [
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}},
        {"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{
            "textDocument":{"uri":"file:///C:/Projects/Delphi-RAG-lint/tests/fixtures/Docs.pas"},
            "position":{"line":13,"character":15}
        }},
        {"jsonrpc":"2.0","id":3,"method":"shutdown","params":{}},
    ]

elif test_id == 'T25':
    # SignatureHelp: Calls.pas line 16 (0-based 15) = "  Compute(10);"
    # character 9 (0-based) = just after the '(' at col 9.
    # Walk left finds '(' at col 9, callee ends at col 8 "Compute".
    msgs = [
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}},
        {"jsonrpc":"2.0","id":2,"method":"textDocument/signatureHelp","params":{
            "textDocument":{"uri":"file:///C:/Projects/Delphi-RAG-lint/tests/fixtures/Calls.pas"},
            "position":{"line":15,"character":9}
        }},
        {"jsonrpc":"2.0","id":3,"method":"shutdown","params":{}},
    ]

elif test_id == 'T26':
    # didOpen on LoopFBN.pas which has FieldByName-in-loop findings.
    msgs = [
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}},
        {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{
            "textDocument":{
                "uri":"file:///C:/Projects/Delphi-RAG-lint/tests/fixtures/LoopFBN.pas",
                "languageId":"pascal",
                "version":1,
                "text":""
            }
        }},
        {"jsonrpc":"2.0","id":2,"method":"shutdown","params":{}},
    ]

else:
    print('Unknown test id: ' + test_id, file=sys.stderr)
    sys.exit(1)

write_frames(msgs, out_path)
