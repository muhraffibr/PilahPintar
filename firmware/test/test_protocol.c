/*
 * Uji unit pp_protocol di PC (tanpa board).
 *
 *   gcc -std=c99 -Wall -Wextra -o test_protocol test_protocol.c ../esp32/PilahPintar_ESP32/pp_protocol.c
 *   ./test_protocol
 */
#include <stdio.h>
#include <string.h>

#include "../esp32/PilahPintar_ESP32/pp_protocol.h"

static int failures = 0;

#define CHECK(cond)                                                   \
  do {                                                                \
    if (!(cond)) {                                                    \
      printf("GAGAL  %s:%d  %s\n", __FILE__, __LINE__, #cond);         \
      failures++;                                                     \
    }                                                                 \
  } while (0)

/* Masukkan string byte demi byte; kembalikan hasil terakhir yang bukan PP_NONE. */
static pp_result_t feed_all(pp_reader_t *r, const char *s, pp_msg_t *msg) {
  pp_result_t last = PP_NONE;
  for (; *s; s++) {
    pp_result_t res = pp_reader_feed(r, *s, msg);
    if (res != PP_NONE) last = res;
  }
  return last;
}

static void test_build_and_parse_roundtrip(void) {
  char buf[64];
  const char *f[] = {"logam", "OK", "Kaleng minuman"};
  size_t n = pp_build(buf, sizeof buf, "SRT", f, 3);
  CHECK(n == strlen(buf));
  CHECK(buf[0] == '$' && buf[n - 1] == '\n');

  pp_reader_t r;
  pp_msg_t m;
  pp_reader_init(&r);
  CHECK(feed_all(&r, buf, &m) == PP_MSG);
  CHECK(pp_is(&m, "SRT"));
  CHECK(m.nfields == 3);
  CHECK(strcmp(pp_field(&m, 0), "logam") == 0);
  CHECK(strcmp(pp_field(&m, 2), "Kaleng minuman") == 0);
  CHECK(strcmp(pp_field(&m, 5), "") == 0);
}

static void test_known_checksum(void) {
  /* XOR dari "CMD,START" = 0x26 -> frame "$CMD,START*26\n" */
  char buf[32];
  const char *f[] = {"START"};
  pp_build(buf, sizeof buf, "CMD", f, 1);
  CHECK(strcmp(buf, "$CMD,START*26\n") == 0);
}

static void test_without_checksum_and_crlf(void) {
  pp_reader_t r;
  pp_msg_t m;
  pp_reader_init(&r);
  CHECK(feed_all(&r, "$STS,RUN,0\r\n", &m) == PP_MSG);
  CHECK(pp_is(&m, "STS"));
  CHECK(strcmp(pp_field(&m, 0), "RUN") == 0);
  CHECK(strcmp(pp_field(&m, 1), "0") == 0);
}

static void test_bad_checksum_rejected(void) {
  pp_reader_t r;
  pp_msg_t m;
  pp_reader_init(&r);
  CHECK(feed_all(&r, "$CMD,START*00\n", &m) == PP_ERR_CHECKSUM);
  /* reader tetap bisa menerima frame berikutnya */
  CHECK(feed_all(&r, "$CMD,STOP\n", &m) == PP_MSG);
  CHECK(strcmp(pp_field(&m, 0), "STOP") == 0);
}

static void test_resync_on_noise(void) {
  pp_reader_t r;
  pp_msg_t m;
  pp_reader_init(&r);
  /* sampah di luar frame & frame terpotong lalu '$' baru */
  CHECK(feed_all(&r, "xx\n$STS,RU$PING\n", &m) == PP_MSG);
  CHECK(pp_is(&m, "PING"));
  CHECK(m.nfields == 0);
}

static void test_overflow(void) {
  pp_reader_t r;
  pp_msg_t m;
  char longline[200];
  memset(longline, 'A', sizeof longline);
  longline[0] = '$';
  longline[sizeof longline - 2] = '\n';
  longline[sizeof longline - 1] = '\0';
  pp_reader_init(&r);
  CHECK(feed_all(&r, longline, &m) == PP_ERR_OVERFLOW);
  CHECK(feed_all(&r, "$PING\n", &m) == PP_MSG);
}

static void test_format_errors(void) {
  pp_msg_t m;
  CHECK(pp_parse_body("", 0, &m) == PP_ERR_FORMAT);                 /* tipe kosong */
  CHECK(pp_parse_body("A,1,2,3,4,5,6,7", 15, &m) == PP_ERR_FORMAT); /* > 6 field */
  CHECK(pp_parse_body("CMD*1", 5, &m) == PP_ERR_FORMAT);             /* checksum 1 digit */
  CHECK(pp_parse_body("CMD,*ZZ", 7, &m) == PP_ERR_FORMAT);           /* bukan hex */
}

static void test_empty_field_allowed(void) {
  pp_msg_t m;
  CHECK(pp_parse_body("NAK,START,", 10, &m) == PP_MSG);
  CHECK(m.nfields == 2);
  CHECK(strcmp(pp_field(&m, 1), "") == 0);
}

static void test_build_buffer_too_small(void) {
  char buf[8];
  const char *f[] = {"START"};
  CHECK(pp_build(buf, sizeof buf, "CMD", f, 1) == 0);
}

int main(void) {
  test_build_and_parse_roundtrip();
  test_known_checksum();
  test_without_checksum_and_crlf();
  test_bad_checksum_rejected();
  test_resync_on_noise();
  test_overflow();
  test_format_errors();
  test_empty_field_allowed();
  test_build_buffer_too_small();
  if (failures == 0) {
    printf("Semua tes pp_protocol lulus.\n");
    return 0;
  }
  printf("%d tes gagal.\n", failures);
  return 1;
}
