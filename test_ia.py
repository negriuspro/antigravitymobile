import asyncio
import websockets
import json
import os

FOLDER = r"C:\Users\je416\Desktop\proyectos con ia\provando las ia"
HUB = "ws://127.0.0.1:8002"

# (provider, model, nombre_display)
TESTS_AGI = [
    ("groq", "llama-3.3-70b-versatile", "Groq_Llama3.3_70B"),
    ("groq", "llama-3.1-8b-instant", "Groq_Llama3.1_8B"),
    ("groq", "meta-llama/llama-4-scout-17b-16e-instruct", "Groq_Llama4_Scout"),
    ("groq", "qwen/qwen3-32b", "Groq_Qwen3_32B"),
    ("cerebras", "gpt-oss-120b", "Cerebras_GPT_OSS_120B"),
    ("cerebras", "zai-glm-4.7", "Cerebras_ZAI_GLM_4.7"),
]


async def test_agi(provider, model, display):
    """Prueba con orquestador: usa /agi/stream que tiene herramienta write_file."""
    path = f"{FOLDER}\\{display}.txt"
    prompt = (
        f'Usa la herramienta write_file para escribir el archivo "{path}". '
        f"El contenido debe ser exactamente: "
        f'"Hola Angel, soy {display}. Prueba con orquestador activado."'
    )
    out = ""
    async with websockets.connect(f"{HUB}/agi/stream", open_timeout=5) as ws:
        await ws.send(
            json.dumps({"prompt": prompt, "provider": provider, "model": model})
        )
        for _ in range(60):
            msg = await asyncio.wait_for(ws.recv(), timeout=30)
            try:
                d = json.loads(msg)
                if d.get("done"):
                    break
            except Exception:
                out += msg
    return out


async def test_claude_code(display):
    """Prueba Claude Code via /claude/stream."""
    path = f"{FOLDER}\\{display}.txt"
    prompt = (
        f'Crea el archivo "{path}" con el contenido exacto: '
        f'"Hola Angel, soy {display}. Prueba con orquestador activado."'
    )
    out = ""
    async with websockets.connect(f"{HUB}/claude/stream", open_timeout=5) as ws:
        await ws.send(json.dumps({"prompt": prompt}))
        for _ in range(60):
            msg = await asyncio.wait_for(ws.recv(), timeout=60)
            try:
                d = json.loads(msg)
                if d.get("done"):
                    break
            except Exception:
                out += msg
    return out


async def test_sin_orq(provider, model, display):
    """Prueba sin orquestador: usa /ws/chat que NO tiene herramientas."""
    path = f"{FOLDER}\\{display}_sin_orq.txt"
    prompt = f'Crea el archivo "{path}" con el contenido "Hola Angel esto no deberia funcionar".'
    out = ""
    async with websockets.connect(f"{HUB}/ws/chat", open_timeout=5) as ws:
        await ws.send(
            json.dumps(
                {
                    "provider": provider,
                    "model": model,
                    "messages": [{"role": "user", "content": prompt}],
                }
            )
        )
        for _ in range(30):
            msg = await asyncio.wait_for(ws.recv(), timeout=15)
            try:
                d = json.loads(msg)
                if d.get("type") == "chunk":
                    out += d.get("text", "")
                if d.get("type") == "end":
                    break
            except Exception:
                pass
    return out


async def main():
    os.makedirs(FOLDER, exist_ok=True)

    print("=" * 65)
    print("PRUEBA CON ORQUESTADOR (deben crear archivos .txt)")
    print("=" * 65)

    # Claude Code primero
    display = "Claude_Code"
    print(f"\n[{display}]", flush=True)
    try:
        out = await test_claude_code(display)
        path = f"{FOLDER}\\{display}.txt"
        exists = os.path.exists(path)
        print(f"  Archivo creado: {'SI OK' if exists else 'NO FALLO'}")
        if exists:
            print(f"  Contenido: {open(path, encoding='utf-8').read()[:80]}")
        else:
            print(f"  Output: {out[:120]}")
    except Exception as e:
        print(f"  ERROR: {e}")

    # Resto de IAs via AGI
    for provider, model, display in TESTS_AGI:
        print(f"\n[{display}]", flush=True)
        try:
            out = await test_agi(provider, model, display)
            path = f"{FOLDER}\\{display}.txt"
            exists = os.path.exists(path)
            print(f"  Archivo creado: {'SI OK' if exists else 'NO FALLO'}")
            if exists:
                print(f"  Contenido: {open(path, encoding='utf-8').read()[:80]}")
            else:
                print(f"  Output: {out[:120]}")
        except Exception as e:
            print(f"  ERROR: {e}")

    print()
    print("=" * 65)
    print("PRUEBA SIN ORQUESTADOR (NO deben crear archivos)")
    print("=" * 65)

    for provider, model, display in TESTS_AGI[:2]:
        print(f"\n[{display} sin orq]", flush=True)
        try:
            out = await test_sin_orq(provider, model, display)
            path = f"{FOLDER}\\{display}_sin_orq.txt"
            exists = os.path.exists(path)
            print(
                f"  Archivo creado: {'SI MALO - falla de seguridad' if exists else 'NO OK - bloqueado correctamente'}"
            )
            print(f"  Respuesta (solo texto): {out[:100]}")
        except Exception as e:
            print(f"  ERROR: {e}")

    print()
    print("ARCHIVOS EN LA CARPETA:")
    for f in sorted(os.listdir(FOLDER)):
        print(f"  {f}")


asyncio.run(main())
