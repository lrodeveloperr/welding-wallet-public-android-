import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

const String approvedAdMobPublisherId = '8054612600809568';
const String googleDemoPublisherId = '3940256099942544';

class AdConfiguration {
  const AdConfiguration();

  static const _androidProductionBanner = String.fromEnvironment(
    'WELDING_ANDROID_ADMOB_BANNER_ID',
  );
  static const _iosProductionBanner = String.fromEnvironment(
    'WELDING_IOS_ADMOB_BANNER_ID',
  );

  static const androidTestBanner =
      'ca-app-pub-3940256099942544/9214589741';
  static const iosTestBanner =
      'ca-app-pub-3940256099942544/2435281174';

  String get bannerUnitId {
    if (!kReleaseMode) {
      return Platform.isIOS ? iosTestBanner : androidTestBanner;
    }
    final candidate = Platform.isIOS
        ? _iosProductionBanner
        : _androidProductionBanner;
    return isApprovedProductionBanner(candidate) ? candidate : '';
  }

  static bool isApprovedProductionBanner(String value) {
    final match = RegExp(r'^ca-app-pub-(\d{16})/\d{10}$').firstMatch(
      value.trim(),
    );
    return match != null &&
        match.group(1) == approvedAdMobPublisherId &&
        match.group(1) != googleDemoPublisherId;
  }
}

class AdService extends ChangeNotifier {
  AdService({AdConfiguration configuration = const AdConfiguration()})
    : _configuration = configuration;

  final AdConfiguration _configuration;
  bool _started = false;
  bool _canLoadAds = false;
  bool _privacyOptionsRequired = false;
  bool _disposed = false;

  bool get canLoadAds => _canLoadAds && _configuration.bannerUnitId.isNotEmpty;
  bool get privacyOptionsRequired => _privacyOptionsRequired;
  String get bannerUnitId => _configuration.bannerUnitId;

  Future<void> initialize() async {
    if (_started || bannerUnitId.isEmpty) return;
    _started = true;

    try {
      final update = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(tagForUnderAgeOfConsent: false),
        () => update.complete(),
        (_) => update.complete(),
      );
      await update.future;

      await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
      _privacyOptionsRequired =
          await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
      _canLoadAds = await ConsentInformation.instance.canRequestAds();
      if (_canLoadAds) await MobileAds.instance.initialize();
    } catch (_) {
      _canLoadAds = false;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> showPrivacyOptions() async {
    await ConsentForm.showPrivacyOptionsForm((_) {});
    _canLoadAds = await ConsentInformation.instance.canRequestAds();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
