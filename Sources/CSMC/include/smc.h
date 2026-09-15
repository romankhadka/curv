#ifndef SMC_H
#define SMC_H
#include <stdint.h>

// Thin C bridge to AppleSMC. Reads work as any user; writes need root.
int smc_open(void);
void smc_close(void);
int smc_key_count(uint32_t *count);
int smc_key_at_index(uint32_t index, char key[5]);
int smc_key_info(const char *key, uint32_t *size, char type[5]);
int smc_read_bytes(const char *key, uint8_t *buf, uint32_t *len);
int smc_write_bytes(const char *key, const uint8_t *buf, uint32_t len);
int smc_read_float(const char *key, float *out);
int smc_write_float(const char *key, float value);
int smc_read_u8(const char *key, uint8_t *out);
int smc_write_u8(const char *key, uint8_t value);

#endif
