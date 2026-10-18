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

/* Sama dengan nilai bawaan config.h (aturan pantulan masih mati). */
static const sr_config_t kDefault = {2200, true, 45, 0.0f, 25, 0.0f};

/* Setelah kalibrasi: aturan styrofoam & kertas dinyalakan. */
static const sr_config_t kCalibrated = {2200, true, 45, 20.0f, 25, 12.0f};

static sr_features_t item(bool ind, bool cap, int soil, int height, float signal) {
  sr_features_t f;
  f.inductive = ind;
  f.capacitive = cap;
  f.soil_min_raw = soil;
  f.height_mm = height;
  f.signal_mcps = signal;
  return f;
}

static sr_category_t classify(sr_features_t f, const sr_config_t *cfg) {
  return sr_classify(&f, cfg).category;
}

static void test_metal_wins_over_everything(void) {
  /* Kaleng berisi sisa minuman: induktif + kapasitif + basah + tinggi. */
  sr_features_t f = item(true, true, 1500, 60, 30.0f);
  sr_result_t r = sr_classify(&f, &kDefault);
  CHECK(r.category == SR_LOGAM);
  CHECK(strcmp(r.reason, "Logam (induktif)") == 0);
}

static void test_wet_is_organic(void) {
  CHECK(classify(item(false, false, 1800, 20, 5.0f), &kDefault) == SR_ORGANIK);
  CHECK(classify(item(false, false, 2200, 0, 0.0f), &kDefault) == SR_ORGANIK); /* tepat di batas */
  CHECK(classify(item(false, false, 2201, 10, 5.0f), &kDefault) != SR_ORGANIK);
  CHECK(classify(item(false, false, -1, 10, 5.0f), &kDefault) == SR_ANORGANIK); /* soil tak terbaca */
}

static void test_tall_is_bottle_unless_bright(void) {
  CHECK(classify(item(false, false, 3000, 45, 8.0f), &kDefault) == SR_RECYCLABLE);
  CHECK(classify(item(false, false, 3000, 44, 8.0f), &kDefault) == SR_ANORGANIK);
  /* Aturan styrofoam mati secara bawaan: benda tinggi & terang tetap botol. */
  CHECK(classify(item(false, false, 3000, 80, 50.0f), &kDefault) == SR_RECYCLABLE);
  CHECK(classify(item(false, false, 3000, 80, 50.0f), &kCalibrated) == SR_ANORGANIK);
  CHECK(classify(item(false, false, 3000, 80, 10.0f), &kCalibrated) == SR_RECYCLABLE);
}

static void test_capacitive_low_item_is_organic(void) {
  CHECK(classify(item(false, true, 3000, 20, 5.0f), &kDefault) == SR_ORGANIK);
  sr_config_t off = kDefault;
  off.capacitive_means_organic = false;
  CHECK(classify(item(false, true, 3000, 20, 5.0f), &off) == SR_ANORGANIK);
}

static void test_paper_rule_needs_calibration(void) {
  sr_features_t paper = item(false, false, 3000, 15, 15.0f);
  CHECK(classify(paper, &kDefault) == SR_ANORGANIK);
  CHECK(classify(paper, &kCalibrated) == SR_RECYCLABLE);
  CHECK(strcmp(sr_classify(&paper, &kCalibrated).reason, "Kertas (terang)") == 0);
  /* Kresek: pendek tapi pantulan lemah -> residu. */
  CHECK(classify(item(false, false, 3000, 15, 6.0f), &kCalibrated) == SR_ANORGANIK);
  /* Tidak terlihat VL53L1X: tidak boleh dianggap kertas. */
  CHECK(classify(item(false, false, 3000, 0, 15.0f), &kCalibrated) == SR_ANORGANIK);
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
      item(true, false, 3000, 0, 0.0f),     item(false, false, 1000, 0, 0.0f),
      item(false, false, 3000, 80, 50.0f),  item(false, false, 3000, 80, 1.0f),
      item(false, true, 3000, 10, 1.0f),    item(false, false, 3000, 15, 15.0f),
      item(false, false, 3000, 10, 1.0f),
  };
  for (size_t i = 0; i < sizeof samples / sizeof samples[0]; i++) {
    CHECK(strlen(sr_classify(&samples[i], &kCalibrated).reason) < 24);
  }
}

int main(void) {
  test_metal_wins_over_everything();
  test_wet_is_organic();
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
