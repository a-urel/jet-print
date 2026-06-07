/// Wires all built-in expression function families (spec 005a).
library;

import '../function_registry.dart';
import 'format_functions.dart';
import 'logic_functions.dart';
import 'math_functions.dart';
import 'string_functions.dart';

/// Registers every built-in function family (math, string, logic, format) into
/// [registry]. Consumers may register additional functions afterwards, or
/// register families individually via the per-family entry points.
void registerBuiltInFunctions(JetFunctionRegistry registry) {
  registerMathFunctions(registry);
  registerStringFunctions(registry);
  registerLogicFunctions(registry);
  registerFormatFunctions(registry);
}
