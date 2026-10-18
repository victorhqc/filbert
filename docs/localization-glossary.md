# Localization glossary

Every translation in a `Localizable.xcstrings` catalog follows this glossary.

## Sources of truth

When in doubt, use the term that the vendor uses in its own localized docs. Check in this order:

1. Apple's localized macOS help, for macOS terms: `support.apple.com/<locale>/guide/mac-help/...`. Locales: `de-de`, `es-lamr` (Latin America, use for `es-MX`), `es-es`, `pt-br`, `pt-pt`, `ru-ru`, `zh-cn`, `ja-jp`.
   For Japanese, macOS's own UI strings come first. They live in the `.loctable` files under `/System`, and their style differs from Apple's help pages.
2. Google's localized developer docs, for API terms: `ai.google.dev/...?hl=<locale>`.
3. The provider's own localized UI or docs, for provider-specific terms. Z.ai and DeepSeek have Chinese UIs.

Record new terms here with the source. **⚠︎** marks a term that no source has confirmed yet.

## Conventions

| | de-DE | es-MX | es-ES | pt-BR | pt-PT | ru | zh-Hans | ja |
|---|---|---|---|---|---|---|---|---|
| Address the user | du | tú | tú | você, omitted where possible | formal imperative ("Verifique"), no "tu" | вы, lowercase | 你 (as macOS) | omitted, never あなた (as macOS) |
| Recent past | Perfekt | simple past: "No se pudo", "falló" | present perfect: "No se ha podido", "ha fallado" | simple past: "falhou" | simple past: "falhou" | perfective past | 了 / 失败 | polite past: "できませんでした", "失敗しました" |
| Ongoing action | "wird geladen" | gerund: "cargando" | gerund: "cargando" | gerund: "carregando" | a + infinitive: "a carregar" | present | 正在… | …中: "読み込み中…" |
| Buttons, menu items | infinitive | infinitive | infinitive | infinitive | infinitive | infinitive | verb | noun or plain verb phrase: "アップデートを確認", "Filbertを終了" |
| Instructions in a sentence | imperative | imperative | imperative | imperative | imperative | imperative | verb | …してください |
| Quotes | „…“ | “…” | «…» | “…” | «…» | «…» | “…” | “…” |
| Ellipsis in menu items | "Einstellungen …" (space) | "…" | "…" | "…" | "…" | "…" | "…" | "…" |

- Sentence case everywhere. German nouns keep their capital letter.
- Product names stay in English: Filbert, Claude Code, Codex, Cursor, Gemini CLI, DeepSeek, OpenCode Go, Z.ai, Sparkle.
- The " · " separator stays as is in every language.
- Chinese uses full-width punctuation (，。：！？（）) and puts a half-width space between Chinese and Latin letters or digits: "API 密钥", "5 分钟".
- Never hand-write units such as "min" or "h". Durations, dates, and numbers come from the system formatters in the display language.
- Counted strings use plural variations, not "(s)" or a fixed form. Russian needs `one`, `few`, `many`, and `other` (1 минута, 2 минуты, 5 минут, 21 минута). Chinese needs only `other`. The catalog test checks the forms.
- A count that arrives as formatted text (`%@`), such as "%@ credits remaining", can't use plural variations. Phrase it so the noun doesn't agree with the number, for example "Осталось кредитов: %@".
- Russian durations arrive in the nominative ("1 минута"). Never put them after a word that needs another case ("через", "в течение", "за", "больше"). Use a colon or parentheses instead: "Время ожидания: %@", "на основе истории (%@)".
- Russian writes ё wherever it belongs: "учётные данные", "ещё", "сохранённый".
- Japanese sentences use です/ます. Buttons and menu items don't.
- Japanese puts no space between Japanese and Latin letters, digits, or placeholders: "APIキー", "5分", "%@を終了", "Macの". Google's docs add the space ("API キー"); macOS does not, and Filbert follows macOS.
- Japanese uses full-width 、。（）, but half-width ? ! and ": ", as macOS does: "残り: %@", "今すぐダウンロードしますか?".
- Japanese "try again later" is "あとでやり直してください", as in macOS and Sparkle.
- Japanese counted strings use one `other` form, like Chinese.

