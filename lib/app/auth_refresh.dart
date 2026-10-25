import 'package:flutter/foundation.dart';

/// Notifies [GoRouter] when the Supabase auth session changes.
class AuthRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}
