import ActivityKit
import SwiftUI
import WidgetKit

private func kelivoWidgetLocalized(_ key: String, fallback: String) -> String {
  NSLocalizedString(key, tableName: nil, bundle: .main, value: fallback, comment: "")
}

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
        VStack(alignment: .leading, spacing: 2) {
          Text(context.state.conversationTitle)
            .lineLimit(1)
          Text(context.state.detail)
            .lineLimit(2)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
      }
      .padding()
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
            Text(context.state.conversationTitle)
              .lineLimit(1)
            Text(context.state.detail)
              .lineLimit(3)
          }
          .font(.subheadline)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
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
    if state.isFinished {
      return state.success
        ? kelivoWidgetLocalized("ios_background_generation_finished_success", fallback: "Done")
        : kelivoWidgetLocalized("ios_background_generation_finished_interrupted", fallback: "Interrupted")
    }
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
