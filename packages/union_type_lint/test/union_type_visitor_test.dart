
import 'package:test/test.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:union_type_lint/union_type_visitor.dart';


void main() {
  test('Validate OnTap UnionType', () {

    String onTap = """

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


abstract class ISurfaceOnTapVoid {
  void onTap();
}

typedef SurfaceOnTapVoid = void Function();
typedef SurfaceOnTapCtx = void Function(BuildContext);

@UnionType([SurfaceOnTapVoid, SurfaceOnTapCtx, ISurfaceOnTapVoid])
typedef SurfaceOnTap = dynamic;

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

    """;


    final result = analyze(onTap);
    expect(result.violationsFound, 4);

    expect(result.violations[0], 'void Function(int) does not match any allowed type in @UnionType OnTap: [VoidCallback, OnTapCtx, OnTapCtxData, IOnTap]. Line 41.');
    expect(result.violations[1], 'MyInvalidOnTap does not match any allowed type in @UnionType OnTap: [VoidCallback, OnTapCtx, OnTapCtxData, IOnTap]. Line 44.');
    expect(result.violations[2], 'void Function(double) does not match any allowed type in @UnionType OnTap: [VoidCallback, OnTapCtx, OnTapCtxData, IOnTap]. Line 48.');
    expect(result.violations[3], 'void Function(int) does not match any allowed type in @UnionType SurfaceOnTap: [SurfaceOnTapVoid, SurfaceOnTapCtx, ISurfaceOnTapVoid]. Line 68.');
  });
}



UnionTypeVisitor analyze(String content) {

  final visitor = UnionTypeVisitor(logging: LoggingVariant.print);

  final result = parseString(
    content: content,
    featureSet: FeatureSet.latestLanguageVersion(), // default SDK feature set
    throwIfDiagnostics: false,
  );

  final unit = result.unit;
  unit.visitChildren(visitor);

  return visitor;
}
