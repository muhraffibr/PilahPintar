#include "sort_rules.h"

static sr_result_t result(sr_category_t category, const char *reason) {
  sr_result_t r;
  r.category = category;
  r.reason = reason;
  return r;
}

sr_result_t sr_classify(const sr_features_t *f, const sr_config_t *cfg) {
  if (f->inductive) return result(SR_LOGAM, "Logam (induktif)");

  if (f->soil_min_raw >= 0 && f->soil_min_raw <= cfg->soil_wet_raw) {
    return result(SR_ORGANIK, "Organik (basah)");
  }

  if (f->height_mm >= cfg->bottle_min_height_mm) {
    if (cfg->styrofoam_min_signal_mcps > 0 &&
        f->signal_mcps >= cfg->styrofoam_min_signal_mcps) {
      return result(SR_ANORGANIK, "Styrofoam (terang)");
    }
    return result(SR_RECYCLABLE, "Botol (tinggi)");
  }

  if (f->capacitive && cfg->capacitive_means_organic) {
    return result(SR_ORGANIK, "Organik (kapasitif)");
  }

  if (cfg->paper_min_signal_mcps > 0 && f->height_mm > 0 &&
      f->height_mm <= cfg->paper_max_height_mm &&
      f->signal_mcps >= cfg->paper_min_signal_mcps) {
    return result(SR_RECYCLABLE, "Kertas (terang)");
  }

  return result(SR_ANORGANIK, "Residu");
}

const char *sr_category_key(sr_category_t c) {
  switch (c) {
    case SR_ORGANIK: return "organik";
    case SR_RECYCLABLE: return "recyclable";
    case SR_LOGAM: return "logam";
    default: return "anorganik";
  }
}
