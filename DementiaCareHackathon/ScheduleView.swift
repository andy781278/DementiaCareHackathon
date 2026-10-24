//
//  ScheduleView.swift
//  DementiaCareHackathon
//
//  Weekly calendar of events. The patient and the caretaker see the same events.
//

import SwiftUI

struct ScheduleView: View {
    @ObservedObject var schedule: ScheduleStore
    /// "patient" or "caretaker", saved on new events.
    let createdBy: String
    /// False when the caretaker is not connected to a patient yet.
    let isAvailable: Bool

    @State private var weekStart = ScheduleView.startOfWeek(containing: Date())
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var showingAdd = false

    var body: some View {
        Group {
            if isAvailable {
                VStack(spacing: 0) {
                    weekHeader
                    dayStrip
                    Divider()
                    eventList
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 56))
                        .foregroundColor(.secondary)
                    Text("Connect to a patient to see their schedule.")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .navigationTitle("Schedule")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add event", systemImage: "plus")
                        .font(.title2)
                }
                .disabled(!isAvailable)
            }
        }
        .sheet(isPresented: $showingAdd) {
            EventEditorView(day: selectedDay) { event, recording in
                var saved = event
                saved.createdBy = createdBy
                schedule.add(saved, recording: recording)
            }
        }
    }

    // MARK: - Week header and day strip

    private var weekHeader: some View {
        HStack {
            Button {
                moveWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2.bold())
                    .frame(width: 48, height: 48)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(weekRangeText)
                    .font(.title3.bold())
                Button("Today") {
                    weekStart = ScheduleView.startOfWeek(containing: Date())
                    selectedDay = Calendar.current.startOfDay(for: Date())
                }
                .font(.body)
            }

            Spacer()

            Button {
                moveWeek(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title2.bold())
                    .frame(width: 48, height: 48)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var dayStrip: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { offset in
                let day = Calendar.current.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDay)
                let isToday = Calendar.current.isDateInToday(day)
                let hasEvents = schedule.events.contains { $0.occurs(on: day) }

                Button {
                    selectedDay = day
                } label: {
                    VStack(spacing: 4) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.subheadline)
                        Text(day.formatted(.dateTime.day()))
                            .font(.title2.bold())
                        Circle()
                            .fill(hasEvents ? (isSelected ? Color.white : Color.accentColor) : Color.clear)
                            .frame(width: 6, height: 6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelected ? Color.accentColor : (isToday ? Color.accentColor.opacity(0.15) : Color.clear))
                    )
                    .foregroundColor(isSelected ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }

    // MARK: - Events for the selected day

    private var eventsForSelectedDay: [ScheduleEvent] {
        schedule.events
            .filter { $0.occurs(on: selectedDay) }
            .sorted { $0.minutesSinceMidnight < $1.minutesSinceMidnight }
    }

    private var eventList: some View {
        let events = eventsForSelectedDay
        return List {
            Section {
                if events.isEmpty {
                    Text("No events on this day.")
                        .font(.title3)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(events) { event in
                        EventRow(event: event)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            schedule.delete(events[index])
                        }
                    }
                }
            } header: {
                Text(selectedDay.formatted(date: .complete, time: .omitted))
                    .font(.headline)
            } footer: {
                if !events.isEmpty {
                    Text("Swipe left on an event to delete it.")
                        .font(.body)
                }
            }

            if let errorMessage = schedule.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "wifi.exclamationmark")
                        .foregroundColor(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Helpers

    private var weekRangeText: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let startText = weekStart.formatted(.dateTime.month(.abbreviated).day())
        let endText = end.formatted(.dateTime.month(.abbreviated).day())
        return "\(startText) – \(endText)"
    }

    private func moveWeek(by weeks: Int) {
        let calendar = Calendar.current
        weekStart = calendar.date(byAdding: .day, value: 7 * weeks, to: weekStart) ?? weekStart
        selectedDay = calendar.date(byAdding: .day, value: 7 * weeks, to: selectedDay) ?? selectedDay
    }

    static func startOfWeek(containing date: Date) -> Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start
            ?? Calendar.current.startOfDay(for: date)
    }
}

struct EventRow: View {
    let event: ScheduleEvent

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(event.timeText)
                .font(.title3.bold())
                .frame(width: 100, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.title3)
                Text(detailText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var detailText: String {
        var parts: [String] = []
        parts.append(event.hasReminder ? event.reminderText : "No reminder")
        if event.repeatRule != .never {
            parts.append(event.repeatRule.title)
        }
        if event.hasCustomRecording {
            parts.append("Voice message")
        }
        if event.createdBy == "caretaker" {
            parts.append("Added by caretaker")
        } else if event.createdBy == "patient" {
            parts.append("Added by patient")
        }
        return parts.joined(separator: " · ")
    }
}

struct EventEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var date: Date
    @State private var repeatRule: RepeatRule = .never
    @State private var reminder: ReminderOption = .atTime
    @StateObject private var recorder = VoiceRecorder()

    private let onSave: (ScheduleEvent, Data?) -> Void

    init(day: Date, onSave: @escaping (ScheduleEvent, Data?) -> Void) {
        let calendar = Calendar.current
        var start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        // For today, start at the next full hour if 9 AM has already passed.
        if start < Date() && calendar.isDateInToday(day) {
            start = calendar.dateInterval(of: .hour, for: Date())?.end ?? Date()
        }
        _date = State(initialValue: start)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("For example: Take blue pill", text: $title)
                        .font(.title3)
                } header: {
                    Text("Event name")
                }

                Section {
                    DatePicker("Date and time", selection: $date)
                        .font(.title3)
                    Picker("Repeat", selection: $repeatRule) {
                        ForEach(RepeatRule.allCases) { rule in
                            Text(rule.title).tag(rule)
                        }
                    }
                    .font(.title3)
                } header: {
                    Text("When")
                }

                Section {
                    Picker("Remind", selection: $reminder) {
                        ForEach(ReminderOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .font(.title3)
                } header: {
                    Text("Reminder")
                } footer: {
                    Text("The reminder plays on the patient's phone and is read aloud. It repeats more often for higher dementia levels.")
                }

                if reminder != .none {
                    Section {
                        VoiceMessageControls(recorder: recorder)
                            .padding(.vertical, 4)
                    } header: {
                        Text("Voice message (optional)")
                    } footer: {
                        Text("If you record a message, the patient hears it instead of the reminder being read aloud. Up to \(Int(VoiceRecorder.maxSeconds)) seconds.")
                    }
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recorder.stopRecording()
                        recorder.stopPlaying()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let event = ScheduleEvent(
                            title: title.trimmed,
                            date: date,
                            repeatRule: repeatRule,
                            reminderMinutesBefore: reminder.rawValue
                        )
                        recorder.stopPlaying()
                        onSave(event, reminder == .none ? nil : recorder.recordedData)
                        dismiss()
                    }
                    .disabled(title.trimmed.isEmpty || recorder.isRecording)
                }
            }
        }
    }
}
