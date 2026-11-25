"""Host-only exact-build driver transformation; no device writes."""
from pathlib import Path
import struct, hashlib, json, base64

import argparse
ap=argparse.ArgumentParser(description=__doc__)
ap.add_argument('stock',type=Path)
ap.add_argument('v12',type=Path)
ap.add_argument('output_directory',type=Path)
args=ap.parse_args()
ROOT=args.output_directory.resolve()
ROOT.mkdir(parents=True,exist_ok=True)
ORIGINAL=args.stock.read_bytes()
V12=args.v12.read_bytes()
sha=lambda b: hashlib.sha256(b).hexdigest()
assert sha(ORIGINAL)=='d205f2480c621b0eef866b61c684f9c9669136e932d4a0ee3914fccaf0c60139'
assert sha(V12)=='aaa967a88106757dc7aa9958a8206f520a6e040bf57299b7964e12ae06bb53c0'
SHOFF=struct.unpack_from('<Q',ORIGINAL,0x28)[0]
SECTIONS=[struct.unpack_from('<IIQQQQIIQQ',ORIGINAL,SHOFF+i*64) for i in range(38)]
TEXT=SECTIONS[11][4]
SYMTAB=SECTIONS[36]; STRTAB=SECTIONS[37]
STRINGS=ORIGINAL[STRTAB[4]:STRTAB[4]+STRTAB[5]]
SYMS={}
for idx,off in enumerate(range(SYMTAB[4],SYMTAB[4]+SYMTAB[5],24)):
    name,info,other,section,value,size=struct.unpack_from('<IBBHQQ',ORIGINAL,off)
    name=STRINGS[name:STRINGS.index(0,name)].decode()
    SYMS[name]=(idx,section,value,size)
RELAS={}
for off in range(SECTIONS[12][4],SECTIONS[12][4]+SECTIONS[12][5],24):
    addr,info,addend=struct.unpack_from('<QQq',ORIGINAL,off)
    RELAS[addr]=(off,info>>32,info&0xffffffff,addend)

data=bytearray(V12)
# Restore the complete stock reinit wrapper before replacing ownership logic.
START,END=0x395cc,0x39888
data[TEXT+START:TEXT+END]=ORIGINAL[TEXT+START:TEXT+END]
for addr,(off,si,ty,ad) in RELAS.items():
    if START<=addr<END: data[off:off+24]=ORIGINAL[off:off+24]

ranges=[(0x39494,0x394b8),(0x394c8,0x394cc),(0x39524,0x39528),
        (0x395fc,0x39600),(0x3963c,0x39678),(0x39780,0x39784),
        (0x397a4,0x397b4),(0x397c8,0x397cc),(0x39840,0x39884),
        (0x7974c,0x79754),(0x797b4,0x797b8)]
free=[]
for addr,(off,si,ty,ad) in RELAS.items():
    if any(a<=addr<b for a,b in ranges):
        struct.pack_into('<QQq',data,off,addr,0,0)
        free.append(off)
used=[]
def relocation(addr,kind,name=None,source=None):
    if source is not None:
        _,si,_,ad=RELAS[source]
    else:
        si=SYMS[name][0]; ad=0
    preferred=RELAS.get(addr,(None,))[0]
    off=preferred if preferred in free else free[0]
    free.remove(off); used.append((off,addr,kind,si,ad))
    struct.pack_into('<QQq',data,off,addr,(si<<32)|kind,ad)
def word(addr,value):
    assert addr%4==0 and any(a<=addr<b for a,b in ranges)
    struct.pack_into('<I',data,TEXT+addr,value)
