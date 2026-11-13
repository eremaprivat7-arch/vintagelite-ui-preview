import SwiftUI

private let allFiles = "Все"

struct CatalogView: View {
    @EnvironmentObject private var license: LicenseSession
    @State private var assets: [PrivateContentAsset] = []
    @State private var category = allFiles
    @State private var query = ""
    @State private var loading = true
    @State private var problem: String?
    @State private var requestID = UUID()
    @State private var loadID = UUID()

    private var categories: [String] {
        [allFiles] + Set(assets.map(\.category)).filter { !$0.isEmpty && $0 != allFiles }.sorted()
    }
    private var visible: [PrivateContentAsset] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return assets.filter { item in
            (category == allFiles || item.category == category)
                && (text.isEmpty || item.title.localizedCaseInsensitiveContains(text))
        }
    }

    var body: some View {
        List {
            ZStack(alignment: .bottomLeading) {
                GeometryReader { proxy in
                    Image("VintageSky").resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                        .accessibilityHidden(true)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
                Text(category == allFiles ? "Все файлы" : category)
                    .font(.largeTitle.bold()).padding(18)
            }
            .frame(height: 155)
            .listRowInsets(EdgeInsets())

            if assets.count > 0 {
                Picker("Раздел", selection: $category) {
                    ForEach(categories, id: \.self) { Text(verbatim: $0).tag($0) }
                }
                .pickerStyle(.menu)
            }
            if loading {
                ProgressView("Загружаем каталог…")
            } else if let problem {
                Text(problem).foregroundStyle(.secondary)
                Button("Повторить") { requestID = UUID() }
            } else if visible.isEmpty {
                Text(assets.isEmpty ? "В каталоге пока нет опубликованных файлов." : "Файлы не найдены.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visible) { asset in
                    NavigationLink {
                        FileDetails(asset: asset)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(asset.title)
                            Text(asset.category).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Файлы")
        .searchable(text: $query, prompt: "Поиск по названию")
        .task(id: requestID) { await reload() }
        .refreshable { await reload() }
    }

    @MainActor private func reload() async {
        let id = UUID()
        loadID = id
        loading = true
        problem = nil
        defer { if loadID == id { loading = false } }
        do {
            let credentials = try license.contentCredentials()
            let result = try await PrivateContentClient.shared.catalog(credentials)
            try Task.checkCancellation()
            guard license.allowed, loadID == id else { return }
            assets = result
            if !categories.contains(category) { category = allFiles }
        } catch {
            guard !Task.isCancelled, loadID == id else { return }
            assets = []
            problem = (error as? PrivateContentError)?.localizedDescription ?? "Не удалось загрузить каталог."
        }
    }
}

private struct FileDetails: View {
    let asset: PrivateContentAsset
    @EnvironmentObject private var license: LicenseSession
    @State private var files: [CatalogFile]?
    @State private var errorText: String?
    @State private var reloadToken = UUID()

    var body: some View {
        List {
            Section {
                LabeledContent("Раздел", value: asset.category)
                LabeledContent("Размер пакета", value: ByteCountFormatter.string(fromByteCount: Int64(asset.size),
                                                                                  countStyle: .file))
            }
            Section("Содержимое") {
                if let errorText {
                    Text(errorText).foregroundStyle(.secondary)
                    Button("Повторить") { reloadToken = UUID() }
                } else if let files {
                    if files.isEmpty { Text("В пакете нет файлов.") }
                    ForEach(files) { file in
                        LabeledContent(file.name, value: ByteCountFormatter.string(fromByteCount: Int64(file.size),
                                                                                    countStyle: .file))
                    }
                } else {
                    ProgressView("Читаем пакет…")
                }
            }
        }
        .navigationTitle(asset.title)
        .task(id: reloadToken) {
            errorText = nil
            files = nil
            do {
                let credentials = try license.contentCredentials()
                let result = try await PrivateContentClient.shared.files(in: asset, credentials: credentials)
                try Task.checkCancellation()
                if license.allowed { files = result }
            } catch {
                if !Task.isCancelled {
                    errorText = (error as? PrivateContentError)?.localizedDescription ?? "Не удалось прочитать пакет."
                }
            }
        }
    }
}
