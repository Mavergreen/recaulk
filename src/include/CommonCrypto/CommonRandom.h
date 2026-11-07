#ifndef RECAULK_COMMONCRYPTO_COMMONRANDOM_H
#define RECAULK_COMMONCRYPTO_COMMONRANDOM_H
/* spec: the 11.3 SDK's CommonCrypto/CommonRandom.h, which 10.9's SDK lacks; README.md "Declarations". */
#include <sys/types.h>
#include <CommonCrypto/CommonCryptor.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef CCCryptorStatus CCRNGStatus;
CCRNGStatus CCRandomGenerateBytes(void *bytes, size_t count);
#ifdef __cplusplus
}
#endif
#endif
