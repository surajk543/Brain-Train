/// The player's age group, derived from the birth year asked once on the
/// neutral age screen at first launch (Google Play Families policy, mixed
/// audience). Only the group is stored, on the device (SharedPreferences);
/// it is never sent anywhere. It decides how ads are requested
/// (docs/ADS.md).
enum AgeGroup {
  /// Under 13, or possibly under 13: child-directed ad treatment.
  under13('under13'),

  /// Certainly 13 or older.
  thirteenPlus('13plus');

  const AgeGroup(this.storageValue);

  /// The value kept in SharedPreferences.
  final String storageValue;

  /// The stored group, or null when there is none (or it is unreadable).
  static AgeGroup? parse(String? value) {
    for (final group in values) {
      if (group.storageValue == value) return group;
    }
    return null;
  }

  /// Only the birth year is asked, so someone born in [birthYear] may not
  /// have had this year's birthday yet: they count as 13 or older only once
  /// that is certain (turning 14 this year at the latest). The year they may
  /// still be 12 counts as under 13.
  static AgeGroup fromBirthYear(int birthYear, {required int currentYear}) =>
      currentYear - birthYear >= 14 ? thirteenPlus : under13;
}
