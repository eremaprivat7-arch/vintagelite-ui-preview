# VintageLite UI Preview

Отдельное SwiftUI-приложение для iPhone с iOS 17 или новее. Вкладки «Главная», «Патчи» и «Аккаунт» открываются с демонстрационными данными. На первом запуске тестовый ключ получает три дня. Срок хранится в настройках предпросмотра, поэтому таймер продолжает отсчёт после перезапуска.

## Запуск сборки с Windows

1. Распакуй архив. Создай пустой репозиторий GitHub `vintagelite-ui-preview` без README. Отправь файлы распакованной папки `VintageLiteUIPreview` через PowerShell командами ниже. В корне репозитория должны находиться `.github`, `Preview` и `VintageLiteUIPreview.xcodeproj`.
2. На GitHub открой **Actions → VintageLite UI Preview → Run workflow**. Выбери ветку `main` и подтверди **Run workflow**.
3. Открой завершённый запуск. В разделе **Artifacts** скачай `VintageLite-UI-Preview-unsigned` и распакуй ZIP.
4. Для установки на зарегистрированный iPhone подпиши `VintageLite-UI-Preview-unsigned.ipa` своим действующим сертификатом и подходящим профилем. Идентификатор приложения — `dev.eraskye.vintagelite.uipreview`. В приложении открой «Аккаунт», чтобы увидеть таймер.

### Отправка из PowerShell

Открой PowerShell **в распакованной папке `VintageLiteUIPreview`**, рядом с папкой `Preview`. Для пустого репозитория `eremaprivat7-arch/vintagelite-ui-preview` подойдут следующие команды.

```powershell
git init -b main
git add -- .github Preview VintageLiteUIPreview.xcodeproj README.md LICENSE
git commit -m "Add SwiftUI interface preview"
git remote add origin https://github.com/eremaprivat7-arch/vintagelite-ui-preview.git
git push -u origin main
```

### Запуск на Mac в симуляторе

Открой `VintageLiteUIPreview.xcodeproj` в Xcode 16 или новее, выбери схему `VintageLiteUIPreview` и симулятор iPhone с iOS 17 или новее, затем нажми **⌘R**.

Экран аккаунта, оформление баннера и изображение VintageSky адаптированы из пользовательского проекта `eremaprivat7-arch/vintage-lite`, коммит `598e30c`. В этой версии модель лицензии и каталог заменены локальными примерами. Лицензия исходного проекта приведена в `LICENSE`.
