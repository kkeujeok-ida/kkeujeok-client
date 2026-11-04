import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/l10n/app_localizations.dart';
import 'package:kkeujeok/library/folder_service.dart';
import 'package:kkeujeok/ui/folder_sidebar.dart';
import 'package:kkeujeok/ui/providers.dart';

const _view = FolderView(
  folders: [
    LibraryFolder('a', 'Class', 'root'),
    LibraryFolder('b', 'Math', 'a'),
    LibraryFolder('c', 'Diary', 'root'),
  ],
  noteFolder: {'n1': 'b', 'n2': 'c'},
);

class _Tree extends FolderTreeNotifier {
  @override
  Future<FolderView> build() async => _view;
}

void main() {
  testWidgets('the tree shows, folds, and a tap picks the folder', (t) async {
    late ProviderContainer c;
    await t.pumpWidget(
      ProviderScope(
        overrides: [folderTreeProvider.overrideWith(_Tree.new)],
        child: Consumer(
          builder: (ctx, ref, _) {
            c = ProviderScope.containerOf(ctx);
            return MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: FolderSidebarSection()),
            );
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('All notes'), findsOneWidget);
    expect(find.text('Class'), findsOneWidget);
    expect(find.text('Diary'), findsOneWidget);
    expect(find.text('Math'), findsNothing); // folded

    await t.tap(find.byTooltip('Class')); // the chevron of a folder
    await t.pumpAndSettle();
    expect(find.text('Math'), findsOneWidget);

    await t.tap(find.text('Math'));
    await t.pumpAndSettle();
    expect(c.read(currentFolderProvider), 'b');
    expect(c.read(effectiveFolderProvider), 'b');

    await t.tap(find.text('All notes'));
    await t.pumpAndSettle();
    expect(c.read(effectiveFolderProvider), isNull);
  });

  testWidgets('long press opens the menu; delete asks in a centered dialog', (
    t,
  ) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [folderTreeProvider.overrideWith(_Tree.new)],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(width: 280, child: FolderSidebarSection()),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byTooltip('Class menu'), findsNothing); // no per-row button
    expect(find.text('New folder'), findsNothing);
    await t.longPress(find.text('Class'));
    await t.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Move'), findsOneWidget);
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    final body = find.text('This folder and its note go to the app trash.');
    expect(body, findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    // Centered on the screen, not inside the 280 px sidebar.
    expect((t.getCenter(body).dx - 400).abs() < 100, isTrue);
  });
}
