# Migration Plan — AntigravityMobile
**Generado:** 2026-06-02  
**Objetivo:** Migrar completamente a Flutter moderno  
**Restricciones:** No tocar AngelOS, APK Android, carpetas Android, Tablet Interface

---

## Estado actual

El proyecto **ya es Flutter moderno** (SDK >=3.3.0, Dart records, null safety). No hay HTML/CSS/JS/APK legacy que migrar.

El trabajo es una **modernización interna de Flutter**: eliminar duplicación, implementar estado global, y usar el `MessageBubble` compartido en lugar de los privados.

---

## FASE 1 — Limpieza de archivos huérfanos

**Condición de entrada:** ninguna  
**Riesgo:** bajo — ningún archivo activo los importa  
**Archivos API / Docker afectados:** ninguno

### 1.1 Eliminar widgets huérfanos

Eliminar:
- `mobile/lib/widgets/provider_selector.dart`
  - Sin referencias. Seguro.
- `mobile/lib/widgets/message_bubble.dart`
  - Sin referencias desde pantallas. ⚠️ Antes de eliminar, extraer la lógica de Markdown + copy-to-clipboard hacia el nuevo `ChatBubble` compartido (ver FASE 3.1).

### 1.2 Eliminar modelo huérfano

Eliminar:
- `mobile/lib/models/message.dart`
  - Solo después de haber eliminado `message_bubble.dart` y `provider_selector.dart`.
  - La clase `ChatMessage` canónica ya existe en `session_service.dart`.

### 1.3 Limpiar bytecode huérfano del Hub

Eliminar:
- `hub/routes/__pycache__/jarvis.cpython-311.pyc`
  - Bytecode sin fuente. No hay `from routes.jarvis import router` en `main.py`.

### Entregable FASE 1
- [ ] `provider_selector.dart` eliminado
- [ ] `message_bubble.dart` eliminado (después de FASE 3.1)
- [ ] `models/message.dart` eliminado
- [ ] `jarvis.cpython-311.pyc` eliminado

---

## FASE 2 — Extracción de servicios compartidos

**Objetivo:** eliminar la duplicación de lógica de negocio entre las 3 pantallas de chat  
**Afecta:** `chat_claude_screen.dart`, `agi_chat_screen.dart`, `claude_code_screen.dart`  
**Archivos API / Docker afectados:** ninguno

### 2.1 Mover `ChatMessage` y `ChatSession` a `models/`

Crear `mobile/lib/models/chat.dart` con:
- `class ChatMessage` (tal como está en `session_service.dart`)
- `class ChatSession` (tal como está en `session_service.dart`)

Actualizar `session_service.dart` para importarlos desde `models/chat.dart`.  
Actualizar los 3 screens para importar desde `models/chat.dart`.

### 2.2 Crear `ChatWebSocketService`

Crear `mobile/lib/services/chat_ws_service.dart` que encapsule:
- Conexión WebSocket al Hub
- Parsing de mensajes `type: start/chunk/end`
- Streaming de chunks a un `Stream<ChatEvent>`
- Reconexión automática

Las 3 pantallas actualmente duplican `_connect()`, `_onData()`, `_hubWs`. Este servicio centraliza todo.

**API pública sugerida:**
```dart
class ChatWsService {
  Stream<ChatEvent> connect(String endpoint);
  void send(Map<String, dynamic> payload);
  void close();
}
```

### 2.3 Crear `HubUrlProvider` (ChangeNotifier)

Crear `mobile/lib/providers/hub_url_provider.dart`:
- Carga la Hub URL una sola vez
- Notifica a todos los widgets cuando cambia (desde SettingsScreen)

Esto elimina los 5 lugares donde se hace `prefs.getString('hub_url')` directamente.

### 2.4 Unificar `_fmt` / `_formatDate`

Crear `mobile/lib/utils/date_format.dart`:
```dart
String formatRelativeDate(DateTime dt) { ... }
```

