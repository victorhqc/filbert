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
- Chinese uses full-width punctuation (，。：！？（）) and puts a half-width space between Chinese and Latin letters or digits: "API 密钥", "5 分钟". The space goes only next to Latin letters or digits, never between two Chinese characters. A placeholder whose text starts with a digit gets a space before it. A placeholder whose text ends in a Chinese unit gets no space after it: "请在 %@后重试" → "请在 5分钟后重试", "每隔 %@检查一次" → "每隔 5 分钟检查一次", "%@后重置" → "2小时后重置". Foundation's durations and relative dates have no inner space ("5分钟", "1天2小时", "2小时后"); catalog durations do ("5 分钟"). Both are correct.
- Chinese puts a feature name in “…” when it appears inside a sentence: "无法启用“登录时打开”".
- Never hand-write units such as "min" or "h". Durations, dates, and numbers come from the system formatters in the display language.
- Counted strings use plural variations, not "(s)" or a fixed form. Russian needs `one`, `few`, `many`, and `other` (1 минута, 2 минуты, 5 минут, 21 минута). Chinese needs only `other`. The catalog test checks the forms.
- A count that arrives as formatted text (`%@`), such as "%@ credits remaining", can't use plural variations. Phrase it so the noun doesn't agree with the number, for example "Осталось кредитов: %@".
- Formatted durations can be singular, plural, or compound. Spanish uses neutral labels such as "Tiempo restante: %@" and "Tiempo de uso restante: aprox. %@", not fixed "restantes" or "quedan". Portuguese currency balances use "saldo restante: %@".
- Spanish never puts a word before a duration that must agree with its number ("otros %@", "pasados %@", "unas %@"). Use "%@ más" or "al cabo de %@": "durante %3$@ más".
- Short status rows put the number first, so tail truncation keeps it: "19.6%/día disponible aprox." (es), "Ca. 19,6 %/Tag verfügbar" (de), "~19,6 %/день доступно" (ru), "约 19.6%/天可用" (zh-Hans), "約19.6%/日を利用可能" (ja). Use the short "about" marker: aprox., ca., ~, 约, 約.
- Reset countdowns receive the time left as one nominative duration ("2 hours", "6 days"), not a relative date. The template reads alone, after "15 % · ", after "Limit reached · ", and in "%1$@ limit reached, %2$@". de-DE "noch %@ bis zum Zurücksetzen" (never after "in", which needs the dative). es-ES and es-MX "%@ para restablecerse", and "restableciéndose…" while a reset is in progress. pt-BR "redefinição em %@". pt-PT "repõe-se dentro de %@". ru "до сброса %@" (the duration is the subject; never "через %@"). zh-Hans "%@后重置". ja "リセットまであと%@" (あと keeps "6日" from reading as the 6th of the month).
- es-ES writes "informar de algo", never transitive "informar algo". For a provider that reports nothing, write "No se han indicado límites de uso".
- es-MX uses "reposo" only for Mac sleep, never for a Filbert setting.
- pt-BR writes the minimum check interval as "no máximo uma verificação a cada %@". "verifica no máximo a cada %@" reads as a maximum interval.
- pt-PT writes "Runs out in about %@" as "Esgota-se em cerca de %@", not "dentro de cerca de" (two stacked prepositions).
- Portuguese puts the article before provider names in templates ("o %@", "pelo %@"), because every provider name is masculine.
- Russian durations arrive in the nominative ("1 минута"). Never put them after a word that needs another case ("через", "в течение", "за", "больше", "около"). Use "примерно", a colon, or parentheses instead: "До исчерпания: примерно %@", "на основе истории (%@)". The rule also covers "осталось": write "Осталось использования: примерно %@" or "До конца …: %@", never "осталось %@", because "осталось 1 час" and "осталось 21 минута" don't agree.
- German standalone durations cannot acquire case endings during interpolation. Use "Reicht noch etwa %@" (accusative of duration, identical to the nominative for Tag, Stunde, Minute, Woche), not "in etwa %@" with a duration such as "2 Tage".
- German refresh intervals use "im Abstand von %@", not "alle %@": a 1-minute value would read "alle 1 Minute".
- German never builds a compound from a provider-name placeholder. "%@-Kontingent" gives "Claude Code-Kontingent", which breaks the Duden hyphenation rule. Use "Kontingent bei %@" or "Nutzung von %@".
- German "Wird geladen …" keeps the space before the ellipsis, as in menu items.
- "Keep checking for %@" receives a provider name, not a duration.
- "Refresh" in provider errors means refreshing usage data, not a software update of the provider. Name the data: de-DE "die Claude-Code-Nutzungsdaten aktualisieren", es-MX "actualizar los datos de X" (never "la actualización de X"), es-ES "actualizar los datos de X" ("Actualización de Claude Code" on its own is a software update), pt-BR and pt-PT "atualização dos dados do X" (never "atualização do X"), ru "обновить данные об использовании X", zh-Hans "X 用量数据刷新", ja "Xの使用量データを更新" (never a bare "Xの更新").
- An API-key failure is an authentication failure, not a sign-in failure: de-DE "Authentifizierung fehlgeschlagen", es-MX "Falló la autenticación" (never "No se pudo iniciar sesión"), es-ES "Error de autenticación" (never "No se ha podido iniciar sesión"), pt-BR and pt-PT "Falha na autenticação", ru "Ошибка аутентификации", zh-Hans "认证失败", ja "認証に失敗しました".
- A rate-limit sentence states the limit. It never blames the user ("Hiciste demasiadas solicitudes"). "Rate limited. Try again later." is: de-DE "Anfragelimit erreicht. Versuche es später erneut.", es-MX "Se alcanzó el límite de solicitudes. Inténtalo más tarde.", es-ES "Límite de solicitudes alcanzado. Inténtalo de nuevo más tarde.", pt-BR "Limite de solicitações atingido. Tente novamente mais tarde.", pt-PT "Limite de pedidos atingido. Tente novamente mais tarde.", ru "Достигнут лимит запросов. Повторите попытку позже.", zh-Hans "请求过于频繁。请稍后重试。" (the standard neutral Chinese message), ja "リクエストの上限に達しました。あとでやり直してください。".
- Pace status ("Within / Over current allowance") describes pace, not a used-up quota. Don't use the quota term in it: no "cota" (pt-BR), "quota" (pt-PT), "квота" (ru), 配额 (zh-Hans), or 枠 (ja, where 枠 means the quota window).
- German and Spain Spanish put a space before the percent sign ("25 %"). Mexican Spanish does not ("25%"), because Foundation's `es-MX` and `es-419` percent format omits it and Filbert shows both side by side. In format strings, keep the literal-percent escape: "%lld %%" (de-DE, es-ES), "%lld%%" (es-MX).
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
| sleep / wake (Mac) | repouso, entrar em repouso | modo de pausa, entrar em pausa / reativar |

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
| Keychain | Schlüsselbund | llavero | llavero (item: ítem del llavero) | chaves (app: Acesso às Chaves; item: item das chaves) | porta-chaves (app: Acesso a Porta-chaves; item: elemento de porta-chaves) | связка ключей | 钥匙串 (item: 钥匙串项) | キーチェーン (app: キーチェーンアクセス) |
| API key | API-Schlüssel | clave de API | clave de API | chave de API | chave de API | ключ API | API 密钥 | APIキー |
| Authentication failed (API key) | Authentifizierung fehlgeschlagen | Falló la autenticación | Error de autenticación | Falha na autenticação | Falha na autenticação | Ошибка аутентификации | 认证失败 | 認証に失敗しました |
| credential type (internal error) | Typ der Anmeldedaten | tipo de credencial | tipo de credencial | tipo de credencial | tipo de credencial | тип учётных данных | 凭证类型 | 認証情報の種類 |
| Refresh | Aktualisieren | Actualizar | Actualizar | Atualizar | Atualizar | Обновить | 刷新 | 更新 |
| Retry | Erneut versuchen | Reintentar | Reintentar | Tentar novamente | Tentar novamente | Повторить | 重试 | 再試行 |
| Sign in to X | Bei X anmelden | Iniciar sesión en X | Iniciar sesión en X | Iniciar sessão em X | Iniciar sessão em X | Войти в X | 登录 X | Xにサインイン |
| Launch at login | Bei der Anmeldung starten | Abrir al iniciar sesión | Abrir al iniciar sesión | Abrir ao iniciar sessão | Abrir ao iniciar sessão | Открывать при входе | 登录时打开 | ログイン時に開く |
| Login Items & Extensions | Anmeldeobjekte & Erweiterungen | Elementos de inicio y extensiones | Ítems de inicio y extensiones | Itens de Início de Sessão e Extensões | Início de sessão e extensões | Объекты входа и расширения | 登录项与扩展 | ログイン項目と機能拡張 |
| Quit | Beenden | Salir | Salir | Encerrar | Sair | Завершить | 退出 | 終了 |
| Check for Updates… | Nach Updates suchen … | Buscar actualizaciones… | Buscar actualizaciones… | Buscar atualizações… | Procurar atualizações… | Проверить обновления… | 检查更新… | アップデートを確認… |
| update (software) | Update | actualización | actualización | atualização | atualização | обновление | 更新 | アップデート |
| Update (install button) | Installieren (not "Aktualisieren", which is Refresh) | Actualizar | Actualizar | Atualizar | Atualizar | Обновить | 更新 | アップデート |
| usage | Nutzung | uso | uso | uso | utilização | использование | 用量 | 使用量 |
| limit | Limit | límite | límite | limite | limite | лимит | 上限, 限制 | 上限 |
| quota | Kontingent | cuota | cuota | cota | quota | квота | 配额 | 割り当て |
| rate limit | Anfragelimit | límite de frecuencia | límite de frecuencia | limite de taxa | limite de taxa | ограничение частоты | 速率限制 | レート制限 |
| Limit reached | Limit erreicht | Límite alcanzado | Límite alcanzado | Limite atingido | Limite atingido | Лимит исчерпан | 已达上限 | 上限に達しました |
| reset (quota window) | zurücksetzen, bis zum Zurücksetzen | restablecer | restablecer | redefinir | repor | сбросить, сброс | 重置 | リセット |
| resetting… (quota) | wird zurückgesetzt… | restableciéndose… | restableciéndose… | redefinindo… | a repor… | сброс… | 正在重置… | リセット中… |
| Rate limited | Anfragelimit erreicht | Se alcanzó el límite de solicitudes | Límite de solicitudes alcanzado | Limite de solicitações atingido | Limite de pedidos atingido | Слишком много запросов (label), Достигнут лимит запросов (sentence) | 请求过于频繁 | リクエストの上限に達しました |
| balance | Guthaben | saldo | saldo | saldo | saldo | баланс | 余额 | 残高 |
| credits | Credits | créditos | créditos | créditos | créditos | кредиты | promotional or bonus: 赠金; Codex (OpenAI): 额度; Z.ai usage credits: 积分 | クレジット |
| peak hours | Spitzenzeiten | horas pico | horas punta | horário de pico | horas de ponta | часы пик | 高峰时段 (off-peak: 非高峰时段) | ピーク時間帯 |
| average (pace) | durchschnittlich | promedio | medio | médio | médio | средний | 平均 | 平均 |
| pace status (Within / Over current allowance) | Verbrauch im Plan / Verbrauch über Plan | Dentro del ritmo disponible / Por encima del ritmo disponible | Dentro del ritmo previsto / Por encima del ritmo previsto | Dentro do ritmo sustentável / Acima do ritmo sustentável | Dentro do ritmo previsto / Acima do ritmo previsto | Темп в пределах нормы / Темп выше нормы | 用量未超出当前进度 / 用量超出当前进度 | 想定ペース内 / 想定ペースを超過 |
| the Mac (article) | der Mac | la Mac | el Mac | o Mac | o Mac | Mac | Mac | Mac |
| Keep Awake | Wach halten | Mantener activo | Mantener activo | Manter ativo | Manter ativo | Не засыпать | 保持唤醒 | スリープさせない |
| System Default (language) | Systemstandard | Predeterminado del sistema | Predeterminado del sistema | Padrão do sistema | Predefinição do sistema | Системный | 跟随系统 | システムデフォルト |
| Language (setting) | Sprache | Idioma | Idioma | Idioma | Idioma | Язык | 语言 | 言語 |
| dialog (system window) | Dialog | cuadro de diálogo | cuadro de diálogo | caixa de diálogo | caixa de diálogo | диалоговое окно | 对话框 | ダイアログ |
| helper script | Hilfsskript | script auxiliar | script auxiliar | script auxiliar | script auxiliar | вспомогательный скрипт (buttons: скрипт) | 辅助脚本 | ヘルパースクリプト |
| Fast-check duration (how long fast checks continue after a usage change, not a pause) | Dauer schneller Prüfungen | Duración de consultas rápidas | Duración de consultas rápidas | Duração das verificações rápidas | Duração das verificações rápidas | Длительность быстрых проверок | 快速检查时长 | 高速確認の継続時間 |
| Stop fast checks | Schnelle Prüfungen beenden | Detener consultas rápidas | Detener consultas rápidas | Parar verificações rápidas | Parar verificações rápidas | Остановить быстрые проверки | 停止快速检查 | 高速確認を停止 |
| local time ("%@ (your time)") | (Ortszeit) | (hora local) | (hora local) | (seu horário) | (hora local) | (по вашему времени) | （本地时间） | （現地時間） |
| Use Default (base URL) | Standard verwenden | Usar URL predeterminada | Usar URL por defecto | Usar padrão | Usar predefinição | Вернуть стандартный URL | 使用默认值 | デフォルトを使用 |
| Low below / OK at or above (balance thresholds) | Niedrig unter / OK ab | Bajo: menos de / Suficiente: desde | Bajo si es inferior a / Correcto a partir de | Baixo se menor que / OK a partir de | Baixo se inferior a / OK a partir de | Низкий — ниже / Норма — от | 偏低阈值 / 正常阈值 | 低残高: この値未満 / 十分な残高: この値以上 |
| Included usage (Cursor) | Enthaltene Nutzung | Uso incluido | Uso incluido | Uso incluído | Utilização incluída | Включённое использование | 包含用量 | プランに含まれる使用量 |
| on-demand spend (Cursor) | On-Demand-Ausgaben | gasto bajo demanda | gasto bajo demanda | gastos sob demanda | gastos a pedido | дополнительные расходы | 按需支出 | オンデマンドの支出 |
| pooled spend (Cursor) | gemeinsame Ausgaben | gasto compartido | gasto compartido | gastos compartilhados | gastos partilhados | расходы общего пула | 共享支出 | 共有の支出 |
| granted balance (DeepSeek) | Gewährtes Guthaben | créditos otorgados | créditos otorgados | créditos concedidos | créditos concedidos | бонусный баланс ⚠︎ | 赠金余额 | 付与残高 ⚠︎ |
| topped-up balance (DeepSeek) | Aufgeladenes Guthaben | saldo recargado | saldo recargado | recarregado | carregado | пополнено | 充值余额 | チャージ残高 ⚠︎ |
| credit rate (Z.ai peak hours) | Credit-Tarif (percentage: "%@ des Standard-Credit-Tarifs") | tarifa de créditos | tarifa de créditos | taxa de créditos (percentage: "%@ da taxa de créditos padrão") | taxa de créditos | тариф | 积分消耗 (percentage: "按标准的 %@ 消耗积分") | クレジット消費率 (percentage: "クレジット消費率: 標準の%@") |
| peak multiplier ("3×") | "%lld× Multiplikator" | "Multiplicador %lld×" | "Multiplicador %lld×" | "Multiplicador %lld×" | "Multiplicador %lld×" | "Множитель %lld×" | "%lld 倍" | "%lld倍", not "×" |
| Finder | Finder | Finder | Finder | Finder | Finder | Finder | 访达 | Finder |

