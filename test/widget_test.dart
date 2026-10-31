import 'package:flutter_test/flutter_test.dart';
import 'package:mishwar/main.dart';

void main() {
  testWidgets('app starts', (tester) async {
    await tester.pumpWidget(const MishwarApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('مشوار'), findsWidgets);
  });
}
