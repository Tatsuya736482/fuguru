import 'package:cloud_firestore/cloud_firestore.dart';


class Summary {
  final String title;
  final List<String> knowledges;
  final Timestamp createdAt;
  final String userId;
  final Source source;
  final String id;
  final String state;

  const Summary({
    required this.title,
    required this.knowledges,
    required this.createdAt,
    required this.userId,
    required this.source,
    required this.id,
    required this.state,
  });

  factory Summary.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data()! as Map<String, dynamic>;
    return Summary(
      title: data['title'],
      knowledges: List<String>.from(data['knowledges']),
      createdAt: data['createdAt'],
      userId: data['userId'],
      source: Source.fromMap(data['source']),
      id: data['id'],
      state: data['state'],
    );
  }
}

class Source {
  final String type;
  final String detail;

  const Source({
    required this.type,
    required this.detail,
  });

  factory Source.fromMap(Map<String, dynamic> data) {
    return Source(
      type: data['type'],
      detail: data['detail'],
    );
  }
}

class Knowledge {
  final String title;
  final String content;
  final Timestamp createdAt;
  final String userId;
  final String summaryId;
  final Timestamp updatedAt;
  final int score;
  final String id;

  const Knowledge({
    required this.title,
    required this.content,
    required this.createdAt,
    required this.userId,
    required this.summaryId,
    required this.updatedAt,
    required this.score,
    required this.id,
  });

  factory Knowledge.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data()! as Map<String, dynamic>;
    return Knowledge(
      id: doc['id'],
      title: data['title'],
      content: data['content'],
      createdAt: data['createdAt'],
      userId: data['userId'],
      summaryId: data['summaryId'],
      updatedAt: data['updatedAt'],
      score: data['score'],
    );
  }
}
