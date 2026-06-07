# Dependency Map — AntigravityMobile
**Generado:** 2026-06-02  
**Proyecto:** AntigravityMobile

---

## Leyenda

- ✅ **EN USO** — referenciado activamente, no tocar
- ⚠️ **PARCIAL** — en uso pero con partes obsoletas o duplicadas
- ❌ **OBSOLETO** — sin referencias activas, candidato a eliminar
- 🔁 **DUPLICADO** — existe una versión mejor/más completa sin usar

---

## Flutter — Capa de pantallas (`lib/screens/`)

| Archivo | Estado | Referenciado desde | Notas |
|---|---|---|---|
| `home_screen.dart` | ✅ EN USO | `main.dart` | Shell tab 0, quick actions |
| `chat_claude_screen.dart` | ✅ EN USO | `main.dart` | Shell tab 1 + ruta `/chat` |
| `agi_chat_screen.dart` | ✅ EN USO | `main.dart` | Shell tab 2 + ruta `/agi` |
| `claude_code_screen.dart` | ✅ EN USO | `main.dart` | Ruta `/claude-code` |
| `servers_screen.dart` | ✅ EN USO | `main.dart` | Ruta `/servers` |
| `settings_screen.dart` | ✅ EN USO | `main.dart` | Shell tab 3 + ruta `/settings` |
| `tokens_screen.dart` | ✅ EN USO | `main.dart` | Ruta `/tokens` |

---

## Flutter — Capa de widgets (`lib/widgets/`)

| Archivo | Estado | Referenciado desde | Notas |
|---|---|---|---|
| `chat_toolbar.dart` | ✅ EN USO | `chat_claude_screen`, `agi_chat_screen`, `claude_code_screen` | Toolbar de input (mic, imagen, texto, enviar) |
| `provider_status_dot.dart` | ✅ EN USO | `chat_claude_screen`, `agi_chat_screen`, `claude_code_screen` | Dot de estado por proveedor |
| `message_bubble.dart` | ❌ OBSOLETO | Ninguno | Widget huérfano. Importa `models/message.dart`. Las pantallas usan `_Bubble` inline. Tiene Markdown, copy-to-clipboard — mejor que los inline. |
| `provider_selector.dart` | ❌ OBSOLETO | Ninguno | Widget huérfano. Usa `AIProvider` de models. Las pantallas tienen su propio provider picker inline. |

---

## Flutter — Capa de modelos (`lib/models/`)

| Archivo | Estado | Referenciado desde | Notas |
|---|---|---|---|
| `models/message.dart` | ❌ OBSOLETO | Solo por `message_bubble.dart` y `provider_selector.dart` (también huérfanos) | Define `ChatMessage` alternativo incompatible con el de `session_service.dart` |

---

## Flutter — Capa de servicios (`lib/services/`)

| Archivo | Estado | Referenciado desde | Notas |
|---|---|---|---|
| `session_service.dart` | ✅ EN USO | `chat_claude_screen`, `agi_chat_screen`, `claude_code_screen` | También define `ChatMessage` y `ChatSession` — la definición canónica real |
| `hub_service.dart` | ⚠️ PARCIAL | `home_screen`, `settings_screen`, `chat_toolbar`, `provider_status_dot` | `getHubUrl()` existe pero 5 otros archivos bypasean y leen `SharedPreferences` directamente |
| `api_keys_service.dart` | ✅ EN USO | `chat_claude_screen`, `agi_chat_screen`, `claude_code_screen`, `settings_screen` | — |
| `token_service.dart` | ✅ EN USO | `chat_claude_screen`, `agi_chat_screen`, `claude_code_screen`, `tokens_screen`, `provider_status_dot` | — |

---

## Flutter — Tema y entrada

| Archivo | Estado | Referenciado desde | Notas |
|---|---|---|---|
| `theme/app_theme.dart` | ✅ EN USO | Casi todos los archivos | Tema oscuro con Google Fonts Inter |
| `main.dart` | ✅ EN USO | Entrypoint | Define `_Shell` con BottomNavigationBar, rutas |

---

## Flutter — Paquetes (`pubspec.yaml`)

