"""Execute the real patched wrapper instructions with stubbed kernel calls.

This is an offline ownership/control-flow test, not a Wi-Fi hardware test.
LLVM is used only for independent instruction decoding.
"""
from pathlib import Path
import ctypes as C
import struct,re,json,hashlib

ROOT=Path(__file__).resolve().parent
DATA=(ROOT/'qca6750_v13.ko').read_bytes()
manifest=json.loads((ROOT/'driver_patch.json').read_text())
assert hashlib.sha256(DATA).hexdigest()==manifest['output_sha256']
shoff=struct.unpack_from('<Q',DATA,0x28)[0]
sections=[struct.unpack_from('<IIQQQQIIQQ',DATA,shoff+i*64) for i in range(38)]
strings=DATA[sections[37][4]:sections[37][4]+sections[37][5]]
syms=[]
for p in range(sections[36][4],sections[36][4]+sections[36][5],24):
    no,info,other,sec,value,size=struct.unpack_from('<IBBHQQ',DATA,p)
    syms.append((strings[no:strings.index(0,no)].decode(),sec,value,size))
byname={s[0]:i for i,s in enumerate(syms)}
base={6:0x60000000,7:0x70000000,9:0x50000000,11:0x40000000}
def address(idx,add=0):
    n,sec,v,size=syms[idx]
    return (base.get(sec,0x90000000+idx*0x1000)+v+add)
def symaddr(name): return address(byname[name])
rel={}
for off in range(sections[12][4],sections[12][4]+sections[12][5],24):
    a,info,add=struct.unpack_from('<QQq',DATA,off)
    if not info&0xffffffff: continue
    assert a not in rel,hex(a)
    rel[a]=(info&0xffffffff,info>>32,add)
    assert a%4==0

lib=C.CDLL('libLLVM.so.20.1')
for k in ['TargetInfo','Target','TargetMC','AsmPrinter','Disassembler']:
    getattr(lib,'LLVMInitializeAArch64'+k)()
lib.LLVMCreateDisasm.argtypes=[C.c_char_p,C.c_void_p,C.c_int,C.c_void_p,C.c_void_p]
lib.LLVMCreateDisasm.restype=C.c_void_p
ctx=lib.LLVMCreateDisasm(b'aarch64-linux-gnu',None,0,None,None)
lib.LLVMDisasmInstruction.argtypes=[C.c_void_p,C.POINTER(C.c_uint8),C.c_uint64,C.c_uint64,C.c_char_p,C.c_size_t]
lib.LLVMDisasmInstruction.restype=C.c_size_t
code={}
for lo,hi in [(0x3944c,0x39888),(0x7974c,0x79754),(0x797b4,0x797b8)]:
    for a in range(lo,hi,4):
        raw=DATA[sections[11][4]+a:sections[11][4]+a+4]
        out=C.create_string_buffer(256)
        assert lib.LLVMDisasmInstruction(ctx,(C.c_uint8*4).from_buffer_copy(raw),4,a,out,256)==4
        text=out.value.decode().strip()
        code[a]=text.split(None,1)[0],text.split(None,1)[1] if len(text.split(None,1))>1 else ''

