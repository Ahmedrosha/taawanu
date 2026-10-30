import 'package:go_router/go_router.dart';

import 'features/adhkar/adhkar_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/groups/create_group_screen.dart';
import 'features/groups/explore_screen.dart';
import 'features/groups/group_board_screen.dart';
import 'features/groups/group_settings_screen.dart';
import 'features/groups/groups_screen.dart';
import 'features/groups/invite_screen.dart';
import 'features/groups/join_screen.dart';
import 'features/home/home_screen.dart';
import 'features/prayer/prayer_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/reader/reader_screen.dart';
import 'features/shell/home_shell.dart';
import 'models/group_models.dart';
import 'services/auth_service.dart';

/// رابط دعوة فتح التطبيق قبل تسجيل الدخول: بنرجعله بعد الدخول.
String? _pendingLocation;

final appRouter = GoRouter(
  initialLocation: '/home',
  // أي تغيير في حالة الدخول بيعيد حساب التوجيه.
  refreshListenable: AuthService.instance,
  redirect: (context, state) {
    final signedIn = AuthService.instance.isSignedIn;
    final loc = state.matchedLocation;
    final atLogin = loc == '/login';
    if (!signedIn && !atLogin) {
      if (loc.startsWith('/j/') || loc.startsWith('/join/')) _pendingLocation = state.uri.toString();
      return '/login';
    }
    if (signedIn && atLogin) {
      final pending = _pendingLocation;
      _pendingLocation = null;
      return pending ?? '/home';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),

    // شاشات كاملة فوق التبويبات.
    GoRoute(path: '/create-group', builder: (context, state) => const CreateGroupScreen()),
    GoRoute(path: '/explore', builder: (context, state) => const ExploreScreen()),
    GoRoute(
      path: '/group/:id',
      builder: (context, state) => GroupBoardScreen(groupId: state.pathParameters['id']!),
      routes: [
        GoRoute(
          path: 'invite',
          redirect: (context, state) => state.extra is Group ? null : '/group/${state.pathParameters['id']}',
          builder: (context, state) => InviteScreen(group: state.extra! as Group),
        ),
        GoRoute(
          path: 'settings',
          redirect: (context, state) => state.extra is Group ? null : '/group/${state.pathParameters['id']}',
          builder: (context, state) => GroupSettingsScreen(group: state.extra! as Group),
        ),
      ],
    ),
    // رابط الدعوة: https://taawanu.app/j/CODE بيفتح هنا.
    GoRoute(path: '/j/:code', redirect: (context, state) => '/join/${state.pathParameters['code']}'),
    GoRoute(path: '/join/:code', builder: (context, state) => JoinScreen(code: state.pathParameters['code'])),
    GoRoute(path: '/public/:id', builder: (context, state) => JoinScreen(publicGroupId: state.pathParameters['id'])),
    GoRoute(
      path: '/read',
      redirect: (context, state) => state.extra is ReadRequest ? null : '/home',
      builder: (context, state) => ReaderScreen(request: state.extra! as ReadRequest),
    ),

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
          GoRoute(path: '/prayer', builder: (context, state) => const PrayerScreen()),
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
