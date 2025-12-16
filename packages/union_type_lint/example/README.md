
# Example

```dart

class BuildContext {}

abstract class IOnTap {
  void onTap(BuildContext context, dynamic data);
}

class MyOnTap implements IOnTap {
  const MyOnTap();
  @override
  void onTap(BuildContext context, data) {
  }
}

class MyInvalidOnTap {
  const MyInvalidOnTap();
  void onTap(BuildContext context, data) {
  }
}

typedef VoidCallback = void Function();
typedef OnTapCtx = void Function(BuildContext);
typedef OnTapCtxData = void Function(BuildContext, dynamic);

@UnionType([VoidCallback, OnTapCtx, OnTapCtxData, IOnTap])
typedef OnTap = dynamic;

class TestClass {
  final OnTap? onTap;
  const TestClass(this.onTap);
}

void notify(OnTap fn) {print('notify: ' + fn);}

final valid = TestClass((BuildContext ctx) => print('valid')); // ✅
final invalid = TestClass((int value) => print('invalid')); // ❌

final validIOnTap = TestClass(const MyOnTap()); // ✅
final invalidIOnTap = TestClass(const MyInvalidOnTap()); // ❌ MyInvalidOnTap don't implement IOnTap

void main() {
  notify(() => print('valid')); // ✅
  notify((double v) => print('invalid')); // ❌
}


```