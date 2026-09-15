#include "smc.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_WRITE_BYTES 6
#define SMC_CMD_READ_INDEX 8
#define SMC_CMD_READ_KEYINFO 9

typedef struct { uint32_t dataSize; uint32_t dataType; uint8_t dataAttributes; } SMCKeyInfo;
typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimit;
typedef struct {
  uint32_t key; SMCVersion vers; SMCPLimit pLimit; SMCKeyInfo keyInfo;
  uint8_t result, status, data8; uint32_t data32; uint8_t bytes[32];
} SMCKeyData;

static io_connect_t conn = 0;

static uint32_t key4(const char *k) {
  return ((uint32_t)k[0] << 24) | ((uint32_t)k[1] << 16) | ((uint32_t)k[2] << 8) | (uint32_t)k[3];
}

static void key_str(uint32_t k, char out[5]) {
  out[0] = (k >> 24) & 0xff; out[1] = (k >> 16) & 0xff; out[2] = (k >> 8) & 0xff; out[3] = k & 0xff; out[4] = 0;
}

static int call(SMCKeyData *in, SMCKeyData *out) {
  size_t sz = sizeof(SMCKeyData);
  if (IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, in, sz, out, &sz) != KERN_SUCCESS) return -1;
  return out->result == 0 ? 0 : -1;
}

int smc_open(void) {
  if (conn) return 0;
  io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
  if (!svc) return -1;
  kern_return_t r = IOServiceOpen(svc, mach_task_self(), 0, &conn);
  IOObjectRelease(svc);
  return r == KERN_SUCCESS ? 0 : -1;
}

void smc_close(void) {
  if (conn) IOServiceClose(conn);
  conn = 0;
}

int smc_key_count(uint32_t *count) {
  uint8_t b[32]; uint32_t n;
  if (smc_read_bytes("#KEY", b, &n) || n != 4) return -1;
  *count = ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | b[3];
  return 0;
}

int smc_key_at_index(uint32_t index, char key[5]) {
  SMCKeyData in = {0}, out = {0};
  in.data8 = SMC_CMD_READ_INDEX; in.data32 = index;
  if (call(&in, &out)) return -1;
  key_str(out.key, key);
  return 0;
}

int smc_key_info(const char *key, uint32_t *size, char type[5]) {
  SMCKeyData in = {0}, out = {0};
  in.key = key4(key); in.data8 = SMC_CMD_READ_KEYINFO;
  if (call(&in, &out)) return -1;
  *size = out.keyInfo.dataSize;
  key_str(out.keyInfo.dataType, type);
  return 0;
}

int smc_read_bytes(const char *key, uint8_t *buf, uint32_t *len) {
  uint32_t size; char type[5];
  if (smc_key_info(key, &size, type) || size > 32) return -1;
  SMCKeyData in = {0}, out = {0};
  in.key = key4(key); in.keyInfo.dataSize = size; in.data8 = SMC_CMD_READ_BYTES;
  if (call(&in, &out)) return -1;
  memcpy(buf, out.bytes, size); *len = size;
  return 0;
}

int smc_write_bytes(const char *key, const uint8_t *buf, uint32_t len) {
  if (len > 32) return -1;
  SMCKeyData in = {0}, out = {0};
  in.key = key4(key); in.keyInfo.dataSize = len; in.data8 = SMC_CMD_WRITE_BYTES;
  memcpy(in.bytes, buf, len);
  return call(&in, &out);
}

int smc_read_float(const char *key, float *out) {
  uint8_t b[32]; uint32_t n;
  if (smc_read_bytes(key, b, &n) || n != 4) return -1;
  memcpy(out, b, 4);
  return 0;
}

int smc_write_float(const char *key, float value) {
  uint8_t b[4]; memcpy(b, &value, 4);
  return smc_write_bytes(key, b, 4);
}

int smc_read_u8(const char *key, uint8_t *out) {
  uint8_t b[32]; uint32_t n;
  if (smc_read_bytes(key, b, &n) || n != 1) return -1;
  *out = b[0];
  return 0;
}

int smc_write_u8(const char *key, uint8_t value) {
  return smc_write_bytes(key, &value, 1);
}
