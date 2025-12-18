## Union Type for Dart

This repository provides TypeScript-like **union types** for Dart using annotations and an analyzer plugin.

The solution is split into **two packages**, following Dart best practices:

- `union_type_annotation` — runtime-safe annotation library
- `union_type_lint` — analyzer plugin that validates union types at analysis time

## Packages

### union_type_annotation

A lightweight annotation package that defines the `@UnionType` annotation.

- Contains **no analyzer logic**
- Has **zero runtime overhead**
- Safe to use in production code

```dart
@UnionType([VoidCallback, OnTapCtx])
typedef OnTap = dynamic;
```


### union_type_lint

An **analyzer plugin** that enforces `@UnionType` constraints at analysis time.

It reports warnings when a value assigned to a union type does not match any allowed type.


## Installation

### 1. Add the annotation dependency

```yaml
dependencies:
  union_type_annotation: ^1.0.0
```

### 2. Add the analyzer plugin

```yaml
dev_dependencies:
  union_type_lint: ^1.0.0
```

### 3. Enable the plugin

Create or update `analysis_options.yaml`:

```yaml
plugins:
  union_type_lint: ^1.0.0
```


## Example

```dart

typedef VoidCallback = void Function();
typedef OnTapCtx = void Function(BuildContext);

@UnionType([VoidCallback, OnTapCtx])
typedef OnTap = Object?;  // could be dynamic

class TestClass {
  final OnTap? onTap;
  const TestClass(this.onTap);
}

final valid = TestClass(() => print('ok'));      // ✅
final invalid = TestClass((int v) {});           // ❌ analyzer warning

```

> ℹ️ Validation is performed **only by the analyzer plugin**.
> The annotation itself does not perform runtime checks.

