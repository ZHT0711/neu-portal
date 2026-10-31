import 'package:flutter/material.dart';

import 'app.dart';
import 'core/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  state.loadSettings().then((_) => state.restoreSession());
  runApp(NEUPortalApp(state: state));
}
