import SwiftUI
import UIKit
import Foundation

@main
struct VintageLiteUIPreviewApp: App {
    @StateObject private var license = LicenseSession()

    var body: some Scene {
        WindowGroup {
            PreviewTabs()
                .environmentObject(license)
                .environment(\.locale, Locale(identifier: "ru"))
                .preferredColorScheme(.dark)
        }
    }
}

// This app uses a local example key solely to exercise the account display.
final class LicenseSession: ObservableObject {
    @Published private(set) var expiresAt: Date?
    let activeKey = "PREVIEW-DEMO"

    init() {
        let defaults = UserDefaults.standard
        let storageKey = "previewExpiry"
        if let saved = defaults.object(forKey: storageKey) as? Date {
            expiresAt = saved
        } else {
            let initialExpiry = Date().addingTimeInterval(3 * 24 * 60 * 60)
            defaults.set(initialExpiry, forKey: storageKey)
            expiresAt = initialExpiry
        }
    }
}

private enum PreviewTab: Hashable {
    case home, patches, account
}

private struct PreviewTabs: View {
    @State private var selection: PreviewTab = .patches

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                List {
                    Section("Устройство") {
                        LabeledContent("Модель", value: UIDevice.current.model)
                        LabeledContent("iOS", value: UIDevice.current.systemVersion)
                    }
                    Section("Об этой сборке") {
                        LabeledContent("Приложение", value: "VintageLite UI")
                        LabeledContent("Данные", value: "Демонстрационные")
                    }
                }
                .navigationTitle("3105")
            }
            .tabItem { Label("Главная", systemImage: "house.fill") }
            .tag(PreviewTab.home)

            NavigationStack { PreviewCatalog() }
                .tabItem { Label("Патчи", systemImage: "shippingbox.fill") }
                .tag(PreviewTab.patches)

            LicenseAccountView()
                .tabItem { Label("Аккаунт", systemImage: "person.crop.circle.fill") }
                .tag(PreviewTab.account)
        }
    }
}

private enum PreviewCategory: String, CaseIterable, Hashable {
    case boost = "Boost"
    case skin = "Mod Skin"
    case fps = "FPS"
    case holo = "Holo"

    var exampleName: String {
        switch self {
        case .boost: return "Пример профиля"
        case .skin: return "Демооблик"
        case .fps: return "Профиль экрана"
        case .holo: return "Пример эффекта"
        }
    }

    var symbol: String {
        switch self {
        case .boost: return "bolt.fill"
        case .skin: return "tshirt.fill"
        case .fps: return "speedometer"
        case .holo: return "cube"
        }
    }
}

private struct PreviewCatalog: View {
    @State private var category: PreviewCategory = .boost
    @State private var query = ""

    private var showsExample: Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || category.exampleName.localizedCaseInsensitiveContains(text)
    }

    var body: some View {
        List {
            banner
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.black)
                .listRowSeparator(.hidden)

            Picker("Раздел", selection: $category) {
                ForEach(PreviewCategory.allCases, id: \.self) { category in
                    Text(verbatim: category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.black)

            if showsExample {
                NavigationLink {
                    List {
                        LabeledContent("Раздел", value: category.rawValue)
                        LabeledContent("Источник", value: "Данные предпросмотра")
                    }
                    .navigationTitle(category.exampleName)
                } label: {
                    Label(category.exampleName, systemImage: category.symbol)
                }
            } else {
                Text("По этому запросу ничего не найдено")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
        .navigationTitle("VINTAGE LITE")
        .searchable(text: $query, prompt: "Найти в каталоге")
    }

    private var banner: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geometry in
                Image("VintageSky").resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped().accessibilityHidden(true)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 7) {
                Text("VINTAGE LITE").font(.caption.weight(.bold)).tracking(3)
                Text(category.rawValue.uppercased()).font(.largeTitle.weight(.black))
            }
            .foregroundStyle(.white).padding(18)
        }
        .frame(height: 165)
    }
}

struct LicenseAccountView: View {
    @EnvironmentObject private var license: LicenseSession
    @State private var copied = false
    private let mint = Color(red: 0.40, green: 0.91, blue: 0.74)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("VINTAGE LITE").font(.title.bold())
                        Spacer()
                        Image(systemName: "bolt.fill").font(.title)
                    }
                    .foregroundStyle(.black).padding(22)
                    .background(mint, in: RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 18) {
                        if let end = license.expiresAt {
                            TimelineView(.periodic(from: .now, by: 1)) { tick in
                                let seconds = max(0, Int(ceil(end.timeIntervalSince(tick.date))))
                                VStack(alignment: .leading, spacing: 14) {
                                    Label(seconds > 0 ? "Ключ активен" : "Срок истёк",
                                          systemImage: "clock").font(.subheadline.bold())
                                    Text(String(format: "%d д %02d:%02d:%02d", seconds / 86400,
                                                seconds / 3600 % 24, seconds / 60 % 60, seconds % 60))
                                        .font(.system(size: 38, weight: .bold, design: .rounded))
                                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                                }.foregroundStyle(mint)
                            }
                            Divider()
                            Text("Действует до").foregroundStyle(.secondary)
                            Text(end.formatted(date: .long, time: .shortened))
                        } else {
                            Text("Уточняем срок ключа…")
                        }
                        Divider()
                        Text("Ключ на этом устройстве").foregroundStyle(.secondary)
                        Text("•••• " + String(license.activeKey.suffix(4))).monospaced()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Тестовый ключ").font(.headline)
                        Text("Здесь можно проверить копирование ключа предпросмотра.")
                            .foregroundStyle(.secondary)
                        Button(copied ? "Ключ скопирован" : "Скопировать ключ") {
                            UIPasteboard.general.string = license.activeKey
                            copied = true
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                }.frame(maxWidth: 560).padding().frame(maxWidth: .infinity)
            }
            .navigationTitle("Аккаунт")
        }
    }
}
