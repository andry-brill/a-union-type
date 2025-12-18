
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

class UnionType {
  final List<Type> allowed;
  const UnionType(this.allowed);
}

typedef VoidCallback = void Function();
typedef OnTapCtx = void Function(BuildContext);
typedef OnTapCtxData = void Function(BuildContext, dynamic);

@UnionType([VoidCallback, OnTapCtx, OnTapCtxData, IOnTap])
typedef OnTap = Object?;

class TestClass {
  final OnTap? onTap;
  const TestClass(this.onTap);
}

void notify(OnTap fn) {print('notify: $fn');}

final valid = TestClass((BuildContext ctx) => print('valid')); // ✅
final invalid = TestClass((int value) => print('invalid')); // ❌

final validIOnTap = TestClass(const MyOnTap()); // ✅
final invalidIOnTap = TestClass(const MyInvalidOnTap()); // ❌ MyInvalidOnTap don't implement IOnTap

void main() {
  notify(() => print('valid')); // ✅
  notify((double v) => print('invalid')); // ❌
}


abstract class ISurfaceOnTapVoid {
  void onTap();
}

typedef SurfaceOnTapVoid = void Function();
typedef SurfaceOnTapCtx = void Function(BuildContext);

@UnionType([SurfaceOnTapVoid, SurfaceOnTapCtx, ISurfaceOnTapVoid])
typedef SurfaceOnTap = Object?;

abstract class ISurface {

  final SurfaceOnTap onTap;
  const ISurface(this.onTap);
}

final invalidSurface = USurface(onTap: (int i) {
}, child: "invalid");

final validSurface = USurface(onTap: () {
}, child: "valid");

class USurface implements ISurface {

  @override final SurfaceOnTap onTap;

  final Object child;
  const USurface({required this.child, this.onTap});

  const USurface.decorator({required this.child})
      : onTap = null;

}

