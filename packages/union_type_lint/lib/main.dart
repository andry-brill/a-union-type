import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:union_type_lint/union_type_rule.dart';

final plugin = UnionTypePlugin();

class UnionTypePlugin extends Plugin {

  @override
  String get name => 'UnionType';

  @override
  void register(PluginRegistry registry) {
    registry.registerWarningRule(UnionTypeRule());
  }

}
