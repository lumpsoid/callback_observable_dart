/// A generic callback type that returns a value of type [T].
typedef Callback<T> = void Function(T);

/// A callback that returns nothing.
typedef VoidCallback = Callback<void>;

/// Defines the ability to notify listeners of a change.
// ignore: one_member_abstracts
abstract interface class Notifier<T> {
  const Notifier();

  /// Notifies all registered listeners.
  void notify(T value);
}

/// Defines the ability to register and unregister [VoidCallback] listeners.
abstract interface class Listener<T> {
  const Listener();

  /// Registers [listener] to be called on future notifications.
  void addListener(Callback<T> listener);

  /// Unregisters a previously added [listener].
  ///
  /// Does nothing if [listener] was never added.
  void removeListener(Callback<T> listener);
}

/// Combines [Notifier] and [Listener] into a single observable interface.
abstract interface class Observable<T> implements Notifier<T>, Listener<T> {
  const Observable();

  bool get isDisposed;

  void reset();

  void dispose();
}

/// A specialised [Observable] for notifications that carry no meaningful value.
///
/// Use [VoidObservable] when you only need to signal that *something happened*,
/// without attaching any accompanying data. It is purely type sugar over
/// `Observable<void>`, keeping call-sites free of distracting `<void>`
/// annotations.
abstract class VoidObservable implements Observable<void> {
  const VoidObservable();
}

abstract class VoidNotifier implements Notifier<void> {
  const VoidNotifier();

  void notifyListeners() => notify(null);
}

abstract class VoidListener implements Notifier<void> {
  const VoidListener();
}

abstract interface class ObservableValue<T> implements Observable<T> {
  T get value;
}

mixin ObservableReplayOnSubscribe<T> on ObservableValue<T> {
  @override
  void addListener(Callback<T> listener) {
    super.addListener(listener);
    listener(value);
  }
}

/// An [Observable] implementation that silently ignores all operations.
///
/// Useful as a default or placeholder where an [Observable] is required
/// but no actual notification behaviour is needed.
class NoOpObservable implements VoidObservable {
  /// Creates a constant no-op observable.
  const NoOpObservable({this.isDisposed = false});

  @override
  final bool isDisposed;

  /// Does nothing.
  @override
  void addListener(VoidCallback listener) {}

  /// Does nothing.
  @override
  void removeListener(VoidCallback listener) {}

  /// Does nothing.
  @override
  void notify(void value) {}

  @override
  void reset() {}

  @override
  void dispose() {}
}

/// A [Notifier] that safely handles listener removal during notification
/// by using tombstoning — nulling out removed entries instead of shifting the
/// list mid-iteration, then compacting once the notification cycle ends.
class TombstoneObservable<T> implements Observable<T> {
  final List<Callback<T>?> _listeners = [];
  int _notifyDepth = 0;
  bool _hasTombstones = false;
  bool _disposed = false;

  void _assertNotDisposed() {
    assert(!_disposed, 'TombstoneObservable has already been disposed.');
  }

  /// Registers [listener] to receive future notifications.
  @override
  void addListener(Callback<T> listener) {
    _assertNotDisposed();
    _listeners.add(listener);
  }

  /// Unregisters [listener].
  ///
  /// If called during an active [notify] cycle the entry is tombstoned (set to
  /// `null`) and removed once the outermost notification cycle completes,
  /// preventing index-shift bugs during iteration.
  @override
  void removeListener(Callback<T> listener) {
    _assertNotDisposed();
    final idx = _listeners.indexOf(listener);
    if (idx == -1) return;
    if (_notifyDepth > 0) {
      _listeners[idx] = null;
      _hasTombstones = true;
    } else {
      _listeners.removeAt(idx);
    }
  }

  /// Calls every registered listener with [value].
  ///
  /// Re-entrant calls are supported; tombstone compaction is deferred until
  /// the outermost invocation returns.
  @override
  void notify(T value) {
    _assertNotDisposed();

    if (_listeners.isEmpty) return;

    _notifyDepth++;
    try {
      for (var i = 0; i < _listeners.length; i++) {
        _listeners[i]?.call(value);
      }
    } finally {
      _notifyDepth--;
      if (_notifyDepth == 0 && _hasTombstones) {
        _listeners.removeWhere((cb) => cb == null);
        _hasTombstones = false;
      }
    }
  }

  /// Removes all registered listeners without notifying them and without
  /// marking the observable as disposed. Safe to call at any time, including
  /// during an active [notify] cycle (all live entries are tombstoned).
  @override
  void reset() {
    if (_notifyDepth > 0) {
      // Tombstone every live entry; compaction runs when notify unwinds.
      for (var i = 0; i < _listeners.length; i++) {
        if (_listeners[i] != null) {
          _listeners[i] = null;
          _hasTombstones = true;
        }
      }
    } else {
      _listeners.clear();
    }
  }

  /// Permanently tears down this observable.
  ///
  /// All listeners are removed (tombstoned if inside a [notify] cycle) and
  /// further calls to [addListener], [removeListener], or [notify] will throw
  /// an [AssertionError] in debug mode.
  ///
  /// Calling [dispose] more than once is a no-op.
  @override
  void dispose() {
    if (_disposed) return;
    reset();
    _disposed = true;
  }

  /// Whether this observable has been disposed.
  @override
  bool get isDisposed => _disposed;
}
