

/// Declares a *union type* for a `typedef` in Dart.
///
/// This is a lightweight alternative to **TypeScript union types**,
/// implemented via an annotation and validated at analysis time
/// (not at runtime).
///
/// ## Usage
/// ```dart
/// typedef VoidCallback = void Function();
/// typedef OnTapCtx = void Function(BuildContext);
///
/// @UnionType([VoidCallback, OnTapCtx])
/// typedef OnTap = dynamic;
/// ```
///
/// The accompanying analyzer plugin will report warnings when:
/// - a value assigned to `OnTap` does not match any allowed type
/// - a function signature is incompatible
/// - a class does not implement an allowed interface
///
/// ## Notes
/// - This annotation itself performs **no runtime checks**
/// - Validation is done entirely by the analyzer plugin
class UnionType {

  /// List of allowed types for the annotated union typedef.
  ///
  /// Each entry must be a `Type`, such as a function typedef or an interface/class.
  final List<Type> allowed;

  /// Declares a *union type* for a `typedef` in Dart.
  ///
  /// This is a lightweight alternative to **TypeScript union types**,
  /// implemented via an annotation and validated at analysis time
  /// (not at runtime).
  ///
  /// ## Usage
  /// ```dart
  /// typedef VoidCallback = void Function();
  /// typedef OnTapCtx = void Function(BuildContext);
  ///
  /// @UnionType([VoidCallback, OnTapCtx])
  /// typedef OnTap = dynamic;
  /// ```
  ///
  /// The accompanying analyzer plugin will report warnings when:
  /// - a value assigned to `OnTap` does not match any allowed type
  /// - a function signature is incompatible
  /// - a class does not implement an allowed interface
  ///
  /// ## Notes
  /// - This annotation itself performs **no runtime checks**
  /// - Validation is done entirely by the analyzer plugin
  const UnionType(this.allowed);
}
