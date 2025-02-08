import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:frontend/create_account.dart';
import 'package:frontend/login_page.dart';
import 'package:frontend/models/user.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  User? _user;

  UserModel? _userData;

  late final StreamSubscription<User?> _authStateSubscription;
  @override
  void initState() {
    super.initState();
    _authStateSubscription =
        FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (mounted) {
        setState(() {
          _user = user;
        });

        if (_user != null) {
          // Fetch user data
          _fetchUser();
        }
      }
    });
  }

  Future<void> _fetchUser() async {
    // Fetch user data
    final document = await FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .get();
    final user = UserModel.fromFirestore(document);
    setState(() {
      _userData = user;
    });
  }

  @override
  void dispose() {
    _authStateSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Account Page")),
        body: Center(
          child: FilledButton(
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => LoginPage(
                          onComplete: () {},
                        )),
              );
            },
            child: const Text("ログイン"),
          ),
        ),
      );
    } else {
      return Scaffold(
        appBar: AppBar(title: const Text("アカウント")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 50,
                backgroundImage: _user!.photoURL != null
                    ? NetworkImage(_user!.photoURL!)
                    : null,
                child: _user!.photoURL == null
                    ? const Icon(Icons.person, size: 50)
                    : null,
              ),
              const SizedBox(height: 20),
              if (_user!.email != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.email, size: 16),
                    const SizedBox(width: 5),
                    SelectableText(
                      '${_user!.email}',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                )
              else
                const Text(
                  'メールがありません',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              const SizedBox(height: 20),
              if (_userData?.name != null && _userData?.name != '')
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.person, size: 16),
                    const SizedBox(width: 5),
                    Text(
                      _userData!.name,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                )
              else
                const Text(
                  '名前がありません',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              const SizedBox(height: 20),
              if (_userData?.preference != null && _userData?.preference != '')
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star, size: 16),
                    const SizedBox(width: 5),
                    Text(
                      _userData!.preference,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                )
              else
                const Text(
                  'プリファレンスがありません',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              const SizedBox(height: 20),
              if (_userData?.language != null && _userData?.language != '')
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.language, size: 16),
                    const SizedBox(width: 5),
                    Text(
                      _userData!.language,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                )
              else
                const Text(
                  '言語がありません',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              const SizedBox(height: 20),
              Spacer(),
              OutlinedButton(
                onPressed: () async {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => CreateAccount(
                            onComplete: () {
                              _fetchUser();
                            },
                            isEditing: true)),
                  );
                },
                child: const Text("アカウント編集"),
              ),
              const SizedBox(height: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red, // Dangerous color
                ),
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("ログアウトしました")),
                  );
                },
                child: const Text("ログアウト"),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      );
    }
  }
}
