/*
 * sort_rules — aturan klasifikasi sampah berbasis sensor (rule-based).
 *
 * Murni C tanpa Arduino, sehingga bisa diuji di PC:
 *   gcc -std=c99 -Wall -Wextra -o test_sort_rules firmware/test/test_sort_rules.c firmware/esp32/PilahPintar_ESP32/sort_rules.c
 *
 * Urutan aturan (aturan pertama yang cocok dipakai):
 *   1. Induktif aktif                                     -> logam
 *   2. Soil moisture basah                                -> organik
 *   3. Tinggi >= bottle_min_height_mm:
 *        pantulan >= styrofoam_min_signal (jika aktif)    -> anorganik (styrofoam)
 *        selain itu                                       -> recyclable (botol)
 *   4. Kapasitif aktif (jika capacitive_means_organic)    -> organik
 *   5. Pendek & pantulan >= paper_min_signal (jika aktif) -> recyclable (kertas)
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
  bool inductive;     /* sensor induktif pernah aktif */
  bool capacitive;    /* sensor kapasitif pernah aktif */
  int soil_min_raw;   /* ADC soil moisture terendah (makin kecil makin basah); -1 = tidak ada */
  int height_mm;      /* tinggi maksimum terukur VL53L1X; 0 = tidak terlihat */
  float signal_mcps;  /* kekuatan pantulan maksimum VL53L1X (MCPS) */
} sr_features_t;

/* Ambang batas. Nilai 0 pada *_min_signal_mcps mematikan aturan tersebut. */
typedef struct {
  int soil_wet_raw;
  bool capacitive_means_organic;
  int bottle_min_height_mm;
  float styrofoam_min_signal_mcps;
  int paper_max_height_mm;
  float paper_min_signal_mcps;
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