Eliminar las 3 implementaciones duplicadas en las pantallas.

### 2.5 Unificar `_saveSession`

Mover la lógica de auto-título (truncar primer mensaje a 40 chars) a un método en `SessionService`:
```dart
Future<void> saveWithAutoTitle(ChatSession session, List<ChatMessage> messages)
```

Eliminar las 3 implementaciones duplicadas.

### Entregable FASE 2
- [ ] `models/chat.dart` creado con `ChatMessage` y `ChatSession`
- [ ] `session_service.dart` importa desde `models/chat.dart`
- [ ] `services/chat_ws_service.dart` creado
- [ ] `providers/hub_url_provider.dart` creado (ChangeNotifier)
- [ ] `utils/date_format.dart` creado
- [ ] `SessionService.saveWithAutoTitle()` creado

---

## FASE 3 — Unificación de widgets

**Objetivo:** un solo `ChatBubble` en lugar de 3 clases `_Bubble` privadas

### 3.1 Actualizar `MessageBubble` como `ChatBubble`

Actualizar `mobile/lib/widgets/chat_bubble.dart` (renombrar de `message_bubble.dart`):
- Usar `ChatMessage` de `models/chat.dart` (no el viejo `models/message.dart`)
- Mantener soporte Markdown con `flutter_markdown` (ya instalado)
- Mantener copy-to-clipboard con long press
- Añadir soporte para `imageB64` (que los `_Bubble` de claude y agi tienen pero `message_bubble` no tenía)
- Recibir `Color accentColor` como parámetro (para que cada pantalla pase su color)

**Campos necesarios del nuevo `ChatBubble`:**
```dart
class ChatBubble extends StatelessWidget {
  final ChatMessage msg;       // de models/chat.dart
  final Color accentColor;
  final bool renderMarkdown;   // false para streams en curso (evita re-parse)
}
```

### 3.2 Reemplazar `_Bubble` en las 3 pantallas

Reemplazar en:
- `chat_claude_screen.dart` — `class _Bubble` → `ChatBubble`
- `agi_chat_screen.dart` — `class _Bubble` → `ChatBubble`
- `claude_code_screen.dart` — `class _BubbleWidget` → `ChatBubble`

### Entregable FASE 3
- [ ] `widgets/chat_bubble.dart` creado (reemplazo de `message_bubble.dart`)
- [ ] `_Bubble` eliminado de `chat_claude_screen.dart`
- [ ] `_Bubble` eliminado de `agi_chat_screen.dart`
- [ ] `_BubbleWidget` eliminado de `claude_code_screen.dart`

---

## FASE 4 — Estado global con Provider

**Objetivo:** usar el paquete `provider` ya instalado (actualmente sin uso)

### 4.1 Wiring en `main.dart`

Envolver `MaterialApp` en `MultiProvider`:

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => HubUrlProvider()),
    ChangeNotifierProvider(create: (_) => TokenProvider()),
  ],
  child: MaterialApp(...),
)
```

### 4.2 Migrar carga de Hub URL

Reemplazar los 5 accesos directos a `prefs.getString('hub_url')` por:
```dart
context.read<HubUrlProvider>().url
```

### 4.3 TokenProvider (opcional, baja prioridad)

Si se quiere que el `ProviderStatusDot` reaccione en tiempo real a cambios de cuota, crear `TokenProvider` como `ChangeNotifier`.

### Entregable FASE 4
- [ ] `providers/hub_url_provider.dart` registrado en `main.dart`
- [ ] Los 5 accesos directos a `hub_url` en SharedPreferences reemplazados
- [ ] `provider` package efectivamente en uso

---

## FASE 5 — Correcciones de AG-CORE

**Objetivo:** corregir violaciones de políticas  
**AG-CORE-001:** Catch vacío prohibido  
**AG-CORE-004:** Credenciales / paths sensibles

### 5.1 Reemplazar catch vacíos

Por cada `catch (_) {}` identificado en el `legacy-report.md`:

```dart
// Antes (violación AG-CORE-001)
} catch (_) {}

