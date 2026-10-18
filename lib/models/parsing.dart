/// Helper konversi nilai mentah dari Firebase Realtime Database.
///
/// RTDB mengembalikan `Map<Object?, Object?>`, angka bisa `int` atau `double`,
/// dan firmware bisa mengirim timestamp dalam detik maupun milidetik.
library;

Map<String, dynamic>? asStringMap(Object? value) {
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  if (value is List) {
    return {
      for (var i = 0; i < value.length; i++)
        if (value[i] != null) '$i': value[i],
    };
  }
  return null;
}

/// Anak-anak sebuah node yang masing-masing berupa map (mis. `bins/*`).
Map<String, Map<String, dynamic>> childMaps(Object? value) {
  final root = asStringMap(value);
  if (root == null) return const {};
  final out = <String, Map<String, dynamic>>{};
  root.forEach((key, child) {
    final m = asStringMap(child);
    if (m != null) out[key] = m;
  });
  return out;
}

double? asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? asInt(Object? value) {
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

bool? asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final t = value.toLowerCase();
    if (t == 'true' || t == '1') return true;
    if (t == 'false' || t == '0') return false;
  }
  return null;
}

/// Epoch milidetik (atau detik bila < 1e11) maupun string ISO-8601.
DateTime? asDateTime(Object? value) {
  if (value is num) {
    final ms = value < 100000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(ms.round());
  }
  if (value is String) {
    final asNum = num.tryParse(value);
    if (asNum != null) return asDateTime(asNum);
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}

String? asNonEmptyString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
