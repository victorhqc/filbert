# Localization glossary

Every translation in a `Localizable.xcstrings` catalog follows this glossary.

## Sources of truth

When in doubt, use the term that the vendor uses in its own localized docs. Check in this order:

1. Apple's localized macOS help, for macOS terms: `support.apple.com/<locale>/guide/mac-help/...`. Locales: `de-de`, `es-lamr` (Latin America, use for `es-MX`), `es-es`, `pt-br`, `pt-pt`, `ru-ru`, `zh-cn`, `zh-tw`, `ja-jp`.
   For Japanese and Traditional Chinese, macOS's own UI strings come first. They live in the `.loctable` files under `/System`, and their style differs from Apple's help pages.
2. Google's localized developer docs, for API terms: `ai.google.dev/...?hl=<locale>`.
3. The provider's own localized UI or docs, for provider-specific terms. Z.ai and DeepSeek have Simplified Chinese UIs only.

Traditional Chinese (`zh-Hant`) follows Taiwan usage and its own source order in (ui 36) Plan step 1: the platform that owns the term in `zh-TW`, then another major platform in `zh-TW` (Apple, Google, Microsoft, OpenAI, Anthropic), then Taiwan usage (NAER `terms.naer.edu.tw`, Taiwan media), then Hong Kong. A Simplified page gives only the meaning, never the wording.

Record new terms here with the source. **⚠︎** marks a term that no source has confirmed yet.

## Conventions

| | de-DE | es-MX | es-ES | pt-BR | pt-PT | ru | zh-Hans | zh-Hant | ja |
|---|---|---|---|---|---|---|---|---|---|
| Address the user | du | tú | tú | você, omitted where possible | formal imperative ("Verifique"), no "tu" | вы, lowercase | 你 (as macOS) | 你 (as macOS), never 您 | omitted, never あなた (as macOS) |
| Recent past | Perfekt | simple past: "No se pudo", "falló" | present perfect: "No se ha podido", "ha fallado" | simple past: "falhou" | simple past: "falhou" | perfective past | 了 / 失败 | "無法…", "…失敗" (as macOS: "認證失敗") | polite past: "できませんでした", "失敗しました" |
| Ongoing action | "wird geladen" | gerund: "cargando" | gerund: "cargando" | gerund: "carregando" | a + infinitive: "a carregar" | present | 正在… | 正在… or …中: "正在下載⋯", "載入中⋯" | …中: "読み込み中…" |
| Buttons, menu items | infinitive | infinitive | infinitive | infinitive | infinitive | infinitive | verb | verb phrase: "檢查更新項目⋯", "結束Filbert" | noun or plain verb phrase: "アップデートを確認", "Filbertを終了" |
| Instructions in a sentence | imperative | imperative | imperative | imperative | imperative | imperative | verb | 請…: "請檢查…，然後再試一次。" | …してください |
| Quotes | „…“ | “…” | «…» | “…” | «…» | «…» | “…” | 「…」 | “…” |
| Ellipsis in menu items | "Einstellungen …" (space) | "…" | "…" | "…" | "…" | "…" | "…" | "⋯" (U+22EF, as macOS) | "…" |

