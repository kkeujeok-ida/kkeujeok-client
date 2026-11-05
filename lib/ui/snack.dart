import 'package:flutter/material.dart';

/// The one auto-dismiss time for every snackbar. A SnackBar with an action
/// persists by default, so each one goes through [appSnackBar] to get it.
const kSnackDuration = Duration(seconds: 4);

SnackBar appSnackBar({required Widget content, SnackBarAction? action}) =>
    SnackBar(
      content: content,
      action: action,
      duration: kSnackDuration,
      persist: false,
    );
