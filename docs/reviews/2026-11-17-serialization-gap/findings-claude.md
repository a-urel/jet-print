F1 [major] Three places it stops short of a database
claim: `kReportDefinitionSchemaVersion` is `2` and is stamped as the first key of every document.
evidence: `report_definition_codec.dart` declares `kReportDefinitionSchemaVersion = 3` and `kReportDefinitionBaselineSchemaVersion = 2`; `encodeDefinition` stamps `schemaVersionFor(def)`, 3 for roll paper and 2 otherwise; CHANGELOG 1.1.0 *Compatibility* says the same.
fix: State the constant as 3 and say the stamped key is `schemaVersionFor`'s lowest-holding version, not the constant.

F2 [major] What a consumer must do today
claim: The save sample stores `schemaVersion: JetReportFormat.schemaVersion` as the row's version column.
evidence: `JetReportFormat.schemaVersion` is 3 while `encodeDefinition` stamps a sheet report 2; the document's own point One says "a host reads each row's own key", and CHANGELOG 1.1.0 says "A host that stores the stamped version should read it from each document".
fix: Make the sample read `schemaVersion` from the encoded map and reserve the constant for the "is this row from the future" comparison.

F3 [major] What would have to be exported
claim: Migration "needs only the version constant above for a consumer to know which rows to re-save"; `decodeDefinition` migrates "whenever `rawVersion` is below the current one".
evidence: `decodeDefinition` in `report_definition_codec.dart` runs `runMigrations` only when `rawVersion < kReportDefinitionBaselineSchemaVersion` (2); a v2 row under this build is current and re-saves as 2, so comparing against the exported 3 flags every sheet report forever, and the baseline constant is not exported.
fix: Correct the migration trigger to "below the baseline" and record that the re-save question now needs the unexported baseline, reopening the third item.

F4 [minor] The exported surface, name by name
claim: The unexported names in `report_definition_codec.dart` are the top-level codec functions and the constant `kReportDefinitionSchemaVersion`.
evidence: The same file also declares `kReportDefinitionBaselineSchemaVersion` and `schemaVersionFor`, both unexported and both deciding what a row actually carries.
fix: Add the two names to the inventory, since the page's argument now depends on them.

F5 [minor] Three places it stops short of a database
claim: A host finds `UnknownElement` and `UnknownScopeNode` by recursion "and reads `typeKey`".
evidence: `unknown_scope_node.dart` → `UnknownScopeNode` exposes `String? kind` and `rawJson`; only `UnknownElement` in `unknown_element.dart` has `typeKey`.
fix: Say `typeKey` for elements and `kind` for scope nodes.

F6 [minor] Three places it stops short of a database
claim: The barrel-only test "reads it instead of reconstructing it", and reconstructing the constant from an encoded fixture "is the surface reporting a hole in itself".
evidence: In `test/domain/serialization/report_format_test.dart`, *throws ReportFormatException on a version newer than the build* uses `JetReportFormat.schemaVersion`, but *preserves an unknown element type byte-for-byte* still obtains the number as `encodeDefinition(_fixture())['schemaVersion']`.
fix: Either note the remaining reconstruction or narrow the claim to the one test named.

F7 [minor] What would have to be exported
claim: The section lists "Two things, and a third that needs nothing", then calls the malformed-input boundary "the fourth item".
evidence: The preceding heading is *Three places it stops short of a database* and names three; no fourth place is introduced anywhere in the document.
fix: Either add the error-contract gap to the enumerated places or drop the "fourth item" framing.

F8 [hunch] Three places it stops short of a database
claim: The schema-version export landed in `c4a7f8d` before 0.1.0, and the error boundary in `7535890`.
evidence: not checked (no git access); the CHANGELOG 0.1.0 section does record `JetReportFormat.schemaVersion` and `malformed_input_test.dart` exists, which is consistent.
fix: Confirm both hashes resolve on `main` before the next edit, or cite CHANGELOG sections instead.

VERDICT: revise — the schema-version facts predate roll paper; constant, stamping, migration trigger and the save sample are now wrong.
