// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:callback_observer/callback_observable.dart';
import 'package:test/test.dart';

void main() {
  group('CallbackObserver', () {
    test('can be instantiated', () {
      expect(CallbackObserver(), isNotNull);
    });
  });
}
