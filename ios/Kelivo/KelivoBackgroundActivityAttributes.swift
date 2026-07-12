import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct KelivoBackgroundActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var title: String
    var conversationTitle: String
    var detail: String
    var tokenCount: Int
    var tokenLabel: String
    var isFinished: Bool
    var success: Bool
  }

  var taskId: String
}
