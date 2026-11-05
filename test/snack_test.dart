import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/ui/snack.dart';

void main() {
  testWidgets('a snackbar with an action still closes after kSnackDuration', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => ScaffoldMessenger.of(ctx).showSnackBar(
                appSnackBar(
                  content: const Text('hi'),
                  action: SnackBarAction(label: 'Undo', onPressed: () {}),
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('go'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('hi'), findsOneWidget);
    await t.pump(kSnackDuration + const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(find.text('hi'), findsNothing);
  });
}
