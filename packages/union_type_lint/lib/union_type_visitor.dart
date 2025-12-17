library union_type_lint;

import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

enum LoggingVariant {
  none,
  print,
  file
}

class UnionTypeVisitor extends RecursiveAstVisitor<void> {

  final LoggingVariant logging;
  final file = File('union_type_lint_log.txt');
  UnionTypeVisitor({this.logging = LoggingVariant.none});

  // Map from typedef name to list of allowed type names (from annotation)
  final Map<String, List<String>> unionTypes = {};

  // Map from typedef name to its actual function signature
  final Map<String, String> typedefSignatures = {};

  // List of violations found during analysis
  final List<String> violations = [];
  int violationsFound = 0;

  // Track function expressions checked in visitInstanceCreationExpression to avoid duplicates
  final Set<int> checkedInInstanceCreation = {};

  void addUnionType(String typedefName, List<String> allowedTypes) {
    unionTypes[typedefName] = allowedTypes;
  }

  void addTypedefSignature(String typedefName, String signature) {
    typedefSignatures[typedefName] = signature;
  }

  void log(String log) {
    if (logging == LoggingVariant.print) print('[LOG] $log');
    if (logging == LoggingVariant.file) file.writeAsStringSync('$log\n', mode: FileMode.append);
  }

  void reportViolation({
    required String target,
    required String unionTypeName,
    required List<String> allowedTypes,
    int? lineNumber,
    required AstNode node,
    int? offset,
    int? length
  }) {

    violationsFound++;

    if (logging != LoggingVariant.none) {

      final message = '$target does not match any allowed type in @UnionType $unionTypeName: $allowedTypes. Line $lineNumber.';
      violations.add(message);

      log('⚠️  $message');
    }
  }

  bool isUnionType(String typeName) {
    return unionTypes.containsKey(typeName);
  }

  List<String> getAllowedTypes(String unionTypeName) {
    return unionTypes[unionTypeName] ?? [];
  }

  // Resolve a typedef name to its function signature
  String? resolveTypedef(String typedefName) {
    return typedefSignatures[typedefName];
  }

  @override
  void visitClassTypeAlias(ClassTypeAlias node) {
    visitTypeAlias(node);
    super.visitClassTypeAlias(node);
  }

  @override
  void visitFunctionTypeAlias(FunctionTypeAlias node) {
    visitTypeAlias(node);
    super.visitFunctionTypeAlias(node);
  }

  @override
  void visitGenericTypeAlias(GenericTypeAlias node) {
    visitTypeAlias(node);
    super.visitGenericTypeAlias(node);
  }

  void visitTypeAlias(TypeAlias node) {
    final typedefName = node.name.lexeme;
    log('visitTypeAlias: Found typedef "$typedefName"');

    // Check for @UnionType annotation
    for (final metadata in node.metadata) {
      final annotationName = metadata.name.name;
      log('visitTypeAlias: Checking annotation "$annotationName" on typedef "$typedefName"');
      if (annotationName == 'UnionType') {
        final allowedTypes = _extractAllowedTypes(metadata);
        log('visitTypeAlias: Found UnionType annotation on "$typedefName" with allowed types: $allowedTypes');
        addUnionType(typedefName, allowedTypes);
      }
    }

  }

