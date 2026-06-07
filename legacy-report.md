# Legacy Report — AntigravityMobile
**Generado:** 2026-06-02  
**Auditor:** ArchitectAgent + RefactorAgent  
**Proyecto:** AntigravityMobile — Panel remoto Flutter para Antigravity AI

---

## Resumen ejecutivo

El proyecto está en buen estado general: es Flutter moderno, sin HTML/CSS/JS legacy, sin APKs antiguas, sin bridges Android legacy. La app es una Flutter Web app servida por nginx en Docker.

Los problemas son internos al código Flutter: archivos huérfanos, duplicación masiva de lógica entre pantallas, y falta de capa de estado global.

**No hay código HTML/CSS/JS/APK que eliminar.** El proyecto nunca tuvo esa pila — siempre fue Flutter Web.

---

## 1. Archivos Flutter huérfanos (no tienen referencias activas)

### 1.1 `mobile/lib/models/message.dart`

```
Estado: HUÉRFANO — no referenciado por ninguna pantalla activa
```

Define un `ChatMessage` alternativo con campos `id`, `role: MessageRole`, `provider: AIProvider`, `timestamp`, `isStreaming`. **Ninguna pantalla lo usa.** Las pantallas usan otro `ChatMessage` definido dentro de `session_service.dart`.

Solo lo importan los dos widgets huérfanos (ver 1.2 y 1.3).

Conflicto real: existe un `ChatMessage` en `session_service.dart` (con `content`, `isAssistant`, `imageB64`) que es el que usan todos los screens. El `ChatMessage` de `models/message.dart` tiene una firma completamente diferente e incompatible.

### 1.2 `mobile/lib/widgets/message_bubble.dart`

```
Estado: HUÉRFANO — no importado por ninguna pantalla
```

Importa `models/message.dart`. Usa `flutter_markdown` para renderizar Markdown. Es un widget bien escrito con soporte para copiar al portapapeles. **Ninguna pantalla lo usa.** Las tres pantallas de chat definen sus propios widgets privados `_Bubble` / `_BubbleWidget` con `Text()` simple (sin Markdown).

### 1.3 `mobile/lib/widgets/provider_selector.dart`

```
Estado: HUÉRFANO — no importado por ninguna pantalla
```

Importa `AIProvider` de `models/message.dart`. Renderiza pills horizontales por proveedor. **Ninguna pantalla lo usa.** La pantalla AGI Chat tiene su propio `_showProviderPicker()` inline.

### 1.4 `hub/routes/__pycache__/jarvis.cpython-311.pyc`

```
Estado: HUÉRFANO — bytecode compilado sin fuente correspondiente
```

Existe `jarvis.cpython-311.pyc` en `__pycache__` pero no hay `jarvis.py` en `routes/`. El route fue eliminado pero el bytecode compilado quedó. **Nunca fue registrado en `main.py` actual** — no hay `from routes.jarvis import router`.

---

## 2. Código duplicado en Flutter (código activo pero repetido)

### 2.1 Clase `ChatMessage` — duplicada en 2 lugares

| Archivo | Definición | ¿Usada? |
|---|---|---|
| `services/session_service.dart:4` | `class ChatMessage { content, isAssistant, imageB64 }` | ✅ Sí — 3 pantallas |
| `models/message.dart:4` | `class ChatMessage { id, role, provider, timestamp, isStreaming }` | ❌ No — huérfana |

### 2.2 Widget `_Bubble` — definido 3 veces de forma casi idéntica

| Archivo | Nombre clase | Línea |
|---|---|---|
| `screens/chat_claude_screen.dart` | `class _Bubble` | 283 |
| `screens/agi_chat_screen.dart` | `class _Bubble` | 394 |
| `screens/claude_code_screen.dart` | `class _BubbleWidget` | 579 |

Las tres hacen exactamente lo mismo: burbuja de usuario a la derecha (color de acento), burbuja de asistente a la izquierda (fondo `AppTheme.surface`). La variante de `claude_code_screen` no soporta imágenes, las otras dos sí. **Existe `message_bubble.dart` que debería cumplir esta función pero está huérfano.**

### 2.3 Método `_fmt`/`_formatDate` — duplicado 2 veces

| Archivo | Nombre | Línea |
|---|---|---|
| `screens/chat_claude_screen.dart` | `String _fmt(DateTime)` | 274 |
| `screens/agi_chat_screen.dart` | `String _fmt(DateTime)` | 385 |
| `screens/claude_code_screen.dart` | `String _formatDate(DateTime)` | 524 |

