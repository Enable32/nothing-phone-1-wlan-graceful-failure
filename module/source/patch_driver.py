#!/usr/bin/env python3
"""Apply the recorded exact-build patch to a regular file, never a device."""
import argparse,base64,hashlib,json
from pathlib import Path

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('input',type=Path); p.add_argument('output',type=Path)
    args=p.parse_args()
    m=json.loads((Path(__file__).parent/'driver_patch.json').read_text())
    if not args.input.is_file(): p.error('input must be a regular file')
    if args.output.exists() or args.input.resolve()==args.output.resolve():
        p.error('output must be a different, new file')
    b=bytearray(args.input.read_bytes())
    digest=lambda a:hashlib.sha256(a).hexdigest()
    if len(b)!=m['size'] or digest(b) not in m['accepted_sha256']:
        p.error('unsupported input size/SHA-256')
    if b[:6]!=b'\x7fELF\x02\x01' or int.from_bytes(b[18:20],'little')!=183:
        p.error('expected an ELF64 little-endian AArch64 module')
    for patch in m['patches']:
        off=patch['offset']; raw=base64.b64decode(patch['data'],validate=True)
        if off<0 or off+len(raw)>len(b): p.error('patch is outside the file')
        b[off:off+len(raw)]=raw
    if digest(b)!=m['output_sha256']: p.error('output SHA-256 mismatch')
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open('xb') as out: out.write(b)
    print(digest(b),args.output)

if __name__=='__main__': main()
