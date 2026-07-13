import '../models/todo_task.dart';

/// Local, offline near-duplicate detection for task titles — deliberately
/// NOT an AI call: this is a pure string-similarity problem, not one that
/// needs a model's judgment, so it should be instant and free rather than
/// round-tripping to Groq on every keystroke (same reasoning as
/// SmartSnoozeHelper on the native alarm side).
class DuplicateTaskService {
  DuplicateTaskService._();

  static const _stopwords = {'the', 'a', 'an', 'to', 'of', 'my', 'and'};
  static const _similarityThreshold = 0.6;

  /// Returns the most similar task in [openTasks] to [title], or null if
  /// nothing clears the similarity threshold. [openTasks] should already be
  /// filtered to tasks worth warning about (e.g. incomplete/recurring ones).
  static TodoTask? findLikelyDuplicate(String title, List<TodoTask> openTasks) {
    final target = _tokenize(title);
    if (target.isEmpty) return null;

    TodoTask? best;
    var bestScore = 0.0;
    for (final t in openTasks) {
      final candidate = _tokenize(t.title);
      if (candidate.isEmpty) continue;
      final score = _jaccard(target, candidate);
      if (score > bestScore) {
        bestScore = score;
        best = t;
      }
    }
    return bestScore >= _similarityThreshold ? best : null;
  }

  static Set<String> _tokenize(String s) {
    final normalized = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty && !_stopwords.contains(w));
    return normalized.toSet();
  }

  static double _jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty && b.isEmpty) return 0;
    final intersection = a.intersection(b).length;
    final union = a.union(b).length;
    if (union == 0) return 0;
    return intersection / union;
  }
}
