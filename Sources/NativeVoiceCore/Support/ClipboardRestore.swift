import Foundation

/// Puts back whatever was on the clipboard before a transcript was pasted.
///
/// Two things this has to get right, both learned the hard way:
///
/// The delay has to outlast a slow receiver. At 0.45 s an Electron app or a
/// remote desktop read the clipboard only after it had been restored and
/// pasted the old contents instead of the transcript.
///
/// The pending restore has to be cancellable. It overwrites the clipboard
/// unconditionally, so anything the user put there in the meantime — a history
/// entry they clicked — would be thrown straight back out.
public final class ClipboardRestore: @unchecked Sendable {
    private let delay: TimeInterval
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var work: DispatchWorkItem?

    public init(delay: TimeInterval = 1.2, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }

    // `work` is written by whoever schedules or cancels and cleared by the
    // work item on `queue`. Those are different threads, so the access is
    // locked rather than left to chance.
    public var isPending: Bool { lock.lock(); defer { lock.unlock() }; return work != nil }

    /// `previous` stays optional all the way through: the clipboard may have
    /// held an image or a file, and substituting an empty string for that
    /// would wipe it instead of restoring it.
    public func schedule(previous: String?, restore: @escaping (String?) -> Void) {
        cancel()
        let item = DispatchWorkItem { [weak self] in
            restore(previous)
            guard let self else { return }
            self.lock.lock(); self.work = nil; self.lock.unlock()
        }
        lock.lock(); work = item; lock.unlock()
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    public func cancel() {
        lock.lock()
        let item = work
        work = nil
        lock.unlock()
        item?.cancel()
    }
}
