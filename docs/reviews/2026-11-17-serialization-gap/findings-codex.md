F1 [major] What a consumer must do today
claim: Save the encoded JSON alongside schemaVersion: JetReportFormat.schemaVersion.
evidence: report_definition_codec.dart → schemaVersionFor writes 2 for sheet reports, while JetReportFormat.schemaVersion is 3; continuous_schema_version_test.dart pins both values.
fix: Encode once and store the encoded map's schemaVersion alongside JSON produced from that same map.
F2 [major] What would have to be exported
claim: Comparing a row's version with the public version constant tells a consumer which rows need migration and re-saving.
evidence: report_definition_codec.dart → decodeDefinition migrates only versions below baseline 2; valid sheet reports remain version 2 after re-saving although the public constant is 3.
fix: Explain the distinction between supported and migration-baseline versions, and specify a migration-detection strategy that does not repeatedly select current sheet reports.
F3 [minor] Three places it stops short of a database
claim: A host can detect UnknownElement and UnknownScopeNode recursively and read typeKey.
evidence: unknown_element.dart → UnknownElement exposes typeKey, but unknown_scope_node.dart → UnknownScopeNode exposes kind and rawJson, with no typeKey member.
fix: Name typeKey for unknown elements and kind for unknown scope nodes.
F4 [minor] The round trip is real, and first-party code uses it through the barrel
claim: Host callback failures reach onError rather than escaping.
evidence: JetReportDesigner.onError is optional; host_callback.dart → runHostCallback rethrows synchronous failures and sends asynchronous failures to the current zone when onError is null.
fix: Qualify the error-routing guarantee as applying when the host supplies onError.
VERDICT: revise — The database example stores incorrect version metadata, and migration guidance misclassifies valid sheet reports.
