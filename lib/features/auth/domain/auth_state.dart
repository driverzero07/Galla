sealed class AuthState {
  const AuthState();
}

/// Reading secure storage at startup.
class AuthLoading extends AuthState {
  const AuthLoading();
}

/// No shop on this phone yet: show first-time setup.
class AuthNeedsSetup extends AuthState {
  const AuthNeedsSetup();
}

/// Shop exists, app is locked: show the PIN login.
class AuthLocked extends AuthState {
  const AuthLocked({required this.phone});
  final String phone; // E.164
}

class AuthUnlocked extends AuthState {
  const AuthUnlocked({required this.shopId, required this.phone});
  final String shopId;
  final String phone; // E.164
}
