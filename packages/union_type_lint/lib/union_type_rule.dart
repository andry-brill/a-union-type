import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart';
import 'package:union_type_lint/union_type_visitor.dart';


class UnionTypeRule extends AnalysisRule {

  static const LintCode code = LintCode(
    'union_type',
    _UnionTypeRuleVisitor.template,
  );

  UnionTypeRule()
      : super(
    name: 'union_type',
    description: 'Validates that values assigned to UnionType typedefs match allowed types.',
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _UnionTypeRuleVisitor(this, context);
    registry.addCompilationUnit(this, visitor);
  }
}


class _UnionTypeRuleVisitor extends UnionTypeVisitor {

  final AnalysisRule analysisRule;
  final RuleContext context;

  _UnionTypeRuleVisitor(this.analysisRule, this.context) : super (verbose: LoggingVariant.none);

  static const String template = '{0} does not match any allowed type in @UnionType {1}: [{2}].';

  @override
  void reportViolation({required String target, required String unionTypeName, required List<String> allowedTypes, int? lineNumber, required AstNode node, int? offset, int? length}) {
    super.reportViolation(target: target, unionTypeName: unionTypeName, allowedTypes: allowedTypes, lineNumber: lineNumber, node: node, offset: offset, length: length);

    if (context.isInLibDir) {
      List<Object> arguments = [target, unionTypeName, allowedTypes.join(", ")];
      if (offset != null && length != null) {
        analysisRule.reportAtOffset(offset, length, arguments: arguments);
      } else {
        analysisRule.reportAtNode(node, arguments: arguments);
      }
    }
  }

  @override
  void visitCompilationUnit(CompilationUnit node) {
    super.visitCompilationUnit(node);
  }

}


