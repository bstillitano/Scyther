//
//  NetworkRuleHeaderField.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Foundation

/// One editable header row in ``NetworkRuleEditorView``.
///
/// Headers are persisted as a `[String: String]` dictionary, which has no order and no identity —
/// editing one directly in a `ForEach` would make rows jump around as the developer types a name,
/// and would collapse two half-typed rows into one the moment their names matched. The editor
/// therefore works on an ordered array of these, each carrying its own identifier, and folds the
/// array back into a dictionary only when it writes to the rule.
///
/// The same type backs the "remove these headers" list, where only ``name`` is meaningful and
/// ``value`` is left empty.
struct NetworkRuleHeaderField: Identifiable, Equatable {
    /// A stable identity, so a row keeps its focus while its name is being typed.
    let id: UUID

    /// The header name, e.g. `Authorization`.
    var name: String

    /// The header value. Unused by the "remove these headers" list.
    var value: String

    /// Creates a header row.
    ///
    /// - Parameters:
    ///   - id: A stable identity. Defaults to a fresh one.
    ///   - name: The header name. Defaults to empty, which is what a newly added row starts as.
    ///   - value: The header value. Defaults to empty.
    init(id: UUID = UUID(), name: String = "", value: String = "") {
        self.id = id
        self.name = name
        self.value = value
    }

    /// Whether this row names a header. Unnamed rows are dropped when the editor writes to a rule.
    var isNamed: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The header name with surrounding whitespace removed.
    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

internal extension Array where Element == NetworkRuleHeaderField {
    /// The named rows folded into the dictionary a rule persists.
    ///
    /// Later rows win a name collision, matching what the developer sees: the last row they typed
    /// is the one whose value survives.
    var headerDictionary: [String: String] {
        reduce(into: [String: String]()) { result, field in
            guard field.isNamed else { return }
            result[field.trimmedName] = field.value
        }
    }

    /// The names of the named rows, in order, for a rewrite's remove list.
    var headerNames: [String] {
        filter(\.isNamed).map(\.trimmedName)
    }

    /// Builds editable rows from a persisted header dictionary, ordered by name so the list is
    /// stable across launches rather than following the dictionary's arbitrary hashing order.
    ///
    /// - Parameter headers: The persisted headers.
    /// - Returns: One row per header.
    static func fields(from headers: [String: String]) -> [NetworkRuleHeaderField] {
        headers.sorted { $0.key < $1.key }.map { NetworkRuleHeaderField(name: $0.key, value: $0.value) }
    }

    /// Builds editable rows from a persisted list of header names.
    ///
    /// - Parameter names: The persisted names.
    /// - Returns: One row per name, with an empty value.
    static func fields(from names: [String]) -> [NetworkRuleHeaderField] {
        names.map { NetworkRuleHeaderField(name: $0) }
    }
}
