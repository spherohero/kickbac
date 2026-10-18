import Foundation

@main struct CameraActivityChecks {
    static func main() {
        var activity = CameraActivity()
        var session = CameraRequestOrder()
        let oldView = UUID()
        let currentView = UUID()
        let oldStart = activity.activate(owner: oldView)
        let oldStop = activity.deactivate(owner: oldView)!
        let currentStart = activity.activate(owner: currentView)
        precondition(session.accept(currentStart))
        precondition(!session.accept(oldStop) && !session.accept(oldStart))
        precondition(activity.deactivate(owner: oldView) == nil)
        precondition(activity.owner == currentView && activity.isCurrent(currentStart))
        // An inactive, offscreen camera page must not stop the visible camera.
        precondition(activity.deactivate(owner: UUID()) == nil)
        let pause = activity.deactivate(owner: currentView)!
        precondition(activity.nextRequest() == nil && session.accept(pause))
        precondition(!activity.isCurrent(currentStart) && !session.accept(currentStart))
        let resumed = activity.activate(owner: currentView)
        precondition(session.accept(resumed))
        let retake = activity.nextRequest()!
        precondition(session.accept(retake) && !session.accept(pause))
        precondition(!activity.isCurrent(resumed) && activity.isCurrent(retake))
        print("Camera lifecycle checks passed: stale view disposal, offscreen pages, out-of-order start/stop, permission/background pause, foreground resume and retake.")
    }
}
