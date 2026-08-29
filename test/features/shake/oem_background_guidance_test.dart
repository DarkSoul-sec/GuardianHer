import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/features/shake/domain/oem_background_guidance.dart';

void main() {
  test('miui token maps to Xiaomi-family Autostart guidance', () {
    final hint = oemBackgroundGuidance('miui');
    expect(hint, isNotNull);
    expect(hint, contains('Xiaomi / Redmi / POCO'));
    expect(hint, contains('Autostart'));
  });

  test('coloros token maps to Oppo-family auto-launch guidance', () {
    final hint = oemBackgroundGuidance('coloros');
    expect(hint, contains('Oppo / OnePlus / realme'));
  });

  test('funtouch token maps to Vivo-family guidance', () {
    expect(oemBackgroundGuidance('funtouch'), contains('Vivo / iQOO'));
  });

  test('emui token maps to Huawei guidance', () {
    expect(oemBackgroundGuidance('emui'), contains('Huawei'));
  });

  test('magicos token maps to Honor guidance', () {
    expect(oemBackgroundGuidance('magicos'), contains('Honor'));
  });

  test('samsung token maps to sleeping-apps guidance', () {
    final hint = oemBackgroundGuidance('samsung');
    expect(hint, contains('Samsung'));
    expect(hint, contains('Sleeping apps'));
  });

  test('null and unknown tokens yield no extra copy', () {
    expect(oemBackgroundGuidance(null), isNull);
    expect(oemBackgroundGuidance('google'), isNull);
    expect(oemBackgroundGuidance(''), isNull);
  });
}
