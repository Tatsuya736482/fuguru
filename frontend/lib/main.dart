import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:frontend/create_account.dart';
import 'package:frontend/login_page.dart';
import 'package:frontend/on_board_page.dart';
import 'package:frontend/navigation.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fuguru',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
        useMaterial3: true,
        extensions: const [SkeletonizerConfigData()],
      ),
      home: MainWrapper(),
    );
  }
}

class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});

  @override
  _MainWrapperState createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  bool _shouldShowCreateAccount = false;
  bool _isFirstTime = true;
  bool _isLoading = true;
  bool _isLoadingUser = true;

  @override
  void initState() {
    super.initState();
    _checkFirstTime();
    _fetchUser();
  }

  Future<void> _checkFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isFirstTime = prefs.getBool('isFirstTime') ?? true;
      _isLoading = false;
    });
  }

  Future<void> _fetchUser() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      setState(() {
        _shouldShowCreateAccount = false;
      });
      return;
    }

    try {
      final document = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      if (document.exists) {
        setState(() {
          _shouldShowCreateAccount = false;
        });
      } else {
        setState(() {
          _shouldShowCreateAccount = true;
        });
      }
    } catch (e) {
      debugPrint("Error fetching user: $e");
      setState(() {
        _shouldShowCreateAccount = false;
      });
    } finally {
      setState(() => _isLoadingUser = false);
    }
  }

  Future<void> _setFirstTimeComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isFirstTime', false);
    setState(() => _isFirstTime = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface),
      child: _buildView(),
    );
  }

  Widget _buildView() {
    if (_isLoading) {
      return _loadingIndicator();
    } else if (_isFirstTime) {
      return OnBoardPage(onComplete: _setFirstTimeComplete);
    } else {
      return _buildAuthenticatedView();
    }
  }

  Widget _loadingIndicator() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildAuthenticatedView() {
    return StreamBuilder(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return const Center(child: Text('エラーが発生しました'));
          } else if (snapshot.hasData) {
            if (_shouldShowCreateAccount) {
              return CreateAccount(
                onComplete: () {
                  _fetchUser();
                },
              );
            } else {
              return Navigation();
            }
          } else {
            return LoginPage(onComplete: () {
              _fetchUser();
            });
          }
        });
  }
}
