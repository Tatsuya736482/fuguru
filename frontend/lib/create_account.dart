import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:frontend/models/user.dart';

class CreateAccount extends StatefulWidget {
  final VoidCallback onComplete;
  final bool isEditing;
  const CreateAccount(
      {Key? key, required this.onComplete, this.isEditing = false});
  @override
  _CreateAccountState createState() => _CreateAccountState();
}

class _CreateAccountState extends State<CreateAccount> {
  final _formKey = GlobalKey<FormState>();
  final _preferenceController = TextEditingController();
  final _languageController = TextEditingController();
  final _nameController = TextEditingController();
  var _isLoading = false;

  UserModel? _userData;

  @override
  void initState() {
    super.initState();
    _fetchUser();
  }

  @override
  void dispose() {
    _preferenceController.dispose();
    _languageController.dispose();
    _nameController.dispose();

    super.dispose();
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
      _preferenceController.text = user.preference;
      _languageController.text = user.language;
      _nameController.text = user.name;
    });
  }

  Future<void> _createAccount() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .set({
        'preference': _preferenceController.text,
        'language': _languageController.text,
        'name': _nameController.text,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('アカウントが正常に作成されました')),
      );
      if (widget.isEditing) {
        Navigator.pop(context);
      }
      widget.onComplete();
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _createEmptyAccount() async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .set({
      'preference': '',
      'language': '',
      'name': '',
    });
    widget.onComplete();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('後でプロフィールで編集できます')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('アカウント作成'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                children: <Widget>[
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(labelText: '名前'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '名前を入力してください';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _preferenceController,
                    decoration: InputDecoration(labelText: 'プリファレンス'),
                    maxLines: 5,
                    minLines: 3,
                    keyboardType: TextInputType.multiline,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'プリファレンスを入力してください';
                      }
                      return null;
                    },
                  ),
                  DropdownButtonFormField<String>(
                    value: _languageController.text.isEmpty
                        ? null
                        : _languageController.text,
                    items: [
                      '英語',
                      '日本語',
                      '中国語',
                      'スペイン語',
                      'フランス語',
                      'ドイツ語',
                      'イタリア語',
                      '韓国語',
                      'ロシア語',
                      'その他',
                    ]
                        .map((label) => DropdownMenuItem(
                              child: Text(label),
                              value: label,
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        if (value == 'その他') {
                          _languageController.clear();
                        } else {
                          _languageController.text = value!;
                        }
                      });
                    },
                    decoration: InputDecoration(labelText: '言語'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '言語を選択してください';
                      }
                      return null;
                    },
                    isExpanded: true,
                  ),
                  SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: widget.isEditing
                            ? () {
                                Navigator.pop(context);
                              }
                            : _createEmptyAccount,
                        child: Text(widget.isEditing ? "戻る" : 'スキップ'),
                      ),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _createAccount,
                        child: _isLoading
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(widget.isEditing ? '保存する' : 'アカウント作成'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
