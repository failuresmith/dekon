abstract final class EventSchema {
  static const currentVersion = 1;

  static bool isSupported(int version) => version == currentVersion;

  static bool isFutureVersion(int version) => version > currentVersion;
}