// Después
} catch (e) {
  debugPrint('[NombreClase] error: $e');
}
```

En producción (build release), `debugPrint` no imprime. En debug sí. Alternativa: usar un `logger` package.

Archivos afectados:
- `services/hub_service.dart:39`
- `screens/chat_claude_screen.dart:88`
- `screens/agi_chat_screen.dart:122`
- `screens/claude_code_screen.dart:162, 184`
- `screens/servers_screen.dart:48, 74`
- `widgets/chat_toolbar.dart:204, 267`

### 5.2 Mover `kDesktopFolders` a configuración

Mover las rutas hardcodeadas de `chat_toolbar.dart:11-19` a un archivo de configuración externo o a `SharedPreferences` con UI para editarlos desde `SettingsScreen`.

Mínimo: mover a una constante en `core/constants.dart` claramente marcada como "configuración del entorno del usuario".

### Entregable FASE 5
- [ ] 9 catch vacíos corregidos
- [ ] `kDesktopFolders` sacado de producción o configurable

---

## Orden de ejecución recomendado

```
FASE 1 (parcial: provider_selector + jarvis.pyc)
  ↓
FASE 2 (modelos + servicios)
  ↓
FASE 3 (ChatBubble unificado)
  ↓
FASE 1 (completar: message_bubble + models/message.dart)
  ↓
FASE 4 (state management)
  ↓
FASE 5 (AG-CORE fixes)
```

---

## Organización de carpetas objetivo

```
mobile/lib/
├── main.dart
├── models/
│   └── chat.dart              ← ChatMessage + ChatSession (unificados)
├── providers/
│   └── hub_url_provider.dart  ← ChangeNotifier para Hub URL
├── screens/
│   ├── home_screen.dart
│   ├── chat_claude_screen.dart
│   ├── agi_chat_screen.dart
│   ├── claude_code_screen.dart
│   ├── servers_screen.dart
│   ├── settings_screen.dart
│   └── tokens_screen.dart
├── services/
│   ├── api_keys_service.dart
│   ├── chat_ws_service.dart   ← NUEVO — WebSocket centralizado
│   ├── hub_service.dart
│   ├── session_service.dart
│   └── token_service.dart
├── theme/
│   └── app_theme.dart
├── utils/
│   └── date_format.dart       ← NUEVO — formatRelativeDate()
└── widgets/
    ├── chat_bubble.dart        ← NUEVO (reemplaza 3 _Bubble privados)
    ├── chat_toolbar.dart
    └── provider_status_dot.dart
```

**Eliminados:**
- `models/message.dart` ❌
- `widgets/message_bubble.dart` ❌ (reemplazado por chat_bubble.dart)
- `widgets/provider_selector.dart` ❌

---

## Archivos eliminados (lista final)

| Archivo | Razón | Reemplazado por |
|---|---|---|
| `mobile/lib/models/message.dart` | Huérfano, conflicto con `session_service.dart` | `models/chat.dart` |
| `mobile/lib/widgets/message_bubble.dart` | Huérfano, reemplazado por versión unificada | `widgets/chat_bubble.dart` |
| `mobile/lib/widgets/provider_selector.dart` | Huérfano, sin reemplazo necesario | — |
| `hub/routes/__pycache__/jarvis.cpython-311.pyc` | Bytecode sin fuente | — |

**Total: 4 archivos eliminados**

---

## Lo que NO cambia

- Hub backend Python (FastAPI) — sin modificaciones
- Docker Compose — sin modificaciones
- Nginx — sin modificaciones
- API WebSocket/HTTP — sin cambios de contrato
- `hub/routes/daniel.py` — en espera de confirmar si tiene consumidores externos
