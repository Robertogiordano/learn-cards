import LearnCore
import SwiftUI

/// Everything about telling the time on one page: both ways of saying it, the "halb" trap,
/// the questions and the words around a time. Every German line can be heard.
struct TimeCheatSheetView: View {
    @Environment(\.dismiss) private var dismiss

    /// One hour, every 5 minutes, from 3:00 to 4:00.
    private let hourTable: [ClockTime] = stride(from: 0, through: 60, by: 5).map { ClockTime(hour: 15, minute: $0) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SayLine(german: "Wie spät ist es?", english: "What time is it?")
                    SayLine(german: "Wie viel Uhr ist es?", english: "What time is it? (same)")
                    SayLine(german: "Es ist halb vier.", english: "It's half past three.")
                    SayLine(german: "Um wie viel Uhr …?", english: "At what time …?")
                    SayLine(german: "Um halb acht.", english: "At half past seven.")
                } header: {
                    Text("Asking and answering")
                } footer: {
                    Text("Answer with “Es ist …”; for “when?” use “um …”.")
                }

                Section {
                    HStack(alignment: .top, spacing: 12) {
                        registerColumn(title: "Official", subtitle: "24 h · timetables, radio, appointments",
                                       lines: ["15:20", "fünfzehn Uhr zwanzig", "hour + Uhr + minutes"])
                        Divider()
                        registerColumn(title: "Everyday", subtitle: "12 h · talking, clock faces",
                                       lines: ["3:20", "zwanzig nach drei", "minutes + nach / vor + hour"])
                    }
                    .padding(.vertical, 4)
                    SayLine(german: "Der Zug fährt um siebzehn Uhr zwölf.", english: "The train leaves at 17:12.")
                    SayLine(german: "Wir treffen uns um Viertel nach fünf.", english: "We meet at quarter past five.")
                } header: {
                    Text("Two ways")
                } footer: {
                    Text("In the official way the minutes come after “Uhr” and there is no “nach”, “vor” or “halb”. 1:00 is “ein Uhr”; alone it is “eins” (Viertel nach eins).")
                }

                Section {
                    HStack(spacing: 16) {
                        ClockFace(time: ClockTime(hour: 3, minute: 30))
                            .frame(width: 84, height: 84)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("halb vier = 3:30")
                                .font(.title3.bold())
                            Text("not 4:30! “halb” is half way TO the next hour.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    SayLine(german: "halb eins", english: "12:30")
                    SayLine(german: "halb acht", english: "7:30")
                } header: {
                    Text("The trap: halb")
                } footer: {
                    Text("Think “half (of the way) to four”. Viertel vor and the minutes around halb also look at the next hour.")
                }

                Section {
                    ForEach(hourTable, id: \.self) { time in
                        HStack(spacing: 12) {
                            ClockFace(time: time)
                                .frame(width: 34, height: 34)
                            Text(time.digital12)
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .frame(width: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(GermanTime.informalVariants(time), id: \.self) { phrase in
                                    Text(phrase)
                                        .font(.subheadline)
                                }
                            }
                            Spacer()
                            ListenButton(text: "Es ist \(GermanTime.informal(time)).")
                        }
                    }
                } header: {
                    Text("One hour, every 5 minutes")
                } footer: {
                    Text("Up to :20 count from the hour (nach); from :40 count to the next hour (vor). :25 and :35 count from “halb”. At :20 and :40 both ways are common.")
                }

                Section {
                    timeOfDayRow("morgens", "in the morning", "5–10")
                    timeOfDayRow("vormittags", "late morning", "10–12")
                    timeOfDayRow("mittags", "at midday", "12–14")
                    timeOfDayRow("nachmittags", "in the afternoon", "14–18")
                    timeOfDayRow("abends", "in the evening", "18–22")
                    timeOfDayRow("nachts", "at night", "22–5")
                    SayLine(german: "um acht Uhr abends", english: "at 8 pm (= zwanzig Uhr)")
                } header: {
                    Text("Times of day")
                } footer: {
                    Text("The everyday way has no am/pm: add morgens, abends … when it matters.")
                }

                Section {
                    SayLine(german: "kurz nach drei", english: "just after three")
                    SayLine(german: "kurz vor halb vier", english: "just before half past three")
                    SayLine(german: "gegen sieben", english: "around seven")
                    SayLine(german: "Punkt zwölf", english: "twelve sharp")
                    SayLine(german: "von neun bis fünf", english: "from nine to five")
                    SayLine(german: "ab acht Uhr", english: "from eight o'clock on")
                    SayLine(german: "Mitternacht · Mittag", english: "midnight · noon")
                    SayLine(german: "eine Viertelstunde · eine halbe Stunde", english: "a quarter of an hour · half an hour")
                    SayLine(german: "Meine Uhr geht vor / nach.", english: "My watch is fast / slow.")
                } header: {
                    Text("Useful words")
                }
            }
            .navigationTitle("Telling the time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func registerColumn(title: String, subtitle: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.clock)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(lines[0])
                .font(.title3.monospacedDigit().weight(.semibold))
                .padding(.top, 4)
            Text(lines[1])
                .font(.subheadline.weight(.medium))
            Text(lines[2])
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timeOfDayRow(_ german: String, _ english: String, _ hours: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(german)
                    .font(.subheadline.weight(.semibold))
                Text(english)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(hours)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            ListenButton(text: german)
        }
    }
}

/// A German line with its English and a button to hear it.
private struct SayLine: View {
    let german: String
    let english: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(german)
                    .font(.subheadline.weight(.semibold))
                Text(english)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ListenButton(text: german)
        }
    }
}

private struct ListenButton: View {
    let text: String

    var body: some View {
        Button {
            Speaker.shared.speak(text)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(Color.clock)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Listen")
    }
}
