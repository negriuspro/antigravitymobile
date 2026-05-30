# AGENTS.md -- AntigravityMobile
# Generado por Antigravity AI v3 el 2026-05-25
# Instrucciones especificas de este proyecto.

## Proyecto

- Nombre: AntigravityMobile
- Tipo: webapp
- Agente principal: ArchitectAgent + UiUxAgent
- Modo: MODE_FAST

## Reglas de sesion

- Leer siempre .ai/STATE.md al inicio
- Maximo 3 archivos modificados por sesion (Change Scope Limiter)
- Cerrar sesion con: Close-Session -Auto -Summary "..." -Agent "NombreAgente" -FinalState "Estado" -FilesModified N

## Politicas AG-CORE activas

Ver: c:/Users/je416/Desktop/AI_IDE_Agents/core/policies.md

Criticas para este proyecto:
- AG-CORE-001: No catch vacio -- siempre loguear
- AG-CORE-004: No credenciales en texto plano
- AG-CORE-005: Sanitizar inputs en capa de entrada
- AG-CORE-006: No console.log/print en produccion