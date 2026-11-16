"""compare two mp_dmtrace JSON files: for A and B print the first time each differs and the differing addresses (data 0x300+idx; idx0 = [6F]). usage: trace_diff.py TAG1 TAG2"""
import json, sys
a=json.load(open('/tmp/trace_%s.json'%sys.argv[1])); b=json.load(open('/tmp/trace_%s.json'%sys.argv[2]))
for k in 'AB':
    for ra,rb in zip(a,b):
        d=[i for i,(x,y) in enumerate(zip(ra[k],rb[k])) if x!=y]
        if d: print(k,'first differing snapshot t=%.2f'%ra['t'],'n=%d'%len(d),' addrs:',' '.join('%s'%('6F' if i==0 else '%03X'%(0x300+i-1)) for i in d[:40])); break
    else: print(k,'no difference')
