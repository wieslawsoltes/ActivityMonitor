#include "SystemBridge.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <net/route.h>
#include <net/if_dl.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/ps/IOPSKeys.h>
#include <string.h>
#include <stdlib.h>
int am_processes(AMProcess *out, int capacity) {
 int mib[4]={CTL_KERN,KERN_PROC,KERN_PROC_ALL,0}; size_t size=0;
 if(sysctl(mib,4,NULL,&size,NULL,0)!=0) return 0;
 size+=64*sizeof(struct kinfo_proc);
 if(!out) return (int)(size/sizeof(struct kinfo_proc));
 struct kinfo_proc *processes=malloc(size);
 if(!processes) return 0;
 if(sysctl(mib,4,processes,&size,NULL,0)!=0) {free(processes);return 0;}
 int count=(int)(size/sizeof(struct kinfo_proc)), n=0;
 mach_timebase_info_data_t timebase;
 mach_timebase_info(&timebase);
 for(int i=0;i<count && n<capacity;i++) {
  struct kinfo_proc *info=&processes[i];
  AMProcess p={0}; p.pid=info->kp_proc.p_pid; p.ppid=info->kp_eproc.e_ppid; p.uid=info->kp_eproc.e_ucred.cr_uid;p.translated=(info->kp_proc.p_flag & P_TRANSLATED)!=0;
  p.start=(uint64_t)info->kp_proc.p_starttime.tv_sec*1000000+info->kp_proc.p_starttime.tv_usec;
  proc_name(p.pid,p.name,sizeof(p.name));
  if(!p.name[0]) strlcpy(p.name,info->kp_proc.p_comm,sizeof(p.name));
  struct proc_taskinfo task={0};
  if(proc_pidinfo(p.pid,PROC_PIDTASKINFO,0,&task,sizeof(task)) == sizeof(task)) {
   p.accessible=1; p.threads=task.pti_threadnum;
   // proc_taskinfo uses Mach absolute ticks, not nanoseconds on Apple silicon.
   p.cpu=(uint64_t)(((long double)task.pti_total_user+task.pti_total_system)*timebase.numer/timebase.denom);
   p.resident=task.pti_resident_size;
  }
  struct rusage_info_v4 r={0};
  if(proc_pid_rusage(p.pid,RUSAGE_INFO_V4,(rusage_info_t *)&r)==0) {
   p.ioAccessible=1; p.footprint=r.ri_phys_footprint; p.read=r.ri_diskio_bytesread; p.written=r.ri_diskio_byteswritten;
  }
  out[n++]=p;
 }
 free(processes); return n;
}
void am_system(AMSystem *o) {
 memset(o,0,sizeof(*o)); o->battery=-1;
 mach_port_t host=mach_host_self(); host_cpu_load_info_data_t cpu; mach_msg_type_number_t count=HOST_CPU_LOAD_INFO_COUNT;
 if(host_statistics(host,HOST_CPU_LOAD_INFO,(host_info_t)&cpu,&count)==KERN_SUCCESS) {o->user=cpu.cpu_ticks[CPU_STATE_USER]+cpu.cpu_ticks[CPU_STATE_NICE]; o->system=cpu.cpu_ticks[CPU_STATE_SYSTEM]; o->idle=cpu.cpu_ticks[CPU_STATE_IDLE];}
 vm_statistics64_data_t vm; count=HOST_VM_INFO64_COUNT; vm_size_t page; host_page_size(host,&page);
 if(host_statistics64(host,HOST_VM_INFO64,(host_info64_t)&vm,&count)==KERN_SUCCESS) {o->free=(uint64_t)vm.free_count*page;o->active=(uint64_t)vm.active_count*page;o->inactive=(uint64_t)vm.inactive_count*page;o->wired=(uint64_t)vm.wire_count*page;o->compressed=(uint64_t)vm.compressor_page_count*page;}
 mach_port_deallocate(mach_task_self(),host);
 size_t len=sizeof(o->physical); sysctlbyname("hw.memsize",&o->physical,&len,NULL,0);
 struct xsw_usage swap; len=sizeof(swap); if(sysctlbyname("vm.swapusage",&swap,&len,NULL,0)==0)o->swap=swap.xsu_used;
 len=sizeof(o->pressure);sysctlbyname("kern.memorystatus_vm_pressure_level",&o->pressure,&len,NULL,0);
 // NET_RT_IFLIST2 supplies 64-bit counters; getifaddrs exposes wrapping 32-bit counters.
 int mib[6]={CTL_NET,PF_ROUTE,0,0,NET_RT_IFLIST2,0}; size_t networkSize=0;
 if(sysctl(mib,6,NULL,&networkSize,NULL,0)==0 && networkSize>0) {
  char *network=malloc(networkSize);
  if(network && sysctl(mib,6,network,&networkSize,NULL,0)==0) {
   for(char *cursor=network;cursor+sizeof(struct if_msghdr)<=network+networkSize;) {
    struct if_msghdr *header=(struct if_msghdr *)cursor;
    if(header->ifm_msglen==0 || cursor+header->ifm_msglen>network+networkSize) break;
    if(header->ifm_type==RTM_IFINFO2 && header->ifm_msglen>=sizeof(struct if_msghdr2)) {
     struct if_msghdr2 *info=(struct if_msghdr2 *)cursor;
     if(!(info->ifm_flags&IFF_LOOPBACK)) {
      o->received+=info->ifm_data.ifi_ibytes;o->sent+=info->ifm_data.ifi_obytes;
      o->packetsIn+=info->ifm_data.ifi_ipackets;o->packetsOut+=info->ifm_data.ifi_opackets;
     }
    }
    cursor+=header->ifm_msglen;
   }
  }
  free(network);
 }
 CFTypeRef power=IOPSCopyPowerSourcesInfo(); if(power) {CFArrayRef list=IOPSCopyPowerSourcesList(power);if(list){for(CFIndex i=0;i<CFArrayGetCount(list);i++){CFDictionaryRef d=IOPSGetPowerSourceDescription(power,CFArrayGetValueAtIndex(list,i));CFNumberRef current=CFDictionaryGetValue(d,CFSTR(kIOPSCurrentCapacityKey)), max=CFDictionaryGetValue(d,CFSTR(kIOPSMaxCapacityKey));int c=0,m=0;if(current&&max){CFNumberGetValue(current,kCFNumberIntType,&c);CFNumberGetValue(max,kCFNumberIntType,&m);if(m)o->battery=100*c/m;}o->charging=CFDictionaryGetValue(d,CFSTR(kIOPSIsChargingKey))==kCFBooleanTrue;CFStringRef state=CFDictionaryGetValue(d,CFSTR(kIOPSPowerSourceStateKey));o->externalPower=state&&CFEqual(state,CFSTR(kIOPSACPowerValue));}CFRelease(list);}CFRelease(power);}
}
