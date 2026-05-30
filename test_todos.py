import asyncio, websockets, json, os

FOLDER = r"C:\Users\je416\Desktop\proyectos con ia\provando las ia"
HUB = "ws://127.0.0.1:8002"

TESTS = [
    # (tipo, provider, model, display)
    ("claude", None, None,                                          "Claude_Code"),
    ("agi", "groq",     "llama-3.3-70b-versatile",                 "Groq_Llama3.3_70B"),
    ("agi", "groq",     "meta-llama/llama-4-scout-17b-16e-instruct","Groq_Llama4_Scout"),
    ("agi", "groq",     "qwen/qwen3-32b",                          "Groq_Qwen3_32B"),
    ("agi", "cerebras", "qwen-3-235b-a22b-instruct-2507",          "Cerebras_Qwen3_235B"),
    ("agi", "cerebras", "gpt-oss-120b",                            "Cerebras_GPT_OSS_120B"),
    ("agi", "cerebras", "llama3.1-8b",                             "Cerebras_Llama3.1_8B"),
    ("agi", "groq",     "llama-3.3-70b-versatile",                 "Chat_Groq_Llama3.3"),
    ("agi", "groq",     "meta-llama/llama-4-scout-17b-16e-instruct","Chat_Groq_Llama4_Scout"),
    ("agi", "groq",     "qwen/qwen3-32b",                          "Chat_Groq_Qwen3_32B"),
    ("agi", "cerebras", "qwen-3-235b-a22b-instruct-2507",          "Chat_Cerebras_Qwen3"),
    ("agi", "cerebras", "gpt-oss-120b",                            "Chat_Cerebras_GPT_OSS"),
    ("agi", "gemini",   "gemini-1.5-flash",                        "Chat_Gemini_1.5_Flash"),
    ("agi", "gemini",   "gemini-1.5-pro",                          "Chat_Gemini_1.5_Pro"),
    ("agi", "gemini",   "gemini-2.0-flash",                        "Chat_Gemini_2.0_Flash"),
    ("claude_chat", None, "claude-sonnet-4-6",                     "Claude_Chat_Sonnet4.6"),
]

async def run(tipo, provider, model, display):
    path = f"{FOLDER}\\{display}.txt"
    content = f"Hola Angel, soy {display}. Prueba exitosa con orquestador activado."

    if tipo == "claude":
        prompt = f'Crea el archivo "{path}" con el contenido exacto: "{content}"'
        async with websockets.connect(f"{HUB}/claude/stream", open_timeout=5) as ws:
            await ws.send(json.dumps({"prompt": prompt}))
            out = ""
            for _ in range(60):
                msg = await asyncio.wait_for(ws.recv(), timeout=60)
                try:
                    d = json.loads(msg)
                    if d.get("done"): break
                except: out += msg
            return out

    elif tipo == "agi":
        prompt = f'Usa write_file para crear "{path}" con contenido: "{content}"'
        async with websockets.connect(f"{HUB}/agi/stream", open_timeout=5) as ws:
            await ws.send(json.dumps({"prompt": prompt, "provider": provider, "model": model}))
            out = ""
            for _ in range(60):
                msg = await asyncio.wait_for(ws.recv(), timeout=30)
                try:
                    d = json.loads(msg)
                    if d.get("done"): break
                except: out += msg
            return out

    elif tipo == "claude_chat":
        # Claude chat via /ws/chat endpoint (usa CLI internamente)
        prompt = f'Crea el archivo "{path}" con el contenido exacto: "{content}"'
        async with websockets.connect(f"{HUB}/ws/chat", open_timeout=5) as ws:
            await ws.send(json.dumps({"provider": "claude", "model": model,
                                      "messages": [{"role": "user", "content": prompt}]}))
            out = ""
            for _ in range(60):
                msg = await asyncio.wait_for(ws.recv(), timeout=60)
                try:
                    d = json.loads(msg)
                    if d.get("type") == "chunk": out += d.get("text", "")
                    if d.get("type") == "end": break
                except: pass
            return out

    else:  # chat - sin orquestador
        prompt = f'Di exactamente sin nada más: "Hola Angel, soy {display}. Sin orquestador, solo chat."'
        async with websockets.connect(f"{HUB}/ws/chat", open_timeout=5) as ws:
            await ws.send(json.dumps({"provider": provider, "model": model,
                                      "messages": [{"role": "user", "content": prompt}]}))
            out = ""
            for _ in range(30):
                msg = await asyncio.wait_for(ws.recv(), timeout=15)
                try:
                    d = json.loads(msg)
                    if d.get("type") == "chunk": out += d.get("text", "")
                    if d.get("type") == "end": break
                except: pass
            return out

async def main():
    os.makedirs(FOLDER, exist_ok=True)
    print(f"\nCarpeta: {FOLDER}\n")
    print(f"{'MODELO':<35} {'ARCHIVO':^10} {'RESULTADO'}")
    print("-" * 75)

    for tipo, provider, model, display in TESTS:
        path = f"{FOLDER}\\{display}.txt"
        already = os.path.exists(path)
        if already:
            print(f"  {display:<33} [YA EXISTE] saltando")
            continue
        try:
            out = await run(tipo, provider, model, display)
            exists = os.path.exists(path)
            if tipo in ("claude", "agi", "claude_chat"):
                status = "CREADO OK" if exists else f"FALLO: {out[:60]}"
            else:
                # Chat: mostrar la respuesta
                status = f"RESP: {out.strip()[:60]}"
            print(f"  {display:<33} {status}")
        except Exception as e:
            print(f"  {display:<33} ERROR: {e}")

    print()
    print("ARCHIVOS EN LA CARPETA:")
    for f in sorted(os.listdir(FOLDER)):
        print(f"  {f}")

asyncio.run(main())
