import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:lightning/core/node_model.dart';

class ConsistencyChecker {
  /// Validates if the exported configuration map is consistent with the original raw data.
  /// If [strict] is true, it requires all keys to match exactly.
  /// Returns a list of differences found.
  static List<String> checkConsistency(
    NodeModel node,
    Map<String, dynamic> exportedData,
  ) {
    if (node.rawData == null) return [];

    final List<String> differences = [];
    final original = node.rawData!;

    // We only check keys that exist in the original data to see if they were modified/dropped
    original.forEach((key, value) {
      if (!exportedData.containsKey(key)) {
        differences.add("Missing field: $key (Original value: $value)");
      } else {
        final exportedValue = exportedData[key];
        // Normalize value comparison (strings vs numbers etc)
        if (value.toString() != exportedValue.toString()) {
          differences.add(
            "Modified field: $key (Original: $value, Exported: $exportedValue)",
          );
        }
      }
    });

    // Check for unexpected extra fields (optional, but good for "100% fidelity" check)
    exportedData.forEach((key, value) {
      if (!original.containsKey(key)) {
        // Some fields like 'v' or 'ps' might be added if missing in raw but present in model
        // This is generally acceptable but we note it for strict auditing
        debugPrint("Note: Extra field in export: $key = $value");
      }
    });

    return differences;
  }

  /// High-level audit for Xray protocols
  static bool auditNode(NodeModel node, String exportedLink) {
    try {
      if (node.protocol == 'vmess') {
        final base64Part = exportedLink.substring(8);
        String normalized = base64Part;
        while (normalized.length % 4 != 0) normalized += '=';
        final exportedData = jsonDecode(utf8.decode(base64.decode(normalized)));
        final diffs = checkConsistency(node, exportedData);
        if (diffs.isNotEmpty) {
          debugPrint("VMess Consistency Audit Failed: ${diffs.join(', ')}");
          return false;
        }
      } else {
        final uri = Uri.parse(exportedLink);
        final exportedQuery = uri.queryParameters;
        final diffs = checkConsistency(node, exportedQuery);
        if (diffs.isNotEmpty) {
          debugPrint(
            "${node.protocol.toUpperCase()} Consistency Audit Failed: ${diffs.join(', ')}",
          );
          return false;
        }
      }
    } catch (e) {
      debugPrint("Audit error: $e");
      return false;
    }
    return true;
  }
}
