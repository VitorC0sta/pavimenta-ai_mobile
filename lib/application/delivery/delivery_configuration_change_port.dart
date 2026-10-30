/// Hook through which a change of destination or credential reaches the
/// delivery coordinator (design E4.4 `onConfigurationChanged`, E4.6).
///
/// The coordinator implements it. The two calls bracket one write of the
/// destination or the credential: [suspendForConfigurationChange] runs before
/// anything is written, and [onConfigurationChanged] runs once the write is
/// settled.
abstract interface class DeliveryConfigurationChangePort {
  /// Cancels or suspends the attempt that uses the old configuration, before
  /// the new value is written.
  ///
  /// It cancels the request in flight and the preparation under way, and it
  /// completes only when the old attempt can no longer open a socket, persist
  /// an outcome (a decision, a retry, or a pause), or start a new snapshot.
  /// Until [onConfigurationChanged] is called no new attempt starts.
  ///
  /// It must not throw. If it does, nothing is written.
  Future<void> suspendForConfigurationChange();

  /// Asks for one immediate, coalesced evaluation of the queue.
  ///
  /// It ends the suspension started by [suspendForConfigurationChange]. It
  /// does not wait for the evaluation, so it never blocks the caller.
  void onConfigurationChanged();
}