class Machine:
    STACK=0x80010000; SHADOW=0x81000000
    SYNC=0xa0010000; DSC=0xa0020000; HDD=0xa0030000
    HIF=0xa0040000; QDF=0xa0050000
    def __init__(self,*,unloading=False,recovering=True,busy=False,reinit_ret=0,
                 fw_down=False,hdd=True,hif=True,qdf=True,smmu_ret=0,race=False,counter=0):
        self.r={f'x{i}':0x100000+i for i in range(31)}
        self.r.update(sp=self.STACK,x18=self.SHADOW,x0=0xa0000000,x1=0,x2=0xa0060000,x3=0xa0070000)
        self.initial=dict(self.r); self.mem={}; self.trace=[]; self.flags=9 if recovering else 1
        self.unloading=unloading; self.busy=busy; self.reinit_ret=reinit_ret
        self.fw_down=fw_down; self.hdd=hdd; self.hif=hif; self.qdf=qdf; self.smmu_ret=smmu_ret
        self.race=race; self.owned=False; self.starts=0; self.stops=0
        self.drained=False; self.reinits=0; self.shutdowns=0; self.completions=0
        self.wake=0; self.qos=0; self.eq=False; self.hs=False; self.bits=64
        self.put(symaddr('__stack_chk_guard'),8,0x12345678abcdef01)
        self.put(self.SYNC+8,8,self.DSC)
        self.put(0x60000128,1,counter)
        self.put(symaddr('wlan_start_ret_val'),4,0xabcdef01)
    def reg(self,n):
        n=n.strip()
        if n in ['xzr','wzr']: return 0
        if n.startswith('w'): return self.r['x'+n[1:]]&0xffffffff
        return self.r[n]
    def set(self,n,v):
        if n in ['xzr','wzr']: return
        bits=32 if n.startswith('w') else 64
        self.r['x'+n[1:] if n.startswith('w') else n]=v&((1<<bits)-1)
    def get(self,a,size):
        assert a>=4096,('null read',hex(self.pc),hex(a))
        return sum(self.mem.get(a+i,0)<<(8*i) for i in range(size))
    def put(self,a,size,v):
        assert a>=4096,('null write',hex(a))
        for i in range(size): self.mem[a+i]=(v>>(8*i))&255
    def atom(self,s): return int(s[1:],0) if s.startswith('#') else self.reg(s)
    def memaddr(self,s):
        s=s.strip()
        m=re.match(r'\[([^]]+)\](!)?(?:, (#[^ ]+))?$',s); assert m,s
        z=[x.strip() for x in m[1].split(',')]; old=self.reg(z[0]); a=old
        if len(z)>1:
            inc=self.atom(z[1])
            if len(z)>2:
                sign,shift=z[2].split(); assert sign=='sxtw'
                if inc&0x80000000: inc-=1<<32
                inc<<=int(shift[1:],0)
            a+=inc
        if m[2]: self.set(z[0],a)
        if m[3]: self.set(z[0],old+int(m[3][1:],0))
        return a
    def call(self,name):
        arg=[self.reg(f'x{i}') for i in range(4)]; ret=0
        self.trace.append((hex(self.pc),name))
        if name=='qdf_is_driver_unloading': ret=int(self.unloading)
        elif name=='cds_get_driver_state':
            if self.race and self.owned: self.flags&=~8
            ret=self.flags
        elif name=='__osif_psoc_sync_trans_start':
            self.starts+=1
            assert arg[0]==self.initial['x0'] and arg[1]==self.r['sp']
            assert arg[2]>=0x50000000
            self.put(arg[1],8,0)
            if self.busy: ret=-16
            else:
                assert not self.owned
                self.owned=True; self.put(arg[1],8,self.SYNC)
        elif name in ['dsc_psoc_wait_for_ops','osif_psoc_sync_wait_for_ops']:
            assert self.owned and arg[0]==(self.DSC if name.startswith('dsc') else self.SYNC)
            self.drained=True
        elif name=='dsc_psoc_trans_stop':
            assert self.owned and arg[0]==self.DSC
            self.owned=False; self.stops+=1
        elif name=='cds_get_context':
            ret={51:self.HDD if self.hdd else 0,61:self.HIF if self.hif else 0,
                 64:self.QDF if self.qdf else 0}[arg[0]]
        elif name=='hdd_wlan_re_init':
            assert self.owned and self.drained
            self.reinits+=1; ret=self.reinit_ret
        elif name=='hdd_wlan_shutdown':
            assert self.owned and self.drained
            self.shutdowns+=1
        elif name=='qdf_is_fw_down': ret=int(self.fw_down)
        elif name=='cds_smmu_mem_map_setup': ret=self.smmu_ret
        elif name=='cds_clear_driver_state': self.flags&=~arg[0]
        elif name=='cds_set_driver_state': self.flags|=arg[0]
        elif name=='qdf_wake_lock_acquire': self.wake+=1
        elif name=='qdf_wake_lock_release': self.wake-=1
        elif name=='pld_request_pm_qos': self.qos+=1
        elif name=='pld_remove_pm_qos': self.qos-=1
        elif name=='complete':
            assert not self.owned
            self.completions+=1
        elif name in ['__qdf_bug','__stack_chk_fail','osif_psoc_sync_trans_resume','__osif_psoc_sync_trans_start_wait']:
            raise AssertionError(('forbidden call',name,self.trace))
        elif name in ['qdf_trace_msg','hif_mask_interrupt_call','hif_disable_isr','hdd_handle_cached_commands']:
            pass
        elif name=='hdd_soc_recovery_cleanup':
            assert self.owned
        else: raise AssertionError(('unknown call',name))
        for i in range(18): self.set(f'x{i}',0xcafe0000+i*16)
        self.set('x0',ret)
    def run(self,start):
        self.pc=start
        for steps in range(1500):
            op,args=code[self.pc]; nxt=self.pc+4
            vals=[x.strip() for x in args.split(',')]
            relocation=rel.get(self.pc)
            if op=='nop': pass
            elif op=='ret':
                assert self.r['sp']==self.STACK and self.r['x18']==self.SHADOW
                for i in [19,20,21,22,23,24,29,30]: assert self.reg(f'x{i}')==self.initial[f'x{i}'],i
                result=self.reg('w0'); return result-(1<<32) if result&0x80000000 else result
            elif op=='bl':
                assert relocation and relocation[0]==283
                name,sec,v,size=syms[relocation[1]]
                if not name and sec==11:
                    name=next(s[0] for s in syms if s[1]==11 and s[2]==relocation[2] and s[3])
                self.set('x30',self.pc+4); self.call(name)
            elif op=='b': nxt=self.pc+int(args[1:],0)
            elif op in ['b.eq','b.ne','b.hs']:
                take=self.eq if op=='b.eq' else not self.eq if op=='b.ne' else self.hs
                if take: nxt=self.pc+int(args[1:],0)
            elif op in ['cbz','cbnz']:
                if (self.reg(vals[0])==0)==(op=='cbz'): nxt=self.pc+int(vals[1][1:],0)
            elif op in ['tbz','tbnz']:
                zero=not (self.reg(vals[0]) & (1<<int(vals[1][1:],0)))
                if zero==(op=='tbz'): nxt=self.pc+int(vals[2][1:],0)
            elif op=='mov': self.set(vals[0],self.atom(vals[1]))
            elif op=='adrp':
                assert relocation and relocation[0]==275
                self.set(vals[0],address(relocation[1],relocation[2])&~4095)
            elif op in ['add','sub','and']:
                imm=(address(relocation[1],relocation[2])&4095) if relocation else self.atom(vals[2])
                a=self.reg(vals[1]); self.set(vals[0],a+imm if op=='add' else a-imm if op=='sub' else a&imm)
            elif op in ['cmp','tst']:
                a,b=self.atom(vals[0]),self.atom(vals[1]); self.eq=(a==b if op=='cmp' else a&b==0); self.hs=a>=b
            elif op in ['stp','ldp']:
                aa=self.memaddr(args.split(',',2)[2]); sz=4 if vals[0].startswith('w') else 8
                for i in range(2):
                    if op=='stp': self.put(aa+i*sz,sz,self.reg(vals[i]))
                    else: self.set(vals[i],self.get(aa+i*sz,sz))
            elif op in ['ldr','ldrb','str','strb']:
                aa=self.memaddr(args.split(',',1)[1]); sz=1 if op.endswith('b') else 4 if vals[0].startswith('w') else 8
                if relocation:
                    assert relocation[0] in [278,285,286]
                    aa+=address(relocation[1],relocation[2])&4095
                if op.startswith('str'): self.put(aa,sz,self.reg(vals[0]))
                else: self.set(vals[0],self.get(aa,sz))
            else: raise AssertionError(('unsupported',hex(self.pc),op,args))
            self.pc=nxt
        raise AssertionError('instruction limit')