### Japanese only

Terms that the other languages don't need in the table above, from the same macOS strings:

- Advanced (tab): 詳細. About (tab): 情報. Status: 状況.
- server: サーバ. interface: インターフェイス. import: 読み込む. timed out: タイムアウトしました.
- Re-import: もう一度読み込む. Don't use 再読み込み, because macOS uses it for Reload.
- quota window: 枠 ("5時間枠"). Weekly: 週間. Monthly: 月間.
- Fast checks are always 高速確認, never 高速更新.
- Disclosure state (VoiceOver): 折りたたまれています / 展開されています. Actions: 折りたたむ / 展開する.
- "%@ limit reached": "%@: 上限に達しました". With a reset date, use a new sentence: "%1$@の上限に達しました。%2$@".
- Cursor's named Auto mode: Auto, not 自動.

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
- Codex credits (zh-Hans): OpenAI's product-specific credit-usage help uses 额度, 额度余额, and 剩余额度. Prefer these to the broader service-credit translation 积分.
- DeepSeek balances (zh-Hans): DeepSeek API docs "Get user balance" in `zh-cn` use 赠金余额 and 充值余额.
- Japanese conventions and terms: macOS 27 UI strings on the dev Mac (`.loctable` files in AppKit, System Settings, its extensions, Utilities, CoreServices, and Security). They use “…” in 2,530 strings and 「…」 in none, half-width ? and :, full-width （）, and no space before Latin text in 3,157 strings against 22. Source of システム設定, 言語と地域, 一般, 外観, ログイン項目と機能拡張, ログイン時に開く, 再試行, サインイン, 終了, アップデートを確認, 上限に達しました, レート制限されています, リセット, キーチェーンアクセス, システムデフォルト, スリープさせない, プロバイダ, ヘルパーツール, スクリプト, 平均.
- Japanese tone, Language, dialog, the Mac: Apple Mac User Guide "Change the language your Mac uses" (`mh26684`) and "Open items automatically when you log in" (`mh15189`) in `ja-jp`. Both write "Macの", omit the subject, and use です/ます.
- Sparkle's own `ja` strings: "アップデートを確認できませんでした", "あとでやり直してください", "%@をアップデート中".
- API key, quota, usage, rate limit (ja): Google Gemini API docs "API keys" and "Rate limits" with `hl=ja` (APIキー, 割り当て, 使用量, レート制限).
- OpenAI's Japanese credit-usage help confirms クレジット, 残高, and クレジット残高. The native review confirmed 月間 and クレジット消費率. No Japanese vendor source was established for the DeepSeek balance terms; these keep ⚠︎.
- 週間 (ja): Anthropic help "使用制限のベストプラクティス" (support.claude.com/ja/articles/9797557) uses 週間制限. OpenAI help (help.openai.com/ja-jp/articles/20001507) uses 週間レート制限.
- ピーク時間帯 (ja): the standard term in Japanese coverage of Anthropic's peak-hour change (innovatopia.jp/ai/ai-news/90568). No first-party vendor page was found.
- Collapsed / Expanded, Use Default, Reload (ja): macOS 27 `.loctable` strings: 折りたたまれています, 展開されています, デフォルトを使用 (8×), Reload → 再読み込み (10×).
- Keychain item, authentication error, "Inténtalo de nuevo más tarde" (es-ES): macOS 27 `es` UI strings (`.loctable` in Security, AppKit, System Settings and its extensions). "ítem(s) del llavero" appears 25 times and "elemento del llavero" never. "Error de autenticación. Comprueba tu nombre de usuario y contraseña…" appears 27 times.
- informar (es-ES): RAE, *Diccionario panhispánico de dudas*, s.v. "informar". Spain uses "informar de algo". Transitive "informar algo" is American usage.
- Percent sign (es-MX): Foundation `es-MX`/`es-419` percent format gives "50%" and `es-ES` gives "50 %". Apple `es-lamr` writes "al 100%" (support.apple.com/es-lamr/102338).
- Sleep (es-MX): Apple Mac User Guide in `es-lamr` "Poner la Mac en reposo o sacarla de reposo" (`mh10330`).
- reset, quota, requests (pt-BR): Google Gemini API docs "Rate limits" with `hl=pt-br`: "As cotas de solicitações por dia (RPD) são redefinidas à meia-noite do horário do Pacífico."
- Sleep (pt-BR): Apple Mac User Guide (`mchle41a6ccd`) in `pt-br`: "Impedir o repouso automático…".
- Extensões (pt-BR): Apple's "Itens de Início de Sessão e Extensões" uses "extensão" for app extensions, so Filbert does not use it for a longer fast-check period.
- Sleep (pt-PT): Apple Mac User Guide "Especificar definições para o modo de pausa e reativação do Mac" (`mchle41a6ccd`) in `pt-pt`: "modo de pausa", "Reativar".
- Login items, keychain items (pt-PT), re-confirmed: Apple `mh15189` in `pt-pt` ("Início de sessão e extensões", "elemento de início de sessão") and Keychain Access `kyca1083` in `pt-pt` ("elementos de porta-chaves", "Acesso a Porta‑chaves").
- Cursor terms (ru): Cursor pricing docs `cursor.com/ru/docs/account/pricing` use «Включённое использование», «дополнительное использование» (current plans; «по требованию» only for legacy plans), and «общий пул».
- credits, usage limits (ru): OpenAI help in `ru-ru` (articles 11369540 "Using Codex with your ChatGPT plan" and 12642688 "Using credits…") use «кредиты» and «лимиты использования».
- Peak hours, off-peak, multiplier (zh-Hans): Z.ai Coding Plan docs (`docs.bigmodel.cn/cn/coding-plan/overview`): "高峰时段：每周一至周五的 14:00～18:00", "非高峰时段", "按 1 倍积分消耗", "按 0.5 倍积分消耗".