## Spanish: Mexico vs. Spain

| English | es-MX | es-ES |
|---|---|---|
| add | agregar | añadir |
| computer | computadora | ordenador |
| icon | ícono | icono |
| check (verify) | revisar | comprobar |
| peak hours | horas pico | horas punta |
| Settings | Configuración | Ajustes |

Guard-test deny lists (ui 31 AC1). Only unambiguous words go here. Spain also uses "configuración" as a common noun, so it is not denied in `es-ES`.

- `es-MX` denies: Ajustes, ordenador, añadir, icono (no accent), comprobar / comprueba, horas punta, vosotros verb forms, llave de API, refrescar, coste, el Mac / del Mac.
- `es-ES` denies: Configuración del Sistema, computadora, agregar, ícono, horas pico, la Mac, llave de API.
- `de-DE` denies: Sie, Ihnen, Ihr… (case-sensitive, because lowercase "sie" means "them"), nochmal.
- `ja` denies: あなた, 「 and 」, full-width ？ ！ ：, and a space between Japanese and a Latin letter or digit.
- `StringCatalogCoverageTests` enforces these lists.

## Portuguese: Brazil vs. Portugal

| English | pt-BR | pt-PT |
|---|---|---|
| connection | conexão | ligação |
| file | arquivo | ficheiro |
| screen | tela | ecrã |
| user | usuário | utilizador |
| save | salvar | guardar |
| Settings | Ajustes | Definições |
| provider | provedor | fornecedor |
| Quit | Encerrar | Sair |

## Terms

