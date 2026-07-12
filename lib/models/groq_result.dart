/// Uniform success/fail wrapper for every Groq AI call, so UI call sites
/// never need to catch exceptions — AI is an enhancement, never a blocker.
class GroqResult<T> {
  final T? data;
  final String? error;
  final bool isSuccess;

  const GroqResult.ok(this.data)
      : error = null,
        isSuccess = true;

  const GroqResult.fail(this.error)
      : data = null,
        isSuccess = false;
}