| Paquete | Estado | Dónde se usa | Notas |
|---|---|---|---|
| `flutter` | ✅ EN USO | Todo | SDK base |
| `web_socket_channel: ^2.4.0` | ✅ EN USO | 3 pantallas de chat | WebSocket con Hub |
| `http: ^1.2.1` | ✅ EN USO | `hub_service`, `servers_screen`, `provider_status_dot`, `chat_toolbar` | HTTP calls |
| `shared_preferences: ^2.3.2` | ✅ EN USO | Todos los servicios + pantallas | Persistencia local |
| `provider: ^6.1.2` | ❌ NO USADO | Ninguno | En pubspec, **nunca importado** |
| `google_fonts: ^6.2.1` | ✅ EN USO | `app_theme.dart` | Inter font |
| `url_launcher: ^6.3.0` | ⚠️ DUDOSO | No se encontró en código fuente | Posiblemente vestigial |
| `file_picker: ^8.1.2` | ✅ EN USO | `chat_toolbar.dart` | Pick de imágenes |
| `speech_to_text: ^6.6.2` | ✅ EN USO | `chat_toolbar.dart` | STT |
| `flutter_markdown: ^0.7.3` | ⚠️ SOLO EN HUÉRFANO | Solo `message_bubble.dart` (huérfano) | Si se elimina `message_bubble.dart` sin reemplazar, se puede quitar |

---

## Hub Backend — Rutas (`hub/routes/`)

| Archivo | Estado | Llamado desde | Notas |
|---|---|---|---|
| `health.py` | ✅ EN USO | Docker healthcheck, `hub_service.dart` | `GET /health` |
| `chat.py` | ✅ EN USO | 3 pantallas Flutter | `WS /ws/chat` — multi-provider streaming |
| `servers.py` | ✅ EN USO | `servers_screen.dart` | `GET/POST /servers/*` |
| `agi_agent.py` | ✅ EN USO | `claude_code_screen.dart` | `WS /agi/stream` |
| `claude_code.py` | ✅ EN USO | `claude_code_screen.dart` | `WS /claude/stream` |
| `files.py` | ✅ EN USO | `chat_toolbar.dart` | `GET /files/list`, `GET /files/image` |
| `providers.py` | ✅ EN USO | `provider_status_dot.dart` | `GET /providers/status` |
| `daniel.py` | ⚠️ EXTERNO | No desde Flutter — sistema externo | `POST /daniel` — endpoint para voz desde "Daniel". No eliminar sin confirmar |
| `__pycache__/jarvis.cpython-311.pyc` | ❌ OBSOLETO | Ninguno | Bytecode sin fuente. Nunca registrado en `main.py`. |

---

## Hub Backend — Providers (`hub/providers/`)

| Archivo | Estado | Llamado desde | Notas |
|---|---|---|---|
| `anthropic.py` | ✅ EN USO | `chat.py`, `daniel.py`, `claude_code.py` | `stream_claude` |
| `gemini.py` | ✅ EN USO | `chat.py` | `stream_gemini` |
| `groq.py` | ✅ EN USO | `chat.py`, `agi_agent.py` | `stream_groq` |
| `cerebras.py` | ✅ EN USO | `chat.py` | `stream_cerebras` |
| `codex.py` | ✅ EN USO | `chat.py`, `claude_code.py` | `stream_codex` (OpenAI) |
| `openrouter.py` | ✅ EN USO | `chat.py` | `stream_openrouter` |
| `models.py` | ✅ EN USO | `agi_agent.py` | Definiciones de modelos/providers |

---

## Hub Backend — Core (`hub/core/`)

| Archivo | Estado | Notas |
|---|---|---|
| `config.py` | ✅ EN USO | Settings con pydantic-settings, lee `.env` |
| `ws_manager.py` | ✅ EN USO | Gestiona conexiones WebSocket activas |

---

## Docker / Infraestructura

| Archivo | Estado | Notas |
|---|---|---|
| `docker-compose.yml` | ✅ EN USO | Producción — nginx, frontend, backend, redis, docker-socket-proxy |
| `docker-compose.dev.yml` | ✅ EN USO | Overrides de desarrollo |
| `nginx/` | ✅ EN USO | Gateway único, proxy a frontend y backend |
| `nginx-mobile.conf` | ✅ EN USO | Config nginx principal |
| `hub/Dockerfile` | ✅ EN USO | Imagen backend Python |
| `mobile/Dockerfile` | ✅ EN USO | Imagen frontend Flutter Web |
| `scripts/` | ✅ EN USO | backup, deploy, rollback, start/stop WSL |

---

## Resumen — qué puede eliminarse

### Eliminar con seguridad (sin referencias, con reemplazo):

| Archivo | Condición para eliminar |
|---|---|
| `mobile/lib/models/message.dart` | Después de eliminar los 2 widgets que lo importan |
| `mobile/lib/widgets/message_bubble.dart` | Después de reemplazar los `_Bubble` inline en pantallas (FASE 3) |
| `mobile/lib/widgets/provider_selector.dart` | Sin condición — huérfano total |
| `hub/routes/__pycache__/jarvis.cpython-311.pyc` | Sin condición — bytecode huérfano |

### NO eliminar sin confirmación:

| Archivo | Motivo |
|---|---|
| `hub/routes/daniel.py` | Sistema externo podría estar llamando `/daniel` |
| `url_launcher` en pubspec | Verificar si hay uso en web views oculto antes de quitar |
