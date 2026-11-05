import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/storage/hint_store.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('a hint leaves for good once done, and stays gone', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer make() => ProviderContainer(
      overrides: [hintStoreProvider.overrideWithValue(HintStore(prefs))],
    );
    final c = make();
    expect(c.read(hintsProvider), {Hint.firstNote, Hint.penEdit});
    c.read(hintsProvider.notifier).done(Hint.penEdit);
    expect(c.read(hintsProvider), {Hint.firstNote});
    expect(make().read(hintsProvider), {Hint.firstNote}); // after a restart
  });
}
