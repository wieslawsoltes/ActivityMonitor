#include "SystemBridge.h"
#include <mach/mach_time.h>
#include <pthread.h>
#include <sys/sysctl.h>

static pthread_once_t once = PTHREAD_ONCE_INIT;
static uint64_t numerator = 1, denominator = 1;

static void initialize_timebase(void) {
 mach_timebase_info_data_t timebase;
 if (mach_timebase_info(&timebase) == KERN_SUCCESS && timebase.denom) {
  numerator = timebase.numer; denominator = timebase.denom;
 }
#if defined(__x86_64__)
 // proc_taskinfo reports host ticks even when Rosetta translates the caller's
 // mach_timebase_info to 1:1. Read the host frequency instead of hard-coding an
 // Apple silicon clock rate. See XNU tests/sched/setitimer.c: abs_to_nanos_host.
 int translated = 0; size_t size = sizeof(translated);
 if (sysctlbyname("sysctl.proc_translated", &translated, &size, NULL, 0) == 0 && translated) {
  uint64_t frequency = 0; size = sizeof(frequency);
  if (sysctlbyname("hw.tbfrequency", &frequency, &size, NULL, 0) == 0 && frequency) {
   numerator = 1000000000; denominator = frequency;
  }
 }
#endif
}

uint64_t am_host_nanoseconds(uint64_t ticks) {
 pthread_once(&once, initialize_timebase);
 __uint128_t result = (__uint128_t)ticks * numerator / denominator;
 return result > UINT64_MAX ? UINT64_MAX : (uint64_t)result;
}
