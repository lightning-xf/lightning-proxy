import 'package:flutter/foundation.dart';

class SubscriptionModel {
  final String id;
  final String name;
  final String url;
  final DateTime? lastUpdate;
  final String? error;
  final int? totalData;
  final int? usedData;
  final DateTime? expireDate;
  final bool autoUpdate;
  final int updateInterval; // in hours
  final bool isUpdating;
  final bool isFile;

  SubscriptionModel({
    required this.id,
    required this.name,
    required this.url,
    this.lastUpdate,
    this.error,
    this.totalData,
    this.usedData,
    this.expireDate,
    this.autoUpdate = true,
    this.updateInterval = 24,
    this.isUpdating = false,
    this.isFile = false,
  });

  SubscriptionModel copyWith({
    String? id,
    String? name,
    String? url,
    DateTime? lastUpdate,
    String? error,
    int? totalData,
    int? usedData,
    DateTime? expireDate,
    bool? autoUpdate,
    int? updateInterval,
    bool? isUpdating,
    bool? isFile,
  }) {
    return SubscriptionModel(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      error: error ?? this.error,
      totalData: totalData ?? this.totalData,
      usedData: usedData ?? this.usedData,
      expireDate: expireDate ?? this.expireDate,
      autoUpdate: autoUpdate ?? this.autoUpdate,
      updateInterval: updateInterval ?? this.updateInterval,
      isUpdating: isUpdating ?? this.isUpdating,
      isFile: isFile ?? this.isFile,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'lastUpdate': lastUpdate?.toIso8601String(),
      'error': error,
      'totalData': totalData,
      'usedData': usedData,
      'expireDate': expireDate?.toIso8601String(),
      'autoUpdate': autoUpdate,
      'updateInterval': updateInterval,
      'isFile': isFile,
    };
  }

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) {
    return SubscriptionModel(
      id: json['id'],
      name: json['name'],
      url: json['url'],
      lastUpdate: json['lastUpdate'] != null
          ? DateTime.parse(json['lastUpdate'])
          : null,
      error: json['error'],
      totalData: json['totalData'],
      usedData: json['usedData'],
      expireDate: json['expireDate'] != null
          ? DateTime.parse(json['expireDate'])
          : null,
      autoUpdate: json['autoUpdate'] ?? true,
      updateInterval: json['updateInterval'] ?? 24,
      isFile: json['isFile'] ?? false,
    );
  }
}
