import SwiftUI
import UIKit

@main
struct VintageLiteApp: App {
    @StateObject private var license = LicenseSession()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Group {
                if license.allowed {
                    MainTabs()
                } else {
                    ActivationView()
                }
            }
            .environmentObject(license)
            .environment(\.locale, Locale(identifier: "ru"))
            .preferredColorScheme(.dark)
            .task { await license.resume() }
            .onChange(of: phase) { _, next in
                if next == .background { license.suspend() }
                if next == .active { Task { await license.resume() } }
            }
        }
    }
}

private struct ActivationView: View {
    @EnvironmentObject private var license: LicenseSession
    @State private var input = ""

    var body: some View {
        NavigationStack {
            Form {
                if license.maintenance || license.needsUpdate {
                    Section {
                        Label(license.needsUpdate ? "Обнови приложение" : "Технические работы",
                              systemImage: "clock")
                        Button("Проверить ещё раз") { Task { await license.resume() } }
                            .disabled(license.busy)
                    }
                } else if license.hasSavedKey {
                    Section {
                        if license.busy {
                            ProgressView("Проверяем ключ…")
                        } else {
                            Button("Проверить сохранённый ключ") { Task { await license.resume() } }
                            Button("Ввести другой ключ") {
                                input = ""
                                license.forgetKey()
                            }
                        }
                    }
                } else {
                    Section("Лицензионный ключ") {
                        SecureField("Введи свой ключ", text: $input)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .onSubmit { activate() }
                        Button("Активировать") { activate() }
                            .disabled(license.busy || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if license.busy { ProgressView("Проверяем…") }
                    }
                }
                if !license.message.isEmpty {
                    Section { Text(license.message).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("VintageLite")
        }
    }

    private func activate() {
        guard !license.busy, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let key = input
        Task { if await license.verify(key) { input = "" } }
    }
}

private struct MainTabs: View {
    var body: some View {
        TabView {
            NavigationStack {
                List {
                    Section("Устройство") {
                        LabeledContent("Модель", value: UIDevice.current.model)
                        LabeledContent("iOS", value: UIDevice.current.systemVersion)
                    }
                    Section("Приложение") {
                        LabeledContent("Версия", value: VintageRelease.version)
                        LabeledContent("Сборка", value: VintageRelease.build)
                    }
                }
                .navigationTitle("VintageLite")
            }
            .tabItem { Label("Главная", systemImage: "house.fill") }
            NavigationStack { CatalogView() }
                .tabItem { Label("Файлы", systemImage: "shippingbox.fill") }
            AccountView()
                .tabItem { Label("Аккаунт", systemImage: "person.crop.circle.fill") }
        }
    }
}

private struct AccountView: View {
    @EnvironmentObject private var license: LicenseSession
    @State private var copied = false
    private let mint = Color(red: 0.40, green: 0.91, blue: 0.74)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("VintageLite").font(.title.bold())
                        Spacer()
                        Image(systemName: "bolt.fill").font(.title)
                    }
                    .foregroundStyle(.black).padding(22)
                    .background(mint, in: RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 14) {
                        if let end = license.expiresAt {
                            TimelineView(.periodic(from: .now, by: 1)) { tick in
                                let seconds = max(0, Int(ceil(end.timeIntervalSince(tick.date))))
                                Label(seconds > 0 ? "Ключ активен" : "Срок истёк", systemImage: "clock")
                                Text(String(format: "%d д %02d:%02d:%02d", seconds / 86400,
                                            seconds / 3600 % 24, seconds / 60 % 60, seconds % 60))
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                            }
                            .foregroundStyle(mint)
                            Divider()
                            Text("Действует до").foregroundStyle(.secondary)
                            Text(end.formatted(date: .long, time: .shortened))
                        }
                        Divider()
                        Text("Ключ на этом устройстве").foregroundStyle(.secondary)
                        Text("•••• " + String(license.activeKey.suffix(4))).monospaced()
                        Button(copied ? "Ключ скопирован" : "Скопировать ключ") {
                            UIPasteboard.general.setItems([["public.utf8-plain-text": license.activeKey]],
                                options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
                            copied = true
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                }
                .frame(maxWidth: 560).padding().frame(maxWidth: .infinity)
            }
            .navigationTitle("Аккаунт")
        }
    }
}
