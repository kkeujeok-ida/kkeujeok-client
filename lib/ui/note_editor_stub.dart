import 'package:flutter/material.dart';

import '../design_tokens/build/tokens.dart';
import '../model/note.dart';

/// Entry point of the writing screen: only the `editor-corner` (back + title,
/// display only) and an empty page area. Story 2.5 replaces the body.
class NoteEditorStub extends StatelessWidget {
  const NoteEditorStub({super.key, required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelMedium;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: note.title,
      explicitChildNodes: true,
      child: Scaffold(
        body: SafeArea(
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: Padding(
              padding: const EdgeInsets.all(KkjTokens.spacing3),
              child: DecoratedBox(
                decoration: const ShapeDecoration(
                  color: KkjLight.componentsEditorCornerBackground,
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: KkjLight.componentsEditorCornerBorder,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .backButtonTooltip,
                      constraints: const BoxConstraints(
                        minWidth: KkjTokens.spacingHitMinAndroid,
                        minHeight: KkjTokens.spacingHitMinAndroid,
                      ),
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: KkjTokens.spacing4,
                        ),
                        child: Text(
                          note.title,
                          style: label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
