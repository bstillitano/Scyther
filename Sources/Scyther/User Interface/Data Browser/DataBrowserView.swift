//
//  DataBrowserView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI
import Combine

struct DataBrowserView: View {
    let data: [String: [String: Any]]
    var title: String = "Data Browser"
    var path: [String] = []

    @StateObject private var viewModel: DataBrowserSwiftUIViewModel
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var searchSubject = PassthroughSubject<String, Never>()
    @State private var cancellable: AnyCancellable?

    init(data: [String: [String: Any]], title: String = "Data Browser", path: [String] = []) {
        self.data = data
        self.title = title
        self.path = path
        _viewModel = StateObject(wrappedValue: DataBrowserSwiftUIViewModel(data: data))
    }

    private var breadcrumb: String? {
        guard !path.isEmpty else { return nil }
        return path.joined(separator: " → ")
    }

    private var filteredSections: [DataBrowserSection] {
        guard !debouncedSearchText.isEmpty else { return viewModel.sections }

        let search = debouncedSearchText.lowercased()
        return viewModel.sections.compactMap { section in
            let filteredItems = section.items.filter { item in
                item.key.lowercased().contains(search) ||
                (item.valueDescription?.lowercased().contains(search) ?? false)
            }
            guard !filteredItems.isEmpty else { return nil }
            return DataBrowserSection(title: section.title, items: filteredItems)
        }
    }

    var body: some View {
        List {
            ForEach(filteredSections) { section in
                Section(section.title) {
                    if section.items.isEmpty {
                        Text("No \(section.title)")
                            .fontWeight(.bold)
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(section.items) { item in
                            row(for: item)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .searchable(text: $searchText, prompt: "Search keys and values")
        .onChange(of: searchText) { newValue in
            searchSubject.send(newValue)
        }
        .onAppear {
            cancellable = searchSubject
                .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
                .sink { debouncedSearchText = $0 }
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }

    @ViewBuilder
    private func row(for item: DataBrowserItem) -> some View {
        switch item.itemType {
        case .navigable(let nestedData):
            NavigationLink {
                DataBrowserView(data: nestedData, title: item.key)
            } label: {
                LabeledContent(item.key, value: item.valueDescription ?? "")
            }

        case .plain:
            LabeledContent(item.key, value: item.valueDescription ?? "")
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = "\(item.key): \(item.valueDescription ?? "")"
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
        }
    }
}

struct DataBrowserSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [DataBrowserItem]
}

struct DataBrowserItem: Identifiable {
    let id = UUID()
    let key: String
    let valueDescription: String?
    let itemType: DataBrowserItemType
}

enum DataBrowserItemType {
    case plain
    case navigable(data: [String: [String: Any]])
}

class DataBrowserSwiftUIViewModel: ViewModel {
    private let data: [String: [String: Any]]
    @Published var sections: [DataBrowserSection] = []

    init(data: [String: [String: Any]]) {
        self.data = data
        super.init()
    }

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await prepareObjects()
    }

    @MainActor
    private func prepareObjects() async {
        sections = data.map { key, value in
            let items = value.map { objectKey, objectValue in
                parseItem(key: objectKey, value: objectValue)
            }.sorted { lhs, rhs in
                // Sort array indices numerically, e.g. [0], [1], [2], ..., [10], [11]
                if let lhsIndex = extractArrayIndex(from: lhs.key),
                   let rhsIndex = extractArrayIndex(from: rhs.key) {
                    return lhsIndex < rhsIndex
                }
                // Fall back to alphabetical for non-array keys
                return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
            }

            return DataBrowserSection(title: key, items: items)
        }.sorted { $0.title < $1.title }
    }

    private func extractArrayIndex(from key: String) -> Int? {
        // Match keys like "[0]", "[123]", etc.
        guard key.hasPrefix("["), key.hasSuffix("]") else { return nil }
        let indexString = String(key.dropFirst().dropLast())
        return Int(indexString)
    }

    private func parseItem(key: String, value: Any) -> DataBrowserItem {
        let dataRow = DataRow(title: key, from: value)

        switch dataRow {
        case .array(let title, let arrayData):
            var subData: [String: Any] = [:]
            arrayData.enumerated().forEach { index, element in
                subData["\(index)"] = element
            }
            let nestedData: [String: [String: Any]] = ["Array Data": subData]
            return DataBrowserItem(
                key: title ?? key,
                valueDescription: "Array",
                itemType: .navigable(data: nestedData)
            )

        case .dictionary(let title, let dictionaryData):
            let nestedData: [String: [String: Any]] = ["Dictionary Data": dictionaryData as [String: Any]]
            return DataBrowserItem(
                key: title ?? key,
                valueDescription: "Dictionary",
                itemType: .navigable(data: nestedData)
            )

        case .json(let title, let jsonData):
            if let arrayData = jsonData as? NSArray {
                var subData: [String: Any] = [:]
                arrayData.enumerated().forEach { index, element in
                    subData["\(index)"] = element
                }
                let nestedData: [String: [String: Any]] = ["Array Data": subData]
                return DataBrowserItem(
                    key: title ?? key,
                    valueDescription: "Array",
                    itemType: .navigable(data: nestedData)
                )
            } else if let dictionaryData = jsonData as? NSDictionary {
                let nestedData: [String: [String: Any]] = ["Dictionary Data": dictionaryData.swiftDictionary]
                return DataBrowserItem(
                    key: title ?? key,
                    valueDescription: "Dictionary",
                    itemType: .navigable(data: nestedData)
                )
            } else {
                return DataBrowserItem(
                    key: title ?? key,
                    valueDescription: String(describing: jsonData),
                    itemType: .plain
                )
            }

        case .string(let title, let stringData):
            return DataBrowserItem(
                key: title ?? key,
                valueDescription: stringData,
                itemType: .plain
            )
        }
    }
}

#Preview {
    NavigationStack {
        DataBrowserView(data: [
            "User Info": [
                "name": "John Doe",
                "age": 30,
                "email": "john@example.com"
            ],
            "Settings": [
                "darkMode": true,
                "notifications": false
            ]
        ])
    }
}
