# Localisation & App Language Override — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Localise every user-facing string in Scyther into twelve languages through a String Catalog resolved by one helper, and add a Language page that forces the host app's language via `AppleLanguages`.

**Architecture:** Per-module JSON fragments under `Scripts/localization/strings/` are the source of truth for keys and translations; `Scripts/localization/build_catalog.py` merges them into `Sources/Scyther/Resources/Localizable.xcstrings`, which SwiftPM compiles into `<lang>.lproj` tables inside `Bundle.module`. A free function `localized(_:)` resolves a `String.LocalizationValue` against `LanguageOverride.effectiveBundle`, which is the forced language's `.lproj` sub-bundle when an override is set and the module bundle otherwise. Views pass the resulting `String` to SwiftUI verbatim. A lint test fails the build on any SwiftUI literal not routed through the helper, and a catalog test fails on any key missing a language or with mismatched placeholders.

**Tech Stack:** Swift 6 (language mode v6, strict concurrency), SwiftUI, XCTest, iOS 16+, Swift Package Manager, Python 3 (catalog generator, standard library only).

**Spec:** `docs/superpowers/specs/2026-09-04-localisation-design.md`

## Global Constraints

- **iOS only.** Never build for macOS. `swift build` does not work; this target requires UIKit.
- **Build/test on the booted simulator.** Resolve it once per task with
  `S=$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next(x["udid"] for v in d.values() for x in v if x["state"]=="Booted"))')`
  and use `-destination "platform=iOS Simulator,id=$S"`. If nothing is booted, run
  `xcrun simctl boot 0EEED0FF-A025-468E-9466-3BDE708B41B0` (iPhone 17 Pro) first.
- **Full test command:** `xcodebuild test -scheme Scyther -destination "platform=iOS Simulator,id=$S" -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|failed \(|Executed [0-9]+ tests|TEST " | sort -u | tail -8`
- **Example app build:** `xcodebuild build -project Example/ScytherExample.xcodeproj -scheme ScytherExample -destination "platform=iOS Simulator,id=$S" -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD " | tail -2`
- **Swift 6 strict concurrency.** Any static mutable state must be `nonisolated(unsafe)` behind a lock or `@MainActor`. `UserDefaults` statics must be `nonisolated(unsafe)`.
- **Minimum deployment target iOS 16.** No iOS 17-only API without `#available`.
- **MVVM + separate view model files. DocC `///` on every new type and member. README updated. Alerts only, never `.confirmationDialog`. Always use `ShareLink` where a tap triggers a share.**
- **Never put a Claude session URL or any Claude mention in a commit message, PR body, or release note.**
- **Exact names:** helper `localized(_:comment:)`; catalog `Sources/Scyther/Resources/Localizable.xcstrings`; fragments `Scripts/localization/strings/<Module>.json`; generator `Scripts/localization/build_catalog.py`; bookkeeping key `Scyther.Localization.PreferredLanguage`; system key `AppleLanguages`; facade `Scyther.localization`; menu item `MenuItem.language` with id `language`; lint marker `// scyther:unlocalised`.
- **Languages (exactly these codes):** `fr`, `de`, `es`, `it`, `pt-BR`, `nl`, `ja`, `zh-Hans`, `zh-Hant`, `ko`, `ru`, `ar`. Source language `en`.
- **Strings that must NOT be localised:** `UserDefaults` keys, file and folder names, HAR fields, cURL text, `logMessage` output, URL schemes, SF Symbol names, `Scyther` (the brand), technical tokens (`HAR`, `cURL`, `JSON`, `XML`, `HTML`, `GraphQL`, `REST`, `UUID`, `IDFV`, `APNS`, `FCM`, `IP`, `FPS`, `UserDefaults`, `Keychain`, `CoreData`, `SwiftData`, `SQLite`, HTTP method names, status code digits), and test fixtures.

---

## Translation Rules (apply in every module task)

1. Translate meaning, not words. Keep the register formal and concise; these are labels in a developer tool.
2. Keep every placeholder exactly as in English (`%lld`, `%@`, `%1$@`), in the position the target grammar needs.
3. Keep technical tokens listed in Global Constraints untranslated.
4. Chips and toolbar labels must stay short: prefer the shortest natural form.
5. Japanese: no spaces between Japanese and Latin tokens except before/after placeholders where the English had one. Chinese: use full-width punctuation `，。：` . Arabic: sentence text in Arabic, keep Latin technical tokens as is; the layout direction is handled by the app.
6. Russian and Arabic plurals must use the full CLDR category set listed below.
7. Use the glossary below for recurring terms so modules agree with each other.

### CLDR plural categories per language

| Language | Categories |
| --- | --- |
| en, de, es, it, pt-BR, nl | `one`, `other` |
| fr | `one`, `other` |
| ru | `one`, `few`, `many`, `other` |
| ar | `zero`, `one`, `two`, `few`, `many`, `other` |
| ja, zh-Hans, zh-Hant, ko | `other` |

### Glossary

| en | fr | de | es | it | pt-BR | nl | ja | zh-Hans | zh-Hant | ko | ru | ar |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Done | Terminé | Fertig | Listo | Fine | Concluído | Gereed | 完了 | 完成 | 完成 | 완료 | Готово | تم |
| Cancel | Annuler | Abbrechen | Cancelar | Annulla | Cancelar | Annuleren | キャンセル | 取消 | 取消 | 취소 | Отмена | إلغاء |
| Reset | Réinitialiser | Zurücksetzen | Restablecer | Ripristina | Redefinir | Herstellen | リセット | 重置 | 重設 | 재설정 | Сбросить | إعادة تعيين |
| Clear | Effacer | Leeren | Borrar | Cancella | Limpar | Wissen | 消去 | 清除 | 清除 | 지우기 | Очистить | مسح |
| Delete | Supprimer | Löschen | Eliminar | Elimina | Excluir | Verwijderen | 削除 | 删除 | 刪除 | 삭제 | Удалить | حذف |
| Export | Exporter | Exportieren | Exportar | Esporta | Exportar | Exporteren | 書き出す | 导出 | 匯出 | 내보내기 | Экспортировать | تصدير |
| Share | Partager | Teilen | Compartir | Condividi | Compartilhar | Delen | 共有 | 共享 | 分享 | 공유 | Поделиться | مشاركة |
| Search | Rechercher | Suchen | Buscar | Cerca | Buscar | Zoeken | 検索 | 搜索 | 搜尋 | 검색 | Поиск | بحث |
| Copy | Copier | Kopieren | Copiar | Copia | Copiar | Kopiëren | コピー | 拷贝 | 拷貝 | 복사 | Скопировать | نسخ |
| Close | Fermer | Schließen | Cerrar | Chiudi | Fechar | Sluiten | 閉じる | 关闭 | 關閉 | 닫기 | Закрыть | إغلاق |
| Save | Enregistrer | Sichern | Guardar | Salva | Salvar | Bewaar | 保存 | 存储 | 儲存 | 저장 | Сохранить | حفظ |
| Any | Tous | Alle | Cualquiera | Qualsiasi | Qualquer | Alle | すべて | 任意 | 任意 | 모두 | Любой | أي |
| System Default | Par défaut du système | Systemstandard | Predeterminado del sistema | Predefinito di sistema | Padrão do sistema | Systeemstandaard | システムのデフォルト | 系统默认 | 系統預設 | 시스템 기본값 | Системный по умолчанию | الإعداد الافتراضي للنظام |
| Network Logs | Journaux réseau | Netzwerkprotokolle | Registros de red | Log di rete | Registros de rede | Netwerklogboeken | ネットワークログ | 网络日志 | 網路記錄 | 네트워크 로그 | Сетевые журналы | سجلات الشبكة |
| Request | Requête | Anfrage | Solicitud | Richiesta | Solicitação | Verzoek | リクエスト | 请求 | 請求 | 요청 | Запрос | طلب |
| Response | Réponse | Antwort | Respuesta | Risposta | Resposta | Antwoord | レスポンス | 响应 | 回應 | 응답 | Ответ | استجابة |
| Headers | En-têtes | Header | Encabezados | Intestazioni | Cabeçalhos | Headers | ヘッダー | 标头 | 標頭 | 헤더 | Заголовки | الترويسات |
| Body | Corps | Body | Cuerpo | Corpo | Corpo | Body | ボディ | 正文 | 內容 | 본문 | Тело | المحتوى |
| Language | Langue | Sprache | Idioma | Lingua | Idioma | Taal | 言語 | 语言 | 語言 | 언어 | Язык | اللغة |
| Settings | Réglages | Einstellungen | Ajustes | Impostazioni | Ajustes | Instellingen | 設定 | 设置 | 設定 | 설정 | Настройки | الإعدادات |
| Enabled | Activé | Aktiviert | Activado | Attivato | Ativado | Ingeschakeld | 有効 | 已启用 | 已啟用 | 활성화됨 | Включено | مفعّل |

---

## Fragment Format (source of truth for keys and translations)

One JSON file per module at `Scripts/localization/strings/<Module>.json`. Top-level keys are the **English source strings exactly as they appear in the `localized("…")` call after interpolation placeholders are substituted** (`\(count)` for an `Int` becomes `%lld`, `\(name)` for a `String` becomes `%@`).

Simple string:

```json
{
  "Network logs": {
    "comment": "Navigation title of the request list",
    "fr": "Journaux réseau",
    "de": "Netzwerkprotokolle",
    "es": "Registros de red",
    "it": "Log di rete",
    "pt-BR": "Registros de rede",
    "nl": "Netwerklogboeken",
    "ja": "ネットワークログ",
    "zh-Hans": "网络日志",
    "zh-Hant": "網路記錄",
    "ko": "네트워크 로그",
    "ru": "Сетевые журналы",
    "ar": "سجلات الشبكة"
  }
}
```

Plural string (the `en` entry is required whenever `plural` is true; every language supplies the categories from the CLDR table):

