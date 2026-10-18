/*
 * pp_protocol — protokol UART ESP32 <-> STM32 (PilahPintar)
 *
 * File ini IDENTIK di firmware ESP32 dan STM32. Jika mengubah salah satunya,
 * salin ke yang lain.
 *
 * Format frame (teks, satu baris):
 *
 *     $TIPE,field1,field2*CS\n
 *
 *   - Diawali '$'. Setiap '$' baru membuang sisa frame sebelumnya (resync).
 *   - TIPE dan field dipisah koma; field tidak boleh berisi ',' '*' '$'.
 *   - CS = XOR semua byte di antara '$' dan '*', ditulis 2 digit hex.
 *     Contoh: "$CMD,START*" -> CS dihitung dari "CMD,START".
 *   - Diakhiri '\n' ('\r' diabaikan).
 *   - "*CS" boleh dihilangkan (PP_ALLOW_NO_CHECKSUM) agar mudah diuji
 *     dengan mengetik manual di Serial Monitor. Jika ada, wajib benar.
 */
#ifndef PP_PROTOCOL_H
#define PP_PROTOCOL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PP_MAX_LINE 96      /* panjang maksimum satu frame (tanpa '\n') */
#define PP_MAX_FIELDS 6     /* jumlah field maksimum setelah TIPE */
#define PP_MAX_TOKEN 24     /* panjang maksimum TIPE / satu field + '\0' */

#ifndef PP_ALLOW_NO_CHECKSUM
#define PP_ALLOW_NO_CHECKSUM 1
#endif

typedef struct {
  char type[PP_MAX_TOKEN];
  uint8_t nfields;
  char fields[PP_MAX_FIELDS][PP_MAX_TOKEN];
} pp_msg_t;

typedef enum {
  PP_NONE = 0,         /* byte diterima, frame belum lengkap */
  PP_MSG,              /* frame lengkap & valid -> isi *out */
  PP_ERR_CHECKSUM,     /* checksum salah */
  PP_ERR_FORMAT,       /* format salah (tipe kosong, field terlalu banyak/panjang) */
  PP_ERR_OVERFLOW      /* frame lebih panjang dari PP_MAX_LINE */
} pp_result_t;

typedef struct {
  char buf[PP_MAX_LINE + 1];
  uint8_t len;
  bool in_frame;
  bool overflow;
} pp_reader_t;

void pp_reader_init(pp_reader_t *r);

/* Masukkan satu byte dari UART. Mengembalikan PP_MSG jika satu frame valid
 * selesai diterima (hasilnya di *out). */
pp_result_t pp_reader_feed(pp_reader_t *r, char c, pp_msg_t *out);

/* Parse satu baris tanpa '$' di depan dan tanpa '\n', mis. "CMD,START*4B". */
pp_result_t pp_parse_body(const char *body, size_t len, pp_msg_t *out);

/* XOR semua byte s[0..n-1]. */
uint8_t pp_checksum(const char *s, size_t n);

/* Menyusun frame lengkap ke out, mis. pp_build(buf, sizeof buf, "ACK", f, 1)
 * -> "$ACK,START*hh\n". Mengembalikan panjang (tanpa '\0'), atau 0 jika
 * buffer tidak cukup. */
size_t pp_build(char *out, size_t cap, const char *type,
                const char *const *fields, uint8_t nfields);

/* Helper: true jika msg->type == type. */
bool pp_is(const pp_msg_t *msg, const char *type);

/* Helper: field ke-i atau "" jika tidak ada. */
const char *pp_field(const pp_msg_t *msg, uint8_t i);

#ifdef __cplusplus
}
#endif

#endif /* PP_PROTOCOL_H */