def branch(addr,target,op=0x14000000):
    delta=target-addr
    assert delta%4==0 and -(1<<27)<=delta<(1<<27)
    word(addr,op|((delta//4)&0x3ffffff))
def bitbranch(addr,target,bit=3,nonzero=False):
    delta=target-addr
    assert delta%4==0 and -(1<<15)<=delta<(1<<15)
    word(addr,(0x37000000 if nonzero else 0x36000000)|(bit<<19)|(((delta//4)&0x3fff)<<5))
def cbz(addr,target):
    delta=target-addr
    assert delta%4==0 and -(1<<20)<=delta<(1<<20)
    word(addr,0x34000000|(((delta//4)&0x7ffff)<<5))
def call(addr,name):
    word(addr,0x94000000); relocation(addr,283,name=name)
NOP=0xd503201f

# Shutdown: reject unloading or late callbacks; acquire only a fresh transaction.
# The v1.2 common exit still stops exactly the transaction owned by this callback.
bitbranch(0x39494,0x394d0,bit=0,nonzero=True)
call(0x39498,'cds_get_driver_state')
bitbranch(0x3949c,0x394d0)
branch(0x394a0,0x394b8)
for a in range(0x394a4,0x394b0,4): word(a,NOP)
# Existing missing-context paths join this logging tail, then the owned exit.
call(0x394b0,'qdf_trace_msg')
branch(0x394b4,0x394d0)
call(0x394c8,'__osif_psoc_sync_trans_start')
bitbranch(0x39524,0x394d0)

# Invalid bus values keep their real -EINVAL result, without using the guard stub.
word(0x395fc,0x54000002|((((0x39660-0x395fc)//4)&0x7ffff)<<5))
# Reinit: check state, acquire a new transaction, drain already-started operations,
# and then execute the original initialization body. No transaction resume.
call(0x3963c,'cds_get_driver_state')
bitbranch(0x39640,0x39634)
word(0x39644,0x90000002); relocation(0x39644,275,source=0x3961c)
word(0x39648,0x91000042); relocation(0x39648,277,source=0x39624)
word(0x3964c,0x910003e1)  # mov x1, sp
word(0x39650,0xaa1303e0)  # mov x0, x19
call(0x39654,'__osif_psoc_sync_trans_start')
cbz(0x39658,0x3966c)
branch(0x3965c,0x39840)
branch(0x39668,0x3963c)
word(0x3966c,0xf94003e0)  # ldr x0, [sp] (owned osif sync)
call(0x39670,'osif_psoc_sync_wait_for_ops')
branch(0x39674,0x39678)

# Reinit errors take normal cleanup, including owned transaction release.
# Remove only this wrapper's third-failure assertion, not global crash controls.
branch(0x39780,0x39784)
branch(0x397a4,0x397b4)
for a in range(0x397a8,0x397b4,4): word(a,NOP)
word(0x397c8,0xb9000314)  # str w20, [x24] (preserve actual status)
relocation(0x397c8,285,name='wlan_start_ret_val')
# Acquisition failure owns nothing: return the real error, without stopping
# someone else's transaction or signaling their in-progress completion.
word(0x39840,0x2a0003f4)  # mov w20, w0
branch(0x39844,0x397d0)
for a in range(0x39848,0x39884,4): word(a,NOP)

# The stock real reinit assumes an adapter exists; reject a missing adapter via
# its existing wake-lock-release/error return instead of a NULL-based completion.
delta=(0x797dc-0x7974c)//4
word(0x7974c,0xb4000000|((delta&0x7ffff)<<5))  # cbz x0
branch(0x79750,0x7976c)
# On an actual start failure, preserve cleanup and return its error rather than
# invoking the optional recovery-failure panic configured by the stock driver.
branch(0x797b4,0x797b8)

BUILD_ID=hashlib.sha256(b'Spacewar-2509261631-QCA6750-owned-reinit-v1.3-test').digest()[:8]
data[0x6098d0:0x6098d8]=BUILD_ID
assert len(data)==len(ORIGINAL)==14749616

# Canonical writes work from both supported input versions, including restoring
# bytes that v1.2 changed and v1.3 keeps stock.
changed=[i for i,(a,b,c) in enumerate(zip(ORIGINAL,V12,data)) if a!=c or b!=c]
spans=[]
for i in changed:
    if spans and i-spans[-1][1]<=8: spans[-1][1]=i+1
    else: spans.append([i,i+1])
chunks=[{'offset':a,'data':base64.b64encode(data[a:b]).decode()} for a,b in spans]
manifest={'schema':1,'device':'Spacewar','build':'2509261631',
    'kernel':'5.4.274-qgki-g4670d6bdb795','size':len(data),
    'accepted_sha256':[sha(ORIGINAL),sha(V12)],'output_sha256':sha(data),
    'loaded_build_id':BUILD_ID.hex(),'patches':chunks}
for source in [ORIGINAL,V12]:
    test=bytearray(source)
    for p in chunks:
        b=base64.b64decode(p['data']); test[p['offset']:p['offset']+len(b)]=b
    assert test==data
(ROOT/'qca6750_v13.ko').write_bytes(data)
(ROOT/'driver_patch.json').write_text(json.dumps(manifest,indent=2)+'\n')
(ROOT/'new_relocations.json').write_text(json.dumps(used,indent=2)+'\n')
print(json.dumps({k:manifest[k] for k in ['output_sha256','loaded_build_id','size']},indent=2))
print('Patch chunks:',len(chunks),'payload bytes:',sum(len(base64.b64decode(p['data'])) for p in chunks))
