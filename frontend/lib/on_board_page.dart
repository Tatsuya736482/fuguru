import 'package:flutter/material.dart';
import 'package:frontend/login_page.dart';

class OnBoardPage extends StatefulWidget {
  final VoidCallback onComplete;
  const OnBoardPage({required this.onComplete, super.key});

  @override
  _OnBoardPageState createState() => _OnBoardPageState();
}

class _OnBoardPageState extends State<OnBoardPage> {
  int currentPage = 0;

  final List<Map<String, String>> onboardData = [
    {
      "title": "Fuguruへようこそ",
      "description": "あなたのパーソナライズされた知識管理ツール",
      "image": "assets/images/onboard_1.jpeg"
    },
    {
      "title": "知ったことを省略",
      "description": "知識を整理して、新しい情報を効率よく取り込むことができます",
      "image": "assets/images/onboard_2.webp"
    },
    {
      "title": "ドキュメントを追加だけで",
      "description": "ドキュメントを追加するだけで、自動的にあなただけのコンテンツになります",
      "image": "assets/images/onboard_3.webp"
    }
  ];

  void nextPage() {
    if (currentPage < onboardData.length - 1) {
      setState(() {
        currentPage++;
      });
    } else {
      // Navigate to the next page or home screen
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Spacer(),
              ClipOval(
                child: SizedBox.fromSize(
                  size: Size.fromRadius(48), // Image radius
                  child: Image.asset(onboardData[currentPage]["image"] ?? "",
                      fit: BoxFit.cover),
                ),
              ),
              SizedBox(height: 20),
              Text(
                onboardData[currentPage]["title"] ?? "",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  onboardData[currentPage]["description"] ?? "",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ),
              Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: ElevatedButton(
                  onPressed: nextPage,
                  child: Text(
                    currentPage < onboardData.length - 1 ? "次へ" : "始める！",
                  ),
                ),
              ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  onboardData.length,
                  (index) => buildDot(index),
                ),
              ),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildDot(int index) {
    return Container(
      margin: EdgeInsets.only(right: 8),
      height: 8,
      width: currentPage == index ? 16 : 8,
      decoration: BoxDecoration(
        color: currentPage == index ? Colors.blue : Colors.grey,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
