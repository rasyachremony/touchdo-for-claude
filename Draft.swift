// The to-do being typed on the Touch Bar: text, caret, selection and undo, edited like a Mac text field.
// Positions count Characters. Self-check: ./test.sh
import Foundation

struct Draft {
    enum Unit { case char, word, line }

    private(set) var text = ""
    private(set) var caret = 0
    private(set) var anchor: Int?           // other end of the selection; nil when nothing is selected
    private var history: [(text: String, caret: Int)] = []

    init(_ text: String = "") { self.text = text; caret = text.count }

    var selection: Range<Int>? {
        guard let anchor, anchor != caret else { return nil }
        return max(0, min(anchor, caret))..<min(text.count, max(anchor, caret))
    }
    var selectedText: String? { selection.map { String(Array(text)[$0]) } }

    // MARK: Editing

    mutating func insert(_ typed: String) {
        let clean = String(typed.map { $0.isNewline ? " " : $0 }).filter { char in
            char.unicodeScalars.allSatisfy { $0.properties.generalCategory != .control && !(0xF700...0xF8FF).contains($0.value) }
        }
        guard !clean.isEmpty else { return }
        remember()
        removeSelection()
        let before = text.count                        // an accent or skin tone can merge into the previous character,
        text.insert(contentsOf: clean, at: index(caret))   // so move by how much the text actually grew
        caret = min(max(caret + text.count - before, 0), text.count)
    }

    /// Backspace (with ⌥ a word, with ⌘ to the start). A selection is deleted instead.
    mutating func deleteBackward(_ unit: Unit = .char) {
        if selection != nil { remember(); return removeSelection() }
        anchor = nil
        let from = boundary(before: caret, unit)
        guard from < caret else { return }
        remember()
        text.removeSubrange(index(from)..<index(caret))
        caret = from
    }

    /// Forward delete (with ⌥ a word, with ⌘ or Ctrl-K to the end). A selection is deleted instead.
    mutating func deleteForward(_ unit: Unit = .char) {
        if selection != nil { remember(); return removeSelection() }
        anchor = nil
        let to = boundary(after: caret, unit)
        guard to > caret else { return }
        remember()
        text.removeSubrange(index(caret)..<index(to))
    }

    mutating func cut() -> String? {
        guard let cut = selectedText else { return nil }
        remember()
        removeSelection()
        return cut
    }

    mutating func undo() {
        guard let last = history.popLast() else { return }
        text = last.text
        caret = min(last.caret, text.count)
        anchor = nil
    }

    // MARK: Moving and selecting

    mutating func selectAll() { anchor = 0; caret = text.count }

    /// Arrow keys: with shift the selection grows, without it a selection collapses to that side first.
    mutating func move(left: Bool, _ unit: Unit = .char, extend: Bool = false) {
        if extend {
            if anchor == nil { anchor = caret }
        } else if let range = selection, unit == .char {
            caret = left ? range.lowerBound : range.upperBound
            anchor = nil
            return
        } else {
            anchor = nil
        }
        caret = left ? boundary(before: caret, unit) : boundary(after: caret, unit)
        if anchor == caret { anchor = nil }            // nothing ended up selected
    }

    // MARK: Helpers

    private func index(_ i: Int) -> String.Index { text.index(text.startIndex, offsetBy: min(max(i, 0), text.count)) }

    private mutating func remember() {
        history.append((text, caret))
        if history.count > 100 { history.removeFirst() }
    }

    private mutating func removeSelection() {
        guard let range = selection else { anchor = nil; return }
        text.removeSubrange(index(range.lowerBound)..<index(range.upperBound))
        caret = range.lowerBound
        anchor = nil
    }

    private static func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

    private func boundary(before i: Int, _ unit: Unit) -> Int {
        switch unit {
        case .char: return max(0, i - 1)
        case .line: return 0
        case .word:
            let chars = Array(text)
            var j = min(i, chars.count)
            while j > 0, !Draft.isWord(chars[j - 1]) { j -= 1 }   // skip spaces and punctuation, then the word
            while j > 0, Draft.isWord(chars[j - 1]) { j -= 1 }
            return j
        }
    }

    private func boundary(after i: Int, _ unit: Unit) -> Int {
        switch unit {
        case .char: return min(text.count, i + 1)
        case .line: return text.count
        case .word:
            let chars = Array(text)
            var j = max(i, 0)
            while j < chars.count, !Draft.isWord(chars[j]) { j += 1 }
            while j < chars.count, Draft.isWord(chars[j]) { j += 1 }
            return j
        }
    }
}
