import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:frontend/models/knowledge.dart';

class SummaryDetailPage extends StatefulWidget {
  const SummaryDetailPage(
      {super.key,
      this.knowledgeIds,
      this.summary,
      this.summaryId,
      this.highlightKnowledgeId});
  final Summary? summary;
  final List<String>? knowledgeIds;
  final String? summaryId;
  final String? highlightKnowledgeId;

  @override
  State<SummaryDetailPage> createState() => _SummaryDetailPageState();
}

class _SummaryDetailPageState extends State<SummaryDetailPage> {
  List<Knowledge>? _knowledges;
  Summary? _summary;
  List<String>? _knowledgeIds;

  final _controller = ScrollController();

  final _listViewKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    if (widget.summaryId != null) {
      _fetchSummary(widget.summaryId!);
    } else if (widget.knowledgeIds != null) {
      _fetchKnowledges(widget.knowledgeIds!);
    }

  }

  Future<void> _fetchSummary(String summaryId) async {
    final document = await FirebaseFirestore.instance
        .collection('summaries')
        .doc(summaryId)
        .get();

    final summary = Summary.fromFirestore(document);
    setState(() {
      _summary = summary;
      _knowledgeIds = summary.knowledges;
    });
    _fetchKnowledges(summary.knowledges);
  }

  Future<void> _fetchKnowledges(List<String> knowledgeIds) async {
    final knowledges = await Future.wait(knowledgeIds.map((id) async {
      final document = await FirebaseFirestore.instance
          .collection('knowledges')
          .doc(id)
          .get();
      if (document.exists) {
        return Knowledge.fromFirestore(document);
      } else {
        return null;
      }
    }).toList());

    setState(() {
      _knowledges = knowledges
          .where((element) => element != null)
          .toList()
          .cast<Knowledge>();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_knowledges == null) {
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
        title: Text(widget.summary?.title ?? _summary?.title ?? '詳細'),
        actions: [
          IconButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: Text('削除しますか？'),
                      content: Text('これらの知識を削除してもよろしいですか？'),
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
                                .collection('summaries')
                                .doc(widget.summary?.id ?? widget.summaryId)
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
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 800),
          child: ListView.builder(
            controller: _controller,
            key: _listViewKey,
            itemCount: _knowledges!.length,
            itemBuilder: (context, index) {
              final knowledge = _knowledges![index];
              return Padding(
                padding:
                    const EdgeInsets.only(top: 16.0, left: 16.0, right: 16.0),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[200]!),
                    color: _knowledges![index].id == widget.highlightKnowledgeId
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.1)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              knowledge.title,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return AlertDialog(
                                      title: Text('削除しますか？'),
                                      content: Text('この知識を削除してもよろしいですか？'),
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
                                                .collection('knowledges')
                                                .doc(knowledge.id)
                                                .delete();
                                            Navigator.of(context).pop();

                                            setState(() {
                                              _knowledges!.removeAt(index);
                                            });
                                          },
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                              icon: Icon(
                                Icons.close,
                              )),
                        ],
                      ),
                      SizedBox(height: 8),
                      MarkdownBody(data: knowledge.content),
                      SizedBox(height: 16),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
