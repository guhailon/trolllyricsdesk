import Foundation

@MainActor
protocol PlaybackAdapter {

    var platform: MusicPlatform { get }

    func currentState() -> PlaybackState?
}
