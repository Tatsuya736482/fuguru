import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:frontend/models/doc.dart';
import 'package:frontend/summary_detail_page.dart';
import 'package:skeletonizer/skeletonizer.dart';

class DocDetail {
  final String title;
  final String subtitle;
  final String content;

  const DocDetail({
    required this.title,
    required this.subtitle,
    required this.content,
  });
}

class DocDetailPage extends StatefulWidget {
  const DocDetailPage({super.key, required this.docId});
  final String docId;

  @override
  State<DocDetailPage> createState() => _DocDetailPageState();
}

class _DocDetailPageState extends State<DocDetailPage> {
  late final Stream<DocumentSnapshot> _docsStream;
  @override
  initState() {
    super.initState();
    _docsStream = FirebaseFirestore.instance
        .collection('docs')
        .doc(widget.docId)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _docsStream,
      builder:
          (BuildContext context, AsyncSnapshot<DocumentSnapshot> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Center(child: Text('Document not found'));
        }
        var doc = Doc.fromFirestore(snapshot.data!);
        return Scaffold(
          appBar: AppBar(
            title: Text(doc.title),
            actions: [
              GestureDetector(
                  onTap: () {
                    if (doc.summaryState == 'ready') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                SummaryDetailPage(summaryId: doc.summaryId)),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('サマリーがまだ作成されていません'),
                      ));
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Icon(
                          doc.summaryState == 'ready'
                              ? Icons.lightbulb
                              : Icons.lightbulb_outline,
                          color: doc.state == 'ready' ? Colors.yellow : Colors.grey,
                        ),
                      ),
                    ),
                  )),
              IconButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: Text('削除しますか？'),
                          content: Text('このドキュメントを削除してもよろしいですか？'),
                          actions: [
                            TextButton(
                              child: Text('キャンセル'),
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                            ),
                            TextButton(
                              child: Text('削除'),
                              onPressed: () {
                                FirebaseFirestore.instance
                                    .collection('docs')
                                    .doc(doc.id)
                                    .delete();
                                Navigator.of(context).pop();
                                Navigator.of(context).pop();
                              },
                            ),
                          ],
                        );
                      },
                    );
                  },
                  icon: Icon(
                    Icons.delete,
                    color: Colors.red,
                  ))
            ],
          ),
          body: doc.state == 'ready' || doc.state == 'processing'
              ? _buildContent(doc)
              : doc.state == 'error'
                  ? Text('エラーが発生しました')
                  : Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  Widget _buildContent(doc) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 800),
            child: Column(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...doc.contents.map((contentId) {
                          return StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('contents')
                                .doc(contentId)
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Skeletonizer(
                                      effect: PulseEffect(
                                        from: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.4),
                                        to: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.1),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              "lorem ipsum dolor sit amet consectetur adipiscing elit"),
                                          Text(
                                              "lorem ipsum dolor sit amet consectetur adipiscing elit lorem ipsum dolor sit amet consectetur adipiscing elit lorem ipsum dolor sit amet consectetur adipiscing elit"),
                                          Text(
                                              "lorem ipsum dolor sit amet consectetur adipiscing elit lorem ipsum dolor sit amet consectetur adipiscing elit"),
                                        ],
                                      ),
                                    ));
                              }
                              if (snapshot.hasError) {
                                return Center(
                                    child: Text('Error: ${snapshot.error}'));
                              }
                              if (!snapshot.hasData || !snapshot.data!.exists) {
                                return Center(
                                    child: Text('Document not found'));
                              }
                              var docData =
                                  snapshot.data!.data() as Map<String, dynamic>;
                              return _buildDocContent(docData);
                            },
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ),
                Divider(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey[200]!),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                            padding: const EdgeInsets.all(8.0),
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
                                  Text(doc.source['detail']),
                                ])))
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocContent(Map<String, dynamic> docData) {
    if (docData['type'] == 'known') {
      return _buildKnownContent(docData);
    }
    if (docData['state'] == 'init') {
      return _buildInitContent(docData);
    }
    if (docData['type'] == 'mdRaw') {
      return _buildMarkdownContent(docData['detail']);
    }
    if (docData['type'] == 'mdEdited') {
      return _buildEditedContent(docData);
    }

    return Container();
  }

  Widget _buildInitContent(Map<String, dynamic> docData) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              MarkdownBody(data: docData['original']),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKnownContent(Map<String, dynamic> docData) {
    return StatefulBuilder(
      builder: (context, setState) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Container(
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 30,
                      ),
                      Row(
                        spacing: 10,
                        children: [
                          Icon(
                            Icons.speed_rounded,
                            size: 16,
                          ),
                          Text(
                            "${docData['efficiency']}%",
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      _buildConfirmButton(docData['summaryId'] ?? "",
                          docData['knowledgeId'] ?? ""),
                    ],
                  ),
                  Center(
                      child:
                          Text('すべて、既知の情報です', style: TextStyle(fontSize: 10))),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMarkdownContent(String data) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: MarkdownBody(data: data),
    );
  }

  Widget _buildEditedContent(Map<String, dynamic> docData) {
    bool showOriginal = false;

    return StatefulBuilder(
      builder: (context, setState) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Container(
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        iconSize: 16,
                        icon: Icon(showOriginal
                            ? Icons.swap_horiz_rounded
                            : Icons.swap_horiz_rounded),
                        onPressed: () {
                          setState(() {
                            showOriginal = !showOriginal;
                          });
                        },
                      ),
                      Row(
                        spacing: 10,
                        children: [
                          Icon(
                            Icons.speed_rounded,
                            size: 16,
                          ),
                          Text(
                            "${docData['efficiency']}%",
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      _buildConfirmButton(docData['summaryId'] ?? "",
                          docData['knowledgeId'] ?? ""),
                    ],
                  ),
                  MarkdownBody(
                      data: showOriginal
                          ? docData['original']
                          : docData['detail']),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildConfirmButton(String summaryId, String knowledgeId) {
    return Align(
      alignment: Alignment.centerRight,
      child: IconButton(
        iconSize: 16,
        icon: Icon(Icons.description_rounded),
        tooltip: 'Check details',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => SummaryDetailPage(
                      summaryId: summaryId,
                      highlightKnowledgeId: knowledgeId,
                    )
                // KnowledgeDetailPage(knowledgeId: knowledgeId),
                ),
          );

          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('該当する知識がハイライトされています'),
          ));
        },
      ),
    );
  }
}
