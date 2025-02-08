import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:frontend/doc_detail_page.dart';
import 'package:frontend/models/doc.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:flutter/foundation.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final String _userId = FirebaseAuth.instance.currentUser!.uid;
  late final Stream<QuerySnapshot> _docsStream;

  @override
  void initState() {
    super.initState();
    _docsStream = FirebaseFirestore.instance
        .collection('docs')
        .where("userId", isEqualTo: _userId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  List<bool> isSelected = [false, false];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ドキュメント'),
      ),
      floatingActionButton: FloatingActionButton(
          onPressed: () {
            showCreateSheet(context);
          },
          child: const Icon(Icons.add)),
      body: StreamBuilder<QuerySnapshot>(
        stream: _docsStream,
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('エラーが発生しました'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text('ドキュメントがありません。'),
            );
          }

          return ListView(
            children: [
              ...snapshot.data!.docs
                  .map((DocumentSnapshot document) {
                    Doc doc = Doc.fromFirestore(document);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ListTile(
                        title: Text(doc.title),
                        subtitle: Text(DateFormat('yyyy年MM月dd日')
                            .format(doc.createdAt.toDate())),
                        onTap: () {
                          if (doc.state == 'ready') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => DocDetailPage(
                                  docId: doc.id,
                                ),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('ドキュメントが準備中です'),
                              ),
                            );
                          }
                        },
                        leading: const Icon(Icons.book),
                        trailing: const Icon(Icons.arrow_forward_ios),
                      ),
                    );
                  })
                  .toList()
                  .cast()
            ],
          );
        },
      ),
    );
  }

  Future<dynamic> showCreateSheet(BuildContext context) {
    final TextEditingController detailController = TextEditingController();
    PlatformFile? selectedFile;
    bool isLoading = false;

    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
          return SimpleDialog(
            title: const Text(
              'ドキュメントを追加',
              textAlign: TextAlign.center,
            ),
            children: <Widget>[
              Center(
                child: ToggleButtons(
                  onPressed: (index) {
                    setState(() {
                      for (int buttonIndex = 0;
                          buttonIndex < isSelected.length;
                          buttonIndex++) {
                        isSelected[buttonIndex] = buttonIndex == index;
                      }
                    });
                  },
                  isSelected: isSelected,
                  children: const <Widget>[
                    Icon(Icons.link, semanticLabel: 'URL'),
                    Icon(Icons.insert_drive_file, semanticLabel: 'File'),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: isSelected.indexOf(true) == 1
                    ? ElevatedButton(
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: [
                              'pdf',
                              'doc',
                              'docx',
                              'txt',
                              'pptx',
                              'ppt',
                              'xls',
                              'xlsx',
                              'md'
                            ],
                          );
                          if (result != null) {
                            selectedFile = result.files.single;
                            detailController.text = selectedFile?.name ?? "";
                            setState(() {});
                          }
                        },
                        child: Text(detailController.text.isEmpty
                            ? 'ファイルを選択'
                            : detailController.text),
                      )
                    : isSelected.indexOf(true) == 0
                        ? TextField(
                            controller: detailController,
                            decoration: InputDecoration(
                              labelText: 'URL',
                              border: const OutlineInputBorder(),
                            ),
                          )
                        : const Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'ドキュメントのタイプを選択してください',
                                ),
                              ),
                            ],
                          ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('キャンセル'),
                  ),
                  ElevatedButton(
                    onPressed: isLoading
                        ? null
                        : () async {
                            setState(() {
                              isLoading = true;
                            });
                            final String selectedType =
                                isSelected.indexOf(true) == 0 ? 'url' : 'pdf';

                            if (isSelected.indexOf(true) == 1 &&
                                selectedFile != null) {
                              try {
                                final snapshot;
                                if (kIsWeb) {
                                  snapshot = await FirebaseStorage.instance
                                      .ref(
                                          'users/$_userId/${DateTime.now().millisecondsSinceEpoch}-${detailController.text}')
                                      .putData(selectedFile!.bytes!);
                                } else {
                                  snapshot = await FirebaseStorage.instance
                                      .ref(
                                          'users/$_userId/${DateTime.now().millisecondsSinceEpoch}-${detailController.text}')
                                      .putFile(File(selectedFile!.path!));
                                }
                                snapshot.ref.getDownloadURL().then((value) {
                                  FirebaseFirestore.instance
                                      .collection('inputs')
                                      .add({
                                    'userId': _userId,
                                    'type': selectedFile?.extension,
                                    'detail': value,
                                    'title': detailController.text,
                                    'createdAt': Timestamp.now(),
                                  }).then((_) {
                                    setState(() {
                                      isLoading = false;
                                    });
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('ドキュメントが追加されました'),
                                      ),
                                    );
                                  });
                                });
                              } catch (e) {
                                print(e);
                              }
                            } else if (isSelected.indexOf(true) == 0) {
                              FirebaseFirestore.instance
                                  .collection('inputs')
                                  .add({
                                'userId': _userId,
                                'type': selectedType,
                                'detail': detailController.text,
                                'createdAt': Timestamp.now(),
                              }).then((_) {
                                setState(() {
                                  isLoading = false;
                                });
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('ドキュメントが追加されました'),
                                  ),
                                );
                              });
                            } else {
                              setState(() {
                                isLoading = false;
                              });
                            }
                          },
                    child: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('作成'),
                  ),
                ],
              ),
            ],
          );
        });
      },
    );
  }
}
