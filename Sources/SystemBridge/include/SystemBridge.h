#include <stdint.h>
typedef struct { int32_t pid, ppid, accessible, ioAccessible, translated; uint32_t uid, threads; uint64_t start, cpu, resident, footprint, read, written, wakeups; char name[1024]; } AMProcess;
typedef struct { uint64_t user, system, idle, physical, free, active, inactive, wired, compressed, swap, received, sent, packetsIn, packetsOut; int pressure, battery, charging, externalPower; } AMSystem;
int am_processes(AMProcess *output, int capacity);
void am_system(AMSystem *output);
typedef struct { int vmAccessible; uint64_t purgeable, compressed; } AMMemoryDetails;
void am_memory_details(int32_t pid, AMMemoryDetails *output);
#include "ProcessDiagnostics.h"

#include "CPUDetails.h"
