/*
 * Klien minimal Firebase Realtime Database lewat REST API (HTTPS).
 *
 * - Login memakai Firebase Authentication (Email/Password) akun perangkat.
 * - Token (berlaku 1 jam) diperbarui otomatis.
 * - Path tanpa ".json", mis. get("commands/latest", body).
 */
#pragma once

#include <Arduino.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>

class FirebaseRtdb {
 public:
  void begin(const char *apiKey, const char *databaseUrl, const char *email,
             const char *password);

  // Login / perbarui token bila perlu. Aman dipanggil setiap loop
  // (ada jeda 10 dtk antar percobaan gagal).
  bool ensureAuth();
  bool ready() const { return idToken_.length() > 0; }

  bool get(const String &path, String &response);
  bool patch(const String &path, const String &json);
  bool post(const String &path, const String &json);

  const String &lastError() const { return lastError_; }

 private:
  bool signIn();
  bool refresh();
  bool request(const char *method, const String &url, const String *body,
               String *response, const char *contentType = "application/json");
  String url(const String &path) const;
  void storeToken(const String &idToken, const String &refreshToken,
                  long expiresInSec);

  WiFiClientSecure client_;
  HTTPClient http_;
  String apiKey_, databaseUrl_, email_, password_;
  String idToken_, refreshToken_;
  uint32_t tokenExpiryMs_ = 0;
  uint32_t lastAuthAttemptMs_ = 0;
  bool authAttempted_ = false;
  String lastError_;
};
