import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:success_erp/app.dart';

void main() {
  testWidgets('App renders sign-in screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ERPApp()));
    expect(find.text('Sign in with Google'), findsOneWidget);
  });
}
