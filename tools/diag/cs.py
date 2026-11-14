import sys,types,sysconfig
dm=types.ModuleType('distutils');ds=types.ModuleType('distutils.sysconfig')
ds.get_python_lib=lambda *a,**k:sysconfig.get_paths()['purelib']
dm.sysconfig=ds;sys.modules['distutils']=dm;sys.modules['distutils.sysconfig']=ds
pr=types.ModuleType('pkg_resources')
pr.resource_filename=lambda pkg,p:'/usr/lib/python3.13/site-packages/capstone/'+p
sys.modules['pkg_resources']=pr
import capstone
