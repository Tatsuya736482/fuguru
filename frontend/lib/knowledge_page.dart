import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:frontend/knowledge_detail_page.dart';
import 'package:frontend/models/knowledge.dart';
import 'package:intl/intl.dart';

class KnowledgePage extends StatefulWidget {
  const KnowledgePage({super.key});

  @override
  State<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends State<KnowledgePage> {
  final String _userId = FirebaseAuth.instance.currentUser!.uid;
  late final Stream<QuerySnapshot> _knowledgesStream;

  @override
  void initState() {
    super.initState();
    _knowledgesStream = FirebaseFirestore.instance
        .collection('knowledges')
        .where("userId", isEqualTo: _userId)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('知識'),
      ),
      body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: StreamBuilder<QuerySnapshot>(
            stream: _knowledgesStream,
            builder:
                (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
              if (snapshot.hasError) {
                return const Text('Something went wrong');
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.data!.docs.isEmpty) {
                return const Center(
                  child: Text('知識データがありません。'),
                );
              }

              return ListView(
                children: snapshot.data!.docs
                    .map((DocumentSnapshot document) {
                      Knowledge knowledge = Knowledge.fromFirestore(document);
                      return ListTile(
                        title: Text(knowledge.title),
                        subtitle: Text(DateFormat('yyyy年MM月dd日')
                          .format(knowledge.createdAt.toDate())),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => KnowledgeDetailPage(
                                knowledge: knowledge,
                              ),
                            ),
                          );
                        },
                        leading: const Icon(Icons.lightbulb),
                        trailing: const Icon(Icons.arrow_forward_ios),
                      );
                    })
                    .toList()
                    .cast(),
              );
            },
          )),
    );
  }
}
