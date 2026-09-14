"""Independent FAC1 reference encoder. Run explicitly to review proposed vectors."""
from pathlib import Path
import json
import struct

def encode(v):
    if v is None:
        return b'\0'
    if isinstance(v, bool):
        return b'\1' + bytes([v])
    if isinstance(v, int):
        return b'\2' + struct.pack('<q', v)
    if isinstance(v, str):
        raw = v.encode('utf-8')
        return b'\3' + struct.pack('<q', len(raw)) + raw
    if isinstance(v, tuple):
        return b'\4' + struct.pack('<qq', *v)
    if isinstance(v, list):
        return b'\5' + struct.pack('<q', len(v)) + b''.join(map(encode, v))
    keys = sorted(v, key=lambda k: k.encode('utf-8'))
    return b'\6' + struct.pack('<q', len(keys)) + b''.join(encode(k) + encode(v[k]) for k in keys)

cases = {
    'integers': [None, False, True, 0, -1, -(2**63), 2**63-1, 9007199254740993],
    'ordered_map': {'z': (2, -1), 'a': ['ø', 17]},
}
root = Path(__file__).resolve().parents[2]
target = root / 'tests/game/goldens/codec-v1.json'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps({k: (b'FAC1' + encode(v)).hex() for k, v in cases.items()}, indent=2) + '\n', encoding='utf-8')
