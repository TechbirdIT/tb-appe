import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:appe/screens/login_screen.dart';

void main() {
  testWidgets('Login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pump();
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