- Sentence case everywhere. German nouns keep their capital letter.
- Product names stay in English: Filbert, Claude Code, Codex, Cursor, Gemini CLI, DeepSeek, OpenCode Go, Z.ai, Sparkle.
- The " · " separator stays as is in every language.
- Simplified Chinese uses full-width punctuation (，。：！？（）) and puts a half-width space between Chinese and Latin letters or digits: "API 密钥", "5 分钟". The space goes only next to Latin letters or digits, never between two Chinese characters. A placeholder whose text starts with a digit gets a space before it. A placeholder whose text ends in a Chinese unit gets no space after it: "请在 %@后重试" → "请在 5分钟后重试", "每隔 %@检查一次" → "每隔 5 分钟检查一次", "%@后重置" → "2小时后重置". Foundation's durations and relative dates have no inner space ("5分钟", "1天2小时", "2小时后"); catalog durations do ("5 分钟"). Both are correct.
- Simplified Chinese puts a feature name in “…” when it appears inside a sentence: "无法启用“登录时打开”".
- Never hand-write units such as "min" or "h". Durations, dates, and numbers come from the system formatters in the display language.
- Short durations never use weeks. Seven days or more show days ("9d", "9日", "9 д."), because the week unit renders as a Latin "w" in Japanese.
- Usage-check intervals come from the plural keys `every %lld seconds` and `every %lld minutes`. The phrase includes the "every" word, so templates insert it as is and never add their own: de-DE "jede Minute" / "alle %lld Minuten", es-ES and es-MX "cada minuto" / "cada %lld minutos", pt-BR and pt-PT "a cada minuto" / "a cada %lld minutos", ru "раз в %lld минуту/минуты/минут", zh-Hans "每 %lld 分钟", zh-Hant "每%lld分鐘", ja "%lld分ごと" (templates add に). Only languages whose `one` category holds just 1 (en, de-DE, es-ES, es-MX, pt-BR, pt-PT) may drop the number from the `one` form. Russian `one` also holds 21, so it uses "раз в", never "каждую минуту". Chinese and Japanese have one form, so 1 minute reads "每 1 分钟", "每1分鐘", and "1分ごと".
- Ranges of weekdays or clock times use the `Range format` key: "%1$@–%2$@" in most languages, zh-Hans "%1$@至%2$@" ("周一至周五"), zh-Hant "%1$@至%2$@" ("週一至週五"), ja "%1$@〜%2$@" with U+301C ("月〜金"), as macOS writes it.
- Counted strings use plural variations, not "(s)" or a fixed form. Russian needs `one`, `few`, `many`, and `other` (1 минута, 2 минуты, 5 минут, 21 минута). Chinese needs only `other`. The catalog test checks the forms.
- A count that arrives as formatted text (`%@`), such as "%@ credits remaining", can't use plural variations. Phrase it so the noun doesn't agree with the number, for example "Осталось кредитов: %@".
- Formatted durations can be singular, plural, or compound. Spanish uses neutral labels such as "Tiempo restante: %@" and "Tiempo de uso restante: aprox. %@", not fixed "restantes" or "quedan". Portuguese currency balances use "saldo restante: %@".
- Spanish never puts a word before a duration that must agree with its number ("otros %@", "pasados %@", "unas %@"). Use "%@ más" or "al cabo de %@": "durante %3$@ más".
- Short status rows put the number first, so tail truncation keeps it: "19.6%/día disponible aprox." (es), "Ca. 19,6 %/Tag verfügbar" (de), "~19,6 %/день доступно" (ru), "约 19.6%/天可用" (zh-Hans), "約19.6%/天可用" (zh-Hant), "約19.6%/日を利用可能" (ja). Use the short "about" marker: aprox., ca., ~, 约 (zh-Hans), 約 (zh-Hant, ja).
- Reset countdowns receive the time left as one nominative duration ("2 hours", "6 days"), not a relative date. The template reads alone, after "15 % · ", after "Limit reached · ", and in "%1$@ limit reached, %2$@". de-DE "noch %@ bis zum Zurücksetzen" (never after "in", which needs the dative). es-ES and es-MX "%@ para restablecerse", and "restableciéndose…" while a reset is in progress. pt-BR "redefinição em %@". pt-PT "repõe-se dentro de %@". ru "до сброса %@" (the duration is the subject; never "через %@"). zh-Hans "%@后重置". zh-Hant "%@後重設" ("2小時後重設"). ja "リセットまであと%@" (あと keeps "6日" from reading as the 6th of the month).
- es-ES writes "informar de algo", never transitive "informar algo". For a provider that reports nothing, write "No se han indicado límites de uso".
- es-MX uses "reposo" only for Mac sleep, never for a Filbert setting.
- pt-PT writes "Runs out in about %@" as "Esgota-se em cerca de %@", not "dentro de cerca de" (two stacked prepositions).
- Portuguese puts the article before provider names in templates ("o %@", "pelo %@"), because every provider name is masculine.
- Russian durations arrive in the nominative ("1 минута"). Never put them after a word that needs another case ("через", "в течение", "за", "больше", "около"). Use "примерно", a colon, or parentheses instead: "До исчерпания: примерно %@", "на основе истории (%@)". The rule also covers "осталось": write "Осталось использования: примерно %@" or "До конца …: %@", never "осталось %@", because "осталось 1 час" and "осталось 21 минута" don't agree.
- German standalone durations cannot acquire case endings during interpolation. Use "Reicht noch etwa %@" (accusative of duration, identical to the nominative for Tag, Stunde, Minute, Woche), not "in etwa %@" with a duration such as "2 Tage".
- German never builds a compound from a provider-name placeholder. "%@-Kontingent" gives "Claude Code-Kontingent", which breaks the Duden hyphenation rule. Use "Kontingent bei %@" or "Nutzung von %@".
- German "Wird geladen …" keeps the space before the ellipsis, as in menu items.
- "Keep checking for %@" receives a provider name, not a duration.
- A usage check reads and shows usage data. It is never a software update, so it never uses the word that Filbert's update strings use: de-DE Update or Aktualisierung, es-ES and es-MX actualización, pt-BR and pt-PT atualização, ru обновление or обновить, zh-Hans and zh-Hant 更新, ja 更新 or アップデート. In provider errors, name what was checked: de-DE "die Nutzung von Claude Code prüfen", es-ES and es-MX "consultar el uso de X", pt-BR "verificar o uso do X", pt-PT "verificar a utilização do X", ru "проверить использование X", zh-Hans "检查 X 用量", zh-Hant "檢查X的用量", ja "Xの使用量を確認". Translations carry the meaning of the English, in the language's own idiom, not word for word.
- An API-key failure is an authentication failure, not a sign-in failure: de-DE "Authentifizierung fehlgeschlagen", es-MX "Falló la autenticación" (never "No se pudo iniciar sesión"), es-ES "Error de autenticación" (never "No se ha podido iniciar sesión"), pt-BR and pt-PT "Falha na autenticação", ru "Ошибка аутентификации", zh-Hans "认证失败", zh-Hant "認證失敗", ja "認証に失敗しました".
- A rate-limit sentence states the limit. It never blames the user ("Hiciste demasiadas solicitudes"). "Rate limited. Try again later." is: de-DE "Anfragelimit erreicht. Versuche es später erneut.", es-MX "Se alcanzó el límite de solicitudes. Inténtalo más tarde.", es-ES "Límite de solicitudes alcanzado. Inténtalo de nuevo más tarde.", pt-BR "Limite de solicitações atingido. Tente novamente mais tarde.", pt-PT "Limite de pedidos atingido. Tente novamente mais tarde.", ru "Достигнут лимит запросов. Повторите попытку позже.", zh-Hans "请求过于频繁。请稍后重试。" (the standard neutral Chinese message), zh-Hant "已達速率限制。請稍後再試一次。", ja "リクエストの上限に達しました。あとでやり直してください。".
- Pace status ("Within / Over current allowance") describes pace, not a used-up quota. Don't use the quota term in it: no "cota" (pt-BR), "quota" (pt-PT), "квота" (ru), 配额 (zh-Hans), 配額 (zh-Hant), or 枠 (ja, where 枠 means the quota window).
- German and Spain Spanish put a space before the percent sign ("25 %"). Mexican Spanish does not ("25%"), because Foundation's `es-MX` and `es-419` percent format omits it and Filbert shows both side by side. In format strings, keep the literal-percent escape: "%lld %%" (de-DE, es-ES), "%lld%%" (es-MX).
- Russian writes ё wherever it belongs: "учётные данные", "ещё", "сохранённый".
- Japanese sentences use です/ます. Buttons and menu items don't.
- Japanese puts no space between Japanese and Latin letters, digits, or placeholders: "APIキー", "5分", "%@を終了", "Macの". Google's docs add the space ("API キー"); macOS does not, and Filbert follows macOS.
- Japanese uses full-width 、。（）, but half-width ? ! and ": ", as macOS does: "残り: %@", "今すぐダウンロードしますか?".
- Japanese "try again later" is "あとでやり直してください", as in macOS and Sparkle.
- Japanese counted strings use one `other` form, like Chinese.
- Traditional Chinese follows macOS's own `zh_TW` UI strings, not Apple's help pages or the `zh-Hans` column. macOS writes 「…」 quotes (2,216 strings, “…” in 1), the ⋯ ellipsis (745 strings, … in 1), full-width ，。：？！（）, and no space between Chinese and Latin letters, digits, or placeholders (2,450 strings, against 7): "API金鑰", "5分鐘", "結束Filbert", "%@後重設". Apple's `zh-tw` help pages and Microsoft add the space ("在 Mac 上"); Filbert follows the UI, as it does for Japanese.
- Traditional Chinese puts app, feature, and setting names in 「…」 inside a sentence, as macOS does: "打開「系統設定」", "無法開啟「登入時打開」".
- Traditional Chinese uses Taiwan vocabulary, never a character conversion of `zh-Hans`. Write each value from English. 设置 converts to 設置, but Taiwan says 設定.
- Traditional Chinese counted strings use one `other` form: "%lld分鐘", "%lld小時時段".
- Traditional Chinese "try again" is 再試一次, and "try again later" is "請稍後再試一次", as macOS and Sparkle write them.

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
- `zh-Hant` denies mainland terms: 設置, 默認, 菜單, 軟件, 信息, 網絡, 賬號, 賬戶, 屏幕, 程序, 數據, 服務器, 接口, 登錄, 質量, 優化, 鏈接, 用戶, 保存, 加載, 刷新, 充值, 窗口, 提供商, 密鑰, 激活, 運行, 實時, 在線, 緩存, 圖標, 智能, 按需, 點擊, 鑰匙串, 您. It also denies “ and ”, … (U+2026), half-width , ? ! : ; ( ) next to a Chinese character, and a space between Chinese and a Latin letter, digit, or placeholder. `testTraditionalChineseHasNoSimplifiedCharacters` fails on any value that the ICU `Hans-Hant` transform changes.
- `zh-Hant` review-only terms, because Taiwan also uses them correctly: 文件 (Taiwan: a document; never a file, which is 檔案), 項目 (Taiwan: an item, as in 鑰匙圈項目; never a project, which is 專案), 支持 (never for technical support, which is 支援), 通過 (never for "via", which is 透過).
- `zh-Hant` soft terms, allowed but not preferred: 重置 (use 重設 for a quota), 請求 (use 要求), 閾值 and 臨界值 (use 門檻), 高峰 (use 尖峰), 本地時間 and 當地時間 (for the user's own time, write 你的時區). Taiwan sources also use them, so the test does not deny them.
- `Hans-Hant` exceptions: none yet. Each exception needs a source here before the test accepts it.
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

| English | de-DE | es-MX | es-ES | pt-BR | pt-PT | ru | zh-Hans | zh-Hant | ja |
|---|---|---|---|---|---|---|---|---|---|
| Settings (Filbert's window) | Einstellungen | Configuración | Ajustes | Ajustes | Definições | Настройки | 设置 | 設定 | 設定 |
| System Settings | Systemeinstellungen | Configuración del Sistema | Ajustes del Sistema | Ajustes do Sistema | Definições do Sistema | Системные настройки | 系统设置 | 系統設定 | システム設定 |
| General (tab) | Allgemein | General | General | Geral | Geral | Основные | 通用 | 一般 | 一般 |
| Appearance (tab) | Darstellung | Apariencia | Apariencia | Aparência | Aspeto | Оформление | 外观 | 外觀 | 外観 |
| Providers (tab) | Anbieter | Proveedores | Proveedores | Provedores | Fornecedores | Провайдеры | 提供商 | 提供者 | プロバイダ |
| AI provider | KI-Anbieter | proveedor de IA | proveedor de IA | provedor de IA | fornecedor de IA | ИИ-провайдер | AI 提供商 | AI提供者 | AIプロバイダ |
| menu bar | Menüleiste | barra de menús | barra de menús | barra de menus | barra de menus | строка меню | 菜单栏 | 選單列 | メニューバー |
| Keychain | Schlüsselbund | llavero | llavero (item: ítem del llavero) | chaves (app: Acesso às Chaves; item: item das chaves) | porta-chaves (app: Acesso a Porta-chaves; item: elemento de porta-chaves) | связка ключей | 钥匙串 (item: 钥匙串项) | 鑰匙圈 (app: 「鑰匙圈存取」; item: 鑰匙圈項目) | キーチェーン (app: キーチェーンアクセス) |
| API key | API-Schlüssel | clave de API | clave de API | chave de API | chave de API | ключ API | API 密钥 | API金鑰 | APIキー |
| Authentication failed (API key) | Authentifizierung fehlgeschlagen | Falló la autenticación | Error de autenticación | Falha na autenticação | Falha na autenticação | Ошибка аутентификации | 认证失败 | 認證失敗 | 認証に失敗しました |
| credential type (internal error) | Typ der Anmeldedaten | tipo de credencial | tipo de credencial | tipo de credencial | tipo de credencial | тип учётных данных | 凭证类型 | 憑證類型 | 認証情報の種類 |
| Check usage now (button) | Nutzung jetzt prüfen | Consultar uso ahora | Consultar uso ahora | Verificar uso agora | Verificar utilização agora | Проверить использование | 立即检查用量 | 立即檢查用量 | 今すぐ使用量を確認 |
| usage check | Nutzungsprüfung | consulta de uso | consulta de uso | verificação de uso | verificação da utilização | проверка использования | 用量检查 | 用量檢查 | 使用量の確認 |
| Usage Checks (settings page) | Nutzungsprüfung | Consultas de uso | Consultas de uso | Verificações de uso | Verificações da utilização | Проверка использования | 用量检查 | 用量檢查 | 使用量の確認 |
| Automatic usage checks | Automatische Nutzungsprüfung | Consultas automáticas de uso | Consultas automáticas de uso | Verificação automática de uso | Verificação automática da utilização | Автоматическая проверка использования | 自动检查用量 | 自動檢查用量 | 使用量の自動確認 |
| Check schedule (Regular / Smart) | Prüfrhythmus | Frecuencia de consulta | Frecuencia de consulta | Frequência de verificação | Frequência de verificação | График проверок | 检查频率 | 檢查頻率 | 確認の頻度 |
| Retry | Erneut versuchen | Reintentar | Reintentar | Tentar novamente | Tentar novamente | Повторить | 重试 | 再試一次 | 再試行 |
| Sign in to X | Bei X anmelden | Iniciar sesión en X | Iniciar sesión en X | Iniciar sessão em X | Iniciar sessão em X | Войти в X | 登录 X | 登入X | Xにサインイン |
| Launch at login | Bei der Anmeldung starten | Abrir al iniciar sesión | Abrir al iniciar sesión | Abrir ao iniciar sessão | Abrir ao iniciar sessão | Открывать при входе | 登录时打开 | 登入時打開 | ログイン時に開く |
| Login Items & Extensions | Anmeldeobjekte & Erweiterungen | Elementos de inicio y extensiones | Ítems de inicio y extensiones | Itens de Início de Sessão e Extensões | Início de sessão e extensões | Объекты входа и расширения | 登录项与扩展 | 登入項目與延伸功能 | ログイン項目と機能拡張 |
| Quit | Beenden | Salir | Salir | Encerrar | Sair | Завершить | 退出 | 結束 | 終了 |
| Check for Updates… | Nach Updates suchen … | Buscar actualizaciones… | Buscar actualizaciones… | Buscar atualizações… | Procurar atualizações… | Проверить обновления… | 检查更新… | 檢查更新項目⋯ | アップデートを確認… |
| update (software) | Update | actualización | actualización | atualização | atualização | обновление | 更新 | 更新項目 | アップデート |
| Update (install button) | Installieren (never "Aktualisieren") | Actualizar | Actualizar | Atualizar | Atualizar | Обновить | 更新 | 更新 | アップデート |
| usage | Nutzung | uso | uso | uso | utilização | использование | 用量 | 用量 | 使用量 |
| limit | Limit | límite | límite | limite | limite | лимит | 上限, 限制 | 上限, 限制 | 上限 |
| quota | Kontingent | cuota | cuota | cota | quota | квота | 配额 | 配額 | 割り当て |
| rate limit | Anfragelimit | límite de frecuencia | límite de frecuencia | limite de taxa | limite de taxa | ограничение частоты | 速率限制 | 速率限制 | レート制限 |
| Limit reached | Limit erreicht | Límite alcanzado | Límite alcanzado | Limite atingido | Limite atingido | Лимит исчерпан | 已达上限 | 已達上限 | 上限に達しました |
| reset (quota window) | zurücksetzen, bis zum Zurücksetzen | restablecer | restablecer | redefinir | repor | сбросить, сброс | 重置 | 重設 (not macOS's 重置; every provider and Google write 重設) | リセット |
| resetting… (quota) | wird zurückgesetzt… | restableciéndose… | restableciéndose… | redefinindo… | a repor… | сброс… | 正在重置… | 正在重設⋯ | リセット中… |
| Rate limited | Anfragelimit erreicht | Se alcanzó el límite de solicitudes | Límite de solicitudes alcanzado | Limite de solicitações atingido | Limite de pedidos atingido | Слишком много запросов (label), Достигнут лимит запросов (sentence) | 请求过于频繁 | 已達速率限制 | リクエストの上限に達しました |
| balance | Guthaben | saldo | saldo | saldo | saldo | баланс | 余额 | 餘額 | 残高 |
| credits | Credits | créditos | créditos | créditos | créditos | кредиты | promotional or bonus: 赠金; Codex (OpenAI): 额度; Z.ai usage credits: 积分 | 點數 (every provider, including Z.ai ⚠︎) | クレジット |
| peak hours | Spitzenzeiten | horas pico | horas punta | horário de pico | horas de ponta | часы пик | 高峰时段 (off-peak: 非高峰时段) | 尖峰時段 (off-peak: 離峰時段) | ピーク時間帯 |
| average (pace) | durchschnittlich | promedio | medio | médio | médio | средний | 平均 | 平均 | 平均 |
| pace status (Within / Over current allowance) | Verbrauch im Plan / Verbrauch über Plan | Dentro del ritmo disponible / Por encima del ritmo disponible | Dentro del ritmo previsto / Por encima del ritmo previsto | Dentro do ritmo sustentável / Acima do ritmo sustentável | Dentro do ritmo previsto / Acima do ritmo previsto | Темп в пределах нормы / Темп выше нормы | 用量未超出当前进度 / 用量超出当前进度 | 用量未超前目前進度 / 用量超前目前進度 (Taiwan: 進度超前) | 想定ペース内 / 想定ペースを超過 |
| the Mac (article) | der Mac | la Mac | el Mac | o Mac | o Mac | Mac | Mac | Mac | Mac |
| Keep Mac Awake | Mac wach halten | Mantener la Mac activa | Mantener el Mac activo | Manter o Mac ativo | Manter o Mac ativo | Не давать Mac уснуть | 保持 Mac 唤醒 | 防止Mac進入睡眠 (macOS Battery: 「防止Mac…自動進入睡眠」) | Macをスリープさせない |
| System Default (language) | Systemstandard | Predeterminado del sistema | Predeterminado del sistema | Padrão do sistema | Predefinição do sistema | Системный | 跟随系统 | 系統預設值 | システムデフォルト |
| Language (setting) | Sprache | Idioma | Idioma | Idioma | Idioma | Язык | 语言 | 語言 | 言語 |
| dialog (system window) | Dialog | cuadro de diálogo | cuadro de diálogo | caixa de diálogo | caixa de diálogo | диалоговое окно | 对话框 | 對話框 | ダイアログ |
| helper script | Hilfsskript | script auxiliar | script auxiliar | script auxiliar | script auxiliar | вспомогательный скрипт (buttons: скрипт) | 辅助脚本 | 輔助腳本 | ヘルパースクリプト |
| Fast-check duration (how long fast checks continue after a usage change, not a pause) | Dauer schneller Prüfungen | Duración de consultas rápidas | Duración de consultas rápidas | Duração das verificações rápidas | Duração das verificações rápidas | Длительность быстрых проверок | 快速检查时长 | 快速檢查持續時間 | 高速確認の継続時間 |
| Stop fast checks | Schnelle Prüfungen beenden | Detener consultas rápidas | Detener consultas rápidas | Parar verificações rápidas | Parar verificações rápidas | Остановить быстрые проверки | 停止快速检查 | 停止快速檢查 | 高速確認を停止 |
| local time ("%@ (your time)") | (Ortszeit) | (hora local) | (hora local) | (seu horário) | (hora local) | (по вашему времени) | （本地时间） | （你的時區） (Taiwan 當地時間 means "the time over there") | （現地時間） |
| Use Default (base URL) | Standard verwenden | Usar URL predeterminada | Usar URL por defecto | Usar padrão | Usar predefinição | Вернуть стандартный URL | 使用默认值 | 使用預設值 | デフォルトを使用 |
| Low below / OK at or above (balance thresholds) | Niedrig unter / OK ab | Bajo: menos de / Suficiente: desde | Bajo si es inferior a / Correcto a partir de | Baixo se menor que / OK a partir de | Baixo se inferior a / OK a partir de | Низкий — ниже / Норма — от | 偏低阈值 / 正常阈值 | 偏低門檻 / 正常門檻 | 低残高: この値未満 / 十分な残高: この値以上 |
| Included usage (Cursor) | Enthaltene Nutzung | Uso incluido | Uso incluido | Uso incluído | Utilização incluída | Включённое использование | 包含用量 | 包含用量 | プランに含まれる使用量 |
| on-demand spend (Cursor) | On-Demand-Ausgaben | gasto bajo demanda | gasto bajo demanda | gastos sob demanda | gastos a pedido | дополнительные расходы | 按需支出 | 隨選支出 | オンデマンドの支出 |
| pooled spend (Cursor) | gemeinsame Ausgaben | gasto compartido | gasto compartido | gastos compartilhados | gastos partilhados | расходы общего пула | 共享支出 | 用量池支出 | 共有の支出 |
| granted balance (DeepSeek) | Gewährtes Guthaben | créditos otorgados | créditos otorgados | créditos concedidos | créditos concedidos | бонусный баланс ⚠︎ | 赠金余额 | 贈送餘額 ⚠︎ | 付与残高 ⚠︎ |
| topped-up balance (DeepSeek) | Aufgeladenes Guthaben | saldo recargado | saldo recargado | recarregado | carregado | пополнено | 充值余额 | 儲值餘額 | チャージ残高 ⚠︎ |
| available balance (Kimi API) | Verfügbares Guthaben | saldo disponible | saldo disponible | saldo disponível | saldo disponível | доступный баланс | 可用余额 | 可用餘額 | 利用可能残高 ⚠︎ |
| voucher balance (Kimi API) | Gutscheinguthaben ⚠︎ | saldo de cupones ⚠︎ | saldo de cupones ⚠︎ | saldo de cupons ⚠︎ | saldo de vales ⚠︎ | баланс ваучеров ⚠︎ | 代金券余额 | 代金券餘額 ⚠︎ | クーポン残高 ⚠︎ |
| cash balance (Kimi API) | Barguthaben ⚠︎ | saldo en efectivo | saldo en efectivo | saldo em dinheiro ⚠︎ | saldo em dinheiro ⚠︎ | денежный баланс ⚠︎ | 现金余额 | 現金餘額 | 現金残高 ⚠︎ |
| membership (Kimi Code) | Mitgliedschaft ⚠︎ | membresía ⚠︎ | membresía ⚠︎ | assinatura ⚠︎ | subscrição ⚠︎ | подписка ⚠︎ | 会员 | 會員資格 ⚠︎ | メンバーシップ ⚠︎ |
| mainland China | Festlandchina ⚠︎ | China continental ⚠︎ | China continental ⚠︎ | China continental ⚠︎ | China continental ⚠︎ | материковый Китай ⚠︎ | 国内 | 中國大陸 ⚠︎ | 中国本土 ⚠︎ |
| pay-as-you-go (z.ai API) | Pay-as-you-go ⚠︎ | pago por uso ⚠︎ | pago por uso ⚠︎ | pagamento por uso ⚠︎ | pagamento por utilização ⚠︎ | оплата по мере использования ⚠︎ | 按量付费 ⚠︎ | 隨用隨付 ⚠︎ | 従量課金 ⚠︎ |
| frozen balance (z.ai API) | Eingefroren ⚠︎ | Congelado ⚠︎ | Congelado ⚠︎ | Congelado ⚠︎ | Congelado ⚠︎ | Заморожено ⚠︎ | 冻结金额 ⚠︎ | 凍結金額 ⚠︎ | 凍結中 ⚠︎ |
| spent to date (z.ai API) | Bisher ausgegeben ⚠︎ | Gastado hasta la fecha ⚠︎ | Gastado hasta la fecha ⚠︎ | Gasto até agora ⚠︎ | Gasto até à data ⚠︎ | Потрачено всего ⚠︎ | 累计消费 ⚠︎ | 累計消費 ⚠︎ | 累計支出 ⚠︎ |
| Standard API key (z.ai key type) | Standard-API-Schlüssel ⚠︎ | clave de API Standard ⚠︎ | clave de API Standard ⚠︎ | chave de API Standard ⚠︎ | chave de API Standard ⚠︎ | ключ API типа Standard ⚠︎ | 标准 API 密钥 ⚠︎ | 標準API金鑰 ⚠︎ | Standard APIキー ⚠︎ |
| credit rate (Z.ai peak hours) | Credit-Tarif (percentage: "%@ des Standard-Credit-Tarifs") | tarifa de créditos | tarifa de créditos | taxa de créditos (percentage: "%@ da taxa de créditos padrão") | taxa de créditos | тариф | 积分消耗 (percentage: "按标准的 %@ 消耗积分") | 點數扣除比例 (percentage: "按標準的%@扣除點數") ⚠︎ | クレジット消費率 (percentage: "クレジット消費率: 標準の%@") |
| peak multiplier ("3×") | "%lld× Multiplikator" | "Multiplicador %lld×" | "Multiplicador %lld×" | "Multiplicador %lld×" | "Multiplicador %lld×" | "Множитель %lld×" | "%lld 倍" | "%lld倍" | "%lld倍", not "×" |
| Finder | Finder | Finder | Finder | Finder | Finder | Finder | 访达 | Finder | Finder |

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

### Traditional Chinese only

Terms that the table above doesn't list, from macOS `zh_TW` strings unless noted:

- Advanced: 進階. About (tab): 簡介. Status: 狀態. Version: 版本. Welcome: 歡迎使用.
- server: 伺服器. network: 網路. account: 帳號. connection: 連線. internal error: 內部錯誤. timed out: 逾時. Unknown error: 未知的錯誤.
- request: 要求 (457 macOS strings against 5 for 請求). Model: 模型 (OpenAI, Anthropic). Plan: 方案 (OpenAI, Anthropic, Cursor). Subscription: 訂閱項目 for the noun (macOS), 訂閱 for the verb.
- icon: 圖像 (macOS, 473 strings; Microsoft's 圖示 is Windows usage). Dock: Dock. Accessibility: 輔助使用.
- Open: 打開. Copy: 拷貝. Not Now: 稍後再說. Learn More: 更多內容. Loading: 載入中⋯. Restart (an app): 重新啟動. Restart (the Mac): 重新開機.
- Collapsed / Expanded (VoiceOver): 已收合 / 已展開. Actions: 收合 / 展開.
- Re-import (Cursor credentials): 重新匯入, from Microsoft's 匯入. macOS translates Import as 輸入, which also means "type in", so Filbert does not use it.
- session (Anthropic, Cursor): 工作階段. Session expired: 工作階段已過期.
- quota window: 時段 ("5小時時段", "%lld分鐘時段"). Weekly: 每週. Monthly: 每月. Daily: 每天. Never 窗口.
- shared usage pool (Cursor): 用量池. Top up: 儲值. Insufficient balance: 餘額不足.
- script: 腳本, as Taiwanese developers write it (NAER lists 腳本; the user chose it on 2026-10-20). Apple's 工序指令 belongs to AppleScript and Automator.
- base URL: 基底URL (Microsoft zh-TW). Unlimited: 無限制 (Cursor zh-Hant). hook into a tool: 串接, never the mainland 接入.
- token (LLM): token, as Taiwanese developers write it. Google's machine-translated 權杖 is not used.
- Command names inside a sentence go in 「…」: 「codex login」, 「agent login」.
- An open list ends with 等, not ⋯: （USD、CNY等）.
- Version numbers: "更新至%@版", not "更新至版本%@".
- A 即使 clause goes before its main clause: "即使用量沒有變化，也會…".
- Monitor (provider descriptions, "Monitor Codex subscription usage"): 監控 ⚠︎.
- Cursor's named Auto mode: Auto.

## Language names in the picker

Each language appears in its own name (ui 32 AC1): English, Deutsch, Español (México), Español (España), Português (Brasil), Português (Portugal), Русский, 简体中文, 繁體中文, 日本語.

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
- Kimi API balances (zh-Hans): the Kimi Open Platform "查询余额" page (`platform.kimi.com/docs/api/balance`, 2026-10-23) uses 可用余额, 代金券余额, and 现金余额. The English page (`platform.kimi.ai/docs/api/balance`) says "available, voucher, and cash balances". Kimi has no Traditional Chinese, Japanese, or European-language docs, so the other languages keep ⚠︎ until a native review.
- z.ai API terms: the English z.ai docs (`docs.z.ai/devpack/notice/api-key-management`, 2026-10-23) name the key types Standard, Compatible, and Team Plan, and say "pay-as-you-go". The balance report's Chinese UI terms were not checked, so every language keeps ⚠︎ until a native review. "Coding Plan" stays in English as a product name.
- Kimi Code membership and region (zh-Hans): the Kimi Code docs (`kimi.com/code/docs/`, 2026-10-23) say 会员权益 for membership and label the base URLs 国内 and 海外. zh-Hant keeps 中國大陸, because 國內 reads as Taiwan there. The other languages keep ⚠︎ until a native review.
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

## Sources consulted on 2026-10-20 (zh-Hant)

- macOS 27 `zh_TW` UI strings on the dev Mac: 3,071 `.loctable` files in CoreServices, Applications, AppKit, Security, ExtensionKit, and System Settings. Source of the conventions above and of 設定, 系統設定, 一般, 外觀, 提供者, 選單列, 鑰匙圈, 「鑰匙圈存取」, 鑰匙圈項目, 認證失敗 (295 strings use 認證, 4 use 驗證), 憑證, 重新整理, 再試一次, 登入, 在登入時打開, 登入項目與延伸功能, 結束, 更新, 限制, 預設值, 系統預設值, 使用預設值, 語言, 語言與地區, 平均, 要求, 圖像, Shell工序指令, and the rate-limit sentence "你在短時間內送出了多個要求。請稍後再試一次。".
- Sparkle 2 `zh_TW` strings: 檢查更新項目, 安裝更新項目, 軟體更新, "請稍後再試一次。", "正在下載更新項目⋯".
- Apple Mac User Guide in `zh-tw` (`mh26684`, `mh15189`, `mchlp1446`, `mchle41a6ccd`) and Keychain Access guide (`kyca1083`, `kyca1085`): 選單列, 狀態選單, 「系統設定」, 「語言與地區」, 登入項目, 對話框, 睡眠, 喚醒, "避免在顯示器關閉時自動進入睡眠", 鑰匙圈項目, 工序指令, and 你. The guides put a space around Latin text ("在 Mac 上"); the UI does not.
- Google Gemini API docs with `hl=zh-TW` (`api-key`, `rate-limits`, `api-errors`, `billing`): API 金鑰, 配額, 每分鐘要求數, "配額會在太平洋時間午夜重設", 用量, 餘額, 專案. The pages are machine translations (`zh-TW-x-mtfrom-en`), so they confirm terms but don't decide style. Google One help in `zh-Hant`: 點數, 自動儲值 (Hong Kong: 自動增值).
- OpenAI help in `zh-hant` (articles 12642688, 11369540, 20001507, 20001478, 5955604): 點數, 點數餘額, 剩餘額度, 用量, 用量上限, 每週上限, 速率限制, 重設, "將於 720 小時後重設", 方案, API 金鑰, 登入, 請稍後再試, 模型.
- Anthropic `support.claude.com/zh-TW` (9797557, 11647753, 11145838, 12429409), `code.claude.com/docs/zh-TW` (`authentication`, `errors`), and `platform.claude.com/docs/zh-TW` (`rate-limits`, `errors`): 使用額度, 用量上限, 工作階段限制, 速率限制, 重設, 方案, API 金鑰, 登入, 身分驗證失敗, 已達到使用限制.
- Cursor in `zh-Hant` (`cursor.com/zh-Hant/pricing`, `/blog/june-2025-pricing`, `/changelog/05-04-26`, `/terms/pricing`): 包含用量, 隨選用量, 隨選支出, 用量池, 支出上限, 方案, 請求, Auto, 門檻 ("浮動支出門檻"). Cursor's docs are English only.
- OpenCode in `zh-Hant` (`opencode.ai/zht/go`, `/zht/zen`): 使用限制, 每月使用額度, 訂閱, 儲值, "預估請求次數 / 5 小時".
- DeepSeek and Z.ai have no Traditional Chinese pages. DeepSeek terms come from Taiwan guides (maplefeather.com, zuizhinan.com: 贈送餘額, 儲值, 餘額不足) and cnyes.com (儲值). No source writes 儲值餘額, so it stays ⚠︎. Z.ai terms come from a Taiwan blog (maplefeather.com GLM Coding Plan: 高峰 / 離峰, 積分, "積分只扣標準的 50%"). Filbert uses 點數 for Z.ai as for every provider, because Taiwan first-party sources (OpenAI, Google, Adobe, Microsoft) use 點數; ⚠︎ until the native review.
- Microsoft Terminology Collection, Traditional Chinese (TBX, 2024-11-06, tagged HKG and TWN) and the Microsoft zh-TW style guide (2024-09): 點數, 餘額, 自動加值, 配額, 速率限制, 重設, 隨選, 共用, 金鑰, 匯入, 輪詢. Microsoft uses 您 and Windows terms (功能表列, 圖示); Filbert follows macOS for both.
- NAER term database (`terms.naer.edu.tw`): 配額, 節流, 輪詢, 隨選, 離峰, 門檻, 重設 / 重置.
- Taiwan usage: iThome (174382, 175599, 178590: 點數機制, 尖峰時段, 用量上限, 額度), INSIDE (41668, 42249: 速率限制, "5 小時視窗"), TechNews (尖峰時段), Taipower (尖峰 / 離峰). The mainland-term deny list comes from taiwan.md/terminology and the Microsoft TBX.
- Hong Kong forms recorded, not used: 帳户, 網絡, 再試, 開啟 (for Open), 複製, 進一步了解, 增值, 結餘.
- Native review on 2026-10-20 (ui 36 Plan step 9): 18 style changes, no errors. Sources: Sparkle `zh_TW` "%1$@ %2$@現在已可供下載"; Cursor zh-Hant blog (`june-2025-pricing`, `aug-2025-pricing`) "無限制使用"; Microsoft Learn zh-tw "基底 URL"; Apple Support zh-tw `101114` "如何防止進入睡眠"; EasyCard and icash "儲值餘額"; Taiwan reports for 超前進度.

## Language-review references

- [OpenAI credit usage, Simplified Chinese](https://help.openai.com/zh-hans-cn/articles/12642688-using-credits-for-flexible-usage-in-chatgpt-freegopluspro-sora): Codex usage credits are 额度; the 额度余额 is distinct from the monetary wallet balance.
- [OpenAI credit usage, Japanese](https://help.openai.com/ja-jp/articles/12642688-using-credits-for-flexible-usage-in-chatgpt-personal-plans): クレジット, 残高, クレジット残高.
- [Z.ai Coding Plan, Chinese](https://docs.bigmodel.cn/cn/coding-plan/overview): "非高峰时段内，模型调用按基础积分消耗的 50% 抵扣". The percentage is a charge factor, not consumption per unit of time.
- [Cursor models, Japanese](https://cursor.com/ja/docs/models): "Auto モード".
- [Apple Keychain Access, Simplified Chinese](https://support.apple.com/zh-cn/guide/keychain-access/kyca1083/mac): "钥匙串项".
- [Google Gemini rate limits, Latin American Spanish](https://ai.google.dev/gemini-api/docs/rate-limits?hl=es-419): "límites de frecuencia" and "Si alcanzas un límite de frecuencia…".
- [RAE/ASALE, símbolo](https://www.rae.es/dpd/s%C3%ADmbolo): the percent sign is preceded by a space, as in "25 %".
