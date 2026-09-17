/// Wires all built-in expression function families.
library;

import '../function_registry.dart';
import 'format_functions.dart';
import 'logic_functions.dart';
import 'math_functions.dart';
import 'string_functions.dart';

/// Registers every built-in function family (math, string, logic, format) into
/// [registry]. Further functions can be registered afterwards, and families can
/// be registered individually via the per-family entry points — from inside the
/// package only: no public entry point accepts a [JetFunctionRegistry], so a
/// host cannot reach one (see `expression/function_registry.dart`).
void registerBuiltInFunctions(JetFunctionRegistry registry) {
  registerMathFunctions(registry);
  registerStringFunctions(registry);
  registerLogicFunctions(registry);
  registerFormatFunctions(registry);
}
