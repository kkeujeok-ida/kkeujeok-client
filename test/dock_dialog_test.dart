import 'package:flutter/semantics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/l10n/app_localizations.dart';
import 'package:kkeujeok/ui/dock_dialog.dart';
import 'package:kkeujeok/model/toolbar_pos.dart';

void main() {
  testWidgets('four labelled 48dp icons, current checked, pick pops', (
    t,
  ) async {
    final h = t.ensureSemantics();
    ToolbarDock? got;
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () async => got = await showDialog<ToolbarDock>(
                context: c,
                useSafeArea: false,
                builder: (_) => const DockDialog(current: ToolbarDock.left),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    for (final l in ['Top', 'Right', 'Bottom', 'Left']) {
      expect(find.bySemanticsLabel(l), findsOneWidget);
    }
    expect(find.byIcon(Icons.align_vertical_top), findsOneWidget);
    bool checked(String l) => t
        .getSemantics(find.bySemanticsLabel(l))
        // ignore: deprecated_member_use
        .hasFlag(SemanticsFlag.isChecked);
    expect(checked('Left'), isTrue);
    expect(checked('Top'), isFalse);
    final top = find.ancestor(
      of: find.byIcon(Icons.align_vertical_top),
      matching: find.byType(SizedBox),
    );
    expect(t.getSize(top.first), const Size(48, 48));

    await t.tap(find.byIcon(Icons.align_horizontal_right));
    await t.pumpAndSettle();
    expect(got, ToolbarDock.right);
    h.dispose();
  });
}
