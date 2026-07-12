import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class IosBackgroundGenerationStatus {
  const IosBackgroundGenerationStatus({
    required this.backgroundTaskActive,
    required this.notificationsAuthorized,
    required this.locationTrackingActive,
    required this.locationAlwaysAuthorized,
    required this.locationAuthorizationStatus,
    required this.liveActivityAvailable,
    required this.liveActivityActive,
    required this.liveActivitiesEnabled,
  });

  factory IosBackgroundGenerationStatus.fromMap(Map<dynamic, dynamic>? map) {
    bool readBool(String key) => map?[key] == true;
    final locationStatus =
        (map?['locationAuthorizationStatus'] as String?) ??
        (map?['locationAuthorization'] as String?) ??
        'unavailable';
    final liveActivitiesEnabled =
        readBool('liveActivitiesEnabled') || readBool('liveActivityAvailable');
    return IosBackgroundGenerationStatus(
      backgroundTaskActive: readBool('backgroundTaskActive'),
      notificationsAuthorized: readBool('notificationsAuthorized'),
      locationTrackingActive: readBool('locationTrackingActive'),
      locationAlwaysAuthorized:
          readBool('locationAlwaysAuthorized') || locationStatus == 'always',
      locationAuthorizationStatus: locationStatus,
      liveActivityAvailable: readBool('liveActivityAvailable'),
      liveActivityActive: readBool('liveActivityActive'),
      liveActivitiesEnabled: liveActivitiesEnabled,
    );
  }

  final bool backgroundTaskActive;
  final bool notificationsAuthorized;
  final bool locationTrackingActive;
  final bool locationAlwaysAuthorized;
  final String locationAuthorizationStatus;
  final bool liveActivityAvailable;
  final bool liveActivityActive;
  final bool liveActivitiesEnabled;

  static const unavailable = IosBackgroundGenerationStatus(
    backgroundTaskActive: false,
    notificationsAuthorized: false,
    locationTrackingActive: false,
    locationAlwaysAuthorized: false,
    locationAuthorizationStatus: 'unavailable',
    liveActivityAvailable: false,
    liveActivityActive: false,
    liveActivitiesEnabled: false,
  );
}

class IosBackgroundGenerationService {
  IosBackgroundGenerationService._();

  static final IosBackgroundGenerationService instance =
      IosBackgroundGenerationService._();

  static const MethodChannel _channel = MethodChannel(
    'app.ios_background_generation',
  );

  bool debugForceIosForTest = false;
  final Set<String> _nativeGenerationIds = <String>{};

  bool get _isIos => debugForceIosForTest || Platform.isIOS;

  Future<IosBackgroundGenerationStatus> getStatus() async {
    if (!_isIos) return IosBackgroundGenerationStatus.unavailable;
    final result = await _channel.invokeMethod<dynamic>('getStatus');
    return IosBackgroundGenerationStatus.fromMap(
      result as Map<dynamic, dynamic>?,
    );
  }

  Future<bool> requestNotificationAuthorization() async {
    if (!_isIos) return false;
    return await _channel.invokeMethod<bool>(
          'requestNotificationAuthorization',
        ) ??
        false;
  }

  Future<bool> requestLocationAlwaysAuthorization() async {
    if (!_isIos) return false;
    return await _channel.invokeMethod<bool>(
          'requestLocationAlwaysAuthorization',
        ) ??
        false;
  }

  Future<bool> setLocationTrackingEnabled(bool enabled) async {
    if (!_isIos) return false;
    return await _channel.invokeMethod<bool>(
          'setLocationTrackingEnabled',
          <String, Object?>{'enabled': enabled},
        ) ??
        false;
  }

  Future<bool> openAppSettings() async {
    if (!_isIos) return false;
    return await _channel.invokeMethod<bool>('openAppSettings') ?? false;
  }

  Future<bool> openNotificationSettings() async {
    if (!_isIos) return false;
    return await _channel.invokeMethod<bool>('openNotificationSettings') ??
        false;
  }

  Future<void> start({
    required bool enabled,
    required bool notificationsEnabled,
    required bool refreshEnabled,
    required bool locationTrackingEnabled,
    required bool liveActivityEnabled,
    required String conversationId,
    required String title,
    required String conversationTitle,
    required String detail,
    required String tokenLabel,
    int tokenCount = 0,
  }) async {
    if (!_isIos || !enabled) return;
    if (notificationsEnabled) {
      await requestNotificationAuthorization();
    }
    final started = await _channel
        .invokeMethod<bool>('start', <String, Object?>{
          'notificationsEnabled': notificationsEnabled,
          'refreshEnabled': refreshEnabled,
          'locationTrackingEnabled': locationTrackingEnabled,
          'liveActivityEnabled': liveActivityEnabled,
          'conversationId': conversationId,
          'title': title,
          'conversationTitle': conversationTitle,
          'detail': detail,
          'tokenCount': tokenCount,
          'tokenLabel': tokenLabel,
        });
    if (started == true) {
      _nativeGenerationIds.add(conversationId);
    }
  }

  Future<void> update({
    required String conversationId,
    required String conversationTitle,
    required String detail,
    required String tokenLabel,
    int? tokenCount,
  }) async {
    if (!_isIos || !_nativeGenerationIds.contains(conversationId)) return;
    await _channel.invokeMethod<bool>('update', <String, Object?>{
      'conversationId': conversationId,
      'conversationTitle': conversationTitle,
      'detail': detail,
      'tokenLabel': tokenLabel,
      if (tokenCount != null) 'tokenCount': tokenCount,
    });
  }

  Future<void> finish({
    required String conversationId,
    required String title,
    required String conversationTitle,
    required String detail,
    required bool success,
  }) async {
    if (!_isIos || !_nativeGenerationIds.contains(conversationId)) return;
    try {
      await _channel.invokeMethod<bool>('finish', <String, Object?>{
        'conversationId': conversationId,
        'title': title,
        'conversationTitle': conversationTitle,
        'detail': detail,
        'success': success,
      });
    } finally {
      _nativeGenerationIds.remove(conversationId);
    }
  }

  Future<void> cancel({
    required String conversationId,
    required String conversationTitle,
    String? detail,
  }) async {
    if (!_isIos || !_nativeGenerationIds.contains(conversationId)) return;
    try {
      await _channel.invokeMethod<bool>('cancel', <String, Object?>{
        'conversationId': conversationId,
        'conversationTitle': conversationTitle,
        if (detail != null) 'detail': detail,
      });
    } finally {
      _nativeGenerationIds.remove(conversationId);
    }
  }

  void resetForTest() {
    debugForceIosForTest = false;
    _nativeGenerationIds.clear();
  }
}
