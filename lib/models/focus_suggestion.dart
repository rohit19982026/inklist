/// AI focus-coach output for a Pomodoro session: which task to tackle next
/// and a one-line motivating reason. [taskTitle] may be empty when the model
/// declines to pick a specific task.
class FocusSuggestion {
  final String taskTitle; // '' when no specific task was chosen
  final String message;

  const FocusSuggestion({required this.taskTitle, required this.message});

  bool get hasTask => taskTitle.isNotEmpty;
}
