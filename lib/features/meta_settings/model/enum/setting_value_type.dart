/// Storage family of a metadata-setting value.
///
/// Mirrors the primitive types `SettingsStore` can persist. [enumeration] is a
/// catalog-level placeholder only: enums are stored as their `name` string, so
/// the value table never carries it (see [storageType]).
enum SettingValueType {
  bool,
  int,
  double,
  string,
  stringList,
  enumeration;

  /// The tag actually written for a value of this catalog type.
  SettingValueType get storageType => this == SettingValueType.enumeration ? SettingValueType.string : this;

  static SettingValueType? tryParse(String? name) {
    for (final value in SettingValueType.values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
