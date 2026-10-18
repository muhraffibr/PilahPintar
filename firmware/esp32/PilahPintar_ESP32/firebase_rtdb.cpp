#include "config.h"

#include "firebase_rtdb.h"

#include <ArduinoJson.h>

void FirebaseRtdb::begin(const char *apiKey, const char *databaseUrl,
                         const char *email, const char *password) {
  apiKey_ = apiKey;
  databaseUrl_ = databaseUrl;
  while (databaseUrl_.endsWith("/")) databaseUrl_.remove(databaseUrl_.length() - 1);
  email_ = email;
  password_ = password;

  // Prototype: sertifikat server tidak diverifikasi. Untuk produksi, pasang
  // root CA Google dengan client_.setCACert(...).
  client_.setInsecure();
  http_.setReuse(true);
  http_.setTimeout(8000);
  http_.setConnectTimeout(8000);
}

String FirebaseRtdb::url(const String &path) const {
  return databaseUrl_ + "/" + path + ".json?auth=" + idToken_;
}

void FirebaseRtdb::storeToken(const String &idToken, const String &refreshToken,
                              long expiresInSec) {
  idToken_ = idToken;
  refreshToken_ = refreshToken;
  if (expiresInSec <= 0) expiresInSec = 3600;
  tokenExpiryMs_ = millis() + (uint32_t)expiresInSec * 1000UL;
}

bool FirebaseRtdb::request(const char *method, const String &url,
                           const String *body, String *response,
                           const char *contentType) {
  if (!http_.begin(client_, url)) {
    lastError_ = "HTTP begin gagal";
    return false;
  }
  http_.addHeader("Content-Type", contentType);

  int code;
  if (strcmp(method, "GET") == 0) {
    code = http_.GET();
  } else if (strcmp(method, "PATCH") == 0) {
    code = http_.PATCH(*body);
  } else if (strcmp(method, "POST") == 0) {
    code = http_.POST(*body);
  } else {
    code = http_.PUT(*body);
  }

  String payload = code > 0 ? http_.getString() : String();
  http_.end();
  if (response) *response = payload;

  if (code >= 200 && code < 300) {
    lastError_ = "";
    return true;
  }
  lastError_ = String(method) + " " + code + ": " +
               (code > 0 ? payload.substring(0, 160) : http_.errorToString(code));
  if (code == 401) idToken_ = "";  // token kedaluwarsa/ditolak -> login ulang
  return false;
}

bool FirebaseRtdb::signIn() {
  JsonDocument doc;
  doc["email"] = email_;
  doc["password"] = password_;
  doc["returnSecureToken"] = true;
  String body;
  serializeJson(doc, body);

  String response;
  const String endpoint =
      "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=" + apiKey_;
  if (!request("POST", endpoint, &body, &response)) {
    lastError_ = "Login Firebase gagal (" + lastError_ + ")";
    return false;
  }
  JsonDocument res;
  if (deserializeJson(res, response)) {
    lastError_ = "Respons login tidak valid";
    return false;
  }
  storeToken(res["idToken"].as<String>(), res["refreshToken"].as<String>(),
             String(res["expiresIn"] | "3600").toInt());
  return ready();
}

bool FirebaseRtdb::refresh() {
  const String body = "grant_type=refresh_token&refresh_token=" + refreshToken_;
  String response;
  const String endpoint = "https://securetoken.googleapis.com/v1/token?key=" + apiKey_;
  if (!request("POST", endpoint, &body, &response,
               "application/x-www-form-urlencoded")) {
    return false;
  }
  JsonDocument res;
  if (deserializeJson(res, response)) return false;
  storeToken(res["id_token"].as<String>(), res["refresh_token"].as<String>(),
             String(res["expires_in"] | "3600").toInt());
  return ready();
}

bool FirebaseRtdb::ensureAuth() {
  const uint32_t now = millis();
  // Token masih berlaku > 1 menit.
  if (ready() && (int32_t)(tokenExpiryMs_ - now) > 60000) return true;
  // Jeda antar percobaan agar tidak membanjiri server saat gagal.
  if (authAttempted_ && now - lastAuthAttemptMs_ < 10000) return ready();
  authAttempted_ = true;
  lastAuthAttemptMs_ = now;

  if (refreshToken_.length() > 0 && refresh()) return true;
  return signIn();
}

bool FirebaseRtdb::get(const String &path, String &response) {
  return request("GET", url(path), nullptr, &response);
}

bool FirebaseRtdb::patch(const String &path, const String &json) {
  return request("PATCH", url(path), &json, nullptr);
}

bool FirebaseRtdb::post(const String &path, const String &json) {
  return request("POST", url(path), &json, nullptr);
}
