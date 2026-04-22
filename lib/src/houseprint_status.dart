/// String constants for native status source types.
abstract class HouseprintStatusType {
  static const String bluetooth = 'bluetooth';
  static const String print = 'print';
  static const String unknown = 'unknown';

  static String normalize(String? rawValue) {
    if (rawValue == bluetooth) {
      return bluetooth;
    }
    if (rawValue == print) {
      return print;
    }
    return unknown;
  }
}

/// Structured status event emitted by the native plugin.
class HouseprintStatus {
  HouseprintStatus({
    required this.type,
    required this.state,
    required this.message,
    required this.payload,
  });

  final String type;
  final String state;
  final String message;
  final Map<String, dynamic> payload;

  factory HouseprintStatus.fromDynamic(dynamic value) {
    final Map<dynamic, dynamic> map =
        value is Map ? value : <dynamic, dynamic>{};
    return HouseprintStatus(
      type: HouseprintStatusType.normalize(map['type'] as String?),
      state: map['state'] as String? ?? 'unknown',
      message: map['message'] as String? ?? '',
      payload: _castMap(map['payload']),
    );
  }

  static Map<String, dynamic> _castMap(Object? value) {
    if (value is Map) {
      return value.map<String, dynamic>(
        (dynamic key, dynamic nestedValue) =>
            MapEntry(key.toString(), nestedValue),
      );
    }
    return <String, dynamic>{};
  }
}