  @override
  void visitGenericFunctionType(GenericFunctionType node) {
    // If this is part of a typedef, extract the signature
    final parent = node.parent;
    if (parent is TypeAlias) {
      final typedefName = parent.name.lexeme;
      final signature = _extractTypedefSignature(node);
      log('visitGenericFunctionType: Found function typedef "$typedefName" with signature "$signature"');
      addTypedefSignature(typedefName, signature);
    }
    super.visitGenericFunctionType(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    log('visitVariableDeclaration: Visiting variable "${node.name.lexeme}"');
    if (node.initializer != null) {
      final typeName = _getTypeName(node);
      log('visitVariableDeclaration: Variable has type "$typeName"');
      if (typeName != null && isUnionType(typeName)) {
        log('visitVariableDeclaration: Variable type "$typeName" is a union type, checking assignment');
        _checkAssignment(node.initializer!, typeName, node.offset);
      } else if (typeName != null) {
        log('visitVariableDeclaration: Variable type "$typeName" is NOT a union type');
      }
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    // For function calls, check if arguments are function expressions
    // and try to infer the parameter type from context
    // Note: Without element resolution, this is limited
    log('visitFunctionExpressionInvocation: Found function expression invocation');
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final methodName = node.methodName.name;
    log('visitMethodInvocation: Found method invocation "$methodName"');

    // Check if this might be a constructor call (constructor calls can appear as MethodInvocation)
    final target = node.target;
    log('visitMethodInvocation: Target: ${target?.runtimeType}');

    // Check arguments for function expressions or instance creations that might need union type checking
    // Try to find the function/constructor declaration
    final funcDecl = _findFunctionOrConstructorDeclaration(methodName, node);
    if (funcDecl != null) {
      log('visitMethodInvocation: Found declaration for "$methodName"');
      // Check arguments
      for (int i = 0; i < node.argumentList.arguments.length; i++) {
        final arg = node.argumentList.arguments[i];
        String? paramType;

        // Handle named parameters
        if (arg is NamedExpression) {
          final paramName = arg.name.label.name;
          log('visitMethodInvocation: Argument $i is a named parameter "$paramName"');
          paramType = _getParameterTypeByName(funcDecl, paramName);
        } else {
          // Handle positional parameters
          paramType = _getParameterType(funcDecl, i);
        }

        log('visitMethodInvocation: Parameter $i type string: "$paramType"');
        if (paramType != null) {
          final unionTypeName = _extractUnionTypeName(paramType);
          log('visitMethodInvocation: Extracted union type name from "$paramType": "$unionTypeName"');
          if (unionTypeName != null && isUnionType(unionTypeName)) {
            log('visitMethodInvocation: Parameter $i is union type "$unionTypeName"');

            if (arg is FunctionExpression) {
              log('visitMethodInvocation: Argument $i is FunctionExpression, checking signature');
              // Skip if already checked by visitInstanceCreationExpression
              if (!checkedInInstanceCreation.contains(arg.offset)) {
                _checkFunctionSignature(arg, unionTypeName, arg.offset);
              } else {
                log('visitMethodInvocation: Already checked by visitInstanceCreationExpression, skipping');
              }
            } else if (arg is NamedExpression && arg.expression is FunctionExpression) {
              log('visitMethodInvocation: Argument $i is NamedExpression with FunctionExpression, checking signature');
              final funcExpr = arg.expression as FunctionExpression;
              // Skip if already checked by visitInstanceCreationExpression
              if (!checkedInInstanceCreation.contains(funcExpr.offset)) {
                _checkFunctionSignature(funcExpr, unionTypeName, arg.offset);
              } else {
                log('visitMethodInvocation: Already checked by visitInstanceCreationExpression, skipping');
              }
            } else if (arg is InstanceCreationExpression) {
              log('visitMethodInvocation: Argument $i is InstanceCreationExpression, checking class instance');
              _checkClassInstance(arg, unionTypeName, arg.offset);
            } else if (arg is NamedExpression && arg.expression is InstanceCreationExpression) {
              log('visitMethodInvocation: Argument $i is NamedExpression with InstanceCreationExpression, checking class instance');
              _checkClassInstance(arg.expression as InstanceCreationExpression, unionTypeName, arg.offset);
            } else {
              log('visitMethodInvocation: Argument $i is ${arg.runtimeType}, not checking');
            }
          } else {
            if (unionTypeName != null) {
              log('visitMethodInvocation: Parameter $i type "$unionTypeName" is NOT a registered union type');
            } else {
              log('visitMethodInvocation: Could not extract union type name from parameter type');
            }
          }
        } else {
          log('visitMethodInvocation: Could not get parameter type for argument $i');
        }
      }
    } else {
      log('visitMethodInvocation: Declaration not found for "$methodName"');
    }

    super.visitMethodInvocation(node);
  }

  AstNode? _findFunctionOrConstructorDeclaration(String name, AstNode context) {
    final unit = context.thisOrAncestorOfType<CompilationUnit>();
    if (unit == null) return null;

    for (final declaration in unit.declarations) {
      if (declaration is FunctionDeclaration && declaration.name.lexeme == name) {
        return declaration;
      } else if (declaration is ClassDeclaration) {
        // Check for constructor
        for (final member in declaration.members) {
          if (member is ConstructorDeclaration) {
            // Constructor name might be the class name or a named constructor
            final constructorName = member.name?.lexeme ?? declaration.name.lexeme;
            if (constructorName == name || declaration.name.lexeme == name) {
              return member;
            }
          }
        }
      }
    }
    return null;
  }

  String? _getParameterType(AstNode declaration, int index) {
    if (declaration is FunctionDeclaration) {
      final parameters = declaration.functionExpression.parameters?.parameters ?? [];
      if (index < parameters.length) {
        final param = parameters[index];
        if (param is SimpleFormalParameter && param.type != null) {
          return param.type.toString();
        }
      }
    } else if (declaration is ConstructorDeclaration) {
      final parameters = declaration.parameters.parameters;
      if (index < parameters.length) {
        final param = parameters[index];
        TypeAnnotation? paramType;
        if (param is SimpleFormalParameter) {
          paramType = param.type;
        } else if (param is FieldFormalParameter) {
          // FieldFormalParameter (this.fieldName) doesn't have a type annotation
          // The type comes from the field declaration
          final fieldName = param.name.lexeme;
          log('_getParameterType: FieldFormalParameter (this.fieldName), field name: $fieldName');
          paramType = param.type;
          if (paramType == null) {
            // Look up the field type from the class
            log('_getParameterType: FieldFormalParameter has no type, looking up field declaration');
            final classDecl = declaration.parent;
            if (classDecl is ClassDeclaration) {
              final fieldType = _findFieldType(classDecl, fieldName);
              if (fieldType != null) {
                log('_getParameterType: Found field type: $fieldType');
                return fieldType;
              } else {
                log('_getParameterType: Field "$fieldName" not found in class');
              }
            }
          } else {
            log('_getParameterType: FieldFormalParameter has type: ${paramType.runtimeType}');
          }
        } else if (param is DefaultFormalParameter) {
          final innerParam = param.parameter;
          if (innerParam is SimpleFormalParameter) {
            paramType = innerParam.type;
          } else if (innerParam is FieldFormalParameter) {
            paramType = innerParam.type;
          }
        }
        if (paramType != null) {
          final typeStr = paramType.toString();
          log('_getParameterType: Extracted type string: "$typeStr"');

          // For NamedType, extract the name directly instead of using toString()
          if (paramType is NamedType) {
            final name = paramType.name.lexeme;
            log('_getParameterType: NamedType name: "$name"');
            return name;
          }
          return typeStr;
        } else {
          log('_getParameterType: Could not extract paramType from parameter');
        }
      } else {
        log('_getParameterType: Index $index out of range (${parameters.length} parameters)');
      }
    }
    log('_getParameterType: Returning null');
    return null;
  }

  String? _getParameterTypeByName(AstNode declaration, String paramName) {
    log('_getParameterTypeByName: Looking for parameter "$paramName"');

    if (declaration is FunctionDeclaration) {
      final parameters = declaration.functionExpression.parameters?.parameters ?? [];
      for (final param in parameters) {
        String? foundParamName;
        TypeAnnotation? paramType;

        if (param is SimpleFormalParameter) {
          foundParamName = param.name?.lexeme;
          paramType = param.type;
        } else if (param is DefaultFormalParameter) {
          final innerParam = param.parameter;
          if (innerParam is SimpleFormalParameter) {
            foundParamName = innerParam.name?.lexeme;
            paramType = innerParam.type;
          }
        }

        if (foundParamName == paramName && paramType != null) {
          final typeStr = paramType.toString();
          if (paramType is NamedType) {
            return paramType.name.lexeme;
          }
          return typeStr;
        }
      }
    } else if (declaration is ConstructorDeclaration) {
      final parameters = declaration.parameters.parameters;
      for (final param in parameters) {
        String? foundParamName;
        String? paramTypeStr;

        if (param is SimpleFormalParameter) {
          foundParamName = param.name?.lexeme;
          if (param.type != null) {
            final paramType = param.type!;
            if (paramType is NamedType) {
              paramTypeStr = paramType.name.lexeme;
            } else {
              paramTypeStr = paramType.toString();
            }
          }
        } else if (param is FieldFormalParameter) {
          foundParamName = param.name.lexeme;
          if (param.type != null) {
            final paramType = param.type!;
            if (paramType is NamedType) {
              paramTypeStr = paramType.name.lexeme;
            } else {
              paramTypeStr = paramType.toString();
            }
          } else {
            // Look up the field type from the class
            final classDecl = declaration.parent;
            if (classDecl is ClassDeclaration) {
              paramTypeStr = _findFieldType(classDecl, foundParamName);
            }
          }
        } else if (param is DefaultFormalParameter) {
          final innerParam = param.parameter;
          if (innerParam is SimpleFormalParameter) {
            foundParamName = innerParam.name?.lexeme;
            if (innerParam.type != null) {
              final paramType = innerParam.type!;
              if (paramType is NamedType) {
                paramTypeStr = paramType.name.lexeme;
              } else {
                paramTypeStr = paramType.toString();
              }
            }
          } else if (innerParam is FieldFormalParameter) {
            foundParamName = innerParam.name.lexeme;
            if (innerParam.type != null) {
              final paramType = innerParam.type!;
              if (paramType is NamedType) {
                paramTypeStr = paramType.name.lexeme;
              } else {
                paramTypeStr = paramType.toString();
              }
            } else {
              // Look up the field type from the class
              final classDecl = declaration.parent;
              if (classDecl is ClassDeclaration) {
                paramTypeStr = _findFieldType(classDecl, foundParamName);
              }
            }
          }
        }

        if (foundParamName == paramName) {
          log('_getParameterTypeByName: Found parameter "$paramName" with type "$paramTypeStr"');
          return paramTypeStr;
        }
      }
    }

    log('_getParameterTypeByName: Parameter "$paramName" not found');
    return null;
  }

  String? _findFieldType(ClassDeclaration classDecl, String fieldName) {
    log('_findFieldType: Looking for field "$fieldName" in class "${classDecl.name.lexeme}"');
    for (final member in classDecl.members) {
      if (member is FieldDeclaration) {
        for (final field in member.fields.variables) {
          log('_findFieldType: Found field "${field.name.lexeme}"');
          if (field.name.lexeme == fieldName) {
            // Get the type from the field declaration
            final typeAnnotation = member.fields.type;
            if (typeAnnotation != null && typeAnnotation is NamedType) {
              final typeName = typeAnnotation.name.lexeme;
              log('_findFieldType: Field "$fieldName" has type "$typeName"');
              return typeName;
            } else {
              log('_findFieldType: Field "$fieldName" type annotation: ${typeAnnotation?.runtimeType}');
            }
          }
        }
      }
    }
    log('_findFieldType: Field "$fieldName" not found');
    return null;
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    final funcSig = _getFunctionSignature(node);
    log('visitFunctionExpression: Found function expression with signature "$funcSig"');

    // Check if this function expression is assigned to or passed as a union type
    final parent = node.parent;
    log('visitFunctionExpression: Parent type: ${parent.runtimeType}');

    // Case 1: Assigned to a variable
    if (parent is VariableDeclaration && parent.initializer == node) {
      log('visitFunctionExpression: Case 1 - Function assigned to variable "${parent.name.lexeme}"');
      final typeName = _getTypeName(parent);
      log('visitFunctionExpression: Variable type: "$typeName"');
      if (typeName != null && isUnionType(typeName)) {
        log('visitFunctionExpression: Variable type is union type, checking signature');
        _checkFunctionSignature(node, typeName, node.offset);
      }
    }
    // Case 2: Passed as constructor argument (positional)
    else if (parent is ArgumentList) {
      log('visitFunctionExpression: Case 2 - Function in ArgumentList');
      final grandParent = parent.parent;
      log('visitFunctionExpression: GrandParent type: ${grandParent?.runtimeType}');
      if (grandParent is InstanceCreationExpression) {
        final argIndex = parent.arguments.indexOf(node);
        log('visitFunctionExpression: Found in InstanceCreationExpression at argument index $argIndex');
        if (argIndex >= 0) {
          // Skip - visitInstanceCreationExpression will handle this to avoid duplicate violations
          log('visitFunctionExpression: Skipping - will be handled by visitInstanceCreationExpression');
        }
      } else if (grandParent is FunctionExpressionInvocation) {
        log('visitFunctionExpression: Found in FunctionExpressionInvocation (skipping - needs element resolution)');
        // For function calls, we'd need element resolution to know parameter types
        // Skip for now
      }
    }
    // Case 3: Passed as constructor argument (named)
    else if (parent is NamedExpression && parent.expression == node) {
      log('visitFunctionExpression: Case 3 - Function in NamedExpression');
      final grandParent = parent.parent;
      if (grandParent is ArgumentList) {
        final greatGrandParent = grandParent.parent;
        if (greatGrandParent is InstanceCreationExpression) {
          // Skip - visitInstanceCreationExpression will handle this to avoid duplicate violations
          log('visitFunctionExpression: Skipping - will be handled by visitInstanceCreationExpression');
        }
      }
    }

    super.visitFunctionExpression(node);
  }

  void _checkConstructorArgument(
    FunctionExpression func,
    InstanceCreationExpression creation,
    int argIndex,
    bool isNamed,
    int offset,
    [String? paramName]
  ) {
    log('_checkConstructorArgument: Checking constructor argument (isNamed=$isNamed, argIndex=$argIndex, paramName=$paramName)');

    // Try to find the class and its constructor to get parameter types
    String? typeName;
    final className = creation.staticType?.element?.name;
    log('_checkConstructorArgument: staticType?.element?.name: $className');

    if (className != null) {
      typeName = className;
      log('_checkConstructorArgument: Using element resolution, typeName=$typeName');
    } else {
      // Without element resolution, try to get from AST
      final type = creation.constructorName.type;
      log('_checkConstructorArgument: constructorName.type: ${type.runtimeType}');
      typeName = type.name.lexeme;
      log('_checkConstructorArgument: Looking for class "$typeName"');
    }

    // Look for the class definition to find constructor parameters
    final classDecl = _findClassDeclaration(typeName, creation);
    if (classDecl != null) {
      log('_checkConstructorArgument: Found class declaration for "$typeName"');
      final constructor = _findConstructor(classDecl);
      if (constructor != null) {
        log('_checkConstructorArgument: Found constructor');
        final parameters = constructor.parameters.parameters;
        log('_checkConstructorArgument: Constructor has ${parameters.length} parameters');

        if (isNamed && paramName != null) {
          log('_checkConstructorArgument: Looking for named parameter "$paramName"');
          // Find named parameter
          for (final param in parameters) {
            if (param is DefaultFormalParameter) {
              final innerParam = param.parameter;
              String? foundParamName;
              String? unionTypeName;

              if (innerParam is SimpleFormalParameter) {
                foundParamName = innerParam.name?.lexeme;
                final paramType = innerParam.type;
                log('_checkConstructorArgument: Parameter type: ${paramType?.runtimeType}');
                if (paramType != null) {
                  final typeStr = paramType.toString();
                  unionTypeName = _extractUnionTypeName(typeStr);
                }
              } else if (innerParam is FieldFormalParameter) {
                // For "this.fieldName" syntax, get type from field declaration
                foundParamName = innerParam.name.lexeme;
                log('_checkConstructorArgument: FieldFormalParameter (this.$foundParamName)');
                final fieldType = _findFieldType(classDecl, foundParamName);
                if (fieldType != null) {
                  unionTypeName = _extractUnionTypeName(fieldType);
                  log('_checkConstructorArgument: Found field type: "$unionTypeName"');
                } else {
                  log('_checkConstructorArgument: Could not find field type for "$foundParamName"');
                }
              }

              if (foundParamName == paramName) {
                log('_checkConstructorArgument: Found named parameter "$paramName"');
                log('_checkConstructorArgument: Parameter type name: "$unionTypeName"');
                if (unionTypeName != null && isUnionType(unionTypeName)) {
                  log('_checkConstructorArgument: Parameter type is union type, checking signature');
                  _checkFunctionSignature(func, unionTypeName, offset);
                }
                break;
              }
            }
          }
        } else if (argIndex >= 0 && argIndex < parameters.length) {
          log('_checkConstructorArgument: Looking for positional parameter at index $argIndex');
          // Find positional parameter
          final param = parameters[argIndex];
          log('_checkConstructorArgument: Parameter at index $argIndex: ${param.runtimeType}');
          String? unionTypeName;

          // Handle different parameter types
          if (param is SimpleFormalParameter) {
            final paramType = param.type;
            log('_checkConstructorArgument: SimpleFormalParameter, type: ${paramType?.runtimeType}');
            if (paramType != null) {
              final typeStr = paramType.toString();
              unionTypeName = _extractUnionTypeName(typeStr);
            }
          } else if (param is FieldFormalParameter) {
            // For "this.fieldName" syntax, get type from field declaration
            final fieldName = param.name.lexeme;
            log('_checkConstructorArgument: FieldFormalParameter (this.$fieldName)');
            final fieldType = _findFieldType(classDecl, fieldName);
            if (fieldType != null) {
              unionTypeName = _extractUnionTypeName(fieldType);
              log('_checkConstructorArgument: Found field type: "$unionTypeName"');
            } else {
              log('_checkConstructorArgument: Could not find field type for "$fieldName"');
            }
          } else if (param is DefaultFormalParameter) {
            final innerParam = param.parameter;
            log('_checkConstructorArgument: DefaultFormalParameter, inner: ${innerParam.runtimeType}');
            if (innerParam is SimpleFormalParameter) {
              final paramType = innerParam.type;
              if (paramType != null) {
                final typeStr = paramType.toString();
                unionTypeName = _extractUnionTypeName(typeStr);
              }
            } else if (innerParam is FieldFormalParameter) {
              final fieldName = innerParam.name.lexeme;
              final fieldType = _findFieldType(classDecl, fieldName);
              if (fieldType != null) {
                unionTypeName = _extractUnionTypeName(fieldType);
              }
            }
          }

          if (unionTypeName != null) {
            log('_checkConstructorArgument: Extracted parameter type name: "$unionTypeName"');
            if (isUnionType(unionTypeName)) {
              log('_checkConstructorArgument: Parameter type is union type, checking signature');
              _checkFunctionSignature(func, unionTypeName, offset);
            } else {
              log('_checkConstructorArgument: Parameter type "$unionTypeName" is NOT a union type');
            }
          } else {
            log('_checkConstructorArgument: Could not extract union type name from parameter');
          }
        } else {
          log('_checkConstructorArgument: argIndex $argIndex is out of bounds (parameters.length = ${parameters.length})');
        }
      } else {
        log('_checkConstructorArgument: No constructor found in class');
      }
    } else {
      log('_checkConstructorArgument: Class declaration not found for "$typeName"');
    }
  }

  void _checkConstructorClassArgument(
    InstanceCreationExpression instanceArg,
    InstanceCreationExpression creation,
    int argIndex,
    bool isNamed,
    int offset,
    [String? paramName]
  ) {
    log('_checkConstructorClassArgument: Checking class instance constructor argument (isNamed=$isNamed, argIndex=$argIndex, paramName=$paramName)');

    // Try to find the class and its constructor to get parameter types
    String? typeName;
    final className = creation.staticType?.element?.name;
    log('_checkConstructorClassArgument: staticType?.element?.name: $className');

    if (className != null) {
      typeName = className;
      log('_checkConstructorClassArgument: Using element resolution, typeName=$typeName');
    } else {
      // Without element resolution, try to get from AST
      final type = creation.constructorName.type;
      log('_checkConstructorClassArgument: constructorName.type: ${type.runtimeType}');
      typeName = type.name.lexeme;
      log('_checkConstructorClassArgument: Looking for class "$typeName"');
    }

    // Look for the class definition to find constructor parameters
    final classDecl = _findClassDeclaration(typeName, creation);
    if (classDecl != null) {
      log('_checkConstructorClassArgument: Found class declaration for "$typeName"');
      final constructor = _findConstructor(classDecl);
      if (constructor != null) {
        log('_checkConstructorClassArgument: Found constructor');
        final parameters = constructor.parameters.parameters;
        log('_checkConstructorClassArgument: Constructor has ${parameters.length} parameters');

        if (isNamed && paramName != null) {
          log('_checkConstructorClassArgument: Looking for named parameter "$paramName"');
          // Find named parameter
          for (final param in parameters) {
            if (param is DefaultFormalParameter) {
              final innerParam = param.parameter;
              String? foundParamName;
              String? unionTypeName;

              if (innerParam is SimpleFormalParameter) {
                foundParamName = innerParam.name?.lexeme;
                final paramType = innerParam.type;
                log('_checkConstructorClassArgument: Parameter type: ${paramType?.runtimeType}');
                if (paramType != null) {
                  final typeStr = paramType.toString();
                  unionTypeName = _extractUnionTypeName(typeStr);
                }
              } else if (innerParam is FieldFormalParameter) {
                // For "this.fieldName" syntax, get type from field declaration
                foundParamName = innerParam.name.lexeme;
                log('_checkConstructorClassArgument: FieldFormalParameter (this.$foundParamName)');
                final fieldType = _findFieldType(classDecl, foundParamName);
                if (fieldType != null) {
                  unionTypeName = _extractUnionTypeName(fieldType);
                  log('_checkConstructorClassArgument: Found field type: "$unionTypeName"');
                } else {
                  log('_checkConstructorClassArgument: Could not find field type for "$foundParamName"');
                }
              }

              if (foundParamName == paramName) {
                log('_checkConstructorClassArgument: Found named parameter "$paramName"');
                log('_checkConstructorClassArgument: Parameter type name: "$unionTypeName"');
                if (unionTypeName != null && isUnionType(unionTypeName)) {
                  log('_checkConstructorClassArgument: Parameter type is union type, checking class instance');
                  _checkClassInstance(instanceArg, unionTypeName, offset);
                }
                break;
              }
            }
          }
        } else if (argIndex >= 0 && argIndex < parameters.length) {
          log('_checkConstructorClassArgument: Looking for positional parameter at index $argIndex');
          // Find positional parameter
          final param = parameters[argIndex];
          log('_checkConstructorClassArgument: Parameter at index $argIndex: ${param.runtimeType}');
          String? unionTypeName;

          // Handle different parameter types
          if (param is SimpleFormalParameter) {
            final paramType = param.type;
            log('_checkConstructorClassArgument: SimpleFormalParameter, type: ${paramType?.runtimeType}');
            if (paramType != null) {
              final typeStr = paramType.toString();
              unionTypeName = _extractUnionTypeName(typeStr);
            }
          } else if (param is FieldFormalParameter) {
            // For "this.fieldName" syntax, get type from field declaration
            final fieldName = param.name.lexeme;
            log('_checkConstructorClassArgument: FieldFormalParameter (this.$fieldName)');
            final fieldType = _findFieldType(classDecl, fieldName);
            if (fieldType != null) {
              unionTypeName = _extractUnionTypeName(fieldType);
              log('_checkConstructorClassArgument: Found field type: "$unionTypeName"');
            } else {
              log('_checkConstructorClassArgument: Could not find field type for "$fieldName"');
            }
          } else if (param is DefaultFormalParameter) {
            final innerParam = param.parameter;
            log('_checkConstructorClassArgument: DefaultFormalParameter, inner: ${innerParam.runtimeType}');
            if (innerParam is SimpleFormalParameter) {
              final paramType = innerParam.type;
              if (paramType != null) {
                final typeStr = paramType.toString();
                unionTypeName = _extractUnionTypeName(typeStr);
              }
            } else if (innerParam is FieldFormalParameter) {
              final fieldName = innerParam.name.lexeme;
              final fieldType = _findFieldType(classDecl, fieldName);
              if (fieldType != null) {
                unionTypeName = _extractUnionTypeName(fieldType);
              }
            }
          }

          if (unionTypeName != null) {
            log('_checkConstructorClassArgument: Extracted parameter type name: "$unionTypeName"');
            if (isUnionType(unionTypeName)) {
              log('_checkConstructorClassArgument: Parameter type is union type, checking class instance');
              _checkClassInstance(instanceArg, unionTypeName, offset);
            } else {
              log('_checkConstructorClassArgument: Parameter type "$unionTypeName" is NOT a union type');
            }
          } else {
            log('_checkConstructorClassArgument: Could not extract union type name from parameter');
          }
        } else {
          log('_checkConstructorClassArgument: argIndex $argIndex is out of bounds (parameters.length = ${parameters.length})');
        }
      } else {
        log('_checkConstructorClassArgument: No constructor found in class');
      }
    } else {
      log('_checkConstructorClassArgument: Class declaration not found for "$typeName"');
    }
  }

  ClassDeclaration? _findClassDeclaration(String className, AstNode context) {
    log('_findClassDeclaration: Looking for class "$className"');
    final unit = context.thisOrAncestorOfType<CompilationUnit>();
    if (unit == null) {
      log('_findClassDeclaration: No CompilationUnit found');
      return null;
    }

    log('_findClassDeclaration: Checking ${unit.declarations.length} declarations');
    for (final declaration in unit.declarations) {
      if (declaration is ClassDeclaration && declaration.name.lexeme == className) {
        log('_findClassDeclaration: Found class "$className"');
        return declaration;
      }
    }
    log('_findClassDeclaration: Class "$className" not found');
    return null;
  }

  ConstructorDeclaration? _findConstructor(ClassDeclaration classDecl) {
    log('_findConstructor: Looking for constructor in class "${classDecl.name.lexeme}"');
    log('_findConstructor: Class has ${classDecl.members.length} members');
    for (final member in classDecl.members) {
      if (member is ConstructorDeclaration) {
        log('_findConstructor: Found constructor');
        return member; // Return first constructor
      }
    }
    log('_findConstructor: No constructor found');
    return null;
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    log('visitInstanceCreationExpression: Found instance creation');
    final type = node.constructorName.type;
    final typeName = type.name.lexeme;
    log('visitInstanceCreationExpression: Creating instance of "$typeName"');

    // Check each argument
    for (int i = 0; i < node.argumentList.arguments.length; i++) {
      final arg = node.argumentList.arguments[i];
      log('visitInstanceCreationExpression: Argument $i: ${arg.runtimeType}');

      if (arg is FunctionExpression) {
        log('visitInstanceCreationExpression: Argument $i is a FunctionExpression');
        checkedInInstanceCreation.add(arg.offset);
        _checkConstructorArgument(
          arg,
          node,
          i,
          false,
          arg.offset,
        );
      } else if (arg is NamedExpression && arg.expression is FunctionExpression) {
        log('visitInstanceCreationExpression: Argument $i is a NamedExpression with FunctionExpression');
        final paramName = arg.name.label.name;
        final funcExpr = arg.expression as FunctionExpression;
        checkedInInstanceCreation.add(funcExpr.offset);
        _checkConstructorArgument(
          funcExpr,
          node,
          -1,
          true,
          arg.offset,
          paramName,
        );
      } else if (arg is InstanceCreationExpression) {
        log('visitInstanceCreationExpression: Argument $i is an InstanceCreationExpression');
        _checkConstructorClassArgument(
          arg,
          node,
          i,
          false,
          arg.offset,
        );
      } else if (arg is NamedExpression && arg.expression is InstanceCreationExpression) {
        log('visitInstanceCreationExpression: Argument $i is a NamedExpression with InstanceCreationExpression');
        final paramName = arg.name.label.name;
        _checkConstructorClassArgument(
          arg.expression as InstanceCreationExpression,
          node,
          -1,
          true,
          arg.offset,
          paramName,
        );
      }
    }
      super.visitInstanceCreationExpression(node);
  }

  List<String> _extractAllowedTypes(Annotation node) {
    log('_extractAllowedTypes: Extracting allowed types from annotation');
    final arguments = node.arguments;
    if (arguments == null || arguments.arguments.isEmpty) {
      log('_extractAllowedTypes: No arguments found');
      return [];
    }

    log('_extractAllowedTypes: Found ${arguments.arguments.length} arguments');
    // Extract Type literals from the annotation arguments
    // @UnionType([VoidCallback, OnTapCtx, ...])
    final firstArg = arguments.arguments.first;
    log('_extractAllowedTypes: First argument type: ${firstArg.runtimeType}');

    if (firstArg is ListLiteral) {
      log('_extractAllowedTypes: First argument is ListLiteral with ${firstArg.elements.length} elements');
      final allowedTypes = <String>[];

      for (int i = 0; i < firstArg.elements.length; i++) {
        final element = firstArg.elements[i];
        log('_extractAllowedTypes: Element $i: ${element.runtimeType}');

        String? typeName;
        if (element is TypeLiteral) {
          typeName = _extractTypeName(element);
          log('_extractAllowedTypes: Element $i is TypeLiteral, extracted: "$typeName"');
        } else if (element is Identifier) {
          // Handle SimpleIdentifier - these are type references like VoidCallback, OnTapCtx
          typeName = element.name;
          log('_extractAllowedTypes: Element $i is Identifier, name: "$typeName"');
        }

        if (typeName != null && typeName.isNotEmpty) {
          allowedTypes.add(typeName);
        }
      }

      log('_extractAllowedTypes: Extracted allowed types: $allowedTypes');
      return allowedTypes;
    }

    log('_extractAllowedTypes: First argument is not a ListLiteral');
    return [];
  }

  String _extractTypeName(TypeLiteral node) {
    log('_extractTypeName: Extracting type name from TypeLiteral');
    final type = node.type;
    log('_extractTypeName: Type: ${type.runtimeType}');
    final name = type.name.lexeme;
    log('_extractTypeName: Extracted name: "$name"');
    return name;
    }

  String? _getTypeName(VariableDeclaration node) {
    // Try to get type from the type annotation
    final parent = node.parent;
    log('_getTypeName: Variable parent type: ${parent.runtimeType}');

    if (parent is VariableDeclarationList) {
      final typeAnnotation = parent.type;
      log('_getTypeName: Type annotation: ${typeAnnotation?.runtimeType}');
      if (typeAnnotation != null && typeAnnotation is NamedType) {
        final typeName = typeAnnotation.name.lexeme;
        log('_getTypeName: Extracted type name: "$typeName"');
        return typeName;
      }
    }
    log('_getTypeName: Could not extract type name');
    return null;
  }

  String? _extractUnionTypeName(String typeStr) {
    // Extract the base type name, removing nullable and other modifiers
    // e.g., "OnTap?" -> "OnTap"
    // e.g., "(OnTap?)" -> "OnTap"
    final match = RegExp(r'([A-Za-z][A-Za-z0-9_]*)').firstMatch(typeStr);
    return match?.group(1);
  }

  String _extractTypedefSignature(GenericFunctionType node) {
    // Extract function signature from typedef
    // e.g., typedef VoidCallback = void Function(); -> "void Function()"
    final returnType = node.returnType?.toString() ?? 'void';

    // Get formal parameters
    final formalParams = node.parameters.parameters;
    final paramTypes = formalParams.map((p) {
      if (p is SimpleFormalParameter) {
        final type = p.type;
        if (type != null && type is NamedType) {
          return type.name.lexeme;
        }
      }
      return 'dynamic';
    }).join(', ');

    return '$returnType Function($paramTypes)';
  }

  void _checkAssignment(Expression expression, String unionTypeName, int offset) {
    if (expression is FunctionExpression) {
      _checkFunctionSignature(expression, unionTypeName, offset);
    }
  }

  void _checkFunctionSignature(FunctionExpression func, String unionTypeName, int offset) {
    log('_checkFunctionSignature: Checking function against union type "$unionTypeName"');

    final allowedTypes = getAllowedTypes(unionTypeName);
    log('_checkFunctionSignature: Allowed types for "$unionTypeName": $allowedTypes');

    if (allowedTypes.isEmpty) {
      log('_checkFunctionSignature: No allowed types found, skipping');
      // Union type not found or has no allowed types
      return;
    }

    final funcSignature = _getFunctionSignature(func);
    log('_checkFunctionSignature: Function signature: "$funcSignature"');

    bool matches = false;
    for (final allowedType in allowedTypes) {
      log('_checkFunctionSignature: Checking against allowed type "$allowedType"');
      if (_signaturesMatch(funcSignature, allowedType)) {
        log('_checkFunctionSignature: ✓ Signature matches "$allowedType"');
        matches = true;
        break;
      } else {
        log('_checkFunctionSignature: ✗ Signature does NOT match "$allowedType"');
      }
    }

    if (!matches) {
      final lineInfo = func.thisOrAncestorOfType<CompilationUnit>()?.lineInfo;
      final lineNumber = lineInfo?.getLocation(offset).lineNumber;
      log('_checkFunctionSignature: ✗✗✗ VIOLATION FOUND at line $lineNumber ✗✗✗');
      reportViolation(
        node: func,
        unionTypeName: unionTypeName,
        allowedTypes: allowedTypes,
        target: funcSignature,
        lineNumber: lineNumber,
        offset: offset,
        length: func.length,
      );
    } else {
      log('_checkFunctionSignature: ✓ Function signature is valid');
    }
  }

  String _getFunctionSignature(FunctionExpression func) {
    final parameters = func.parameters?.parameters ?? [];
    log('_getFunctionSignature: Function has ${parameters.length} parameters');

    final paramTypes = parameters.map((p) {
      if (p is SimpleFormalParameter) {
        final type = p.type;
        if (type != null && type is NamedType) {
          final typeName = type.name.lexeme;
          log('_getFunctionSignature: Parameter type: "$typeName"');
          return typeName;
        } else if (type == null) {
          log('_getFunctionSignature: Parameter has no type annotation (dynamic)');
          return 'dynamic';
        }
      }
      log('_getFunctionSignature: Parameter is not SimpleFormalParameter (dynamic)');
      return 'dynamic';
    }).join(', ');

    final signature = 'void Function($paramTypes)';
    log('_getFunctionSignature: Generated signature: "$signature"');
    return signature;
  }

  bool _signaturesMatch(String funcSignature, String allowedType) {
    log('_signaturesMatch: Comparing "$funcSignature" with "$allowedType"');

    // First, check if allowedType is a typedef name that needs resolution
    String resolvedAllowedType = allowedType;
    final typedefSignature = resolveTypedef(allowedType);
    if (typedefSignature != null) {
      log('_signaturesMatch: Resolved typedef "$allowedType" to "$typedefSignature"');
      resolvedAllowedType = typedefSignature;
    } else {
      log('_signaturesMatch: "$allowedType" is not a typedef or not found in typedefSignatures');
    }

    // Extract parameter types from both signatures
    final params1 = _extractParameters(funcSignature);
    final params2 = _extractParameters(resolvedAllowedType);
    log('_signaturesMatch: Function params: $params1');
    log('_signaturesMatch: Allowed type params: $params2');

    // Parameter count must match
    if (params1.length != params2.length) {
      log('_signaturesMatch: Parameter count mismatch (${params1.length} vs ${params2.length})');
      return false;
    }

    // Check parameter type compatibility
    for (int i = 0; i < params1.length; i++) {
      log('_signaturesMatch: Checking param $i: "${params1[i]}" vs "${params2[i]}"');
      if (!_checkTypeCompatibility(params1[i], params2[i])) {
        log('_signaturesMatch: Parameter $i types are NOT compatible');
        return false;
      } else {
        log('_signaturesMatch: Parameter $i types are compatible');
      }
    }

    log('_signaturesMatch: ✓ All parameters match');
    return true;
  }

  List<String> _extractParameters(String signature) {
    // Extract parameter types from signature string
    // e.g., "void Function(BuildContext, dynamic)" -> ["BuildContext", "dynamic"]
    final match = RegExp(r'Function\(([^)]*)\)').firstMatch(signature);
    if (match == null || match.group(1)!.isEmpty) {
      return [];
    }
    return match.group(1)!.split(',').map((s) => s.trim()).toList();
  }

  void _checkClassInstance(InstanceCreationExpression instanceCreation, String unionTypeName, int offset) {
    log('_checkClassInstance: Checking class instance against union type "$unionTypeName"');

    final type = instanceCreation.constructorName.type;

    final className = type.name.lexeme;
    log('_checkClassInstance: Class name: "$className"');

    final allowedTypes = getAllowedTypes(unionTypeName);
    log('_checkClassInstance: Allowed types: $allowedTypes');

    if (allowedTypes.isEmpty) {
      log('_checkClassInstance: No allowed types found, skipping');
      return;
    }

    // Find the class declaration
    final classDecl = _findClassDeclaration(className, instanceCreation);
    if (classDecl == null) {
      log('_checkClassInstance: Class declaration not found for "$className"');
      return;
    }

    // Check if the class implements any of the allowed interface types
    bool matches = false;
    for (final allowedType in allowedTypes) {
      log('_checkClassInstance: Checking against allowed type "$allowedType"');

      // Check if allowedType is a typedef (function type) - skip those for class instances
      final typedefSig = resolveTypedef(allowedType);
      if (typedefSig != null) {
        log('_checkClassInstance: "$allowedType" is a function typedef, skipping for class instance');
        continue;
      }

      // Check if allowedType is an interface that the class implements
      if (_classImplementsInterface(classDecl, allowedType)) {
        log('_checkClassInstance: ✓ Class "$className" implements "$allowedType"');
        matches = true;
        break;
      } else {
        log('_checkClassInstance: ✗ Class "$className" does NOT implement "$allowedType"');
      }
    }

    if (!matches) {
      final lineInfo = instanceCreation.thisOrAncestorOfType<CompilationUnit>()?.lineInfo;
      final lineNumber = lineInfo?.getLocation(offset).lineNumber;
      log('_checkClassInstance: ✗✗✗ VIOLATION FOUND at line $lineNumber ✗✗✗');
      reportViolation(
        target: className,
        unionTypeName: unionTypeName,
        lineNumber: lineNumber,
        allowedTypes: allowedTypes,
        node: instanceCreation,
        offset: offset,
        length: instanceCreation.length,
      );
    } else {
      log('_checkClassInstance: ✓ Class instance is valid');
    }
  }

  bool _classImplementsInterface(ClassDeclaration classDecl, String interfaceName) {
    log('_classImplementsInterface: Checking if "${classDecl.name.lexeme}" implements "$interfaceName"');

    // Check implements clause
    final implementsClause = classDecl.implementsClause;
    if (implementsClause != null) {
      for (final interfaceType in implementsClause.interfaces) {
        final interfaceTypeName = interfaceType.name.lexeme;
        log('_classImplementsInterface: Class implements "$interfaceTypeName"');
        if (interfaceTypeName == interfaceName) {
          log('_classImplementsInterface: ✓ Found matching interface "$interfaceName"');
          return true;
        }
            }
    } else {
      log('_classImplementsInterface: Class has no implements clause');
    }

    log('_classImplementsInterface: ✗ Class does not implement "$interfaceName"');
    return false;
  }

  bool _checkTypeCompatibility(String actualType, String expectedType) {
    log('_checkTypeCompatibility: Comparing "$actualType" with "$expectedType"');

    // Basic type compatibility check
    // - Exact match
    if (actualType == expectedType) {
      log('_checkTypeCompatibility: Exact match');
      return true;
    }

    // - dynamic accepts anything
    if (expectedType == 'dynamic') {
      log('_checkTypeCompatibility: Expected type is dynamic, accepting');
      return true;
    }

    // - Check if expectedType is a typedef that resolves to actualType
    final typedefSig = resolveTypedef(expectedType);
    if (typedefSig != null) {
      log('_checkTypeCompatibility: Expected type is a typedef, resolving to "$typedefSig"');
      final expectedParams = _extractParameters(typedefSig);
      final result = expectedParams.length == 1 && expectedParams[0] == actualType;
      log('_checkTypeCompatibility: Typedef resolution result: $result');
      return result;
    }

    log('_checkTypeCompatibility: Types are NOT compatible');
    return false;
  }

}