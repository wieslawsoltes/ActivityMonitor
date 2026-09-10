#pragma once
#include <stdint.h>
// Every function returns errno (or a Mach error for ports), never synthesized zero data.
typedef struct {
 uint64_t start, userNS, systemNS, virtualBytes, residentBytes;
 uint32_t uid, gid, realUID, realGID, savedUID, savedGID, parent, group, flags, status, fileCount;
 int32_t nice, priority, runningThreads, policy;
 uint32_t faults, pageins, cowFaults, messagesSent, messagesReceived, machCalls, unixCalls, switches;
 int taskError, pathError;
 char executable[4096], cwd[1024], root[1024];
} AMProcessInfo;
typedef struct {
 uint64_t id, userNS, systemNS;
 int32_t cpuScaled, state, policy, priority, basePriority, maxPriority, sleepSeconds, flags, error, uniqueID;
 char name[64];
} AMThread;
typedef struct {
 int32_t fd, type, error, family, protocol, socketType, tcpState;
 uint32_t flags, mode;
 uint64_t size, offset, inode, device, receiveQueue, sendQueue;
 char path[1024], local[1024], remote[1024];
} AMFile;
typedef struct {
 uint64_t address, size, offset, resident, privateResident, sharedResident, swapped, dirty;
 uint32_t protection, maxProtection, shareMode, tag, references, object;
 char path[1024];
} AMRegion;
typedef struct { uint32_t name, rights; } AMPort;
int am_process_identity(int32_t pid, uint64_t *start);
int am_process_info(int32_t pid, AMProcessInfo *out);
int am_process_threads(int32_t pid, AMThread *out, int capacity, int *count, int *truncated);
int am_process_files(int32_t pid, AMFile *out, int capacity, int *count, int *truncated);
int am_process_regions(int32_t pid, AMRegion *out, int capacity, int *count, int *truncated);
int am_process_ports(int32_t pid, AMPort *out, int capacity, int *count, int *truncated);
typedef struct { uint64_t value; char name[64], unit[24]; } AMResourceCounter;
int am_process_resources(int32_t pid, AMResourceCounter *out, int capacity, int *count);
typedef struct { uint32_t name, type; } AMFilePort;
int am_process_fileports(int32_t pid, AMFilePort *out, int capacity, int *count, int *truncated);
