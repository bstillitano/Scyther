//
//  DataBrowserView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

struct DataBrowserView: View {
    let data: [String: [String: Any]]
    var title: String = "Data Browser"

    @StateObject private var viewModel: DataBrowserSwiftUIViewModel

    init(data: [String: [String: Any]], title: String = "Data Browser") {
        self.data = data
        self.title = title
        _viewModel = StateObject(wrappedValue: DataBrowserSwiftUIViewModel(data: data))
    }

    var body: some View {
        List {
            ForEach(viewModel.sections) { section in
                Section(section.title) {
                    if section.items.isEmpty {
                        Text("No \(section.title)")
                            .fontWeight(.bold)
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(section.items) { item in
                            row(for: item)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
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
            }.sorted { $0.key < $1.key }

            return DataBrowserSection(title: key, items: items)
        }.sorted { $0.title < $1.title }
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
