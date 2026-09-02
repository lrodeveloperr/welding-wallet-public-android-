import 'package:flutter_test/flutter_test.dart';
import 'package:welding_wallet/services/ad_service.dart';

void main() {
  group('production AdMob boundary', () {
    test('accepts a banner owned by the approved publisher', () {
      expect(
        AdConfiguration.isApprovedProductionBanner(
          'ca-app-pub-8054612600809568/1234567890',
        ),
        isTrue,
      );
    });

    test('rejects demo, foreign and malformed banner identifiers', () {
      expect(
        AdConfiguration.isApprovedProductionBanner(
          AdConfiguration.androidTestBanner,
        ),
        isFalse,
      );
      expect(
        AdConfiguration.isApprovedProductionBanner(
          'ca-app-pub-1111111111111111/1234567890',
        ),
        isFalse,
      );
      expect(
        AdConfiguration.isApprovedProductionBanner('not-an-ad-unit'),
        isFalse,
      );
    });
  });
}
