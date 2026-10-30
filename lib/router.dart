import 'package:go_router/go_router.dart';

import 'features/adhkar/adhkar_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/groups/create_group_screen.dart';
import 'features/groups/groups_screen.dart';
import 'features/home/home_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/shell/home_shell.dart';
import 'services/auth_service.dart';

final appRouter = GoRouter(
  initialLocation: '/home',
  // أي تغيير في حالة الدخول بيعيد حساب التوجيه.
  refreshListenable: AuthService.instance,
  redirect: (context, state) {
    final signedIn = AuthService.instance.isSignedIn;
    final atLogin = state.matchedLocation == '/login';
    if (!signedIn && !atLogin) return '/login';
    if (signedIn && atLogin) return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    // شاشة كاملة فوق التبويبات.
    GoRoute(path: '/create-group', builder: (context, state) => const CreateGroupScreen()),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => HomeShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/groups', builder: (context, state) => const GroupsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/adhkar', builder: (context, state) => const AdhkarScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
        ]),
      ],
    ),
  ],
);
