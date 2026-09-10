#ifndef AM_CPU_DETAILS_H
#define AM_CPU_DETAILS_H
#include <stdint.h>
typedef struct { int32_t slot, identified; uint32_t user, system, idle, nice; } AMCPUTicks;
// Returns Mach error codes. Caller supplies a bounded output buffer.
int am_cpu_ticks(AMCPUTicks *output, int capacity, int *count, int *truncated);
#endif
