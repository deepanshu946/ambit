import SwiftUI
import AmbitCore

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    private var days: [(day: Date, records: [SessionRecord])] {
        Dictionary(grouping: model.history) { Calendar.current.startOfDay(for: $0.startedAt) }
            .map { ($0.key, $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        Group {
            if model.history.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "clock",
                                       description: Text("Start a mode and end the session to see it here."))
            } else {
                List {
                    Section {
                        LabeledContent("Total focus time") {
                            Text(model.history.totalCompletedTime.hoursAndMinutes).font(.title3.weight(.medium)).monospacedDigit()
                        }
                        .padding(.vertical, 4)
                    }
                    ForEach(days, id: \.day) { group in
                        Section {
                            ForEach(group.records) { RecordRow(record: $0) }
                        } header: {
                            HStack {
                                Text(group.day, format: .dateTime.weekday(.wide).month().day())
                                Spacer()
                                Text(group.records.totalCompletedTime.hoursAndMinutes).monospacedDigit()
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("History")
    }
}

private struct RecordRow: View {
    let record: SessionRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(record.modeName)
                Text("\(record.startedAt.formatted(date: .omitted, time: .shortened)) to \(record.endedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if record.status == .cancelled {
                Label("Discarded", systemImage: "xmark.circle").font(.callout).foregroundStyle(.secondary)
            }
            Text(Duration.seconds(Int(record.elapsed)), format: .time(pattern: .hourMinuteSecond))
                .monospacedDigit()
                .foregroundStyle(record.status == .cancelled ? .secondary : .primary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private extension TimeInterval {
    var hoursAndMinutes: String {
        Duration.seconds(Int(self)).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, zeroValueUnits: .hide))
            .ifEmpty("0m")
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