```json
{
  "%lld requests": {
    "comment": "Count of requests in the export sheet",
    "plural": true,
    "en":      { "one": "%lld request", "other": "%lld requests" },
    "fr":      { "one": "%lld requête", "other": "%lld requêtes" },
    "de":      { "one": "%lld Anfrage", "other": "%lld Anfragen" },
    "es":      { "one": "%lld solicitud", "other": "%lld solicitudes" },
    "it":      { "one": "%lld richiesta", "other": "%lld richieste" },
    "pt-BR":   { "one": "%lld solicitação", "other": "%lld solicitações" },
    "nl":      { "one": "%lld verzoek", "other": "%lld verzoeken" },
    "ja":      { "other": "%lld件のリクエスト" },
    "zh-Hans": { "other": "%lld 个请求" },
    "zh-Hant": { "other": "%lld 個請求" },
    "ko":      { "other": "요청 %lld개" },
    "ru":      { "one": "%lld запрос", "few": "%lld запроса", "many": "%lld запросов", "other": "%lld запроса" },
    "ar":      { "zero": "لا توجد طلبات", "one": "طلب واحد", "two": "طلبان", "few": "%lld طلبات", "many": "%lld طلبًا", "other": "%lld طلب" }
  }
}
```

The generator rejects: a key present in two fragments, a missing language, an empty value, a `plural` entry missing a required category, or a placeholder set that differs from English.

---

## Module Conversion Procedure (referenced by Tasks 3 to 10)

Each module task follows these steps exactly for the directories it names.

1. **List the literals.** From the repo root:
   ```bash
   grep -nE '(\b(Text|Button|Label|Section|LabeledContent|Toggle|TextField|SecureField|NavigationLink|ShareLink|SharePreview|Picker|Menu|Link|Stepper)\(|\.(navigationTitle|alert|accessibilityLabel|accessibilityHint|help)\(|\bprompt:|\btitle:|\bmessage:)\s*"' -r Sources/Scyther/<Dir> | grep -v 'scyther:unlocalised'
   ```
   Also open every file in the directory and look for: enum `displayName`/`title`/`label` computed properties returning English, string arrays of labels, `String(format:)` with English, and UIKit `.text =` / `.title =` / `setTitle(`. The count in each task is the number the grep returned on 2026-09-04; expect a few more from the manual pass.
2. **Write the fragment** `Scripts/localization/strings/<Module>.json` with every key and all twelve languages, following the Translation Rules and Glossary. Interpolations: `Int` → `%lld`, `String` → `%@`. If a literal interpolates anything else (`Double`, `Float`, `CGFloat`, `Date`), format it into a `String` first in the view and interpolate that. Counted strings get `"plural": true`.
3. **Regenerate the catalog:** `python3 Scripts/localization/build_catalog.py` (exits non-zero with a message on any violation).
4. **Convert the call sites.** Each literal becomes `localized("…")`. Patterns:
   - `Text("Network logs")` → `Text(localized("Network logs"))`
   - `Text("Preparing archive of \(count) requests…")` → `Text(localized("Preparing archive of \(count) requests…"))` (key in the fragment: `Preparing archive of %lld requests…`)
   - `Button("Delete", systemImage: "trash", role: .destructive) { … }` → `Button(localized("Delete"), systemImage: "trash", role: .destructive) { … }`
   - `Section("Overview") { … }` → `Section(localized("Overview")) { … }`
   - `LabeledContent("Method", value: viewModel.method)` → `LabeledContent(localized("Method"), value: viewModel.method)`
   - `.navigationTitle("Request Details")` → `.navigationTitle(localized("Request Details"))`
   - `.alert("Export Sensitive Data?", isPresented: …)` → `.alert(localized("Export Sensitive Data?"), isPresented: …)`
   - `.searchable(text: $text, prompt: "Search…")` → `.searchable(text: $text, prompt: localized("Search…"))`
   - `Label("Share Archive", systemImage: "square.and.arrow.up")` → `Label(localized("Share Archive"), systemImage: "square.and.arrow.up")`
   - `.accessibilityLabel("Close")` → `.accessibilityLabel(localized("Close"))`
   - enum: `case .success: return "2xx Success"` → `case .success: return localized("2xx Success")`
   - UIKit: `label.text = "…"` → `label.text = localized("…")`
   - A literal that is genuinely not UI copy (a `UserDefaults` key, a file name) is left alone; if the lint regex still matches it, append `// scyther:unlocalised <reason>` to that line.
5. **Register the directory with the lint test:** add `"Features/<Dir>"` to `UnlocalisedLiteralLintTests.convertedDirectories` in `Tests/ScytherTests/Core/UnlocalisedLiteralLintTests.swift`.
6. **Build and run the full suite** (Global Constraints command). All tests, including `LocalizableCatalogTests` and the lint test, must pass.
7. **Build the example app**, install, launch, and open the converted screen to eyeball it:
   `xcrun simctl install $S <DerivedData>/Build/Products/Debug-iphonesimulator/ScytherExample.app && xcrun simctl launch $S com.scyther.example`.
8. **Commit** the fragment, the regenerated catalog, the converted sources, and the lint list:
   `git add Scripts/localization/strings/<Module>.json Sources/Scyther/Resources/Localizable.xcstrings Sources/Scyther/<Dir> Tests/ScytherTests/Core/UnlocalisedLiteralLintTests.swift && git commit -m "Localise <Module>"`.

---

## File Structure

**Created:**

| Path | Responsibility |
| --- | --- |
| `Scripts/localization/build_catalog.py` | Merge fragments into the `.xcstrings`, validate completeness and placeholders |
| `Scripts/localization/strings/*.json` | Per-module keys and translations (source of truth) |
| `Sources/Scyther/Resources/Localizable.xcstrings` | Generated String Catalog compiled by SwiftPM |
| `Sources/Scyther/Core/ScytherLocalization.swift` | `localized(_:comment:)` helper and `ScytherLocalization.moduleBundle` |
| `Sources/Scyther/Features/Localization/LanguageOverride.swift` | `AppleLanguages` override, available languages, effective bundle, display names |
| `Sources/Scyther/Features/Localization/LanguageViewModel.swift` | Rows, selection, relaunch alert, reset, quit |
| `Sources/Scyther/Features/Localization/LanguageView.swift` | The Language page |
| `Sources/Scyther/Scyther.docc/Localisation.md` | Contributor guide |
| `Example/ScytherExample/Resources/Localizable.xcstrings` | Two example-app strings in all languages so `Bundle.main.localizations` is populated |
| `Tests/ScytherTests/Core/ScytherLocalizationTests.swift` | Helper resolution |
| `Tests/ScytherTests/Core/LocalizableCatalogTests.swift` | Catalog completeness and placeholder parity |
| `Tests/ScytherTests/Core/UnlocalisedLiteralLintTests.swift` | Source lint over converted directories |
| `Tests/ScytherTests/Features/LanguageOverrideTests.swift` | Override read/write/reset, bundles |
| `Tests/ScytherTests/Features/LanguageViewModelTests.swift` | Page behaviour |

**Modified:**

| Path | Change |
| --- | --- |
| `Package.swift` | `defaultLocalization: "en"` |
| `Sources/Scyther/Core/Scyther.swift` | `public static let localization = LanguageOverride.shared` |
| `Sources/Scyther/Features/Menu/MenuSection.swift`, `MenuSectionTint.swift` | Stable `id` per section; tint keyed on id, not title |
| `Sources/Scyther/Features/Menu/MenuItem.swift`, `MenuView.swift`, `MenuSearchIndex.swift` | Localised titles; `.language` row; locale/layout environment |
| Every view, view model, and enum under `Sources/Scyther/Features` and `Sources/Scyther/Shared` | Literals routed through `localized` |
| `Example/ScytherExample.xcodeproj/project.pbxproj` | Register the example catalog; `knownRegions` |
| `README.md`, `CLAUDE.md` | Localisation section, rule line |

---

### Task 1: Package configuration, generator, helper, and override core

**Files:**
- Modify: `Package.swift`
- Create: `Scripts/localization/build_catalog.py`
- Create: `Scripts/localization/strings/Core.json`
- Create: `Sources/Scyther/Resources/Localizable.xcstrings` (generated)
- Create: `Sources/Scyther/Core/ScytherLocalization.swift`
- Create: `Sources/Scyther/Features/Localization/LanguageOverride.swift`
- Test: `Tests/ScytherTests/Core/ScytherLocalizationTests.swift`
- Test: `Tests/ScytherTests/Features/LanguageOverrideTests.swift`

**Interfaces:**
- Produces: `func localized(_ key: String.LocalizationValue, comment: StaticString? = nil) -> String`
- Produces: `enum ScytherLocalization { static let moduleBundle: Bundle; static let supportedLanguages: [String] }`
- Produces: `public final class LanguageOverride: ObservableObject, @unchecked Sendable` with `static let shared`, `init(systemDefaults:scytherDefaults:hostBundle:moduleBundle:)`, `preferredLanguage: String?`, `availableLanguages: [String]`, `effectiveLocale: Locale?`, `effectiveBundle: Bundle`, `setPreferredLanguage(_:)`, `reset()`, `displayName(for:in:)`, `nativeDisplayName(for:)`, `currentLanguageDisplayName`, `currentRegionDisplayName`, `static func languageBundle(for:in:) -> Bundle?`
- Produces: `python3 Scripts/localization/build_catalog.py` regenerating the catalog from all fragments

- [ ] **Step 1: Write the failing helper tests**

`Tests/ScytherTests/Core/ScytherLocalizationTests.swift`:

```swift
//
//  ScytherLocalizationTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class ScytherLocalizationTests: XCTestCase {

    func testModuleBundleContainsCompiledCatalog() throws {
        let bundle = ScytherLocalization.moduleBundle
        for language in ScytherLocalization.supportedLanguages {
            XCTAssertNotNil(bundle.path(forResource: language, ofType: "lproj"), "missing \(language).lproj")
        }
    }

    func testLanguageBundleResolvesKnownKey() throws {
        let french = try XCTUnwrap(LanguageOverride.languageBundle(for: "fr", in: ScytherLocalization.moduleBundle))
        XCTAssertEqual(String(localized: "Language", bundle: french), "Langue")
        let japanese = try XCTUnwrap(LanguageOverride.languageBundle(for: "ja", in: ScytherLocalization.moduleBundle))
        XCTAssertEqual(String(localized: "Language", bundle: japanese), "言語")
    }

    func testLanguageBundleIsNilForUnknownLanguage() {
        XCTAssertNil(LanguageOverride.languageBundle(for: "xx", in: ScytherLocalization.moduleBundle))
    }

    func testLocalizedFallsBackToEnglishSourceForUnknownKey() {
        XCTAssertEqual(localized("This key does not exist in the catalog"), "This key does not exist in the catalog")
    }

    func testLocalizedInterpolatesArguments() throws {
        let french = try XCTUnwrap(LanguageOverride.languageBundle(for: "fr", in: ScytherLocalization.moduleBundle))
        let count = 3
        XCTAssertEqual(String(localized: "\(count) selected", bundle: french), "3 sélectionnés")
    }
}
```

`Tests/ScytherTests/Features/LanguageOverrideTests.swift`:

```swift
//
//  LanguageOverrideTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class LanguageOverrideTests: XCTestCase {

    private var system: UserDefaults!
    private var scyther: UserDefaults!
    private var systemSuite: String!
    private var scytherSuite: String!

    override func setUpWithError() throws {
        systemSuite = "LanguageOverrideTests.system.\(UUID().uuidString)"
        scytherSuite = "LanguageOverrideTests.scyther.\(UUID().uuidString)"
        system = try XCTUnwrap(UserDefaults(suiteName: systemSuite))
        scyther = try XCTUnwrap(UserDefaults(suiteName: scytherSuite))
    }

    override func tearDownWithError() throws {
        system.removePersistentDomain(forName: systemSuite)
        scyther.removePersistentDomain(forName: scytherSuite)
    }

    private func makeOverride(hostBundle: Bundle = .main) -> LanguageOverride {
        LanguageOverride(
            systemDefaults: system,
            scytherDefaults: scyther,
            hostBundle: hostBundle,
            moduleBundle: ScytherLocalization.moduleBundle
        )
    }

    func testNoOverrideByDefault() {
        let override = makeOverride()
        XCTAssertNil(override.preferredLanguage)
        XCTAssertNil(override.effectiveLocale)
        XCTAssertTrue(override.effectiveBundle === ScytherLocalization.moduleBundle)
    }

    func testSettingLanguageWritesAppleLanguagesAndBookkeeping() {
        let override = makeOverride()
        override.setPreferredLanguage("fr")
        XCTAssertEqual(system.stringArray(forKey: LanguageOverride.appleLanguagesKey), ["fr"])
        XCTAssertEqual(scyther.string(forKey: LanguageOverride.bookkeepingKey), "fr")
        XCTAssertEqual(override.preferredLanguage, "fr")
        XCTAssertEqual(override.effectiveLocale?.identifier, "fr")
        XCTAssertEqual(override.effectiveBundle.bundlePath.hasSuffix("fr.lproj"), true)
    }

    func testResetRemovesBothKeys() {
        let override = makeOverride()
        override.setPreferredLanguage("de")
        override.reset()
        XCTAssertNil(system.object(forKey: LanguageOverride.appleLanguagesKey))
        XCTAssertNil(scyther.object(forKey: LanguageOverride.bookkeepingKey))
        XCTAssertNil(override.preferredLanguage)
        XCTAssertTrue(override.effectiveBundle === ScytherLocalization.moduleBundle)
    }

    func testSettingNilBehavesLikeReset() {
        let override = makeOverride()
        override.setPreferredLanguage("de")
        override.setPreferredLanguage(nil)
        XCTAssertNil(system.object(forKey: LanguageOverride.appleLanguagesKey))
        XCTAssertNil(override.preferredLanguage)
    }

    func testPreferredLanguageIsRestoredFromBookkeepingOnInit() {
        scyther.set("ja", forKey: LanguageOverride.bookkeepingKey)
        let override = makeOverride()
        XCTAssertEqual(override.preferredLanguage, "ja")
    }

    func testLanguageNotInCatalogFallsBackToModuleBundle() {
        let override = makeOverride()
        override.setPreferredLanguage("xx")
        XCTAssertTrue(override.effectiveBundle === ScytherLocalization.moduleBundle)
    }

    func testAvailableLanguagesExcludeBaseAndSortByDisplayName() {
        let override = makeOverride(hostBundle: ScytherLocalization.moduleBundle)
        let languages = override.availableLanguages
        XCTAssertFalse(languages.contains("Base"))
        XCTAssertTrue(languages.contains("fr"))
        let names = languages.map { override.displayName(for: $0, in: Locale(identifier: "en")) }
        XCTAssertEqual(names, names.sorted())
    }

    func testDisplayNames() {
        let override = makeOverride()
        XCTAssertEqual(override.displayName(for: "fr", in: Locale(identifier: "en")), "French")
        XCTAssertEqual(override.nativeDisplayName(for: "fr"), "français")
        XCTAssertEqual(override.displayName(for: "zh-Hans", in: Locale(identifier: "en")), "Chinese (Simplified)")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the full test command from Global Constraints.
Expected: compile errors `cannot find 'ScytherLocalization' in scope`, `cannot find 'LanguageOverride' in scope`, `cannot find 'localized' in scope`.

- [ ] **Step 3: Configure the package**

In `Package.swift`, add `defaultLocalization: "en",` as the line immediately after `name: "Scyther",` inside the `Package(` initialiser.

- [ ] **Step 4: Write the generator**

`Scripts/localization/build_catalog.py`:

```python
#!/usr/bin/env python3
"""Merge Scripts/localization/strings/*.json into Sources/Scyther/Resources/Localizable.xcstrings.

Fragments are the source of truth. Run after editing any fragment:
    python3 Scripts/localization/build_catalog.py
Exit status is non-zero on any validation failure; the catalog is not written in that case.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FRAGMENTS = ROOT / "Scripts" / "localization" / "strings"
CATALOG = ROOT / "Sources" / "Scyther" / "Resources" / "Localizable.xcstrings"

SOURCE = "en"
LANGUAGES = ["fr", "de", "es", "it", "pt-BR", "nl", "ja", "zh-Hans", "zh-Hant", "ko", "ru", "ar"]
PLURAL_CATEGORIES = {
    "en": ["one", "other"], "fr": ["one", "other"], "de": ["one", "other"], "es": ["one", "other"],
    "it": ["one", "other"], "pt-BR": ["one", "other"], "nl": ["one", "other"],
    "ja": ["other"], "zh-Hans": ["other"], "zh-Hant": ["other"], "ko": ["other"],
    "ru": ["one", "few", "many", "other"],
    "ar": ["zero", "one", "two", "few", "many", "other"],
}
PLACEHOLDER = re.compile(r"%(\d+\$)?[@dlfsu]|%lld|%\.\d+f")


def placeholders(text):
    return sorted(m.group(0) for m in PLACEHOLDER.finditer(text))


def fail(message):
    print(f"build_catalog: {message}", file=sys.stderr)
    sys.exit(1)


def unit(value, state="needs_review"):
    return {"stringUnit": {"state": state, "value": value}}


def main():
    strings = {}
    owner = {}
    for fragment in sorted(FRAGMENTS.glob("*.json")):
        try:
            data = json.loads(fragment.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            fail(f"{fragment.name}: invalid JSON: {error}")
        for key, entry in data.items():
            if key in owner:
                fail(f"duplicate key {key!r} in {fragment.name} and {owner[key]}")
            owner[key] = fragment.name
            if not isinstance(entry, dict):
                fail(f"{fragment.name}: {key!r} must be an object")
            plural = bool(entry.get("plural", False))
            localizations = {}
            if plural:
                if "en" not in entry:
                    fail(f"{fragment.name}: plural key {key!r} needs an 'en' entry")
                source_forms = entry["en"]
                base_placeholders = placeholders(source_forms.get("other", ""))
                for language in [SOURCE] + LANGUAGES:
                    forms = entry.get(language)
                    if not isinstance(forms, dict):
                        fail(f"{fragment.name}: {key!r} missing plural forms for {language}")
                    missing = [c for c in PLURAL_CATEGORIES[language] if c not in forms or not forms[c]]
                    if missing:
                        fail(f"{fragment.name}: {key!r} {language} missing plural categories {missing}")
                    variations = {}
                    for category, text in forms.items():
                        if category == "other" and placeholders(text) != base_placeholders:
                            fail(f"{fragment.name}: {key!r} {language}.{category} placeholders {placeholders(text)} != {base_placeholders}")
                        variations[category] = unit(text, "translated" if language == SOURCE else "needs_review")
                    localizations[language] = {"variations": {"plural": variations}}
            else:
                base_placeholders = placeholders(key)
                for language in LANGUAGES:
                    text = entry.get(language)
                    if not isinstance(text, str) or not text.strip():
                        fail(f"{fragment.name}: {key!r} missing translation for {language}")
                    if placeholders(text) != base_placeholders:
                        fail(f"{fragment.name}: {key!r} {language} placeholders {placeholders(text)} != {base_placeholders}")
                    localizations[language] = unit(text)
            record = {"localizations": localizations}
            if entry.get("comment"):
                record["comment"] = entry["comment"]
            strings[key] = record

    catalog = {"sourceLanguage": SOURCE, "strings": dict(sorted(strings.items())), "version": "1.0"}
    CATALOG.parent.mkdir(parents=True, exist_ok=True)
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"build_catalog: wrote {len(strings)} keys × {len(LANGUAGES)} languages to {CATALOG.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
```

Make it executable: `chmod +x Scripts/localization/build_catalog.py`.

- [ ] **Step 5: Write the first fragment and generate the catalog**

`Scripts/localization/strings/Core.json`:

```json
{
  "Language": {
    "comment": "Menu row and page title for the app language override",
    "fr": "Langue", "de": "Sprache", "es": "Idioma", "it": "Lingua", "pt-BR": "Idioma", "nl": "Taal",
    "ja": "言語", "zh-Hans": "语言", "zh-Hant": "語言", "ko": "언어", "ru": "Язык", "ar": "اللغة"
  },
  "%lld selected": {
    "comment": "Accessibility suffix for a filter chip with a selection count",
    "plural": true,
    "en":      { "one": "%lld selected", "other": "%lld selected" },
    "fr":      { "one": "%lld sélectionné", "other": "%lld sélectionnés" },
    "de":      { "one": "%lld ausgewählt", "other": "%lld ausgewählt" },
    "es":      { "one": "%lld seleccionado", "other": "%lld seleccionados" },
    "it":      { "one": "%lld selezionato", "other": "%lld selezionati" },
    "pt-BR":   { "one": "%lld selecionado", "other": "%lld selecionados" },
    "nl":      { "one": "%lld geselecteerd", "other": "%lld geselecteerd" },
    "ja":      { "other": "%lld件選択済み" },
    "zh-Hans": { "other": "已选择 %lld 项" },
    "zh-Hant": { "other": "已選取 %lld 項" },
    "ko":      { "other": "%lld개 선택됨" },
    "ru":      { "one": "Выбран %lld", "few": "Выбрано %lld", "many": "Выбрано %lld", "other": "Выбрано %lld" },
    "ar":      { "zero": "لم يتم تحديد شيء", "one": "تم تحديد عنصر واحد", "two": "تم تحديد عنصرين", "few": "تم تحديد %lld عناصر", "many": "تم تحديد %lld عنصرًا", "other": "تم تحديد %lld عنصر" }
  }
}
```

Run `python3 Scripts/localization/build_catalog.py`. Expected output: `build_catalog: wrote 2 keys × 12 languages to Sources/Scyther/Resources/Localizable.xcstrings`.

- [ ] **Step 6: Write the helper**

`Sources/Scyther/Core/ScytherLocalization.swift`:

```swift
//
//  ScytherLocalization.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/9/2026.
//

import Foundation

/// Resolves a piece of Scyther's own UI copy from the package's String Catalog.
///
/// Every user-facing string in Scyther goes through this function so that SwiftUI and UIKit
/// call sites behave identically and follow the ``LanguageOverride``: when a language has been
/// forced from the Language page, strings are read from that language's `.lproj` table inside
/// the module bundle, so Scyther's menu switches language without a relaunch.
///
/// The parameter is a `String.LocalizationValue`, so a literal at the call site is recognised by
/// Xcode's catalog extraction and interpolations become format placeholders (`Int` → `%lld`,
/// `String` → `%@`). Add every new key, with all supported languages, to the fragment for its
/// module under `Scripts/localization/strings/` and run `Scripts/localization/build_catalog.py`.
///
/// ## Usage
///
/// ```swift
/// Text(localized("Network logs"))
/// LabeledContent(localized("Requests"), value: "\(count)")
/// Text(localized("Preparing archive of \(count) requests…"))
/// ```
///
/// - Parameters:
///   - key: The English source text, which is also the catalog key.
///   - comment: Context for translators. Not used at runtime.
/// - Returns: The string in the effective language, or the English source if the key is missing.
func localized(_ key: String.LocalizationValue, comment: StaticString? = nil) -> String {
    String(localized: key, bundle: LanguageOverride.shared.effectiveBundle, comment: comment)
}

/// Package-level localisation constants.
enum ScytherLocalization {
    /// The bundle holding Scyther's compiled String Catalog.
    nonisolated(unsafe) static let moduleBundle: Bundle = .module

    /// The languages shipped in the catalog, in addition to the English source.
    static let supportedLanguages: [String] = [
        "fr", "de", "es", "it", "pt-BR", "nl", "ja", "zh-Hans", "zh-Hant", "ko", "ru", "ar",
    ]
}
```

- [ ] **Step 7: Write the override core**

`Sources/Scyther/Features/Localization/LanguageOverride.swift`:

```swift
//
//  LanguageOverride.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/9/2026.
//

import Combine
import Foundation

/// Forces the host app's language and resolves Scyther's own strings in that language.
///
/// iOS reads the `AppleLanguages` array from standard `UserDefaults` at launch, so writing it
/// changes the whole app's language on the **next** launch without any cooperation from the host.
/// Scyther's own menu switches immediately, because ``localized(_:comment:)`` reads from
/// ``effectiveBundle``: the forced language's `.lproj` inside the module bundle.
///
/// The choice is also recorded in `UserDefaults.scyther` under ``bookkeepingKey`` so the Language
/// page can show that an override is active even if the host rewrites `AppleLanguages`.
///
/// ## Usage
///
/// ```swift
/// Scyther.localization.setPreferredLanguage("fr")   // takes effect app-wide on next launch
/// Scyther.localization.reset()                       // back to the device language
/// ```
///
/// ## Topics
///
/// ### Shared Instance
/// - ``shared``
///
/// ### Override
/// - ``preferredLanguage``
/// - ``setPreferredLanguage(_:)``
/// - ``reset()``
///
/// ### Resolution
/// - ``effectiveLocale``
/// - ``effectiveBundle``
/// - ``languageBundle(for:in:)``
///
/// ### Display
/// - ``availableLanguages``
/// - ``displayName(for:in:)``
/// - ``nativeDisplayName(for:)``
/// - ``currentLanguageDisplayName``
/// - ``currentRegionDisplayName``
public final class LanguageOverride: ObservableObject, @unchecked Sendable {
    /// The shared override, exposed as `Scyther.localization`.
    public static let shared = LanguageOverride()

    /// The standard-defaults key iOS reads at launch.
    static let appleLanguagesKey = "AppleLanguages"

    /// The private-suite key recording Scyther's own override.
    static let bookkeepingKey = "Scyther.Localization.PreferredLanguage"

    /// The BCP 47 identifier forced via `AppleLanguages`, or `nil` for the system default.
    @Published public private(set) var preferredLanguage: String?

    private let lock = NSLock()
    private let systemDefaults: UserDefaults
    private let scytherDefaults: UserDefaults
    private let hostBundle: Bundle
    private let moduleBundle: Bundle
    private var resolvedBundle: Bundle

    /// Creates an override backed by specific stores and bundles. Tests inject throwaway suites.
    ///
    /// - Parameters:
    ///   - systemDefaults: Where `AppleLanguages` is written. Defaults to `.standard`.
    ///   - scytherDefaults: Where the bookkeeping key is written. Defaults to `.scyther`.
    ///   - hostBundle: The bundle whose declared localisations populate ``availableLanguages``.
    ///   - moduleBundle: The bundle holding Scyther's catalog.
    init(
        systemDefaults: UserDefaults = .standard,
        scytherDefaults: UserDefaults = .scyther,
        hostBundle: Bundle = .main,
        moduleBundle: Bundle = ScytherLocalization.moduleBundle
    ) {
        self.systemDefaults = systemDefaults
        self.scytherDefaults = scytherDefaults
        self.hostBundle = hostBundle
        self.moduleBundle = moduleBundle
        let stored = scytherDefaults.string(forKey: Self.bookkeepingKey)
        self.preferredLanguage = stored
        self.resolvedBundle = Self.languageBundle(for: stored, in: moduleBundle) ?? moduleBundle
    }

    // MARK: - Override

    /// Forces a language for the host app (next launch) and Scyther's menu (immediately).
    ///
    /// Writes `[identifier]` to `AppleLanguages` in the system defaults and records the choice in
    /// Scyther's private suite. Passing `nil` is equivalent to ``reset()``.
    ///
    /// - Parameter identifier: A BCP 47 language identifier such as `"fr"` or `"zh-Hans"`.
    public func setPreferredLanguage(_ identifier: String?) {
        guard let identifier, !identifier.isEmpty else {
            reset()
            return
        }
        systemDefaults.set([identifier], forKey: Self.appleLanguagesKey)
        scytherDefaults.set(identifier, forKey: Self.bookkeepingKey)
        let bundle = Self.languageBundle(for: identifier, in: moduleBundle) ?? moduleBundle
        lock.withLock { resolvedBundle = bundle }
        preferredLanguage = identifier
    }

    /// Removes the override so the host app and Scyther follow the device language again.
    public func reset() {
        systemDefaults.removeObject(forKey: Self.appleLanguagesKey)
        scytherDefaults.removeObject(forKey: Self.bookkeepingKey)
        lock.withLock { resolvedBundle = moduleBundle }
        preferredLanguage = nil
    }

    // MARK: - Resolution

    /// The locale matching ``preferredLanguage``, or `nil` when no override is set.
    public var effectiveLocale: Locale? {
        preferredLanguage.map(Locale.init(identifier:))
    }

    /// The bundle Scyther's strings are read from.
    ///
    /// The forced language's `.lproj` sub-bundle when an override is set and the catalog contains
    /// that language; otherwise the module bundle, which follows the device's preferred languages.
    public var effectiveBundle: Bundle {
        lock.withLock { resolvedBundle }
    }

    /// The `.lproj` sub-bundle for a language inside a bundle, or `nil` if it is not present.
    ///
    /// - Parameters:
    ///   - identifier: A language identifier such as `"fr"` or `"pt-BR"`, or `nil`.
    ///   - bundle: The bundle to search.
    static func languageBundle(for identifier: String?, in bundle: Bundle) -> Bundle? {
        guard let identifier,
              let path = bundle.path(forResource: identifier, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    // MARK: - Display

    /// The localisations the host app declares, excluding `Base`, sorted by their name in the current locale.
    public var availableLanguages: [String] {
        hostBundle.localizations
            .filter { $0 != "Base" }
            .sorted { displayName(for: $0) < displayName(for: $1) }
    }

    /// A language's name in `locale`, e.g. `"French"` for `"fr"` in English.
    ///
    /// - Parameters:
    ///   - identifier: The language identifier.
    ///   - locale: The locale to name it in. Defaults to the current locale.
    public func displayName(for identifier: String, in locale: Locale = .current) -> String {
        locale.localizedString(forIdentifier: identifier) ?? identifier
    }

    /// A language's name in itself, e.g. `"français"` for `"fr"`.
    ///
    /// - Parameter identifier: The language identifier.
    public func nativeDisplayName(for identifier: String) -> String {
        Locale(identifier: identifier).localizedString(forIdentifier: identifier) ?? identifier
    }

    /// The name of the language currently in effect: the override if set, else the device's first preferred language.
    public var currentLanguageDisplayName: String {
        let identifier = preferredLanguage ?? Locale.preferredLanguages.first ?? Locale.current.identifier
        return displayName(for: identifier)
    }

    /// The name of the device's region, e.g. `"Australia"`.
    public var currentRegionDisplayName: String {
        guard let region = Locale.current.region?.identifier else { return "" }
        return Locale.current.localizedString(forRegionCode: region) ?? region
    }
}
```

- [ ] **Step 8: Run the tests to verify they pass**

Run the full test command. Expected: `** TEST SUCCEEDED **` with the new `ScytherLocalizationTests` (5) and `LanguageOverrideTests` (8) passing. If `testModuleBundleContainsCompiledCatalog` fails with a missing `.lproj`, the catalog is not being compiled: confirm `defaultLocalization` is set and the file is under `Sources/Scyther/Resources/`.

- [ ] **Step 9: Commit**

```bash
git add Package.swift Scripts/localization Sources/Scyther/Resources/Localizable.xcstrings Sources/Scyther/Core/ScytherLocalization.swift Sources/Scyther/Features/Localization/LanguageOverride.swift Tests/ScytherTests/Core/ScytherLocalizationTests.swift Tests/ScytherTests/Features/LanguageOverrideTests.swift
git commit -m "Add String Catalog generator, localized() helper, and language override core"
```

---

### Task 2: Catalog integrity test and unlocalised-literal lint

**Files:**
- Test: `Tests/ScytherTests/Core/LocalizableCatalogTests.swift`
- Test: `Tests/ScytherTests/Core/UnlocalisedLiteralLintTests.swift`

**Interfaces:**
- Consumes: `ScytherLocalization.moduleBundle`, `ScytherLocalization.supportedLanguages`
- Produces: `UnlocalisedLiteralLintTests.convertedDirectories: [String]` that later tasks append to

- [ ] **Step 1: Write the catalog test**

`Tests/ScytherTests/Core/LocalizableCatalogTests.swift`:

```swift
//
//  LocalizableCatalogTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

/// Parses the shipped catalog source and checks it is complete and consistent.
final class LocalizableCatalogTests: XCTestCase {

    private struct Catalog: Decodable {
        struct Localization: Decodable {
            struct Unit: Decodable { let state: String; let value: String }
            struct Variations: Decodable { let plural: [String: Wrapped]? }
            struct Wrapped: Decodable { let stringUnit: Unit }
            let stringUnit: Unit?
            let variations: Variations?
        }
        struct Entry: Decodable { let localizations: [String: Localization]; let comment: String? }
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private static let placeholder = try! NSRegularExpression(pattern: #"%(\d+\$)?[@dlfsu]|%lld|%\.\d+f"#)

    private func placeholders(in text: String) -> [String] {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return Self.placeholder.matches(in: text, range: range).map { (text as NSString).substring(with: $0.range) }.sorted()
    }

    private func loadCatalog() throws -> Catalog {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Sources/Scyther/Resources/Localizable.xcstrings")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    func testSourceLanguageIsEnglish() throws {
        XCTAssertEqual(try loadCatalog().sourceLanguage, "en")
    }

    func testEveryKeyHasEverySupportedLanguage() throws {
        let catalog = try loadCatalog()
        XCTAssertFalse(catalog.strings.isEmpty)
        for (key, entry) in catalog.strings {
            for language in ScytherLocalization.supportedLanguages {
                guard let localization = entry.localizations[language] else {
                    XCTFail("\(key): missing \(language)"); continue
                }
                if let unit = localization.stringUnit {
                    XCTAssertFalse(unit.value.trimmingCharacters(in: .whitespaces).isEmpty, "\(key): empty \(language)")
                } else if let plural = localization.variations?.plural {
                    XCTAssertFalse(plural.isEmpty, "\(key): empty plural for \(language)")
                } else {
                    XCTFail("\(key): \(language) has neither a stringUnit nor plural variations")
                }
            }
        }
    }

    func testPlaceholdersMatchEnglishInEveryLanguage() throws {
        let catalog = try loadCatalog()
        for (key, entry) in catalog.strings {
            let source: String = entry.localizations["en"]?.variations?.plural?["other"]?.stringUnit.value ?? key
            let expected = placeholders(in: source)
            for (language, localization) in entry.localizations {
                if let unit = localization.stringUnit {
                    XCTAssertEqual(placeholders(in: unit.value), expected, "\(key) [\(language)]")
                } else if let other = localization.variations?.plural?["other"] {
                    XCTAssertEqual(placeholders(in: other.stringUnit.value), expected, "\(key) [\(language).other]")
                }
            }
        }
    }

    func testNoNearDuplicateKeys() throws {
        let keys = try loadCatalog().strings.keys
        var seen: [String: String] = [:]
        for key in keys {
            let normalised = key.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".…:!? "))
            if let existing = seen[normalised], existing != key {
                XCTFail("near-duplicate keys: \(existing) / \(key)")
            }
            seen[normalised] = key
        }
    }

    func testCompiledTablesMatchSource() throws {
        let catalog = try loadCatalog()
        let key = try XCTUnwrap(catalog.strings.keys.first { catalog.strings[$0]?.localizations["fr"]?.stringUnit != nil })
        let french = try XCTUnwrap(LanguageOverride.languageBundle(for: "fr", in: ScytherLocalization.moduleBundle))
        XCTAssertEqual(french.localizedString(forKey: key, value: nil, table: nil), catalog.strings[key]?.localizations["fr"]?.stringUnit?.value)
    }
}
```

- [ ] **Step 2: Write the lint test**

`Tests/ScytherTests/Core/UnlocalisedLiteralLintTests.swift`:

```swift
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
```

- [ ] **Step 3: Run the tests**

Run the full test command. Expected: `** TEST SUCCEEDED **`. `Core` and `Features/Localization` contain no SwiftUI literals yet, and the catalog has two complete keys. If the lint reports a line in `Core` (for example a `title:` in a DocC comment example), it is inside a `///` comment; the test already skips lines starting with `//`, so confirm the line really is a comment before adding the marker.

- [ ] **Step 4: Commit**

```bash
git add Tests/ScytherTests/Core/LocalizableCatalogTests.swift Tests/ScytherTests/Core/UnlocalisedLiteralLintTests.swift
git commit -m "Add catalog integrity and unlocalised-literal lint tests"
```

---

### Task 3: Localise NetworkLogger (pilot module)

**Files:**
- Create: `Scripts/localization/strings/NetworkLogger.json`
- Modify: every file in `Sources/Scyther/Features/NetworkLogger/` that contains UI copy: `NetworkLogsView.swift`, `LogDetailsView.swift`, `HTTPResponseView.swift`, `NetworkLogFilter.swift` (enum display names and dimension titles), `NetworkLogFilterBar.swift`, `NetworkLogFilterSheet.swift`, `NetworkLogFilterSheetComponents.swift`, `NetworkLogAllFiltersSheet.swift`, `NetworkLogAllFiltersSheetViewModel.swift` (`"Any"`, `"Exclude: "`), `NetworkLogExportSheet.swift`, `NetworkLogsViewModel.swift` (`chipTitle` `"Not "` prefix), `LogDetailsViewModel.swift` (`"-"` values stay)
- Modify: `Tests/ScytherTests/Core/UnlocalisedLiteralLintTests.swift` (add `"Features/NetworkLogger"`)
- Modify: `Tests/ScytherTests/Features/NetworkLogFilterTests.swift`, `NetworkLogAllFiltersSheetViewModelTests.swift`, `NetworkLogsViewModelTests.swift` only where a test asserts an English display string (see Step 2)
- Regenerate: `Sources/Scyther/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `localized(_:comment:)`, generator, lint list
- Produces: fragment keys used by Task 4's search sub-page rows (`"Network Logs"` lives in the Menu fragment, not here)

Expected literal count from the grep: **61**, plus enum `displayName` values in `NetworkLogFilter.swift` (status classes 5, API kinds 2, GraphQL operations 4, duration buckets 5, recency windows 4, host modes 2, dimension titles 9, group titles 3) and the `"Any"`, `"Exclude: %@"`, `"Not %@"`, `"%@ · %lld"` composites.

- [ ] **Step 1: Follow the Module Conversion Procedure steps 1 to 5** for `Sources/Scyther/Features/NetworkLogger`.

Composite strings to key precisely:
- `NetworkLogsViewModel.chipTitle`: `"Not \(title)"` → `localized("Not \(title)")` (key `Not %@`); `"\(dimension.title) · \(selected.count)"` → `localized("\(dimension.title) · \(selected.count)")` (key `%@ · %lld`).
- `NetworkLogAllFiltersSheetViewModel.summary`: `"Any"` → `localized("Any")`; `"Exclude: \(joined)"` → `localized("Exclude: \(joined)")` (key `Exclude: %@`).
- `NetworkLogFilterBar`: `"All filters, \(count) selected"` → `localized("All filters, \(count) selected")` (key `All filters, %lld selected`, plural); `"\(dimension.title), \(count) selected"` → key `%@, %lld selected` (plural); `"Clear all filters"`, `"All filters"`.
- `NetworkLogFilterSheetComponents.NetworkLogFilterEmptyRow`: `"No \(dimensionName) values captured yet"` → key `No %@ values captured yet`.
- `NetworkLogExportSheet.warningMessage`: two sentences concatenated. Make them two keys: `The archive contains the full headers, cookies, authentication tokens, and request and response bodies of the %lld requests currently shown. This data may be extremely sensitive. Handle and share it with extreme care.` (plural on `%lld`) and `Redaction is on, but it is best effort and not a guarantee of privacy.`; join with a space in code.
- `NetworkLogExportSheet`: `"Preparing archive of \(viewModel.requestCount) requests…"` → key `Preparing archive of %lld requests…` (plural).
- `LogDetailsView`: `"\(header.key): \(header.value)"` written to the pasteboard is data, not UI copy: leave it and add `// scyther:unlocalised pasteboard payload` if the lint flags it.
- `HTTPResponseView`: the `"Batch (\(n) operations)"` row title → key `Batch (%lld operations)` (plural).

Fragment must contain every key with all twelve languages (roughly 95 keys). Apply the Glossary for Done, Cancel, Reset, Clear, Export, Share, Search, Copy, Close, Any, Request, Response, Headers, Body.

- [ ] **Step 2: Update tests that assert English display strings**

In `Tests/ScytherTests/Features/NetworkLogAllFiltersSheetViewModelTests.swift`, `NetworkLogsViewModelTests.swift`, and `NetworkLogFilterTests.swift`, any assertion such as `XCTAssertEqual(viewModel.summary(for: .method), "Any")` keeps working while the test process runs in English, because `Bundle.module` resolves to the source language. Do **not** change them. If the simulator's language is not English and a test fails on a translated value, set the scheme's test language explicitly rather than editing assertions: add `-testLanguage en -testRegion US` to the `xcodebuild test` command and to `.github/workflows/ci.yml`'s test step.

- [ ] **Step 3: Follow Procedure steps 6 and 7.** Open Network Logs, a request detail, the filter sheet, and the export sheet in the example app.

- [ ] **Step 4: Follow Procedure step 8.** Commit message: `Localise NetworkLogger`.

---

### Task 4: Localise Menu, Shared components, and section identity

**Files:**
- Create: `Scripts/localization/strings/Menu.json`, `Scripts/localization/strings/Shared.json`
- Modify: `Sources/Scyther/Features/Menu/MenuSection.swift`, `MenuSectionTint.swift`, `MenuItem.swift`, `MenuView.swift`, `MenuSearchIndex.swift`, `MenuViewModel.swift` (if it holds copy)
- Modify: `Sources/Scyther/Shared/Components/*.swift` (`TextReaderView`, `TextEntryView`, `DataBrowserView`, `ActivityShareSheet` has none) and `Sources/Scyther/Shared/**` view modifiers with copy
- Modify: `Tests/ScytherTests/Core/UnlocalisedLiteralLintTests.swift` (add `"Features/Menu"`, `"Shared"`)
- Test: `Tests/ScytherTests/Features/MenuSectionTests.swift` (add if absent) for the stable id
- Regenerate catalog

**Interfaces:**
- Produces: `MenuSection(id: String, title: String, items: [MenuItem])`, `MenuSection.tint(forID:)`, `MenuSectionID` constants
- Produces: `MenuItem.title` returning `localized(...)`; `MenuSearchIndex` sub-page rows through `localized(...)`

Expected literal count: Menu **7** in views plus `MenuItem.title` (about 40 cases), `MenuSection` titles (8 plus `"Pinned"`), and the sub-page row labels in `MenuSearchIndex` (about 35). Shared **7**.

- [ ] **Step 1: Write the failing section-identity test**

`Tests/ScytherTests/Features/MenuSectionTests.swift`:

```swift
//
//  MenuSectionTests.swift
//  ScytherTests
//

@testable import Scyther
import SwiftUI
import XCTest

@MainActor
final class MenuSectionTests: XCTestCase {

    func testSectionIDsAreStableAndUnique() {
        let sections = MenuSection.allSections(developerOptions: [])
        let ids = sections.map(\.id)
        XCTAssertEqual(ids, ["device", "application", "networking", "data", "security", "systemTools", "notifications", "uiux"])
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testTintIsKeyedOnIDNotTitle() {
        XCTAssertEqual(MenuSection.tint(forID: "uiux"), .teal)
        XCTAssertEqual(MenuSection.tint(forID: "networking"), .blue)
        XCTAssertEqual(MenuSection.tint(forID: "unknown"), .accentColor)
        let uiux = MenuSection(id: "uiux", title: "Interface utilisateur", items: [])
        XCTAssertEqual(uiux.tint, .teal)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Expected: `extra argument 'id' in call`, `has no member 'tint(forID:)'`.

- [ ] **Step 3: Give sections a stable id and key the tint on it**

In `MenuSection.swift`, replace `var id: String { title }` with `let id: String` and add `id:` as the first parameter of the memberwise initialiser and of every `MenuSection(` call in `allSections`, using these ids in order: `device`, `application`, `developmentTools` (the developer options section), `networking`, `data`, `security`, `systemTools`, `notifications`, `uiux`. The `"Pinned"` section created in `MenuView` gets id `pinned`.

In `MenuSectionTint.swift`, rename `tint(forTitle:)` to `tint(forID:)` and switch on the ids above (same colours). Update its two call sites (`MenuSection.tint` and the `MenuItem.tint` fallback that names `"Development Tools"`, which becomes `tint(forID: "developmentTools")`).

- [ ] **Step 4: Follow the Module Conversion Procedure steps 1 to 5** for `Sources/Scyther/Features/Menu` and `Sources/Scyther/Shared`.

Specifics:
- `MenuItem.title`: every `return "…"` becomes `return localized("…")` except `.developerOption(let name): return name`.
- `MenuSection.allSections`: `title: "Device"` → `title: localized("Device")`, and so on. The `"Pinned"` title in `MenuView` likewise.
- `MenuSearchIndex.subpageRows` (the `(.gridOverlay, ["Enable Grid", …])` table): wrap every label in `localized(...)`. Keywords in `MenuSearchIndex.keywords` stay English (they are search aliases, not display copy); add `// scyther:unlocalised search aliases` to the `static let keywords` line only if the lint pattern matches it (it should not, since the literals are inside array brackets, not an initialiser).
- The device header rows in `MenuView` (`"OS Version"` etc. come from `MenuItem.title`, already handled).

- [ ] **Step 5: Follow Procedure steps 6 and 7.** In the example app, open the menu, search for `network`, and confirm the results still show a breadcrumb.

- [ ] **Step 6: Follow Procedure step 8.** Commit message: `Localise Menu and Shared components; key section tints on stable ids`.

---

### Task 5: Localise DatabaseBrowser

**Files:**
- Create: `Scripts/localization/strings/DatabaseBrowser.json`
- Modify: `Sources/Scyther/Features/DatabaseBrowser/**/*.swift`
- Modify: lint list (add `"Features/DatabaseBrowser"`)
- Regenerate catalog

Expected literal count: **74**. Watch for: SQL keywords and column type names (`INTEGER`, `TEXT`, `NULL`) are technical and stay; error messages built from `Error.localizedDescription` stay; the `"Add Record"`, `"Edit Record"`, `"Schema"`, `"Run Query"` titles and every alert are UI copy.

- [ ] **Step 1: Follow the Module Conversion Procedure steps 1 to 5.**
- [ ] **Step 2: Follow Procedure steps 6 and 7.** Open Database Browser in the example app and the SQL editor.
- [ ] **Step 3: Follow Procedure step 8.** Commit message: `Localise DatabaseBrowser`.

---

### Task 6: Localise NotificationTester and NotificationLogger

**Files:**
- Create: `Scripts/localization/strings/Notifications.json`
- Modify: `Sources/Scyther/Features/NotificationTester/*.swift`, `Sources/Scyther/Features/NotificationLogger/*.swift`
- Modify: lint list (add `"Features/NotificationTester"`, `"Features/NotificationLogger"`)
- Regenerate catalog

Expected literal count: **44**. Watch for: the sample notification title and body that Scyther schedules are UI copy the user sees in a banner, so localise them; payload dictionary keys (`aps`, `alert`) are data and stay.

- [ ] **Step 1: Follow the Module Conversion Procedure steps 1 to 5.**
- [ ] **Step 2: Follow Procedure steps 6 and 7.**
- [ ] **Step 3: Follow Procedure step 8.** Commit message: `Localise NotificationTester and NotificationLogger`.

---

### Task 7: Localise UserDefaults, KeychainBrowser, and CookieBrowser

**Files:**
- Create: `Scripts/localization/strings/DataBrowsers.json`
- Modify: `Sources/Scyther/Features/UserDefaults/*.swift`, `Sources/Scyther/Features/KeychainBrowser/*.swift`, `Sources/Scyther/Features/CookieBrowser/*.swift`
- Modify: lint list (add the three directories)
- Regenerate catalog

Expected literal count: **74**. Watch for: `UserDefaults` suite names, keychain attribute names (`kSecAttrService` labels shown as row keys are data), and cookie attribute names (`Domain`, `Path`, `Expires`, `Secure`, `HttpOnly`) shown as row labels are UI copy and get localised; the raw values stay.

- [ ] **Step 1: Follow the Module Conversion Procedure steps 1 to 5.**
- [ ] **Step 2: Follow Procedure steps 6 and 7.**
- [ ] **Step 3: Follow Procedure step 8.** Commit message: `Localise UserDefaults, Keychain, and Cookie browsers`.

---

### Task 8: Localise CrashLogs, FileBrowser, and DataBrowser

**Files:**
- Create: `Scripts/localization/strings/Files.json`
- Modify: `Sources/Scyther/Features/CrashLogs/*.swift`, `Sources/Scyther/Features/FileBrowser/*.swift`, `Sources/Scyther/Features/DataBrowser/*.swift`
- Modify: lint list (add the three directories)
- Regenerate catalog

Expected literal count: **49**. Watch for: directory display names (`Documents`, `Library`, `Caches`, `tmp`) are folder names and stay; the section headers describing them are UI copy. Crash report field labels are UI copy; the report body written to disk is data.

- [ ] **Step 1: Follow the Module Conversion Procedure steps 1 to 5.**
- [ ] **Step 2: Follow Procedure steps 6 and 7.**
- [ ] **Step 3: Follow Procedure step 8.** Commit message: `Localise CrashLogs, FileBrowser, and DataBrowser`.

---

### Task 9: Localise LocationSpoofer, DeepLinkTester, ServerConfiguration, and EnvironmentVariables

**Files:**
- Create: `Scripts/localization/strings/SystemTools.json`
- Modify: the four feature directories
- Modify: lint list (add the four directories)
- Regenerate catalog

Expected literal count: **49**. Watch for: preset city names in `LocationSpoofer` are proper nouns; localise them (each language has its own exonyms, e.g. `London` → `Londres` in fr/es/pt-BR, `ロンドン` in ja). Route names likewise. URL scheme strings in the deep link tester are data.

- [ ] **Step 1: Follow the Module Conversion Procedure steps 1 to 5.**
- [ ] **Step 2: Follow Procedure steps 6 and 7.**
- [ ] **Step 3: Follow Procedure step 8.** Commit message: `Localise LocationSpoofer, DeepLinkTester, ServerConfiguration, and EnvironmentVariables`.

---

### Task 10: Localise the remaining UI/UX and developer tools

**Files:**
- Create: `Scripts/localization/strings/Interface.json`
- Modify: `Sources/Scyther/Features/AppearanceOverrides`, `FPSCounter`, `GridOverlay`, `TouchVisualiser`, `FeatureFlags`, `ConsoleLogger`, `Fonts`, `InterfacePreviews`, and any UIKit copy in `Sources/Scyther/Core` (`UIView+InterfaceToolkit.swift` size labels are numeric and stay)
- Modify: lint list (add the eight directories)
- Regenerate catalog

Expected literal count: **61**. Watch for: `ColorSchemeOverride` and `ContentSizeCategory` display names in `AppearanceOverrides`; the FPS overlay's `"FPS"` suffix is a technical token and stays; font family names in `Fonts` are data.

- [ ] **Step 1: Follow the Module Conversion Procedure steps 1 to 5.**
- [ ] **Step 2: Follow Procedure steps 6 and 7.**
- [ ] **Step 3: Follow Procedure step 8.** Commit message: `Localise appearance, overlays, feature flags, console, fonts, and previews`.

---

### Task 11: Lock in full coverage

**Files:**
- Modify: `Tests/ScytherTests/Core/UnlocalisedLiteralLintTests.swift`

- [ ] **Step 1: Replace the directory list with the whole tree**

Change `convertedDirectories` to a single entry `[""]` (the empty relative path, meaning all of `Sources/Scyther`) and add a test that no directory under `Sources/Scyther/Features` is missing:

```swift
    func testEveryFeatureDirectoryIsCovered() throws {
        let features = sourcesRoot.appendingPathComponent("Features")
        let names = try FileManager.default.contentsOfDirectory(atPath: features.path).sorted()
        XCTAssertFalse(names.isEmpty)
        XCTAssertEqual(Self.convertedDirectories, [""], "lint must cover the whole source tree once every module is converted")
    }
```

- [ ] **Step 2: Run the full suite**

Expected: `** TEST SUCCEEDED **`. Any offender listed by the lint is a literal missed in Tasks 3 to 10: convert it, add its key to the owning fragment, regenerate, rerun.

- [ ] **Step 3: Commit**

```bash
git add Tests/ScytherTests/Core/UnlocalisedLiteralLintTests.swift Scripts/localization/strings Sources/Scyther/Resources/Localizable.xcstrings Sources/Scyther
git commit -m "Lint the whole source tree for unlocalised literals"
```

---

### Task 12: Language page, menu entry, facade, and example app localisations

**Files:**
- Create: `Sources/Scyther/Features/Localization/LanguageViewModel.swift`
- Create: `Sources/Scyther/Features/Localization/LanguageView.swift`
- Create: `Scripts/localization/strings/Localization.json`
- Modify: `Sources/Scyther/Core/Scyther.swift` (facade)
- Modify: `Sources/Scyther/Features/Menu/MenuItem.swift`, `MenuSection.swift`, `MenuView.swift`, `MenuSearchIndex.swift`
- Create: `Example/ScytherExample/Resources/Localizable.xcstrings`
- Modify: `Example/ScytherExample.xcodeproj/project.pbxproj`
- Test: `Tests/ScytherTests/Features/LanguageViewModelTests.swift`
- Regenerate catalog

**Interfaces:**
- Consumes: `LanguageOverride` (Task 1), `localized` (Task 1), `MenuSection(id:title:items:)` (Task 4)
- Produces: `Scyther.localization`, `MenuItem.language`, `LanguageView`, `LanguageViewModel`

- [ ] **Step 1: Write the failing view model tests**

`Tests/ScytherTests/Features/LanguageViewModelTests.swift`:

```swift
//
//  LanguageViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class LanguageViewModelTests: XCTestCase {

    private var system: UserDefaults!
    private var scyther: UserDefaults!
    private var suites: [String] = []

    override func setUpWithError() throws {
        let a = "LanguageViewModelTests.a.\(UUID().uuidString)", b = "LanguageViewModelTests.b.\(UUID().uuidString)"
        suites = [a, b]
        system = try XCTUnwrap(UserDefaults(suiteName: a))
        scyther = try XCTUnwrap(UserDefaults(suiteName: b))
    }

    override func tearDownWithError() throws {
        system.removePersistentDomain(forName: suites[0])
        scyther.removePersistentDomain(forName: suites[1])
    }

    private func makeViewModel() -> LanguageViewModel {
        let override = LanguageOverride(
            systemDefaults: system, scytherDefaults: scyther,
            hostBundle: ScytherLocalization.moduleBundle, moduleBundle: ScytherLocalization.moduleBundle
        )
        return LanguageViewModel(override: override)
    }

    func testRowsStartWithSystemDefaultThenHostLanguages() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.rows.first?.id, LanguageViewModel.systemDefaultID)
        XCTAssertTrue(viewModel.rows.dropFirst().map(\.id).contains("fr"))
        XCTAssertTrue(viewModel.isSelected(viewModel.rows[0]))
        XCTAssertFalse(viewModel.canReset)
    }

    func testSelectingLanguageSetsOverrideAndRequestsRelaunch() {
        let viewModel = makeViewModel()
        let french = viewModel.rows.first { $0.id == "fr" }!
        viewModel.select(french)
        XCTAssertEqual(system.stringArray(forKey: LanguageOverride.appleLanguagesKey), ["fr"])
        XCTAssertTrue(viewModel.isSelected(french))
        XCTAssertTrue(viewModel.showingRelaunchAlert)
        XCTAssertTrue(viewModel.canReset)
    }

    func testSelectingSystemDefaultResets() {
        let viewModel = makeViewModel()
        viewModel.select(viewModel.rows.first { $0.id == "de" }!)
        viewModel.select(viewModel.rows[0])
        XCTAssertNil(system.object(forKey: LanguageOverride.appleLanguagesKey))
        XCTAssertFalse(viewModel.canReset)
        XCTAssertTrue(viewModel.showingRelaunchAlert)
    }

    func testResetClearsOverride() {
        let viewModel = makeViewModel()
        viewModel.select(viewModel.rows.first { $0.id == "ja" }!)
        viewModel.reset()
        XCTAssertNil(system.object(forKey: LanguageOverride.appleLanguagesKey))
        XCTAssertFalse(viewModel.canReset)
    }

    func testRowsCarryNativeAndLocalisedNames() {
        let viewModel = makeViewModel()
        let french = viewModel.rows.first { $0.id == "fr" }!
        XCTAssertEqual(french.nativeName, "français")
        XCTAssertFalse(french.localizedName.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Expected: `cannot find type 'LanguageViewModel' in scope`.

- [ ] **Step 3: Write the view model**

`Sources/Scyther/Features/Localization/LanguageViewModel.swift`:

```swift
//
//  LanguageViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/9/2026.
//

import Combine
import Foundation
import UIKit

/// One selectable row on the Language page.
struct LanguageRow: Identifiable, Hashable, Sendable {
    /// The language identifier, or ``LanguageViewModel/systemDefaultID``.
    let id: String
    /// The language's name in itself, e.g. "français".
    let nativeName: String
    /// The language's name in the current locale, e.g. "French".
    let localizedName: String
}

/// View model backing ``LanguageView``.
///
/// Lists the host app's declared localisations after a System Default row, applies a selection
/// through ``LanguageOverride``, and raises the relaunch alert. Quitting is only ever triggered by
/// the alert's destructive action.
final class LanguageViewModel: ViewModel {
    /// The id of the row that clears the override.
    static let systemDefaultID = "system"

    /// The override this page edits.
    let override: LanguageOverride

    /// Whether the "Relaunch required" alert is presented.
    @Published var showingRelaunchAlert: Bool = false

    private var cancellable: AnyCancellable?

    /// Creates the view model.
    ///
    /// - Parameter override: The override to edit. Defaults to the shared instance.
    init(override: LanguageOverride = .shared) {
        self.override = override
        super.init()
        cancellable = override.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// The rows to display: System Default first, then the host app's languages.
    var rows: [LanguageRow] {
        let system = LanguageRow(
            id: Self.systemDefaultID,
            nativeName: localized("System Default"),
            localizedName: localized("Follow the device language")
        )
        let languages = override.availableLanguages.map {
            LanguageRow(id: $0, nativeName: override.nativeDisplayName(for: $0), localizedName: override.displayName(for: $0))
        }
        return [system] + languages
    }

    /// Whether the host app declares any language beyond the base localisation.
    var hasLanguages: Bool { !override.availableLanguages.isEmpty }

    /// Whether an override is currently set.
    var canReset: Bool { override.preferredLanguage != nil }

    /// The effective language name for the Current section.
    var currentLanguage: String { override.currentLanguageDisplayName }

    /// The device region name for the Current section.
    var currentRegion: String { override.currentRegionDisplayName }

    /// Whether a row is the active choice.
    ///
    /// - Parameter row: The row to check.
    func isSelected(_ row: LanguageRow) -> Bool {
        (override.preferredLanguage ?? Self.systemDefaultID) == row.id
    }

    /// Applies a row's language and raises the relaunch alert.
    ///
    /// - Parameter row: The tapped row.
    func select(_ row: LanguageRow) {
        if row.id == Self.systemDefaultID {
            override.reset()
        } else {
            override.setPreferredLanguage(row.id)
        }
        showingRelaunchAlert = true
    }

    /// Clears the override without raising the alert.
    func reset() {
        override.reset()
    }

    /// Terminates the process so the host app relaunches in the chosen language.
    ///
    /// Only called from the destructive action of the relaunch alert.
    func quitApp() {
        exit(0)
    }
}
```

- [ ] **Step 4: Write the view**

`Sources/Scyther/Features/Localization/LanguageView.swift`:

```swift
//
//  LanguageView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/9/2026.
//

import SwiftUI

/// The Language page: shows the effective language and region, lists the host app's
/// localisations, and forces one via ``LanguageOverride``.
///
/// Selecting a row applies immediately to Scyther's menu and raises an alert explaining that the
/// host app changes language on its next launch, with a destructive Quit App action.
struct LanguageView: View {
    @StateObject private var viewModel: LanguageViewModel

    /// Creates the page.
    ///
    /// - Parameter viewModel: The view model. Defaults to one editing the shared override.
    init(viewModel: LanguageViewModel = LanguageViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            Section(localized("Current")) {
                LabeledContent(localized("Language"), value: viewModel.currentLanguage)
                LabeledContent(localized("Region"), value: viewModel.currentRegion)
            }
            Section {
                ForEach(viewModel.rows) { row in
                    Button {
                        viewModel.select(row)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.nativeName)
                                    .foregroundStyle(Color.primary)
                                Text(row.localizedName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if viewModel.isSelected(row) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .accessibilityAddTraits(viewModel.isSelected(row) ? .isSelected : [])
                }
            } header: {
                Text(localized("App language"))
            } footer: {
                if viewModel.hasLanguages {
                    Text(localized("Changing the language applies to the whole app the next time it launches. Scyther's menu switches immediately."))
                } else {
                    Text(localized("This app declares no localisations beyond its base language, so there is nothing to switch to."))
                }
            }
            if viewModel.canReset {
                Section {
                    Button(role: .destructive) {
                        viewModel.reset()
                    } label: {
                        Text(localized("Reset Language Override"))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle(localized("Language"))
        .alert(localized("Relaunch required"), isPresented: $viewModel.showingRelaunchAlert) {
            Button(localized("Later"), role: .cancel) {}
            Button(localized("Quit App"), role: .destructive) {
                viewModel.quitApp()
            }
        } message: {
            Text(localized("The app language changes the next time it launches. Scyther's menu has already switched."))
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }
}
```

- [ ] **Step 5: Wire the menu, the facade, and the environment**

- `MenuItem.swift`: add `language` to the UI/UX case list (`case touchVisualiser, appearance, language`), to `allStaticCases` immediately after `.appearance`, `id` → `"language"`, `title` → `localized("Language")`, `icon` → `"globe"`.
- `MenuSection.swift`: insert `.language` after `.appearance` in the `uiux` section's items.
- `MenuView.swift`: `destination(for:)` gets `case .language: LanguageView()`; the row switch gets `case .language: navigationRow(for: item)`. At the root of `body`, add `@ObservedObject private var languageOverride = LanguageOverride.shared` to the view and apply to the `List`:
  ```swift
  .environment(\.locale, languageOverride.effectiveLocale ?? .current)
  .environment(\.layoutDirection, Locale.Language(identifier: languageOverride.preferredLanguage ?? Locale.current.identifier).characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
  ```
- `MenuSearchIndex.swift`: keywords `.language: ["locale", "translation", "localisation", "localization", "i18n", "l10n", "region"]`; sub-page rows `(.language, [localized("System Default"), localized("Reset Language Override")])`.
- `Scyther.swift`: after `public static let database = DatabaseBrowsing.shared` add:
  ```swift
  /// App language override. Forces the host app's language via `AppleLanguages`.
  public static let localization = LanguageOverride.shared
  ```
  and add `localization` to the facade table in the type's DocC block.

- [ ] **Step 6: Add the Localization fragment and regenerate**

`Scripts/localization/strings/Localization.json` with all keys used above (`Current`, `Region`, `App language`, `System Default`, `Follow the device language`, `Changing the language applies to the whole app the next time it launches. Scyther's menu switches immediately.`, `This app declares no localisations beyond its base language, so there is nothing to switch to.`, `Reset Language Override`, `Relaunch required`, `Later`, `Quit App`, `The app language changes the next time it launches. Scyther's menu has already switched.`) in all twelve languages. `Language` already lives in `Core.json`. Run the generator.

- [ ] **Step 7: Give the example app localisations**

Create `Example/ScytherExample/Resources/Localizable.xcstrings` containing the keys `Scyther Example` and `Open Scyther Menu` with `en` plus the twelve languages (state `translated`), for example `fr`: `Exemple Scyther` / `Ouvrir le menu Scyther`, `ja`: `Scyther サンプル` / `Scyther メニューを開く`.

In `Example/ScytherExample.xcodeproj/project.pbxproj`:
- Add a build file: `A10000010000000000000004 /* Localizable.xcstrings in Resources */ = {isa = PBXBuildFile; fileRef = A10000020000000000000004 /* Localizable.xcstrings */; };`
- Add a file reference: `A10000020000000000000004 /* Localizable.xcstrings */ = {isa = PBXFileReference; lastKnownFileType = text.json.xcstrings; path = Localizable.xcstrings; sourceTree = "<group>"; };`
- Add `A10000020000000000000004 /* Localizable.xcstrings */,` to the `Resources` group children (the group with `path = Resources;`).
- Add `A10000010000000000000004 /* Localizable.xcstrings in Resources */,` to the `PBXResourcesBuildPhase` files list.
- Replace `knownRegions = ( en, Base, );` with `knownRegions = ( en, Base, fr, de, es, it, "pt-BR", nl, ja, "zh-Hans", "zh-Hant", ko, ru, ar, );`.

- [ ] **Step 8: Run the full suite and the example app**

Full test command: expected `** TEST SUCCEEDED **` including `LanguageViewModelTests` (5). Build, install, and launch the example app; open Scyther → UI/UX → Language; the list must show thirteen rows; choose Français: the menu title and rows switch to French immediately and the alert appears; tap Later; go back and confirm the Language row now reads "Langue". Choose System Default to restore.

- [ ] **Step 9: Commit**

```bash
git add Sources/Scyther/Features/Localization Sources/Scyther/Core/Scyther.swift Sources/Scyther/Features/Menu Scripts/localization/strings/Localization.json Sources/Scyther/Resources/Localizable.xcstrings Example Tests/ScytherTests/Features/LanguageViewModelTests.swift
git commit -m "Add Language page and Scyther.localization facade; localise the example app"
```

---

### Task 13: Documentation and final verification

**Files:**
- Modify: `README.md`, `CLAUDE.md`
- Create: `Sources/Scyther/Scyther.docc/Localisation.md`

- [ ] **Step 1: README**

Add under UI/UX Tools: `- **Language**: Force the app's language from the debug menu (applies on next launch; Scyther's own menu switches immediately)`. Add a `### Localisation` subsection after Swift 6 Compatibility:

```markdown
### Localisation

Scyther's UI ships in English plus French, German, Spanish, Italian, Brazilian Portuguese, Dutch,
Japanese, Simplified Chinese, Traditional Chinese, Korean, Russian, and Arabic. Strings live in
per-module fragments under `Scripts/localization/strings/`; `Scripts/localization/build_catalog.py`
merges them into `Sources/Scyther/Resources/Localizable.xcstrings`.

Every user-facing string in the package goes through `localized(_:)`, which reads from the package
bundle (or the forced language's table when the Language override is active). A lint test fails the
build if a SwiftUI literal bypasses it, and a catalog test fails if any key is missing a language.

To add a string: use `localized("Your English text")` at the call site, add the key with all
twelve languages to the module's fragment, and run the generator. To add a language: add its code
to `LANGUAGES` in the generator and to `ScytherLocalization.supportedLanguages`, then fill every
fragment.
```

Add `localization` → `LanguageOverride (@MainActor-safe, Sendable)` to the architecture table.

- [ ] **Step 2: DocC article**

`Sources/Scyther/Scyther.docc/Localisation.md`: title `# Localisation`, sections: Supported languages (the list), How strings are resolved (the helper, the bundle, the override), Adding a string (the three steps), Adding a language, The Language page (what it writes, that quitting is user-initiated), and Limitations (host views already on screen do not re-render; keywords are English only). Link ``LanguageOverride`` and ``Scyther/localization``.

- [ ] **Step 3: CLAUDE.md**

Under `## Making Code Changes` add: `ALWAYS route user-facing strings through localized(_:) and add the key with all supported languages to the module's fragment under Scripts/localization/strings, then run Scripts/localization/build_catalog.py.`

- [ ] **Step 4: Final verification**

Run the full suite, the example app build, and `xcodebuild docbuild -scheme Scyther -destination "platform=iOS Simulator,id=$S" -derivedDataPath ./docbuild 2>&1 | grep -E "error:|warning: .*Localisation|BUILD" | tail -3`. All must succeed. Run `python3 Scripts/localization/build_catalog.py` once more and confirm `git status` shows no change to the catalog (the committed catalog matches the fragments).

- [ ] **Step 5: Commit**

```bash
git add README.md CLAUDE.md Sources/Scyther/Scyther.docc/Localisation.md
git commit -m "Document localisation and the Language override"
```

---

## Self-review

- **Spec coverage:** Component 1 → Task 1 (package, catalog) and Tasks 3–10 (keys, plurals). Component 2 → Task 1. Component 3 → Tasks 3–11 including enum names, menu titles, search rows, UIKit labels. Component 4 → Task 1 (core) and Task 12 (facade). Component 5 → Task 12 (page, alert, menu wiring, environment). Component 6 → Task 12 Step 7. Component 7 → Tasks 1, 2, 4, 12. Documentation → Task 13. Rollout order matches Tasks 3, 4–11, then 12–13; translations are authored per module rather than in a separate step, which the spec's risk section allows.
- **Placeholders:** none; every step shows the code or the exact command. Module tasks defer to the single Procedure section by design.
- **Type consistency:** `localized(_:comment:)`, `ScytherLocalization.moduleBundle`, `LanguageOverride.languageBundle(for:in:)`, `LanguageOverride.appleLanguagesKey`, `LanguageOverride.bookkeepingKey`, `MenuSection(id:title:items:)`, `MenuSection.tint(forID:)`, `LanguageViewModel.systemDefaultID`, `LanguageRow`, `UnlocalisedLiteralLintTests.convertedDirectories` are used with the same spelling in every task.
