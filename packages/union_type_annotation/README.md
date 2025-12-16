
## union_type_annotation

`union_type_annotation` provides a simple annotation class for defining **union types** in Dart.  
This allows you to declare a typedef that can accept multiple types, similar to TypeScript union types, and is intended to be validated by a separate analyzer plugin (`union_type_lint`).

---

### Features

- Define union types on `typedef`s using `@UnionType`.
- Works with function typedefs and interface/class types.
- Fully analyzer-plugin compatible, providing compile-time validation of assignments and function signatures.

---

### Getting started

Add `union_type_annotation` as a dependency in your `pubspec.yaml`:

```yaml
dependencies:
  union_type_annotation: ^1.0.0
```

You will typically also want the analyzer plugin to validate your union types:

```yaml
dev_dependencies:
  union_type_lint: ^1.0.0
```

Enable the plugin in `analysis_options.yaml`:

```yaml
plugins:
  union_type_lint: ^1.0.0
```

---

### Usage

```dart
import 'package:union_type_annotation/union_type_annotation.dart';

typedef VoidCallback = void Function();
typedef OnTapCtx = void Function(BuildContext);
abstract class IOnTap { void onTap(BuildContext context, dynamic data); }

@UnionType([VoidCallback, OnTapCtx, IOnTap])
typedef OnTap = dynamic;

class TestClass {
  final OnTap? onTap;
  const TestClass(this.onTap);
}

void main() {
  // ✅ Valid assignments
  final valid1 = TestClass(() => print('callback'));
  final valid2 = TestClass((BuildContext ctx) => print('with context'));

  // ❌ Invalid assignment (plugin will warn)
  final invalid = TestClass((int value) => print('invalid'));
}
```

> **Note:** The `@UnionType` annotation itself does **not perform runtime checks**. Validation is handled entirely by the `union_type_lint` plugin.

---

### Additional information

- Issues and contributions: please use the GitHub repository.
- License: MIT

