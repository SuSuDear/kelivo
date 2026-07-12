import ActivityKit
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 16.1, *)
struct KelivoLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: KelivoBackgroundActivityAttributes.self) { context in
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Image(systemName: context.state.isFinished ? (context.state.success ? "checkmark.circle.fill" : "xmark.circle.fill") : "sparkles")
          Text(context.state.title)
            .font(.headline)
            .lineLimit(1)
          Spacer(minLength: 8)
          Text(context.state.tokenLabel)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        Text(context.state.detail)
          .font(.subheadline)
          .lineLimit(2)
          .foregroundStyle(.secondary)
      }
      .padding()
      .activityBackgroundTint(Color(.secondarySystemBackground))
      .activitySystemActionForegroundColor(.orange)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label("Kelivo", systemImage: context.state.isFinished ? (context.state.success ? "checkmark.circle.fill" : "xmark.circle.fill") : "sparkles")
            .font(.caption)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(shortTokenLabel(context.state))
            .font(.caption.monospacedDigit())
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 2) {
            Text(context.state.title)
              .font(.headline)
              .lineLimit(1)
            Text(context.state.detail)
              .font(.caption)
              .lineLimit(2)
              .foregroundStyle(.secondary)
          }
        }
      } compactLeading: {
        Image(systemName: context.state.isFinished ? (context.state.success ? "checkmark.circle.fill" : "xmark.circle.fill") : "sparkles")
      } compactTrailing: {
        Text(shortTokenLabel(context.state))
          .font(.caption2.monospacedDigit())
      } minimal: {
        Image(systemName: context.state.isFinished ? (context.state.success ? "checkmark" : "xmark") : "sparkles")
      }
      .keylineTint(.orange)
    }
  }

  private func shortTokenLabel(_ state: KelivoBackgroundActivityAttributes.ContentState) -> String {
    if state.isFinished { return state.success ? "完成" : "中断" }
    if state.tokenCount >= 1000 { return "\(state.tokenCount / 1000)k" }
    return "\(state.tokenCount)"
  }
}

@available(iOSApplicationExtension 16.1, *)
@main
struct KelivoLiveActivityExtensionBundle: WidgetBundle {
  var body: some Widget {
    KelivoLiveActivityWidget()
  }
}
