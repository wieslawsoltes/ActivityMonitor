#include "ProcessDiagnostics.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <arpa/inet.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>

static int failure(void) { return errno ? errno : EIO; }
static uint64_t nanos(uint64_t ticks) {
 mach_timebase_info_data_t t; mach_timebase_info(&t);
 return (uint64_t)((long double)ticks * t.numer / t.denom);
}
int am_process_identity(int32_t pid, uint64_t *start) {
 struct proc_bsdinfo b = {0}; *start = 0;
 if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &b, sizeof(b)) != sizeof(b)) return failure();
 *start = b.pbi_start_tvsec * 1000000 + b.pbi_start_tvusec; return 0;
}
int am_process_info(int32_t pid, AMProcessInfo *o) {
 memset(o, 0, sizeof(*o)); struct proc_bsdinfo b = {0};
 if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &b, sizeof(b)) != sizeof(b)) return failure();
 o->start=b.pbi_start_tvsec*1000000+b.pbi_start_tvusec;
 o->uid=b.pbi_uid; o->gid=b.pbi_gid; o->realUID=b.pbi_ruid; o->realGID=b.pbi_rgid;
 o->savedUID=b.pbi_svuid; o->savedGID=b.pbi_svgid; o->parent=b.pbi_ppid; o->group=b.pbi_pgid;
 o->nice=b.pbi_nice; o->flags=b.pbi_flags; o->status=b.pbi_status; o->fileCount=b.pbi_nfiles;
 struct proc_taskinfo t={0};
 if (proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &t, sizeof(t)) == sizeof(t)) {
  o->userNS=nanos(t.pti_total_user); o->systemNS=nanos(t.pti_total_system);
  o->virtualBytes=t.pti_virtual_size; o->residentBytes=t.pti_resident_size;
  o->priority=t.pti_priority; o->runningThreads=t.pti_numrunning; o->policy=t.pti_policy;
  o->faults=t.pti_faults; o->pageins=t.pti_pageins; o->cowFaults=t.pti_cow_faults;
  o->messagesSent=t.pti_messages_sent; o->messagesReceived=t.pti_messages_received;
  o->machCalls=t.pti_syscalls_mach; o->unixCalls=t.pti_syscalls_unix; o->switches=t.pti_csw;
 } else o->taskError=failure();
 if (proc_pidpath(pid, o->executable, sizeof(o->executable)) <= 0) o->pathError=failure();
 struct proc_vnodepathinfo v={0};
 if (proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &v, sizeof(v)) == sizeof(v)) {
  strlcpy(o->cwd,v.pvi_cdir.vip_path,sizeof(o->cwd)); strlcpy(o->root,v.pvi_rdir.vip_path,sizeof(o->root));
 }
 return 0;
}
int am_process_threads(int32_t pid, AMThread *out, int capacity, int *count, int *truncated) {
 *count=0; *truncated=0;
 uint64_t *ids=calloc(capacity+1,sizeof(uint64_t)); if (!ids) return ENOMEM;
 // Optional XNU flavor from bsd/sys/proc_info_private.h. Older kernels fall back
 // to cthread handles, which the UI labels separately from unique thread IDs.
 int unique=1;
 int n=proc_pidinfo(pid,28 /* PROC_PIDLISTTHREADIDS */,0,ids,(capacity+1)*sizeof(uint64_t));
 if(n<=0 && (errno==EINVAL || errno==ENOTSUP)) {
  unique=0;n=proc_pidinfo(pid,PROC_PIDLISTTHREADS,0,ids,(capacity+1)*sizeof(uint64_t));
 }
 if (n<=0) { free(ids); return failure(); }
 n/=sizeof(uint64_t); *truncated=n>capacity; if(n>capacity)n=capacity;
 for(int i=0;i<n;i++) {
  AMThread *o=&out[i]; memset(o,0,sizeof(*o)); o->id=ids[i];o->uniqueID=unique;
  struct proc_threadinfo t={0};
  if(proc_pidinfo(pid,unique?PROC_PIDTHREADID64INFO:PROC_PIDTHREADINFO,ids[i],&t,sizeof(t))==sizeof(t)) {
   o->userNS=t.pth_user_time;o->systemNS=t.pth_system_time;o->cpuScaled=t.pth_cpu_usage;
   o->state=t.pth_run_state;o->policy=t.pth_policy;o->priority=t.pth_curpri;
   o->basePriority=t.pth_priority;o->maxPriority=t.pth_maxpriority;o->sleepSeconds=t.pth_sleep_time;
   o->flags=t.pth_flags;strlcpy(o->name,t.pth_name,sizeof(o->name));
  } else o->error=failure();
 }
 free(ids);*count=n;return 0;
}
static void endpoint(const struct in_sockinfo *s, int local, char *out, size_t size) {
 char host[INET6_ADDRSTRLEN]={0}; int ipv4=(s->insi_vflag & INI_IPV4)!=0;
 const void *addr=local ? (ipv4?(const void *)&s->insi_laddr.ina_46.i46a_addr4:(const void *)&s->insi_laddr.ina_6)
 : (ipv4?(const void *)&s->insi_faddr.ina_46.i46a_addr4:(const void *)&s->insi_faddr.ina_6);
 if(!inet_ntop(ipv4?AF_INET:AF_INET6,addr,host,sizeof(host))) strlcpy(host,"?",sizeof(host));
 snprintf(out,size,ipv4?"%s:%u":"[%s]:%u",host,ntohs((uint16_t)(local?s->insi_lport:s->insi_fport)));
}
int am_process_files(int32_t pid, AMFile *out, int capacity, int *count, int *truncated) {
 *count=0;*truncated=0;
 struct proc_fdinfo *fds=calloc(capacity+1,sizeof(*fds));if(!fds)return ENOMEM;
 errno=0;int n=proc_pidinfo(pid,PROC_PIDLISTFDS,0,fds,(capacity+1)*sizeof(*fds));
 if(n<0 || (n==0 && errno)) {free(fds);return failure();}
 n/=sizeof(*fds);*truncated=n>capacity;if(n>capacity)n=capacity;
 for(int i=0;i<n;i++) {
  AMFile *o=&out[i];memset(o,0,sizeof(*o));o->fd=fds[i].proc_fd;o->type=fds[i].proc_fdtype;o->tcpState=-1;
  struct proc_fileinfo *fi=NULL;
  union {struct vnode_fdinfowithpath vnode;struct socket_fdinfo socket;struct pipe_fdinfo pipe;
   struct kqueue_fdinfo kqueue;struct psem_fdinfo sem;struct pshm_fdinfo shm;} v={0};
  int flavor=0,size=0;
  switch(o->type) {
   case PROX_FDTYPE_VNODE:flavor=PROC_PIDFDVNODEPATHINFO;size=sizeof(v.vnode);break;
   case PROX_FDTYPE_SOCKET:flavor=PROC_PIDFDSOCKETINFO;size=sizeof(v.socket);break;
   case PROX_FDTYPE_PIPE:flavor=PROC_PIDFDPIPEINFO;size=sizeof(v.pipe);break;
   case PROX_FDTYPE_KQUEUE:flavor=PROC_PIDFDKQUEUEINFO;size=sizeof(v.kqueue);break;
   case PROX_FDTYPE_PSEM:flavor=PROC_PIDFDPSEMINFO;size=sizeof(v.sem);break;
   case PROX_FDTYPE_PSHM:flavor=PROC_PIDFDPSHMINFO;size=sizeof(v.shm);break;
   default:o->error=ENOTSUP;continue;
  }
  if(proc_pidfdinfo(pid,o->fd,flavor,&v,size)!=size){o->error=failure();continue;}
  fi=(struct proc_fileinfo *)&v;o->flags=fi->fi_openflags;o->offset=fi->fi_offset;
  const struct vinfo_stat *st=NULL;
  if(o->type==PROX_FDTYPE_VNODE){st=&v.vnode.pvip.vip_vi.vi_stat;strlcpy(o->path,v.vnode.pvip.vip_path,sizeof(o->path));}
  if(o->type==PROX_FDTYPE_PIPE)st=&v.pipe.pipeinfo.pipe_stat;
  if(o->type==PROX_FDTYPE_KQUEUE)st=&v.kqueue.kqueueinfo.kq_stat;
  if(o->type==PROX_FDTYPE_PSEM){st=&v.sem.pseminfo.psem_stat;strlcpy(o->path,v.sem.pseminfo.psem_name,sizeof(o->path));}
  if(o->type==PROX_FDTYPE_PSHM){st=&v.shm.pshminfo.pshm_stat;strlcpy(o->path,v.shm.pshminfo.pshm_name,sizeof(o->path));}
  if(o->type==PROX_FDTYPE_SOCKET){
   const struct socket_info *s=&v.socket.psi;st=&s->soi_stat;o->family=s->soi_family;o->protocol=s->soi_protocol;o->socketType=s->soi_type;
   o->receiveQueue=s->soi_rcv.sbi_cc;o->sendQueue=s->soi_snd.sbi_cc;
   if(s->soi_kind==SOCKINFO_TCP){o->tcpState=s->soi_proto.pri_tcp.tcpsi_state;endpoint(&s->soi_proto.pri_tcp.tcpsi_ini,1,o->local,sizeof(o->local));endpoint(&s->soi_proto.pri_tcp.tcpsi_ini,0,o->remote,sizeof(o->remote));}
   else if(s->soi_kind==SOCKINFO_IN){endpoint(&s->soi_proto.pri_in,1,o->local,sizeof(o->local));endpoint(&s->soi_proto.pri_in,0,o->remote,sizeof(o->remote));}
   else if(s->soi_kind==SOCKINFO_UN){strlcpy(o->local,s->soi_proto.pri_un.unsi_addr.ua_sun.sun_path,sizeof(o->local));strlcpy(o->remote,s->soi_proto.pri_un.unsi_caddr.ua_sun.sun_path,sizeof(o->remote));}
   else if(s->soi_kind==SOCKINFO_KERN_CTL)strlcpy(o->local,s->soi_proto.pri_kern_ctl.kcsi_name,sizeof(o->local));
  }
  if(st){o->size=st->vst_size<0?0:st->vst_size;o->inode=st->vst_ino;o->device=st->vst_dev;o->mode=st->vst_mode;}
 }
 free(fds);*count=n;return 0;
}
int am_process_regions(int32_t pid, AMRegion *out, int capacity, int *count, int *truncated) {
 *count=0;*truncated=0;uint64_t address=0;
 for(int i=0;i<capacity;i++) {
  struct proc_regionwithpathinfo v={0};errno=0;
  if(proc_pidinfo(pid,PROC_PIDREGIONPATHINFO,address,&v,sizeof(v))!=sizeof(v)) return *count && errno==EINVAL ? 0 : failure();
  struct proc_regioninfo *r=&v.prp_prinfo;
  if(!r->pri_size || r->pri_address<address || r->pri_address>UINT64_MAX-r->pri_size)return EOVERFLOW;
  AMRegion *o=&out[(*count)++];memset(o,0,sizeof(*o));
  o->address=r->pri_address;o->size=r->pri_size;o->offset=r->pri_offset;
  o->resident=(uint64_t)r->pri_pages_resident*vm_kernel_page_size;
  o->privateResident=(uint64_t)r->pri_private_pages_resident*vm_kernel_page_size;
  o->sharedResident=(uint64_t)r->pri_shared_pages_resident*vm_kernel_page_size;
  o->swapped=(uint64_t)r->pri_pages_swapped_out*vm_kernel_page_size;
  o->dirty=(uint64_t)r->pri_pages_dirtied*vm_kernel_page_size;
  o->protection=r->pri_protection;o->maxProtection=r->pri_max_protection;o->shareMode=r->pri_share_mode;
  o->tag=r->pri_user_tag;o->references=r->pri_ref_count;o->object=r->pri_obj_id;
  strlcpy(o->path,v.prp_vip.vip_path,sizeof(o->path));address=r->pri_address+r->pri_size;
 }
 *truncated=1;return 0;
}
int am_process_ports(int32_t pid, AMPort *out, int capacity, int *count, int *truncated) {
 *count=0;*truncated=0;mach_port_t task=MACH_PORT_NULL;
 kern_return_t kr=KERN_SUCCESS;
 if(pid==getpid())task=mach_task_self();
 else {kr=task_name_for_pid(mach_task_self(),pid,&task);if(kr!=KERN_SUCCESS)return kr;}
 mach_port_name_array_t names=NULL;mach_port_type_array_t types=NULL;mach_msg_type_number_t nc=0,tc=0;
 kr=mach_port_names(task,&names,&nc,&types,&tc);
 if(kr==KERN_SUCCESS){int n=(int)(nc<tc?nc:tc);*truncated=n>capacity;if(n>capacity)n=capacity;
  for(int i=0;i<n;i++)out[i]=(AMPort){names[i],types[i]};*count=n;
 }
 if(names)vm_deallocate(mach_task_self(),(vm_address_t)names,nc*sizeof(*names));
 if(types)vm_deallocate(mach_task_self(),(vm_address_t)types,tc*sizeof(*types));
 if(pid!=getpid())mach_port_deallocate(mach_task_self(),task);return kr;
}
int am_process_resources(int32_t pid, AMResourceCounter *out, int capacity, int *count) {
 *count=0;struct rusage_info_v4 r={0};
 if(proc_pid_rusage(pid,RUSAGE_INFO_V4,(rusage_info_t *)&r)!=0)return failure();
 #define COUNTER(field,label,units) do { if(*count<capacity) { AMResourceCounter *c=&out[(*count)++];c->value=r.field;strlcpy(c->name,label,sizeof(c->name));strlcpy(c->unit,units,sizeof(c->unit)); } } while(0)
 COUNTER(ri_wired_size,"Wired memory","bytes");
 COUNTER(ri_lifetime_max_phys_footprint,"Peak physical footprint","bytes");
 COUNTER(ri_interval_max_phys_footprint,"Interval peak footprint","bytes");
 COUNTER(ri_logical_writes,"Logical writes","bytes");
 COUNTER(ri_instructions,"Instructions","count");COUNTER(ri_cycles,"CPU cycles","count");
 COUNTER(ri_pkg_idle_wkups,"Package idle wake-ups","count");COUNTER(ri_interrupt_wkups,"Interrupt wake-ups","count");
 COUNTER(ri_child_pageins,"Child page-ins","count");COUNTER(ri_child_pkg_idle_wkups,"Child package wake-ups","count");COUNTER(ri_child_interrupt_wkups,"Child interrupt wake-ups","count");
 COUNTER(ri_cpu_time_qos_default,"QoS default CPU time","Mach ticks");
 COUNTER(ri_cpu_time_qos_maintenance,"QoS maintenance CPU time","Mach ticks");
 COUNTER(ri_cpu_time_qos_background,"QoS background CPU time","Mach ticks");
 COUNTER(ri_cpu_time_qos_utility,"QoS utility CPU time","Mach ticks");
 COUNTER(ri_cpu_time_qos_legacy,"QoS legacy CPU time","Mach ticks");
 COUNTER(ri_cpu_time_qos_user_initiated,"QoS user initiated time","Mach ticks");
 COUNTER(ri_cpu_time_qos_user_interactive,"QoS user interactive time","Mach ticks");
 COUNTER(ri_billed_system_time,"Billed system time","Mach ticks");COUNTER(ri_serviced_system_time,"Serviced system time","Mach ticks");
 COUNTER(ri_runnable_time,"Runnable time","Mach ticks");
 COUNTER(ri_child_user_time,"Child user CPU time","Mach ticks");COUNTER(ri_child_system_time,"Child system CPU time","Mach ticks");
 COUNTER(ri_billed_energy,"Billed energy counter","raw units");COUNTER(ri_serviced_energy,"Serviced energy counter","raw units");
 #undef COUNTER
 return 0;
}
int am_process_fileports(int32_t pid, AMFilePort *out, int capacity, int *count, int *truncated) {
 *count=0;*truncated=0;
 if(capacity<=0 || capacity>65536)return EINVAL;
 struct proc_fileportinfo *ports=calloc(capacity+1,sizeof(*ports));if(!ports)return ENOMEM;
 errno=0;int n=proc_pidinfo(pid,PROC_PIDLISTFILEPORTS,0,ports,(capacity+1)*sizeof(*ports));
 if(n<0 || (n==0 && errno)){free(ports);return failure();}
 n/=sizeof(*ports);*truncated=n>capacity;if(n>capacity)n=capacity;
 for(int i=0;i<n;i++)out[i]=(AMFilePort){ports[i].proc_fileport,ports[i].proc_fdtype};
 *count=n;free(ports);return 0;
}
