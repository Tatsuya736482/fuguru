import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String name;
  final String preference;
  final String language;

  const UserModel({
    required this.id,
    required this.name,
    required this.preference,
    required this.language,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data()! as Map<String, dynamic>;
    return UserModel(
      id: doc.id,
      name: data['name'],
      preference: data['preference'],
      language: data['language'],
    );
  }
}
