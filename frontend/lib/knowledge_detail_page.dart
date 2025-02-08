import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:frontend/models/knowledge.dart';

class KnowledgeDetailPage extends StatefulWidget {
  const KnowledgeDetailPage({super.key, this.knowledge, this.knowledgeId});
  final Knowledge? knowledge;
  final String? knowledgeId;

  @override
  State<KnowledgeDetailPage> createState() => _KnowledgeDetailPageState();
}

class _KnowledgeDetailPageState extends State<KnowledgeDetailPage> {
  Knowledge? _knowledge;

  @override
  void initState() {
    super.initState();
    if (widget.knowledge != null) {
      _knowledge = widget.knowledge;
    } else if (widget.knowledgeId != null) {
      _fetchKnowledge(widget.knowledgeId!);
    }
  }

  Future<void> _fetchKnowledge(String knowledgeId) async {
    // Implement your logic to fetch the Knowledge object using the knowledgeId
    // For example:
    final document = await FirebaseFirestore.instance
        .collection('knowledges')
        .doc(knowledgeId)
        .get();
    setState(() {
      _knowledge = Knowledge.fromFirestore(document);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_knowledge == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('読み込み中'),
        ),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_knowledge!.title),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: MarkdownBody(data: _knowledge!.content),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '参考',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