Lógica idéntica: "ahora" / "hace Xm" / "hace Xh" / "dia/mes".

### 2.4 Método `_saveSession` — duplicado 3 veces

| Archivo | Línea |
|---|---|
| `screens/chat_claude_screen.dart` | 91 |
| `screens/agi_chat_screen.dart` | 125 |
| `screens/claude_code_screen.dart` | 189 |

Lógica idéntica: si el título es "Nueva sesión", usar el primer mensaje del usuario como título (truncado a 40 chars).

### 2.5 WebSocket connect/onData — duplicado 3 veces

Las tres pantallas de chat tienen:
- `_connect()`: crea `WebSocketChannel`, suscribe listeners
- `_onData()`: parsea `type: start/chunk/end` JSON
- `_hubWs`: carga URL desde `SharedPreferences`

Ejemplo en `chat_claude_screen.dart:64` / `agi_chat_screen.dart:98` / `claude_code_screen.dart:133`.

### 2.6 Carga de Hub URL — duplicada en 5 lugares

`prefs.getString('hub_url')` aparece directamente en:
- `chat_claude_screen.dart:53`
- `agi_chat_screen.dart:87`
- `claude_code_screen.dart:122`
- `servers_screen.dart:31`
- `widgets/chat_toolbar.dart:69`

`HubService` tiene `getHubUrl()` para esto pero solo lo usan `home_screen.dart` y `settings_screen.dart`.

---

## 3. Violaciones AG-CORE activas

### AG-CORE-001: Catch vacío prohibido

Los siguientes bloques `catch (_) {}` tragan excepciones silenciosamente:

| Archivo | Línea | Contexto |
|---|---|---|
| `services/hub_service.dart` | 39 | checkHealth — error de HTTP |
| `screens/chat_claude_screen.dart` | 88 | _onData — parse JSON |
| `screens/agi_chat_screen.dart` | 122 | _onData — parse JSON |
| `screens/claude_code_screen.dart` | 162, 184 | _onData — parse JSON |
| `screens/servers_screen.dart` | 48, 74 | _refresh, _action — HTTP errors |
| `widgets/chat_toolbar.dart` | 204, 267 | _showFolderBrowser, _showFolderBrowser |

### AG-CORE-004: Datos sensibles

`kDesktopFolders` en `widgets/chat_toolbar.dart:11-19` tiene rutas absolutas hardcodeadas con el nombre de usuario del sistema:
```dart
_Folder('AntigravityMobile', r'C:\Users\je416\Desktop\AntigravityMobile'),
```

Si el APK o el bundle web se inspeccionan, revelan el nombre de usuario del host.

---

## 4. Estado de gestión de estado

El paquete `provider: ^6.1.2` está en `pubspec.yaml` pero **no hay ningún import de `package:provider/provider.dart`** en todo el proyecto. Todo es `setState` local.

Consecuencia: cada pantalla instancia sus propios `SessionService`, `ApiKeysService`, `TokenService` y `HubService` por separado. No hay caché compartida. Si `SettingsScreen` cambia el Hub URL, las otras pantallas no se enteran hasta que se reconstruyen.

---

## 5. Hub Backend

### Activo y sin issues:
- `main.py` — FastAPI app, bien estructurado
- `routes/chat.py` — WebSocket /ws/chat, todos los providers
- `routes/health.py` — healthcheck
- `routes/servers.py` — Docker container management
- `routes/agi_agent.py` — AGI streaming
- `routes/claude_code.py` — Claude Code streaming
- `routes/files.py` — File browser para desktop del host
- `routes/providers.py` — status de API keys
- `providers/` — anthropic, gemini, groq, cerebras, codex, openrouter

### Potencialmente huérfano / sin uso activo desde Flutter:
- `routes/daniel.py` — endpoint `/daniel` para comandos de voz desde sistema externo "Daniel". No referenciado desde Flutter. Podría estar siendo llamado por un sistema externo.

### Residuo:
- `hub/routes/__pycache__/jarvis.cpython-311.pyc` — bytecode sin fuente

---

## Conclusión

**No hay HTML/CSS/JS/APK legacy que migrar a Flutter** — el proyecto ya está en Flutter.

**El trabajo de migración es interno al Flutter:** eliminar archivos huérfanos, consolidar la duplicación, e implementar estado global con el `provider` package ya instalado.
