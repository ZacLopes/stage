import 'package:flutter/material.dart';
import '../../data/supabase_repository.dart';

class DebugDataScreen extends StatelessWidget {
  final SupabaseRepository repo = SupabaseRepository();

  DebugDataScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Debug: Gamification Data')),
      body: FutureBuilder<Map<String, String>>(
        future: repo.getUserAnswersWithQuestions(),
        builder: (context, snapshot) {
           if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
           if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
           
           final data = snapshot.data ?? {};
           if (data.isEmpty) return const Center(child: Text('No Data Found! (Map is empty)'));

           return ListView.separated(
             padding: const EdgeInsets.all(16),
             itemCount: data.length,
             separatorBuilder: (_, __) => const Divider(),
             itemBuilder: (ctx, i) {
                final key = data.keys.elementAt(i);
                final val = data[key];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(key, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    const SizedBox(height: 4),
                    Text(val ?? 'null', style: const TextStyle(fontFamily: 'Courier')),
                  ],
                );
             },
           );
        },
      ),
    );
  }
}
