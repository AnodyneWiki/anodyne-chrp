import json
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


TIMEOUT = 45
CHUNK_ID = "7085"
BASE_SCOPE = "https://protestkit.us/drugspro/"
ASSET_MANIFEST_URL = BASE_SCOPE + "asset-manifest.json"
TARGET_ROUTE_URL = BASE_SCOPE + "reagents/analyze"
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36"


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def fetch_text(url):
    req = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
    started = time.time()
    try:
        with urlopen(req, timeout=TIMEOUT) as res:
            raw = res.read()
            ctype = res.headers.get("Content-Type", "")
            charset = "utf-8"
            m = re.search(r"charset=([^;\s]+)", ctype, re.I)
            if m:
                charset = m.group(1)
            try:
                text = raw.decode(charset, errors="replace")
            except LookupError:
                text = raw.decode("utf-8", errors="replace")
            return {
                "ok": True,
                "status": res.status,
                "url": res.geturl(),
                "headers": dict(res.headers.items()),
                "text": text,
                "elapsed_ms": round((time.time() - started) * 1000),
            }
    except HTTPError as e:
        return {
            "ok": False,
            "status": e.code,
            "url": url,
            "headers": dict(e.headers.items()) if e.headers else {},
            "text": e.read(8192).decode("utf-8", errors="replace"),
            "elapsed_ms": round((time.time() - started) * 1000),
        }
    except URLError as e:
        return {
            "ok": False,
            "status": None,
            "url": url,
            "headers": {},
            "text": str(e.reason),
            "elapsed_ms": round((time.time() - started) * 1000),
        }


def discover_chunk_url():
    
    manifest_res = fetch_text(ASSET_MANIFEST_URL)
    if manifest_res["ok"]:
        try:
            manifest = json.loads(manifest_res["text"])
            manifest_text = json.dumps(manifest, ensure_ascii=False)
            m = re.search(rf"/static/js/{CHUNK_ID}\.[a-f0-9]+\.chunk\.js", manifest_text)
            if m:
                return BASE_SCOPE.rstrip("/") + m.group(0)
        except Exception:
            pass

    
    route_res = fetch_text(TARGET_ROUTE_URL)
    if route_res["ok"]:
        html = route_res["text"]
        script_refs = re.findall(r'<script[^>]+src="([^"]+)"', html, re.I)
        for ref in script_refs:
            if re.search(rf"/static/js/{CHUNK_ID}\.[a-f0-9]+\.chunk\.js", ref):
                if ref.startswith("http://") or ref.startswith("https://"):
                    return ref
                return BASE_SCOPE.rstrip("/") + ref

        main_ref = next((ref for ref in script_refs if "/static/js/main." in ref), None)
        if main_ref:
            main_url = main_ref if main_ref.startswith("http") else BASE_SCOPE.rstrip("/") + main_ref
            
            main_res = fetch_text(main_url)
            if main_res["ok"]:
                m = re.search(rf"{CHUNK_ID}\.[a-f0-9]+\.chunk\.js", main_res["text"])
                if m:
                    return BASE_SCOPE + "static/js/" + m.group(0)

    raise RuntimeError(f"Could not discover current {CHUNK_ID} analyzer chunk URL dynamically")


def extract_embedded_json(chunk_text):
    m = re.search(r'const\s+r=JSON\.parse\(\'((?:\\.|[^\'])*)\'\)', chunk_text)
    if not m:
        raise RuntimeError("Embedded analyzer JSON payload not found in chunk")
    payload = m.group(1)
    payload = bytes(payload, "utf-8").decode("unicode_escape")
    return json.loads(payload)


def build_output(master, chunk_url):
    colors = master["Tj"]
    reagents = master["aZ"]
    substances = master["sE"]
    reaction_matrix = master["Xv"]

    reagent_by_id = {int(k): v for k, v in reagents.items()}
    color_by_id = {int(k): v for k, v in colors.items()}

    output = {
        "generated_at": now_iso(),
        "source": {
            "chunk_url": chunk_url,
            "chunk_id": CHUNK_ID,
        },
        "counts": {
            "colors": len(colors),
            "reagents": len(reagents),
            "substances_total": len(substances),
            "substances_with_reactions": len(reaction_matrix),
        },
        "substances": [],
    }

    for substance_id_str, reagent_entries in sorted(reaction_matrix.items(), key=lambda x: int(x[0])):
        substance_id = int(substance_id_str)
        substance = substances.get(substance_id_str, {})
        pretty_reagents = []

        for reagent_id_str, variants in sorted(reagent_entries.items(), key=lambda x: int(x[0])):
            reagent_id = int(reagent_id_str)
            reagent = reagent_by_id.get(reagent_id, {})
            pretty_variants = []

            for idx, variant in enumerate(variants, start=1):
                detailed_color_ids = [int(x) for x in (variant[0] or [])]
                simple_color_ids = [int(x) for x in (variant[1] or [])]
                pretty_variants.append(
                    {
                        "variant_index": idx,
                        "reacts": bool(variant[2]),
                        "result_text": variant[3] or "",
                        "detailed_color_ids": detailed_color_ids,
                        "detailed_colors": [
                            color_by_id[color_id]["name"]
                            for color_id in detailed_color_ids
                            if color_id in color_by_id
                        ],
                        "simple_color_ids": simple_color_ids,
                        "simple_colors": [
                            color_by_id[color_id]["name"]
                            for color_id in simple_color_ids
                            if color_id in color_by_id
                        ],
                    }
                )

            pretty_reagents.append(
                {
                    "reagent_id": reagent_id,
                    "reagent_short": reagent.get("shortName", ""),
                    "reagent_name": reagent.get("fullName") or reagent.get("name") or "",
                    "variants": pretty_variants,
                }
            )

        output["substances"].append(
            {
                "substance_id": substance_id,
                "token": substance.get("token", ""),
                "name": substance.get("name", ""),
                "common_name": substance.get("commonName", ""),
                "is_popular": bool(substance.get("isPopular")),
                "reagents": pretty_reagents,
            }
        )

    return output


def DrugsProScraper():
    chunk_url = discover_chunk_url()
    
    chunk_res = fetch_text(chunk_url)
    if not chunk_res["ok"]:
        raise RuntimeError(f"Failed to fetch live analyzer chunk: {chunk_res['status']} {chunk_res['url']}")

    master = extract_embedded_json(chunk_res["text"])
    output = build_output(master, chunk_url)
    return json.dumps(output, ensure_ascii=False, indent=2)
