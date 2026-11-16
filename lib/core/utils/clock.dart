/// Injectable clock so time-dependent logic (auto-lock, "today") is testable.
typedef Clock = DateTime Function();

DateTime systemClock() => DateTime.now();
