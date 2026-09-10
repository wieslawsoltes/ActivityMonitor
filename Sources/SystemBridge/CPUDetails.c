#include "CPUDetails.h"
#include <mach/mach.h>
#include <mach/processor_info.h>
#include <string.h>

int am_cpu_ticks(AMCPUTicks *output, int capacity, int *count, int *truncated) {
 if (!count || !truncated) return KERN_INVALID_ARGUMENT;
 *count = 0; *truncated = 0;
 if (!output || capacity < 1 || capacity > 4096) return KERN_INVALID_ARGUMENT;
 processor_info_array_t load = NULL, basic = NULL;
 mach_msg_type_number_t loadSize = 0, basicSize = 0;
 natural_t cpus = 0, basicCPUs = 0;
 host_t host = mach_host_self();
 kern_return_t result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpus, &load, &loadSize);
 if (result != KERN_SUCCESS) { mach_port_deallocate(mach_task_self(), host); return result; }
 kern_return_t basicResult = host_processor_info(host, PROCESSOR_BASIC_INFO, &basicCPUs, &basic, &basicSize);
 mach_port_deallocate(mach_task_self(), host);
 if (loadSize < cpus * PROCESSOR_CPU_LOAD_INFO_COUNT) { result = KERN_FAILURE; goto cleanup; }
 int identified = basicResult == KERN_SUCCESS && cpus == basicCPUs && basicSize >= cpus * PROCESSOR_BASIC_INFO_COUNT;
 *truncated = cpus > (natural_t)capacity;
 *count = cpus < (natural_t)capacity ? (int)cpus : capacity;
 for (int i = 0; i < *count; i++) {
  processor_cpu_load_info_t row = (processor_cpu_load_info_t)(load + i * PROCESSOR_CPU_LOAD_INFO_COUNT);
  memset(&output[i], 0, sizeof(output[i]));
  output[i].slot = identified ? ((processor_basic_info_t)(basic + i * PROCESSOR_BASIC_INFO_COUNT))->slot_num : i;
  output[i].identified = identified;
  output[i].user = row->cpu_ticks[CPU_STATE_USER]; output[i].system = row->cpu_ticks[CPU_STATE_SYSTEM];
  output[i].idle = row->cpu_ticks[CPU_STATE_IDLE]; output[i].nice = row->cpu_ticks[CPU_STATE_NICE];
 }
cleanup:
 if (load) vm_deallocate(mach_task_self(), (vm_address_t)load, loadSize * sizeof(integer_t));
 if (basic) vm_deallocate(mach_task_self(), (vm_address_t)basic, basicSize * sizeof(integer_t));
 return result;
}
