import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/ui/pen_input_diagnostic.dart';

void main() {
  test('describeButtons names bits', () {
    expect(describeButtons(0), 'none');
    expect(describeButtons(1), 'primary');
    expect(describeButtons(2), 'secondary');
    expect(describeButtons(33), 'primary+eraser');
    expect(describeButtons(8 | 64), 'bit8+bit64');
  });
}
