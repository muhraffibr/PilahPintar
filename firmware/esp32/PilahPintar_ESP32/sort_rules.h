/*
 * sort_rules — aturan klasifikasi sampah berbasis sensor (rule-based).
 *
 * Murni C tanpa Arduino, sehingga bisa diuji di PC:
 *   gcc -std=c99 -Wall -Wextra -o test_sort_rules firmware/test/test_sort_rules.c firmware/esp32/PilahPintar_ESP32/sort_rules.c
 *
 * Sensor (rancangan CD 3): Sharp IR GP2Y0A21 (tinggi), proximity induktif,
 * proximity kapasitif, capacitive soil moisture, raindrop, LDR + laser pointer.
 *
 * Urutan aturan (aturan pertama yang cocok dipakai):
 *   1. Induktif aktif                                     -> logam
 *   2. Soil moisture basah atau raindrop basah            -> organik
 *   3. Tinggi >= bottle_min_height_mm (Sharp IR):
 *        LDR terang & styrofoam_by_bright                 -> anorganik (styrofoam)
 *        selain itu                                       -> recyclable (botol)
 *   4. Kapasitif aktif (jika capacitive_means_organic)    -> organik
 *   5. Pendek & LDR terang & paper_by_bright              -> recyclable (kertas)
 *   6. Selain itu                                         -> anorganik (residu)
 *
 * Sampah yang tidak terbaca sensor apa pun tidak pernah sampai ke sini: ia
 * tidak didorong dan jatuh di ujung sabuk ke tempat sampah anorganik.
 */
#ifndef SORT_RULES_H
#define SORT_RULES_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
  SR_ORGANIK = 0,
  SR_RECYCLABLE,
  SR_LOGAM,
  SR_ANORGANIK,
} sr_category_t;

/* Ciri satu item, dikumpulkan selama item melewati zona sensor. */
typedef struct {
  bool inductive;    /* sensor induktif pernah aktif */
  bool capacitive;   /* sensor kapasitif pernah aktif */
  int soil_min_raw;  /* ADC soil moisture terendah (makin kecil makin basah); -1 = tidak ada */
  bool raindrop;     /* sensor raindrop pernah basah */
  int height_mm;     /* tinggi maksimum terukur Sharp IR; 0 = tidak terlihat */
  bool bright;       /* LDR pernah menerima pantulan laser yang kuat */
} sr_features_t;

typedef struct {
  int soil_wet_raw;
  bool capacitive_means_organic;
  int bottle_min_height_mm;
  bool styrofoam_by_bright; /* aturan styrofoam (butuh LDR terkalibrasi) */
  int paper_max_height_mm;
  bool paper_by_bright;     /* aturan kertas (butuh LDR terkalibrasi) */
} sr_config_t;

typedef struct {
  sr_category_t category;
  const char *reason; /* teks pendek (< 24 karakter), dikirim sebagai "item" */
} sr_result_t;

sr_result_t sr_classify(const sr_features_t *f, const sr_config_t *cfg);

/* Kunci kategori aplikasi & database: "organik", "recyclable", "logam", "anorganik". */
const char *sr_category_key(sr_category_t c);

#ifdef __cplusplus
}
#endif

#endif /* SORT_RULES_H */
