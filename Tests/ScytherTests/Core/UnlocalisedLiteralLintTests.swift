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
    static let convertedDirectories: [String] = [
        "Core",
        "Features/Localization",
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

    func testConvertedDirectoriesHaveNoUnlocalisedLiterals() throws {
        var offenders: [String] = []
        for directory in Self.convertedDirectories {
            let url = sourcesRoot.appendingPathComponent(directory)
            let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil))
            for case let file as URL in enumerator where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                for (index, line) in text.components(separatedBy: "\n").enumerated() {
                    guard !line.contains(Self.marker) else { continue }
                    guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                    let range = NSRange(location: 0, length: (line as NSString).length)
                    if Self.pattern.firstMatch(in: line, range: range) != nil {
                        offenders.append("\(file.lastPathComponent):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "Unlocalised literals:\n" + offenders.joined(separator: "\n"))
    }
}
