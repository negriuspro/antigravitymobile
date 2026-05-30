import base64
import os
from fastapi import APIRouter, Query
from fastapi.responses import JSONResponse

router = APIRouter()

FILES_BASE = os.environ.get("FILES_BASE_PATH", "/data/files")
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp"}


@router.get("/files/list")
def list_dir(path: str = Query(default=FILES_BASE)):
    try:
        if not os.path.isabs(path):
            path = os.path.join(FILES_BASE, path)
        if not os.path.isdir(path):
            return JSONResponse({"error": "No es un directorio"}, status_code=400)

        entries = []
        for name in sorted(os.listdir(path)):
            full = os.path.join(path, name)
            is_dir = os.path.isdir(full)
            ext = os.path.splitext(name)[1].lower()
            entries.append({
                "name": name,
                "path": full,
                "isDir": is_dir,
                "isImage": ext in IMAGE_EXTS,
            })
        return {"path": path, "entries": entries}
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


@router.get("/files/image")
def get_image(path: str = Query(...)):
    try:
        if not os.path.isfile(path):
            return JSONResponse({"error": "Archivo no encontrado"}, status_code=404)
        ext = os.path.splitext(path)[1].lower()
        mime = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",
                ".gif": "image/gif", ".webp": "image/webp", ".bmp": "image/bmp"}.get(ext, "image/jpeg")
        with open(path, "rb") as f:
            data = base64.b64encode(f.read()).decode()
        return {"mime": mime, "data": f"data:{mime};base64,{data}"}
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