## Language-review references

- [OpenAI credit usage, Simplified Chinese](https://help.openai.com/zh-hans-cn/articles/12642688-using-credits-for-flexible-usage-in-chatgpt-freegopluspro-sora): Codex usage credits are 额度; the 额度余额 is distinct from the monetary wallet balance.
- [OpenAI credit usage, Japanese](https://help.openai.com/ja-jp/articles/12642688-using-credits-for-flexible-usage-in-chatgpt-personal-plans): クレジット, 残高, クレジット残高.
- [Z.ai Coding Plan, Chinese](https://docs.bigmodel.cn/cn/coding-plan/overview): "非高峰时段内，模型调用按基础积分消耗的 50% 抵扣". The percentage is a charge factor, not consumption per unit of time.
- [Cursor models, Japanese](https://cursor.com/ja/docs/models): "Auto モード".
- [Apple Keychain Access, Simplified Chinese](https://support.apple.com/zh-cn/guide/keychain-access/kyca1083/mac): "钥匙串项".
- [Google Gemini rate limits, Latin American Spanish](https://ai.google.dev/gemini-api/docs/rate-limits?hl=es-419): "límites de frecuencia" and "Si alcanzas un límite de frecuencia…".
- [RAE/ASALE, símbolo](https://www.rae.es/dpd/s%C3%ADmbolo): the percent sign is preceded by a space, as in "25 %".
