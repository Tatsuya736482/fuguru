import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:frontend/models/knowledge.dart';
import 'package:frontend/summary_detail_page.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SummaryPage extends StatefulWidget {
  const SummaryPage({super.key});

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  final String _userId = FirebaseAuth.instance.currentUser!.uid;
  final CardSwiperController controller = CardSwiperController();
  late final Stream<QuerySnapshot> _summariesStream;

  bool _showingSwiper = false;
  bool _loadingKnowledge = false;
  List<Knowledge> _learningKnowledges = [];

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _summariesStream = FirebaseFirestore.instance
        .collection('summaries')
        .where("userId", isEqualTo: _userId)
        .orderBy('createdAt', descending: true)
        .snapshots();
    _showCardIfNot();
  }

  void _showCardIfNot() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String lastShownDate = prefs.getString('lastShownDate') ??
        DateTime.now().subtract(Duration(days: 1)).toString();
    if (DateTime.now().difference(DateTime.parse(lastShownDate)).inDays < 1) {
      return;
    }
    prefs.setString('lastShownDate', DateTime.now().toString());
    _fetchLearningSummaries();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('知識'),
          actions: [
            if (_loadingKnowledge)
              const Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.amp_stories_sharp),
                onPressed: () {
                  _toggleSwiper();
                },
              ),
          ],
        ),
        body: Stack(children: [
          StreamBuilder<QuerySnapshot>(
            stream: _summariesStream,
            builder:
                (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
              if (snapshot.hasError) {
                return const Text('エラー');
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.data!.docs.isEmpty) {
                return const Center(
                  child: Text('知識データがありません。'),
                );
              }

              return Padding(
                padding: const EdgeInsets.all(16),
                child: ListView(
                  children: snapshot.data!.docs
                      .map((DocumentSnapshot document) {
                        Summary summary = Summary.fromFirestore(document);
                        return ListTile(
                          title: Text(summary.title),
                          subtitle: Text(DateFormat('yyyy年MM月dd日')
                              .format(summary.createdAt.toDate())),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SummaryDetailPage(
                                  knowledgeIds: summary.knowledges,
                                  summary: summary,
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
                ),
              );
            },
          ),
          if (_showingSwiper && _learningKnowledges.isNotEmpty)
            CardSwiper(
              controller: controller,
              allowedSwipeDirection: AllowedSwipeDirection.only(
                right: true,
                left: true,
              ),
              onSwipe: _onSwipe,
              cardsCount: _learningKnowledges.length,
              isLoop: false,
              numberOfCardsDisplayed: 5,
              cardBuilder:
                  (context, index, percentThresholdX, percentThresholdY) =>
                      Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white,
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[200]!),
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (index < _learningKnowledges.length)
                        Text(
                          _learningKnowledges[index].title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      SizedBox(height: 8),
                      if (index < _learningKnowledges.length)
                        Expanded(
                          child: SingleChildScrollView(
                            child: MarkdownBody(
                                data: _learningKnowledges[index].content),
                          ),
                        ),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ElevatedButton(
                              onPressed: () =>
                                  controller.swipe(CardSwiperDirection.left),
                              child: Row(spacing: 10, children: [
                                const Icon(Icons.arrow_circle_left_outlined),
                                const Text('忘れた')
                              ]),
                            ),
                            ElevatedButton(
                              onPressed: () =>
                                  controller.swipe(CardSwiperDirection.right),
                              child: Row(spacing: 10, children: [
                                const Text('覚えている'),
                                const Icon(Icons.arrow_circle_right_outlined),
                              ]),
                            ),
                          ])
                    ],
                  ),
                ),
              ),
            ),
        ]));
  }

  bool _onSwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction,
  ) {
    debugPrint(
      'The card $previousIndex was swiped to the ${direction.name}. Now the card $currentIndex is on top',
    );
    if (currentIndex == null) {
      return true;
    }
    if (direction.name == 'right') {
      _rememberKnowledge(_learningKnowledges[currentIndex]);
    } else {
      _forgetKnowledge(_learningKnowledges[currentIndex]);
    }
    return true;
  }

  void _toggleSwiper() {
    setState(() {
      if (_showingSwiper) {
        _showingSwiper = false;
      } else {
        _fetchLearningSummaries();
      }
    });
  }

  void _fetchLearningSummaries() async {
    setState(() {
      _loadingKnowledge = true;
    });
    final knowledges = await FirebaseFirestore.instance
        .collection('knowledges')
        .where('userId', isEqualTo: _userId)
        .orderBy('score', descending: false)
        .limit(5)
        .get();

    setState(() {
      _loadingKnowledge = false;
      _showingSwiper = true;
      _learningKnowledges = knowledges.docs
          .map((document) => Knowledge.fromFirestore(document))
          .toList();

      print(_learningKnowledges);
    });
  }

  void _forgetKnowledge(Knowledge knowledge) {
    // update to score
    final newScore = (knowledge.score - 10).clamp(0, 100);
    FirebaseFirestore.instance
        .collection('knowledges')
        .doc(knowledge.id)
        .update({'score': newScore});
  }

  void _rememberKnowledge(Knowledge knowledge) {
    // update to score
    final newScore = (knowledge.score + 10).clamp(0, 100);
    FirebaseFirestore.instance
        .collection('knowledges')
        .doc(knowledge.id)
        .update({'score': newScore});
  }
}
