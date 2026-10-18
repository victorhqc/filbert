# Localization glossary

Every translation in a `Localizable.xcstrings` catalog follows this glossary.

## Sources of truth

When in doubt, use the term that the vendor uses in its own localized docs. Check in this order:

1. Apple's localized macOS help, for macOS terms: `support.apple.com/<locale>/guide/mac-help/...`. Locales: `de-de`, `es-lamr` (Latin America, use for `es-MX`), `es-es`, `pt-br`, `pt-pt`, `ru-ru`, `zh-cn`.
2. Google's localized developer docs, for API terms: `ai.google.dev/...?hl=<locale>`.
3. The provider's own localized UI or docs, for provider-specific terms. Z.ai and DeepSeek have Chinese UIs.

Record new terms here with the source. **⚠︎** marks a term that no source has confirmed yet.

## Conventions

| | de-DE | es-MX | es-ES | pt-BR | pt-PT | ru | zh-Hans |
|---|---|---|---|---|---|---|---|
| Address the user | du | tú | tú | você, omitted where possible | formal imperative ("Verifique"), no "tu" | вы, lowercase | 你 (as macOS) |
| Recent past | Perfekt | simple past: "No se pudo", "falló" | present perfect: "No se ha podido", "ha fallado" | simple past: "falhou" | simple past: "falhou" | perfective past | 了 / 失败 |
| Ongoing action | "wird geladen" | gerund: "cargando" | gerund: "cargando" | gerund: "carregando" | a + infinitive: "a carregar" | present | 正在… |
| Buttons, menu items | infinitive | infinitive | infinitive | infinitive | infinitive | infinitive | verb |
| Instructions in a sentence | imperative | imperative | imperative | imperative | imperative | imperative | verb |
| Quotes | „…“ | “…” | «…» | “…” | «…» | «…» | “…” |
| Ellipsis in menu items | "Einstellungen …" (space) | "…" | "…" | "…" | "…" | "…" | "…" |

- Sentence case everywhere. German nouns keep their capital letter.
- Product names stay in English: Filbert, Claude Code, Codex, Cursor, Gemini CLI, DeepSeek, OpenCode Go, Z.ai, Sparkle.
- The " · " separator stays as is in every language.
- Chinese uses full-width punctuation (，。：！？（）) and puts a half-width space between Chinese and Latin letters or digits: "API 密钥", "5 分钟".
- Never hand-write units such as "min" or "h". Durations, dates, and numbers come from the system formatters in the display language.
- Counted strings use plural variations, not "(s)" or a fixed form.

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

- `es-MX` denies: Ajustes, ordenador, añadir, icono (no accent), comprobar / comprueba, horas punta, vosotros verb forms.
- `es-ES` denies: Configuración del Sistema, computadora, agregar, ícono, horas pico.

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

