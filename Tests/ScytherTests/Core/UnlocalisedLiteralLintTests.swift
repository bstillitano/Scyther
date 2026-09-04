//
//  UnlocalisedLiteralLintTests.swift
//  ScytherTests
//

import XCTest

/// Fails when a converted source directory passes a string literal straight to a SwiftUI
/// initialiser or modifier instead of routing it through `localized(_:)`.
///
/// Append a directory to ``convertedDirectories`` once every literal in it is localised. A line
/// that legitimately carries a non-UI literal can opt out with `// scyther:unlocalised <reason>`.
final class UnlocalisedLiteralLintTests: XCTestCase {

    /// Directories under `Sources/Scyther` that have been converted. Grows task by task.
    ///
    /// A single `""` entry means the whole of `Sources/Scyther` is covered.
    static let convertedDirectories: [String] = [
        "",
    ]

    static let marker = "// scyther:unlocalised"

    private static let pattern = try! NSRegularExpression(
        pattern: #"(?:\b(?:Text|Button|Label|Section|LabeledContent|Toggle|TextField|SecureField|NavigationLink|ShareLink|SharePreview|Picker|Menu|Link|Stepper)\(|\.(?:navigationTitle|alert|confirmationDialog|accessibilityLabel|accessibilityHint|help)\(|\bprompt:\s*|\btitle:\s*|\bmessage:\s*)"(?!")"#
    )

    private var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Scyther")
    }

    /// Whether `line` should be reported as an unlocalised literal.
    ///
    /// A line opts out by containing ``marker`` or by being a comment (its trimmed text starts
    /// with `//`, which also catches `///` DocC lines); otherwise it offends when `pattern`
    /// matches it.
    static func offends(_ line: String) -> Bool {
        guard !line.contains(marker) else { return false }
        guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { return false }
        let range = NSRange(location: 0, length: (line as NSString).length)
        return pattern.firstMatch(in: line, range: range) != nil
    }

    func testConvertedDirectoriesHaveNoUnlocalisedLiterals() throws {
        var offenders: [String] = []
        for directory in Self.convertedDirectories {
            let url = sourcesRoot.appendingPathComponent(directory)
            let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil))
            for case let file as URL in enumerator where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                for (index, line) in text.components(separatedBy: "\n").enumerated() {
                    if Self.offends(line) {
                        offenders.append("\(file.lastPathComponent):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "Unlocalised literals:\n" + offenders.joined(separator: "\n"))
    }

    func testEveryFeatureDirectoryIsCovered() throws {
        let features = sourcesRoot.appendingPathComponent("Features")
        let names = try FileManager.default.contentsOfDirectory(atPath: features.path).sorted()
        XCTAssertFalse(names.isEmpty)
        XCTAssertEqual(Self.convertedDirectories, [""], "lint must cover the whole source tree once every module is converted")
    }

    func testPatternCatchesSwiftUILiteralsAndHonoursOptOuts() {
        let offenders = [
            #"Text("Network logs")"#,
            #"Button("Delete", systemImage: "trash", role: .destructive) {"#,
            #"Section("Overview") {"#,
            #"LabeledContent("Method", value: viewModel.method)"#,
            #".navigationTitle("Request Details")"#,
            #".alert("Export Sensitive Data?", isPresented: $flag) {"#,
            #".searchable(text: $text, prompt: "Search via URL")"#,
            #"Label("Share Archive", systemImage: "square.and.arrow.up")"#,
            #".accessibilityLabel("Close")"#,
            #"MenuSection(title: "Device", items: [])"#,
        ]
        for line in offenders {
            XCTAssertTrue(Self.offends(line), "should be flagged: \(line)")
        }
        let allowed = [
            #"Text(localized("Network logs"))"#,
            #"Text(verbatim: "raw")"#,
            #"Image(systemName: "checkmark")"#,
            #"UserDefaults.standard.set(value, forKey: "Scyther_key")"#,
            #"/// Text("documentation example")"#,
            #"// Text("commented out")"#,
            #"Text("Opted out") // scyther:unlocalised pasteboard payload"#,
            #"Text("")"#,
        ]
        for line in allowed {
            XCTAssertFalse(Self.offends(line), "should not be flagged: \(line)")
        }
    }
}