results=[]
def check(label,params,fn,expected,starts,stops,reinits,shutdowns,comps):
    m=Machine(**params); result=m.run(fn)
    if expected is not None: assert result==expected,(label,result,expected,m.trace)
    assert (m.starts,m.stops,m.reinits,m.shutdowns,m.completions)==(starts,stops,reinits,shutdowns,comps),(label,m.trace)
    assert not m.owned and m.wake==m.qos==0,label
    if comps:
        rv=m.get(symaddr('wlan_start_ret_val'),4)
        assert rv==(expected&0xffffffff),(label,rv,expected)
    if reinits and expected==0 and not params.get('fw_down'): assert not m.flags&8
    results.append(label)

REINIT=0x395cc; SHUTDOWN=0x3944c
check('real recovery succeeds',{},REINIT,0,1,1,1,0,1)
check('unloading skips recovery',{'unloading':True},REINIT,0,0,0,0,0,0)
check('late duplicate skips recovery',{'recovering':False},REINIT,0,0,0,0,0,0)
check('busy recovery owns nothing',{'busy':True},REINIT,-16,1,0,0,0,0)
check('real recovery error preserved',{'reinit_ret':-5},REINIT,-5,1,1,1,0,1)
check('third recovery failure returns error',{'reinit_ret':-5,'counter':2},REINIT,-5,1,1,1,0,1)
check('missing QDF context cleans up',{'qdf':False},REINIT,-22,1,1,0,0,1)
check('SMMU failure cleans up',{'smmu_ret':-1},REINIT,-14,1,1,0,0,1)
check('new FW crash retains recovering state',{'fw_down':True},REINIT,0,1,1,1,0,1)
check('normal shutdown releases ownership',{},SHUTDOWN,None,1,1,0,1,0)
check('unloading skips shutdown',{'unloading':True},SHUTDOWN,None,0,0,0,0,0)
check('late shutdown skips safely',{'recovering':False},SHUTDOWN,None,0,0,0,0,0)
check('busy shutdown releases nothing',{'busy':True},SHUTDOWN,None,1,0,0,0,0)
check('shutdown state race releases own transaction',{'race':True},SHUTDOWN,None,1,1,0,0,0)
check('missing HDD context releases shutdown',{'hdd':False},SHUTDOWN,None,1,1,0,0,0)
check('missing HIF context releases shutdown',{'hif':False},SHUTDOWN,None,1,1,0,0,0)
for bus in [8,9,0xffffffff]:
    m=Machine(); m.set('w1',bus); assert m.run(REINIT)==-22 and not m.trace
    results.append(f'invalid bus {bus} rejected')
assert code[0x7974c]==('cbz','x0, #144')
assert code[0x79750]==('b','#28')
assert code[0x797b4]==('b','#4')
m=Machine()
for fn in [SHUTDOWN,REINIT,REINIT,SHUTDOWN]:
    m.r=dict(m.initial)
    m.run(fn)
assert (m.starts,m.stops,m.reinits,m.shutdowns,m.completions)==(2,2,1,1,1)
assert not m.owned and not m.flags&8
results.append('shutdown, recovery, duplicate recovery, late shutdown lifecycle')
print(json.dumps({'passed':len(results),'cases':results,'scope':'actual wrapper instructions; inner driver/kernel calls stubbed; hardware untested'},indent=2))
(ROOT/'test_results.json').write_text(json.dumps({'passed':len(results),'cases':results},indent=2)+'\n')
