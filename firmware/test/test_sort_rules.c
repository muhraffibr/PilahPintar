/*
 * Uji unit sort_rules di PC (tanpa board).
 *
 *   gcc -std=c99 -Wall -Wextra -o test_sort_rules test_sort_rules.c ../esp32/PilahPintar_ESP32/sort_rules.c
 *   ./test_sort_rules
 */
#include <stdio.h>
#include <string.h>

#include "../esp32/PilahPintar_ESP32/sort_rules.h"

static int failures = 0;

#define CHECK(cond)                                                   \
  do {                                                                \
    if (!(cond)) {                                                    \
      printf("GAGAL  %s:%d  %s\n", __FILE__, __LINE__, #cond);         \
      failures++;                                                     \
    }                                                                 \
  } while (0)

/* Sama dengan nilai bawaan config.h (aturan LDR masih mati). */
static const sr_config_t kDefault = {2200, true, 45, false, 25, false};

/* Setelah kalibrasi LDR: aturan styrofoam & kertas dinyalakan. */
static const sr_config_t kCalibrated = {2200, true, 45, true, 25, true};

static sr_features_t item(bool ind, bool cap, int soil, bool rain, int height, bool bright) {
  sr_features_t f;
  f.inductive = ind;
  f.capacitive = cap;
  f.soil_min_raw = soil;
  f.raindrop = rain;
  f.height_mm = height;
  f.bright = bright;
  return f;
}

static sr_category_t classify(sr_features_t f, const sr_config_t *cfg) {
  return sr_classify(&f, cfg).category;
}

static void test_metal_wins_over_everything(void) {
  /* Kaleng berisi sisa minuman: induktif + kapasitif + basah + tinggi. */
  sr_features_t f = item(true, true, 1500, true, 60, true);
  sr_result_t r = sr_classify(&f, &kDefault);
  CHECK(r.category == SR_LOGAM);
  CHECK(strcmp(r.reason, "Logam (induktif)") == 0);
}

static void test_wet_is_organic(void) {
  CHECK(classify(item(false, false, 1800, false, 20, false), &kDefault) == SR_ORGANIK);
  CHECK(classify(item(false, false, 2200, false, 0, false), &kDefault) == SR_ORGANIK); /* batas */
  CHECK(classify(item(false, false, 2201, false, 10, false), &kDefault) != SR_ORGANIK);
  CHECK(classify(item(false, false, -1, false, 10, false), &kDefault) == SR_ANORGANIK);
}

static void test_raindrop_is_organic(void) {
  sr_features_t f = item(false, false, 3000, true, 10, false);
  CHECK(classify(f, &kDefault) == SR_ORGANIK);
  CHECK(strcmp(sr_classify(&f, &kDefault).reason, "Organik (raindrop)") == 0);
  /* Botol basah di luar tetap dianggap organik karena aturan basah lebih dulu. */
  CHECK(classify(item(false, false, 3000, true, 60, false), &kDefault) == SR_ORGANIK);
}

static void test_tall_is_bottle_unless_bright(void) {
  CHECK(classify(item(false, false, 3000, false, 45, false), &kDefault) == SR_RECYCLABLE);
  CHECK(classify(item(false, false, 3000, false, 44, false), &kDefault) == SR_ANORGANIK);
  /* Aturan styrofoam mati secara bawaan: benda tinggi & terang tetap botol. */
  CHECK(classify(item(false, false, 3000, false, 80, true), &kDefault) == SR_RECYCLABLE);
  CHECK(classify(item(false, false, 3000, false, 80, true), &kCalibrated) == SR_ANORGANIK);
  CHECK(classify(item(false, false, 3000, false, 80, false), &kCalibrated) == SR_RECYCLABLE);
}

static void test_capacitive_low_item_is_organic(void) {
  CHECK(classify(item(false, true, 3000, false, 20, false), &kDefault) == SR_ORGANIK);
  sr_config_t off = kDefault;
  off.capacitive_means_organic = false;
  CHECK(classify(item(false, true, 3000, false, 20, false), &off) == SR_ANORGANIK);
}

static void test_paper_rule_needs_calibration(void) {
  sr_features_t paper = item(false, false, 3000, false, 15, true);
  CHECK(classify(paper, &kDefault) == SR_ANORGANIK);
  CHECK(classify(paper, &kCalibrated) == SR_RECYCLABLE);
  CHECK(strcmp(sr_classify(&paper, &kCalibrated).reason, "Kertas (terang)") == 0);
  /* Kresek: pendek tapi tidak memantulkan laser -> residu. */
  CHECK(classify(item(false, false, 3000, false, 15, false), &kCalibrated) == SR_ANORGANIK);
  /* Tidak terlihat Sharp IR: tidak boleh dianggap kertas. */
  CHECK(classify(item(false, false, 3000, false, 0, true), &kCalibrated) == SR_ANORGANIK);
}

static void test_category_keys_match_app(void) {
  CHECK(strcmp(sr_category_key(SR_ORGANIK), "organik") == 0);
  CHECK(strcmp(sr_category_key(SR_RECYCLABLE), "recyclable") == 0);
  CHECK(strcmp(sr_category_key(SR_LOGAM), "logam") == 0);
  CHECK(strcmp(sr_category_key(SR_ANORGANIK), "anorganik") == 0);
}

static void test_reasons_fit_item_field(void) {
  /* Field "item" di ESP32 berukuran 24 byte (23 karakter + '\0'). */
  const sr_features_t samples[] = {
      item(true, false, 3000, false, 0, false),  item(false, false, 1000, false, 0, false),
      item(false, false, 3000, true, 0, false),  item(false, false, 3000, false, 80, true),
      item(false, false, 3000, false, 80, false), item(false, true, 3000, false, 10, false),
      item(false, false, 3000, false, 15, true), item(false, false, 3000, false, 10, false),
  };
  for (size_t i = 0; i < sizeof samples / sizeof samples[0]; i++) {
    CHECK(strlen(sr_classify(&samples[i], &kCalibrated).reason) < 24);
  }
}

int main(void) {
  test_metal_wins_over_everything();
  test_wet_is_organic();
  test_raindrop_is_organic();
  test_tall_is_bottle_unless_bright();
  test_capacitive_low_item_is_organic();
  test_paper_rule_needs_calibration();
  test_category_keys_match_app();
  test_reasons_fit_item_field();
  if (failures == 0) {
    printf("Semua uji sort_rules lulus.\n");
    return 0;
  }
  printf("%d uji gagal.\n", failures);
  return 1;
}