| English | de-DE | es-MX | es-ES | pt-BR | pt-PT | ru | zh-Hans |
|---|---|---|---|---|---|---|---|
| Settings (Filbert's window) | Einstellungen | Configuración | Ajustes | Ajustes | Definições | Настройки | 设置 |
| System Settings | Systemeinstellungen | Configuración del Sistema | Ajustes del Sistema | Ajustes do Sistema | Definições do Sistema | Системные настройки | 系统设置 |
| General (tab) | Allgemein | General | General | Geral | Geral | Основные | 通用 |
| Appearance (tab) | Darstellung | Apariencia | Apariencia | Aparência | Aspeto | Оформление | 外观 |
| Providers (tab) | Anbieter | Proveedores | Proveedores | Provedores | Fornecedores | Провайдеры | 提供商 |
| AI provider | KI-Anbieter | proveedor de IA | proveedor de IA | provedor de IA | fornecedor de IA | ИИ-провайдер | AI 提供商 |
| menu bar | Menüleiste | barra de menús (today "barra de menú") | barra de menús | barra de menus | barra de menus | строка меню | 菜单栏 |
| Keychain | Schlüsselbund | llavero | llavero | chaves (app: Acesso às Chaves; item: item das chaves) | porta-chaves (app: Acesso a Porta-chaves; item: elemento de porta-chaves) | связка ключей | 钥匙串 |
| API key | API-Schlüssel | clave de API (today "llave de API") | clave de API | chave de API | chave de API | ключ API | API 密钥 |
| Refresh | Aktualisieren | Actualizar (today "Refrescar") | Actualizar | Atualizar | Atualizar | Обновить | 刷新 |
| Retry | Erneut versuchen | Reintentar (today "Volver a intentar") | Reintentar | Tentar novamente | Tentar novamente | Повторить | 重试 |
| Sign in to X | Bei X anmelden | Iniciar sesión en X | Iniciar sesión en X | Iniciar sessão em X | Iniciar sessão em X | Войти в X | 登录 X |
| Launch at login | Bei der Anmeldung starten | Abrir al iniciar sesión | Abrir al iniciar sesión | Abrir ao iniciar sessão | Abrir ao iniciar sessão | Открывать при входе | 登录时打开 |
| Login Items & Extensions | Anmeldeobjekte & Erweiterungen | Elementos de inicio y extensiones | Ítems de inicio y extensiones | Itens de Início de Sessão e Extensões | Início de sessão e extensões | Объекты входа и расширения | 登录项与扩展 |
| Quit | Beenden | Salir | Salir | Encerrar | Sair | Завершить | 退出 |
| Check for Updates… | Nach Updates suchen … | Buscar actualizaciones… | Buscar actualizaciones… | Buscar atualizações… | Procurar atualizações… | Проверить обновления… | 检查更新… |
| update (software) | Update | actualización | actualización | atualização | atualização | обновление | 更新 |
| usage | Nutzung | uso | uso | uso | utilização | использование | 用量 |
| limit | Limit | límite | límite | limite | limite | лимит | 上限, 限制 |
| quota | Kontingent | cuota | cuota | cota | quota | квота | 配额 |
| rate limit | Anfragelimit | límite de frecuencia | límite de frecuencia | limite de taxa | limite de taxa | ограничение частоты | 速率限制 |
| Limit reached | Limit erreicht | Límite alcanzado | Límite alcanzado | Limite atingido | Limite atingido | Лимит исчерпан | 已达上限 |
| reset (quota window) | zurücksetzen, Zurücksetzung | restablecer (today mixed with "reiniciar") | restablecer | redefinir | repor | сбросить, сброс | 重置 |
| Rate limited | Anfragelimit erreicht | Se alcanzó el límite de solicitudes | Límite de solicitudes alcanzado | Limite de solicitações atingido | Limite de pedidos atingido | Слишком много запросов | 请求过于频繁 |
| balance | Guthaben | saldo | saldo | saldo | saldo | баланс | 余额 |
| credits | Credits | créditos | créditos | créditos | créditos | кредиты | promotional or bonus: 赠金; purchased: ⚠︎ use the provider's own Chinese UI |
| peak hours | Spitzenzeiten | horas pico | horas punta | horário de pico | horas de ponta | часы пик | 高峰时段 |
| Keep Awake | Wach halten | Mantener activo (today "No dormir") | Mantener activo | Manter ativo | Manter ativo | Не засыпать | 保持唤醒 |
| System Default (language) | Systemstandard | Predeterminado del sistema | Predeterminado del sistema | Padrão do sistema | Predefinição do sistema | Системный | 跟随系统 |

## Language names in the picker

Each language appears in its own name (ui 32 AC1): English, Deutsch, Español (México), Español (España), Português (Brasil), Português (Portugal), Русский, 简体中文.

## Sources consulted on 2026-10-18

- Login Items, System Settings, sign in: Apple Mac User Guide "Open items automatically when you log in" (`mh15189`) in `de-de`, `es-lamr`, `es-es`, `pt-br`, `pt-pt`, `ru-ru`, `zh-cn`.
- Keychain: Apple Keychain Access User Guide in `pt-br` and `pt-pt`.
- menu bar: Apple Mac User Guide glossary in `es-lamr` and `es-es`.
- API key: Google Gemini API docs "API keys" in `ru` and `zh-cn`.
- rate limits, quota, usage, reset (zh-Hans): Google Gemini API docs "Rate limits" in `zh-cn`.
- credits (zh-Hans): Google Cloud docs and codelabs use 赠金.
