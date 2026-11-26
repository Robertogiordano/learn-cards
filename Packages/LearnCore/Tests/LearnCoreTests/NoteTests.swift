import XCTest
@testable import LearnCore

final class NoteTests: XCTestCase {
    func testImprovePromptSendsTitleAndText() {
        let note = StudyNote(title: " es gibt ", text: "= ci sono")
        let instruction = NoteImprovePrompt.userInstruction(for: note)
        XCTAssertTrue(instruction.contains("Title: es gibt"))
        XCTAssertTrue(instruction.contains("= ci sono"))
        XCTAssertTrue(NoteImprovePrompt.userInstruction(for: StudyNote(title: "es gibt")).contains("(empty)"))
    }

    func testParsesImprovement() throws {
        let json = """
        Here: {"title": "es gibt + Akkusativ", "text": " es gibt = c'è / ci sono ", \
        "explanation": "Non è **lui dà**: es è impersonale."}
        """
        let result = try NoteImprovePrompt.parse(json)
        XCTAssertEqual(result.title, "es gibt + Akkusativ")
        XCTAssertEqual(result.text, "es gibt = c'è / ci sono")
        XCTAssertTrue(result.explanation.contains("lui dà"))
    }

    func testMissingExplanationFails() {
        XCTAssertThrowsError(try NoteImprovePrompt.parse(#"{"title": "x", "text": "y", "explanation": " "}"#))
        XCTAssertThrowsError(try NoteImprovePrompt.parse("no json"))
    }

    func testDisplayTitleFallsBackToFirstLine() {
        XCTAssertEqual(StudyNote(text: "es gibt = ci sono\nmore").displayTitle, "es gibt = ci sono")
        XCTAssertEqual(StudyNote(title: "es gibt", text: "x").displayTitle, "es gibt")
        XCTAssertTrue(StudyNote(title: " ", text: "\n").isEmpty)
    }

    func testMergeKeepsNewestCopy() {
        let id = UUID()
        let old = StudyNote(id: id, title: "old", updatedAt: Date(timeIntervalSince1970: 10))
        let new = StudyNote(id: id, title: "new", updatedAt: Date(timeIntervalSince1970: 20))
        let other = StudyNote(title: "other", updatedAt: Date(timeIntervalSince1970: 5))
        let merged = NoteMerger.merge(existing: [old], incoming: [new, other])
        XCTAssertEqual(merged.map(\.title), ["new", "other"])
        XCTAssertEqual(NoteMerger.merge(existing: [new], incoming: [old]).map(\.title), ["new"])
    }

    func testBackupRoundTripsNotes() throws {
        let note = StudyNote(title: "es gibt", text: "= ci sono", explanation: "why")
        let backup = Backup(exportedAt: Date(timeIntervalSince1970: 0), words: [], notes: [note])
        let decoded = try BackupCodec.decode(BackupCodec.encode(backup))
        XCTAssertEqual(decoded.notes?.first?.title, "es gibt")
        XCTAssertEqual(decoded.notes?.first?.explanation, "why")
    }
}

final class LookupPromptTests: XCTestCase {
    func testPhraseLookupAsksForOnePhraseAndReusesCategories() throws {
        let prompt = PhraseLookupPrompt.system(existingCategories: ["Idioms"])
        XCTAssertTrue(prompt.contains("exactly one phrase"))
        XCTAssertTrue(prompt.contains("- german:"))
        XCTAssertTrue(prompt.contains("Idioms"))
        let json = """
        {"phrases": [{"german": "Wie geht's?", "variants": ["Wie geht es Ihnen?"], "english": "How are you?", \
        "response": null, "note": null, "kind": "question", "category": "idioms", "emoji": "👋"}]}
        """
        let entry = try XCTUnwrap(PhraseLookupPrompt.parse(json, existingCategories: ["Idioms"]))
        XCTAssertEqual(entry.german, "Wie geht's?")
        XCTAssertEqual(entry.category, "Idioms")
        XCTAssertEqual(entry.kind, .question)
    }

    func testVerbLookupAsksForOneVerb() throws {
        let prompt = VerbLookupPrompt.system()
        XCTAssertTrue(prompt.contains("exactly one verb"))
        XCTAssertTrue(prompt.contains("- forms:"))
        let json = """
        {"verbs": [{"infinitive": "fahren", "english": "to drive", \
        "forms": ["fahre", "fährst", "fährt", "fahren", "fahrt", "fahren"], "group": "stemChanging", \
        "note": "a → ä with du and er", "emoji": "🚗"}]}
        """
        let verb = try XCTUnwrap(VerbLookupPrompt.parse(json))
        XCTAssertEqual(verb.infinitive, "fahren")
        XCTAssertEqual(verb.english, "drive")
        XCTAssertEqual(verb.group, .stemChanging)
        XCTAssertNil(try VerbLookupPrompt.parse(#"{"verbs": []}"#))
    }
}