| English | de-DE | es-MX | es-ES | pt-BR | pt-PT | ru | zh-Hans | ja |
|---|---|---|---|---|---|---|---|---|
| Settings (Filbert's window) | Einstellungen | Configuración | Ajustes | Ajustes | Definições | Настройки | 设置 | 設定 |
| System Settings | Systemeinstellungen | Configuración del Sistema | Ajustes del Sistema | Ajustes do Sistema | Definições do Sistema | Системные настройки | 系统设置 | システム設定 |
| General (tab) | Allgemein | General | General | Geral | Geral | Основные | 通用 | 一般 |
| Appearance (tab) | Darstellung | Apariencia | Apariencia | Aparência | Aspeto | Оформление | 外观 | 外観 |
| Providers (tab) | Anbieter | Proveedores | Proveedores | Provedores | Fornecedores | Провайдеры | 提供商 | プロバイダ |
| AI provider | KI-Anbieter | proveedor de IA | proveedor de IA | provedor de IA | fornecedor de IA | ИИ-провайдер | AI 提供商 | AIプロバイダ |
| menu bar | Menüleiste | barra de menús | barra de menús | barra de menus | barra de menus | строка меню | 菜单栏 | メニューバー |
| Keychain | Schlüsselbund | llavero | llavero | chaves (app: Acesso às Chaves; item: item das chaves) | porta-chaves (app: Acesso a Porta-chaves; item: elemento de porta-chaves) | связка ключей | 钥匙串 | キーチェーン (app: キーチェーンアクセス) |
| API key | API-Schlüssel | clave de API | clave de API | chave de API | chave de API | ключ API | API 密钥 | APIキー |
| Refresh | Aktualisieren | Actualizar | Actualizar | Atualizar | Atualizar | Обновить | 刷新 | 更新 |
| Retry | Erneut versuchen | Reintentar | Reintentar | Tentar novamente | Tentar novamente | Повторить | 重试 | 再試行 |
| Sign in to X | Bei X anmelden | Iniciar sesión en X | Iniciar sesión en X | Iniciar sessão em X | Iniciar sessão em X | Войти в X | 登录 X | Xにサインイン |
| Launch at login | Bei der Anmeldung starten | Abrir al iniciar sesión | Abrir al iniciar sesión | Abrir ao iniciar sessão | Abrir ao iniciar sessão | Открывать при входе | 登录时打开 | ログイン時に開く |
| Login Items & Extensions | Anmeldeobjekte & Erweiterungen | Elementos de inicio y extensiones | Ítems de inicio y extensiones | Itens de Início de Sessão e Extensões | Início de sessão e extensões | Объекты входа и расширения | 登录项与扩展 | ログイン項目と機能拡張 |
| Quit | Beenden | Salir | Salir | Encerrar | Sair | Завершить | 退出 | 終了 |
| Check for Updates… | Nach Updates suchen … | Buscar actualizaciones… | Buscar actualizaciones… | Buscar atualizações… | Procurar atualizações… | Проверить обновления… | 检查更新… | アップデートを確認… |
| update (software) | Update | actualización | actualización | atualização | atualização | обновление | 更新 | アップデート |
| usage | Nutzung | uso | uso | uso | utilização | использование | 用量 | 使用量 |
| limit | Limit | límite | límite | limite | limite | лимит | 上限, 限制 | 上限 |
| quota | Kontingent | cuota | cuota | cota | quota | квота | 配额 | 割り当て |
| rate limit | Anfragelimit | límite de frecuencia | límite de frecuencia | limite de taxa | limite de taxa | ограничение частоты | 速率限制 | レート制限 |
| Limit reached | Limit erreicht | Límite alcanzado | Límite alcanzado | Limite atingido | Limite atingido | Лимит исчерпан | 已达上限 | 上限に達しました |
| reset (quota window) | zurücksetzen, Zurücksetzung | restablecer | restablecer | redefinir | repor | сбросить, сброс | 重置 | リセット |
| Rate limited | Anfragelimit erreicht | Se alcanzó el límite de solicitudes | Límite de solicitudes alcanzado | Limite de solicitações atingido | Limite de pedidos atingido | Слишком много запросов | 请求过于频繁 | レート制限されています |
| balance | Guthaben | saldo | saldo | saldo | saldo | баланс | 余额 | 残高 ⚠︎ |
| credits | Credits | créditos | créditos | créditos | créditos | кредиты | promotional or bonus: 赠金; Codex (OpenAI): 积分 | クレジット ⚠︎ |
| peak hours | Spitzenzeiten | horas pico | horas punta | horário de pico | horas de ponta | часы пик | 高峰时段 | ピーク時間帯 ⚠︎ |
| average (pace) | durchschnittlich | promedio | medio | médio ⚠︎ | médio ⚠︎ | средний ⚠︎ | 平均 ⚠︎ | 平均 |
| the Mac (article) | der Mac | la Mac | el Mac | o Mac | o Mac | Mac | Mac | Mac |
| Keep Awake | Wach halten | Mantener activo | Mantener activo | Manter ativo | Manter ativo | Не засыпать | 保持唤醒 | スリープさせない |
| System Default (language) | Systemstandard | Predeterminado del sistema | Predeterminado del sistema | Padrão do sistema | Predefinição do sistema | Системный | 跟随系统 | システムデフォルト |
| Language (setting) | Sprache | Idioma | Idioma | Idioma | Idioma | Язык | 语言 | 言語 |
| dialog (system window) | Dialog | cuadro de diálogo | cuadro de diálogo | caixa de diálogo | caixa de diálogo | диалоговое окно | 对话框 | ダイアログ |
| helper script | Hilfsskript | script auxiliar | script auxiliar | script auxiliar | script auxiliar | вспомогательный скрипт (buttons: скрипт) | 辅助脚本 | ヘルパースクリプト |
| granted balance (DeepSeek) | Gewährtes Guthaben | créditos otorgados | créditos otorgados | créditos concedidos | créditos concedidos | предоставленные кредиты | 赠金余额 | 付与残高 ⚠︎ |
| topped-up balance (DeepSeek) | Aufgeladenes Guthaben | saldo recargado | saldo recargado | recarregado | carregado | пополнено | 充值余额 | チャージ残高 ⚠︎ |
| credit rate (Z.ai peak hours) | Credit-Tarif | tarifa de créditos | tarifa de créditos | taxa de créditos | taxa de créditos | тариф | 消耗速率 ⚠︎ | クレジット消費率 ⚠︎ |
| Finder | Finder | Finder | Finder | Finder | Finder | Finder | 访达 | Finder |

### Japanese only

Terms that the other languages don't need in the table above, from the same macOS strings:

- Advanced (tab): 詳細. About (tab): 情報. Status: 状況.
- server: サーバ. interface: インターフェイス. import: 読み込む. timed out: タイムアウトしました.
- quota window: 枠 ("5時間枠"). Weekly: 週間. Monthly: 月間 ⚠︎.
- Quiet window: 静止期間 ⚠︎.

## Language names in the picker

Each language appears in its own name (ui 32 AC1): English, Deutsch, Español (México), Español (España), Português (Brasil), Português (Portugal), Русский, 简体中文, 日本語.

## Sources consulted on 2026-10-18

- du (de-DE): Apple Mac User Guide "Change the language your Mac uses" (`mh26684`) in `de-de` says "Du kannst …" and "Führe … aus".
- Login Items, System Settings, sign in: Apple Mac User Guide "Open items automatically when you log in" (`mh15189`) in `de-de`, `es-lamr`, `es-es`, `pt-br`, `pt-pt`, `ru-ru`, `zh-cn`.
- Keychain: Apple Keychain Access User Guide in `pt-br` and `pt-pt`.
- the Mac (es-MX): Apple Mac User Guide in `es-lamr` says "Apagar o reiniciar la Mac" (`mchlp1066`).
- menu bar: Apple Mac User Guide glossary in `es-lamr` and `es-es`.
- API key: Google Gemini API docs "API keys" in `ru` and `zh-cn`.
- rate limits, quota, usage, reset (zh-Hans): Google Gemini API docs "Rate limits" in `zh-cn`.
- credits (zh-Hans): Google Cloud docs and codelabs use 赠金.
- Language, dialog, the Mac, Language & Region (pt-BR, pt-PT, ru, zh-Hans): Apple Mac User Guide "Change the language your Mac uses" (`mh26684`) in `pt-br`, `pt-pt`, `ru-ru`, `zh-cn`. The `zh-cn` guide uses 你; the `pt-pt` guide uses formal imperatives ("selecione", "Aceda").
- Codex credits (zh-Hans): OpenAI's `zh-Hans-CN` pages use 积分 ("服务积分条款", the ChatGPT rate card).
- DeepSeek balances (zh-Hans): DeepSeek API docs "Get user balance" in `zh-cn` use 赠金余额 and 充值余额.
- Japanese conventions and terms: macOS 27 UI strings on the dev Mac (`.loctable` files in AppKit, System Settings, its extensions, Utilities, CoreServices, and Security). They use “…” in 2,530 strings and 「…」 in none, half-width ? and :, full-width （）, and no space before Latin text in 3,157 strings against 22. Source of システム設定, 言語と地域, 一般, 外観, ログイン項目と機能拡張, ログイン時に開く, 再試行, サインイン, 終了, アップデートを確認, 上限に達しました, レート制限されています, リセット, キーチェーンアクセス, システムデフォルト, スリープさせない, プロバイダ, ヘルパーツール, スクリプト, 平均.
- Japanese tone, Language, dialog, the Mac: Apple Mac User Guide "Change the language your Mac uses" (`mh26684`) and "Open items automatically when you log in" (`mh15189`) in `ja-jp`. Both write "Macの", omit the subject, and use です/ます.
- Sparkle's own `ja` strings: "アップデートを確認できませんでした", "あとでやり直してください", "%@をアップデート中".
- API key, quota, usage, rate limit (ja): Google Gemini API docs "API keys" and "Rate limits" with `hl=ja` (APIキー, 割り当て, 使用量, レート制限).
- No Japanese vendor source was found for credits, balance, peak hours, or the DeepSeek and Z.ai terms. A search found no official Japanese page from OpenAI, DeepSeek, or Z.ai. These keep ⚠︎ for the native review.
