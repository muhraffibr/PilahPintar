/* pp_protocol — lihat pp_protocol.h. File ini IDENTIK di ESP32 dan STM32. */
#include "pp_protocol.h"

#include <string.h>

static const char HEX_DIGITS[] = "0123456789ABCDEF";

void pp_reader_init(pp_reader_t *r) {
  r->len = 0;
  r->in_frame = false;
  r->overflow = false;
}

uint8_t pp_checksum(const char *s, size_t n) {
  uint8_t cs = 0;
  for (size_t i = 0; i < n; i++) cs ^= (uint8_t)s[i];
  return cs;
}

static int hex_value(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  return -1;
}

static bool copy_token(char *dst, const char *src, size_t n) {
  if (n >= PP_MAX_TOKEN) return false;
  memcpy(dst, src, n);
  dst[n] = '\0';
  return true;
}

pp_result_t pp_parse_body(const char *body, size_t len, pp_msg_t *out) {
  /* Pisahkan checksum bila ada. */
  size_t data_len = len;
  for (size_t i = 0; i < len; i++) {
    if (body[i] == '*') {
      data_len = i;
      break;
    }
  }
  if (data_len < len) {
    if (len - data_len != 3) return PP_ERR_FORMAT; /* harus "*hh" */
    int hi = hex_value(body[data_len + 1]);
    int lo = hex_value(body[data_len + 2]);
    if (hi < 0 || lo < 0) return PP_ERR_FORMAT;
    if (pp_checksum(body, data_len) != (uint8_t)((hi << 4) | lo)) {
      return PP_ERR_CHECKSUM;
    }
  } else if (!PP_ALLOW_NO_CHECKSUM) {
    return PP_ERR_CHECKSUM;
  }

  memset(out, 0, sizeof(*out));
  size_t start = 0;
  int token = 0; /* 0 = tipe, 1.. = field */
  for (size_t i = 0; i <= data_len; i++) {
    if (i == data_len || body[i] == ',') {
      size_t n = i - start;
      if (token == 0) {
        if (n == 0 || !copy_token(out->type, body + start, n)) return PP_ERR_FORMAT;
      } else {
        if (token > PP_MAX_FIELDS) return PP_ERR_FORMAT;
        if (!copy_token(out->fields[token - 1], body + start, n)) return PP_ERR_FORMAT;
        out->nfields = (uint8_t)token;
      }
      token++;
      start = i + 1;
    } else if (body[i] == '$') {
      return PP_ERR_FORMAT;
    }
  }
  return PP_MSG;
}

pp_result_t pp_reader_feed(pp_reader_t *r, char c, pp_msg_t *out) {
  if (c == '$') { /* awal frame baru: buang sisa frame sebelumnya */
    r->len = 0;
    r->in_frame = true;
    r->overflow = false;
    return PP_NONE;
  }
  if (!r->in_frame) return PP_NONE; /* abaikan noise di luar frame */
  if (c == '\r') return PP_NONE;
  if (c == '\n') {
    r->in_frame = false;
    if (r->overflow) return PP_ERR_OVERFLOW;
    r->buf[r->len] = '\0';
    return pp_parse_body(r->buf, r->len, out);
  }
  if (r->len >= PP_MAX_LINE) {
    r->overflow = true;
    return PP_NONE;
  }
  r->buf[r->len++] = c;
  return PP_NONE;
}

size_t pp_build(char *out, size_t cap, const char *type,
                const char *const *fields, uint8_t nfields) {
  size_t n = 0;
  if (cap < 2) return 0;
  out[n++] = '$';
  const size_t body_start = n;

  size_t tlen = strlen(type);
  if (n + tlen >= cap) return 0;
  memcpy(out + n, type, tlen);
  n += tlen;

  for (uint8_t i = 0; i < nfields; i++) {
    size_t flen = strlen(fields[i]);
    if (n + 1 + flen >= cap) return 0;
    out[n++] = ',';
    memcpy(out + n, fields[i], flen);
    n += flen;
  }

  uint8_t cs = pp_checksum(out + body_start, n - body_start);
  if (n + 5 > cap) return 0; /* "*hh\n" + '\0' */
  out[n++] = '*';
  out[n++] = HEX_DIGITS[cs >> 4];
  out[n++] = HEX_DIGITS[cs & 0x0F];
  out[n++] = '\n';
  out[n] = '\0';
  return n;
}

bool pp_is(const pp_msg_t *msg, const char *type) {
  return strcmp(msg->type, type) == 0;
}

const char *pp_field(const pp_msg_t *msg, uint8_t i) {
  return i < msg->nfields ? msg->fields[i] : "";
}
