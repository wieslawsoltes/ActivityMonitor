import subprocess,time,json,sys
pid=int(sys.argv[1]);duration=float(sys.argv[2]);path=sys.argv[3]
def read():
 s=subprocess.check_output(['ps','-p',str(pid),'-o','time=,rss='],text=True).split();return sum(float(p)*60**i for i,p in enumerate(reversed(s[0].split(':')))),int(s[1])
a=read();start=time.monotonic();time.sleep(duration);b=read();elapsed=time.monotonic()-start
result=dict(pid=pid,seconds=elapsed,cpu_percent=(b[0]-a[0])/elapsed*100,rss_start_kib=a[1],rss_end_kib=b[1]);open(path,'w').write(json.dumps(result,indent=2));print(json.dumps(result))
