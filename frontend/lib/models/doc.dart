import 'package:cloud_firestore/cloud_firestore.dart';

class Doc {
  final String id;
  final String title;
  final List<dynamic> contents;
  final Timestamp createdAt;
  final Map<String, dynamic> source;
  final String userId;
  final String state;
  final String summaryId;
  final String summaryState;
  final String errorText;

  const Doc(
      {required this.id,
      required this.title,
      required this.contents,
      required this.createdAt,
      required this.source,
      required this.userId,
      required this.state,
      required this.summaryId,
      required this.summaryState,
      required this.errorText});

  factory Doc.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data()! as Map<String, dynamic>;
    return Doc(
        id: doc.id,
        title: data['title'],
        contents: data['contents'],
        createdAt: data['createdAt'],
        source: data['source'],
        userId: data['userId'],
        state: data['state'],
        summaryId: data['summaryId'],
        summaryState: data['summaryState'] ?? '',
        errorText: data['errorText'] ?? '');
  }
}
