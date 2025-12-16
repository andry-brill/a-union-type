import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:union_type_lint/union_type_rule.dart';

@reflectiveTest
class UnionTypeRuleTest extends AnalysisRuleTest {

  @override
  void setUp() {
    rule = UnionTypeRule();
    super.setUp();
  }

  void test_expecting_lints() async {
    await assertDiagnostics(
      """
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
""",
      [
        lint(848, 31, messageContainsAll: [r'void Function(int) does not match any allowed type in @UnionType OnTap: [VoidCallback, OnTapCtx, OnTapCtxData, IOnTap].']),
        lint(973, 22, messageContainsAll: [r'MyInvalidOnTap does not match any allowed type in @UnionType OnTap: [VoidCallback, OnTapCtx, OnTapCtxData, IOnTap].']),
        lint(1102, 30, messageContainsAll: [r'void Function(double) does not match any allowed type in @UnionType OnTap: [VoidCallback, OnTapCtx, OnTapCtxData, IOnTap].'])
      ],
    );
  }

}

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(UnionTypeRuleTest);
  });
}