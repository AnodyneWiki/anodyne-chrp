import re
import json
import sys
from datetime import datetime, timezone

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

POSTS_FILE  = "r_tripreports_posts.jsonl"
EROWID_FILE = "erowid_substances.json"
OUTPUT_FILE = "reddit_test.json"

# Minimum body length to consider a post a real trip report.
# Posts under this threshold are almost always just a title with no content,
# a link post, or a one-liner that carries no useful report data.
MIN_BODY_LENGTH = 500

# ---------------------------------------------------------------------------
# Slang / alias → canonical substance name
# These are common informal names that won't appear in the Erowid list but
# are extremely frequent in trip report text.
# ---------------------------------------------------------------------------

SLANG: dict[str, str] = {
    # Psychedelics
    "acid":          "LSD",
    "lsd":           "LSD",
    "tabs":          "LSD",
    "blotter":       "LSD",
    "shrooms":       "Psilocybin Mushrooms",
    "mushrooms":     "Psilocybin Mushrooms",
    "mush":          "Psilocybin Mushrooms",
    "psilocybin":    "Psilocybin",
    "psilocin":      "Psilocin",
    "dmt":           "DMT",
    "ayahuasca":     "Ayahuasca",
    "salvia":        "Salvia divinorum",
    "mescaline":     "Mescaline",
    "peyote":        "Peyote",
    "ibogaine":      "Ibogaine",
    "iboga":         "Ibogaine",
    "2cb":           "2C-B",
    "2c-b":          "2C-B",
    "nbome":         "NBOMe",
    "25i":           "25I-NBOMe",
    "25b":           "25B-NBOMe",
    "25c":           "25C-NBOMe",
    # Dissociatives
    "ketamine":      "Ketamine",
    "ket":           "Ketamine",
    "special k":     "Ketamine",
    "dxm":           "DXM",
    "robo":          "DXM",
    "pcp":           "PCP",
    "mxe":           "Methoxetamine",
    "nitrous":       "Nitrous Oxide",
    "nos":           "Nitrous Oxide",
    "whippets":      "Nitrous Oxide",
    # Empathogens / entactogens
    "mdma":          "MDMA",
    "molly":         "MDMA",
    "ecstasy":       "MDMA",
    "mda":           "MDA",
    "5mapb":         "5-MAPB",
    "6apb":          "6-APB",
    # Stimulants
    "cocaine":       "Cocaine",
    "coke":          "Cocaine",
    "crack":         "Crack Cocaine",
    "meth":          "Methamphetamine",
    "crystal":       "Methamphetamine",
    "ice":           "Methamphetamine",
    "amphetamine":   "Amphetamine",
    "adderall":      "Amphetamine",
    "speed":         "Amphetamine",
    "vyvanse":       "Lisdexamfetamine",
    "ritalin":       "Methylphenidate",
    "caffeine":      "Caffeine",
    # Depressants / opioids
    "heroin":        "Heroin",
    "dope":          "Heroin",
    "fentanyl":      "Fentanyl",
    "oxycodone":     "Oxycodone",
    "oxy":           "Oxycodone",
    "percocet":      "Oxycodone",
    "hydrocodone":   "Hydrocodone",
    "vicodin":       "Hydrocodone",
    "codeine":       "Codeine",
    "tramadol":      "Tramadol",
    "morphine":      "Morphine",
    "methadone":     "Methadone",
    "buprenorphine": "Buprenorphine",
    "suboxone":      "Buprenorphine",
    "kratom":        "Kratom",
    "alcohol":       "Alcohol",
    "ethanol":       "Alcohol",
    "booze":         "Alcohol",
    "beer":          "Alcohol",
    "wine":          "Alcohol",
    "vodka":         "Alcohol",
    "whiskey":       "Alcohol",
    # Benzodiazepines
    "xanax":         "Alprazolam",
    "alprazolam":    "Alprazolam",
    "xans":          "Alprazolam",
    "valium":        "Diazepam",
    "diazepam":      "Diazepam",
    "klonopin":      "Clonazepam",
    "clonazepam":    "Clonazepam",
    "ativan":        "Lorazepam",
    "lorazepam":     "Lorazepam",
    # Cannabinoids
    "weed":          "Cannabis",
    "cannabis":      "Cannabis",
    "marijuana":     "Cannabis",
    "thc":           "Cannabis",
    "cbd":           "CBD",
    "dabs":          "Cannabis",
    "edibles":       "Cannabis",
    # Deliriants
    "dph":           "Diphenhydramine",
    "benadryl":      "Diphenhydramine",
    "datura":        "Datura",
    "scopolamine":   "Scopolamine",
    # Other
    "ghb":           "GHB",
    "gbl":           "GBL",
    "kanna":         "Kanna",
    "catnip":        "Catnip",
    "nutmeg":        "Nutmeg",
}

# Erowid names that are common English words, generic category labels, or
# otherwise too ambiguous to use as substance detectors in free text.
EROWID_STOPWORDS: set[str] = {
    # Common English words
    "same", "placebo", "tea", "hops", "aloes", "anise", "cacao",
    "myrrh", "ether", "ergot", "coca", "kava", "xenon", "opium",
    # Generic Erowid category labels — not specific substances
    "stimulants", "opioids", "inhalants", "unknown", "mushrooms",
    "plants", "herbs", "supplements", "depressants", "psychedelics",
    "dissociatives", "deliriants", "entactogens", "nootropics",
    "steroids", "pharms", "smart drugs",
    # 3-letter names that are common English words / fragments and produce
    # constant false positives in free text (Unicode apostrophes break \b)
    "don", "met", "dom", "bod", "mem", "pce",
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def load_erowid_substances(path: str) -> dict[str, str]:
    """
    Returns a dict of lowercase_name -> canonical_name for all Erowid
    substances, excluding known stopwords.
    """
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    result = {}
    for item in data:
        name = item["name"]
        if name.lower() not in EROWID_STOPWORDS:
            result[name.lower()] = name
    return result


def detect_substances(text: str, erowid_map: dict[str, str]) -> list[str]:
    """
    Detect substance names in free text using two passes:
      1. Slang/alias dictionary (word-boundary regex)
      2. Erowid canonical names (word-boundary regex, min 3 chars)

    Returns a deduplicated list of canonical substance names, sorted.
    """
    lower = text.lower()
    found: set[str] = set()

    # Pass 1 — slang
    for slang, canonical in SLANG.items():
        if re.search(r"\b" + re.escape(slang) + r"\b", lower):
            found.add(canonical)

    # Pass 2 — Erowid names (skip very short ones that are too ambiguous)
    for name_lower, canonical in erowid_map.items():
        if len(name_lower) < 3:
            continue
        if re.search(r"\b" + re.escape(name_lower) + r"\b", lower):
            found.add(canonical)

    return sorted(found)


def parse_post(post, erowid_map: dict[str, str]) -> dict:
    """
    Convert a JSONL post record into the report dict format used by the pipeline.
    """
    body  = post.get("selftext") or ""
    title = post.get("title") or ""
    parsed = parse_doselog(body, title=title)

    return {
        "id":           post.get("id"),
        "title":        title,
        "author":       post.get("author"),
        "flair":        post.get("link_flair_text"),
        "score":        post.get("score"),
        "upvote_ratio": post.get("upvote_ratio"),
        "num_comments": post.get("num_comments"),
        "pubdate":      datetime.fromtimestamp(
                            post["created_utc"], tz=timezone.utc
                        ).strftime("%Y-%m-%d"),
        "url":          f"https://reddit.com{post.get('permalink', '')}",
        "body_length":  len(body),
        "body":         body,
        "substances":   detect_substances(title + " " + body, erowid_map),
        "doselog":      parsed["doselog"],
        "doses":        parsed["doses"],
        "time_format":  parsed["time_format"],
        "headers":      parsed["headers"],
        "prep_flags":   parsed["prep_flags"],
        "routes":       parsed["routes"],
        "dose_notes":   parsed["dose_notes"],
        "title_doses":  parsed["title_doses"],
    }


# ---------------------------------------------------------------------------
# Dose and timestamp parsing
# ---------------------------------------------------------------------------

# Dose units — must not match inside T+0:00 style timestamps
_UNITS = (
    r"(?:ug|mcg|µg|μg|mg|g\b|ml|mL|tabs?|hits?|caps?|capsules?|"
    r"strips?|blotters?|seeds?|grams?|oz\b|drops?|lines?|bumps?|bowls?|"
    r"points?|pills?)"
)

# Unicode vulgar fractions → float
_VULGAR_FRACTIONS = {
    "½": 0.5, "⅓": 1/3, "⅔": 2/3, "¼": 0.25, "¾": 0.75,
    "⅕": 0.2, "⅖": 0.4, "⅗": 0.6, "⅘": 0.8,
    "⅙": 1/6, "⅚": 5/6, "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875,
}
_VULGAR_RE = re.compile(
    r"([½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞])\s*" + _UNITS, re.IGNORECASE
)

# Written fractions: "1/2", "3/4", "1/4", optionally preceded by a whole number
# e.g. "1/2 tab", "1 1/2 tabs", "2.5 tabs"
_FRAC_RE = re.compile(
    r"(?<!:)(?<!\+)(\d+)?\s*(\d+)/(\d+)\s*" + _UNITS, re.IGNORECASE
)

# Standard decimal/integer dose — negative lookbehind for : and + (clock/T+)
_DOSE_RE = re.compile(
    r"(?<!:)(?<!\+)(\d+(?:[.,]\d+)?)\s*" + _UNITS,
    re.IGNORECASE,
)

# Substance hint near a dose — only known substance names, no generic verbs
_SUB_HINT_RE = re.compile(
    r"\b(lsd|acid|mdma|molly|ecstasy|dmt|ketamine|ket|psilocybin|psilocin|"
    r"mescaline|cocaine|coke|methamphetamine|meth|amphetamine|adderall|"
    r"dxm|dph|diphenhydramine|ghb|gbl|cannabis|weed|thc|cbd|kratom|"
    r"alcohol|etizolam|xanax|alprazolam|diazepam|clonazepam|lorazepam|"
    r"buprenorphine|oxycodone|hydrocodone|fentanyl|heroin|tramadol|codeine|"
    r"morphine|nitrous|salvia|ibogaine|ayahuasca|harmaline|"
    r"2c-[a-z\d]+|4-[a-z]{2,}-\w+|[a-z\d]+-lsd|al-lad|ald-52|"
    r"[a-z\d]+-[a-z\d]*(?:dmt|pce|pcp|dck|mxe|mxpr|mipt|dipt)|"
    r"mushrooms?|shrooms?|peyote|iboga|caapi|ayahuasca|"
    r"ald-?52|1p-lsd|1cp-lsd|4-aco-dmt|4-ho-met|4-ho-mipt|"
    r"mdai|5-mapb|6-apb|5-apb|mda|methylone|butylone)\b",
    re.IGNORECASE,
)

# Route of administration keywords -> canonical label
_ROA_MAP = {
    "oral": "oral", "eaten": "oral", "ate": "oral", "swallowed": "oral",
    "ingested": "oral", "drank": "oral",
    "smoked": "smoked", "smoking": "smoked",
    "vaped": "vaporized", "vaping": "vaporized", "vaporized": "vaporized",
    "vaporised": "vaporized",
    "insufflated": "insufflated", "snorted": "insufflated", "sniffed": "insufflated",
    "railed": "insufflated", "racking": "insufflated",
    "sublingual": "sublingual", "sublingually": "sublingual",
    "plugged": "rectal", "boofed": "rectal", "rectally": "rectal",
    "iv": "intravenous", "intravenous": "intravenous", "injected": "intravenous",
    "im": "intramuscular", "intramuscular": "intramuscular",
    "transdermal": "transdermal", "patch": "transdermal",
    "lemon tek": "oral (lemon tek)", "lemon-tek": "oral (lemon tek)",
    "volumetric": "oral (volumetric)",
}
_ROA_RE = re.compile(
    r"\b(" + "|".join(re.escape(k) for k in _ROA_MAP) + r")\b",
    re.IGNORECASE,
)

# Inline structured dose line: "LSD [blotter] [oral] 125ug at ~11:30pm"
# Substance must start with an uppercase letter or known prefix to avoid
# matching arbitrary prose like "I took 3.5g"
_INLINE_DOSE_RE = re.compile(
    r"([A-Z\d][\w\s\-]{1,25}?)"            # substance: starts uppercase or digit
    r"(?:\s*\[([^\]]+)\])?"                 # optional [form]
    r"(?:\s*\[([^\]]+)\])?"                 # optional [route]
    r"\s*(\d+(?:[.,]\d+)?)\s*" + _UNITS +  # amount + unit
    r"(?:\s+at\s+~?(\d+:\d+(?:\s*[aApP][mM])?))?" ,  # optional "at HH:MM"
    re.IGNORECASE,
)

# -- Timestamp regexes -------------------------------------------------------
# T+0:30 / T+1h / T+45 / T=0 / T=0.5h
_TPLUS_RE = re.compile(
    r"\bT\s*[+=]\s*(\d+(?:[.,]\d+)?)(?::(\d+))?(?:\s*h(?:rs?)?)?\b",
    re.IGNORECASE,
)
# Bare relative: +0:30 / +45 (not preceded by word char or colon)
_REL_RE = re.compile(r"(?<![:\w])\+(\d+)(?::(\d+))?\b")
# Bracket-wrapped clock: [00:38] / [1:07]
_BRACKET_CLOCK_RE = re.compile(r"\[([01]?\d|2[0-3]):([0-5]\d)\]")
# Tilde-prefixed: ~11:30 pm / ~22:15
_TILDE_CLOCK_RE = re.compile(
    r"~([01]?\d|2[0-3]):([0-5]\d)(?:\s*([AaPp][Mm]))?"
)
# Plain clock: 22:15 / 11:00 PM / 10:30am
_CLOCK_RE = re.compile(
    r"\b([01]?\d|2[0-3]):([0-5]\d)(?:\s*([AaPp][Mm]))?\b"
)
# Prose: "after 30 minutes" / "1.5 hours in" / "2 hours later"
_PROSE_TIME_RE = re.compile(
    r"\b(?:after\s+(?:about\s+)?|about\s+)?(\d+(?:[.,]\d+)?)\s*"
    r"(minutes?|mins?|hours?|hrs?)\s*(?:in|later|after)?\b",
    re.IGNORECASE,
)
# "hour 3" / "hour 3-4"
_HOUR_N_RE = re.compile(r"\bhour\s+(\d+)\b", re.IGNORECASE)

# -- Structured header fields ------------------------------------------------
_HEADER_FIELDS = [
    (re.compile(r"^[\*_]*(?:drug|substance|compound)s?[\*_]*\s*:\s*[\*_]*(.+)", re.I), "drug"),
    (re.compile(r"^[\*_]*(?:dose|dosage|amount)[\*_]*\s*:\s*[\*_]*(.+)", re.I),        "dose"),
    (re.compile(r"^[\*_]*(?:route|roa|m\.?o\.?a\.?|method)[\*_]*\s*:\s*[\*_]*(.+)", re.I), "route"),
    (re.compile(r"^[\*_]*duration[\*_]*\s*:\s*[\*_]*(.+)", re.I),                      "duration"),
    (re.compile(r"^[\*_]*set(?:ting)?[\*_]*\s*:\s*[\*_]*(.+)", re.I),                  "set_setting"),
    (re.compile(r"^[\*_]*(?:mindset|mood|mental\s*state)[\*_]*\s*:\s*[\*_]*(.+)", re.I), "mindset"),
    (re.compile(r"^[\*_]*(?:location|place|where)[\*_]*\s*:\s*[\*_]*(.+)", re.I),      "location"),
    (re.compile(r"^[\*_]*(?:companions?|company|with|people)[\*_]*\s*:\s*[\*_]*(.+)", re.I), "companions"),
    (re.compile(r"^[\*_]*music[\*_]*\s*:\s*[\*_]*(.+)", re.I),                         "music"),
    (re.compile(r"^[\*_]*age[\*_]*\s*:\s*[\*_]*(.+)", re.I),                           "age"),
    (re.compile(r"^[\*_]*(?:gender|sex)[\*_]*\s*:\s*[\*_]*(.+)", re.I),                "gender"),
    (re.compile(r"^[\*_]*(?:weight|bw|body\s*weight)[\*_]*\s*:\s*[\*_]*(.+)", re.I),   "weight"),
    (re.compile(r"^[\*_]*(?:experience|exp\.?)[\*_]*\s*:\s*[\*_]*(.+)", re.I),         "experience"),
    (re.compile(r"^[\*_]*tolerance[\*_]*\s*:\s*[\*_]*(.+)", re.I),                     "tolerance"),
    (re.compile(r"^[\*_]*(?:intention|intent|purpose|reason)[\*_]*\s*:\s*[\*_]*(.+)", re.I), "intention"),
]

# Prep/context flags — detected anywhere in body
_PREP_FLAGS = {
    "fasted":        re.compile(r"\bfast(?:ed|ing)\b", re.I),
    "empty_stomach": re.compile(r"\bempty\s+stomach\b", re.I),
    "lemon_tek":     re.compile(r"\blemon[\s-]?tek\b", re.I),
    "volumetric":    re.compile(r"\bvolumetric\b", re.I),
    "allergy_noted": re.compile(r"\ballerg(?:y|ic|ies)\b", re.I),
    "redosed":       re.compile(r"\bre-?dose[d:]?\b", re.I),
}

# Markdown table rows
_TABLE_ROW_RE = re.compile(r"^\|(.+)\|$")
_TABLE_SEP_RE = re.compile(r"^\|[-:\s|]+\|$")


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _mins_to_relative(delta: int) -> str:
    sign = "-" if delta < 0 else ""
    h, m = divmod(abs(delta), 60)
    return f"T{sign}+{h}:{m:02d}" if not sign else f"T-{h}:{m:02d}"


def _normalise_unit(raw: str) -> str:
    r = raw.strip().lower().rstrip("s")
    if r in ("ug", "mcg", "µg", "μg"):
        return "µg"
    if r == "mg":
        return "mg"
    if r in ("g", "gram"):
        return "g"
    if r in ("ml",):
        return "mL"
    return r


def _parse_doses_in_line(line: str) -> list:
    """Extract dose mentions from a line: amount, unit, substance, route, quality.
    Handles integer/decimal, written fractions (1/2, 3/4, 1 1/2),
    and Unicode vulgar fractions (½, ¼, ¾ …).
    """
    VAGUE_UNITS = {"tab", "hit", "cap", "strip", "blotter", "seed",
                   "drop", "line", "bump", "bowl", "point", "pill"}

    # Collect all (start_pos, amount, unit_raw) from all three patterns,
    # then deduplicate by position before building entries.
    raw_hits: list[tuple[int, float, str]] = []

    # 1. Unicode vulgar fractions
    for m in _VULGAR_RE.finditer(line):
        amount = _VULGAR_FRACTIONS.get(m.group(1), 0.0)
        unit_raw = m.group(0)[len(m.group(1)):].strip()
        raw_hits.append((m.start(), amount, unit_raw))

    # 2. Written fractions: "1/2", "1 1/2", "3/4"
    for m in _FRAC_RE.finditer(line):
        whole = int(m.group(1)) if m.group(1) else 0
        num, den = int(m.group(2)), int(m.group(3))
        if den == 0:
            continue
        amount = whole + num / den
        # unit_raw is everything after the fraction digits
        unit_raw = m.group(0)[m.group(0).index("/") + len(str(den)):].strip()
        raw_hits.append((m.start(), amount, unit_raw))

    # 3. Standard decimal/integer
    for m in _DOSE_RE.finditer(line):
        amount = float(m.group(1).replace(",", "."))
        unit_raw = m.group(0)[len(m.group(1)):].strip()
        raw_hits.append((m.start(), amount, unit_raw))

    if not raw_hits:
        return []

    # Deduplicate: if two hits start within 4 chars of each other, keep first
    raw_hits.sort(key=lambda x: x[0])
    deduped_hits: list[tuple[int, float, str]] = []
    last_pos = -10
    for pos, amount, unit_raw in raw_hits:
        if pos - last_pos > 4:
            deduped_hits.append((pos, amount, unit_raw))
            last_pos = pos

    results = []
    for pos, amount, unit_raw in deduped_hits:
        unit = _normalise_unit(unit_raw)

        after  = line[pos + len(str(amount)):pos + len(str(amount)) + 70]
        before = line[max(0, pos - 50):pos]
        context = before + " " + after

        sub_m = _SUB_HINT_RE.search(after) or _SUB_HINT_RE.search(before)
        substance = sub_m.group(0) if sub_m else None

        roa_m = _ROA_RE.search(context)
        route = _ROA_MAP.get(roa_m.group(0).lower()) if roa_m else None

        if unit not in VAGUE_UNITS and substance:
            quality = "precise"
        elif unit not in VAGUE_UNITS and not substance:
            quality = "partial"
        elif unit in VAGUE_UNITS and substance:
            quality = "partial"
        else:
            quality = "vague"

        entry = {"amount": round(amount, 4), "unit": unit, "quality": quality}
        if substance:
            entry["substance"] = substance
        if route:
            entry["route"] = route
        results.append(entry)
    return results


def _parse_raw_timestamp(line: str):
    """
    Returns (kind, display_str, total_minutes) or None.
    Priority: T+ > bracket > tilde > plain clock > rel > prose > hour-N

    Prose/hour-N patterns only fire when they appear within the first 35
    characters of the line — prevents mid-sentence time mentions like
    "about 2 hours later" from being treated as log timestamps.
    """
    m = _TPLUS_RE.search(line)
    if m:
        val = float(m.group(1).replace(",", "."))
        mins_part = int(m.group(2)) if m.group(2) else 0
        total = int(val * 60) + mins_part
        h, mn = divmod(total, 60)
        return ("tplus", f"T+{h}:{mn:02d}", total)

    m = _BRACKET_CLOCK_RE.search(line)
    if m:
        hour, minute = int(m.group(1)), int(m.group(2))
        return ("clock", f"{hour:02d}:{minute:02d}", hour * 60 + minute)

    m = _TILDE_CLOCK_RE.search(line)
    if m:
        hour, minute = int(m.group(1)), int(m.group(2))
        ampm = m.group(3)
        if ampm:
            ampm = ampm.upper()
            if ampm == "PM" and hour != 12:
                hour += 12
            elif ampm == "AM" and hour == 12:
                hour = 0
        return ("clock", f"{hour:02d}:{minute:02d}", hour * 60 + minute)

    m = _CLOCK_RE.search(line)
    if m:
        # Only treat as a log timestamp if the clock time appears near the
        # start of the line (pos <= 10) or is immediately followed by a
        # log separator (dash, en-dash, colon, pipe, AM/PM then separator).
        # This prevents mid-sentence mentions like "it was 1:52 AM and I..."
        pos = m.start()
        after_match = line[m.end():m.end() + 5].strip()
        is_log_position = (
            pos <= 10
            or re.match(r"^[\s]*[-–—:|]", after_match)
            or m.group(3)  # has explicit AM/PM — stronger signal
        )
        if is_log_position:
            hour, minute = int(m.group(1)), int(m.group(2))
            ampm = m.group(3)
            if ampm:
                ampm = ampm.upper()
                if ampm == "PM" and hour != 12:
                    hour += 12
                elif ampm == "AM" and hour == 12:
                    hour = 0
            return ("clock", f"{hour:02d}:{minute:02d}", hour * 60 + minute)

    m = _REL_RE.search(line)
    if m:
        h = int(m.group(1))
        mn = int(m.group(2)) if m.group(2) else 0
        return ("rel", f"T+{h}:{mn:02d}", h * 60 + mn)

    # Prose and hour-N: only fire if match is within first 35 chars of line
    # to avoid treating mid-sentence time mentions as log entries
    m = _PROSE_TIME_RE.search(line)
    if m and m.start() <= 35:
        val = float(m.group(1).replace(",", "."))
        unit = m.group(2).lower()
        total = int(val * 60) if ("hour" in unit or "hr" in unit) else int(val)
        return ("prose", f"T+{total // 60}:{total % 60:02d}", total)

    m = _HOUR_N_RE.search(line)
    if m and m.start() <= 35:
        total = int(m.group(1)) * 60
        return ("prose", f"T+{int(m.group(1))}:00", total)

    return None


def _parse_inline_dose_lines(body: str) -> list:
    """
    Parse structured inline dose lines like:
      LSD [blotter] [oral/sublingual] 125ug at ~11:30 pm
    Only fires when the substance group looks like an actual substance name
    (matched by _SUB_HINT_RE), not arbitrary prose.
    """
    results = []
    for line in body.splitlines():
        line = line.strip()
        for m in _INLINE_DOSE_RE.finditer(line):
            substance_raw = m.group(1).strip(" \t*_")
            # Require the substance group to contain a known substance name
            if not _SUB_HINT_RE.search(substance_raw):
                continue
            sub_m = _SUB_HINT_RE.search(substance_raw)
            substance = sub_m.group(0) if sub_m else substance_raw

            form      = m.group(2).strip() if m.group(2) else None
            route_raw = m.group(3).strip() if m.group(3) else None
            amount    = float(m.group(4).replace(",", "."))
            tail = m.group(0)[m.start(4) - m.start() + len(m.group(4)):].strip()
            unit_raw = tail.split()[0] if tail else ""
            time_str = m.group(5).strip() if m.group(5) else None

            route = None
            if route_raw:
                roa_m = _ROA_RE.search(route_raw)
                route = _ROA_MAP.get(roa_m.group(0).lower()) if roa_m else route_raw

            entry = {"substance": substance, "amount": amount, "unit": _normalise_unit(unit_raw)}
            if form:
                entry["form"] = form
            if route:
                entry["route"] = route
            if time_str:
                entry["time"] = time_str
            results.append(entry)
    return results


def _parse_markdown_table(body: str) -> list:
    """
    Parse a markdown |Time|Notes| table into doselog entries.
    """
    lines = body.splitlines()
    entries = []
    in_table = False
    header_cols = []

    for line in lines:
        line = line.strip()
        if not _TABLE_ROW_RE.match(line):
            in_table = False
            header_cols = []
            continue
        if _TABLE_SEP_RE.match(line):
            continue

        cells = [c.strip().strip("*_") for c in line.strip("|").split("|")]

        if not in_table:
            lower_cells = [c.lower() for c in cells]
            if any("time" in c for c in lower_cells):
                header_cols = lower_cells
                in_table = True
                continue

        if not in_table or not header_cols:
            continue

        row = dict(zip(header_cols, cells))
        time_val = row.get("time", "").strip()
        note_val = row.get("notes", row.get("note", row.get("description", ""))).strip()

        if not time_val:
            continue

        ts = _parse_raw_timestamp(time_val)
        entry = {"time": ts[1] if ts else time_val, "note": note_val}
        doses = _parse_doses_in_line(note_val)
        if doses:
            entry["doses"] = doses
        entries.append(entry)

    return entries


def _parse_headers(body: str) -> dict:
    """Extract structured key:value header fields."""
    result = {}
    for line in body.splitlines():
        line = line.strip()
        for pattern, key in _HEADER_FIELDS:
            m = pattern.match(line)
            if m:
                val = m.group(1).strip().strip("*_").strip()
                if val and key not in result:
                    result[key] = val
                break
    return result


def _parse_prep_flags(body: str) -> list:
    return [flag for flag, pat in _PREP_FLAGS.items() if pat.search(body)]


def _parse_roa_from_body(body: str) -> list:
    found = set()
    for m in _ROA_RE.finditer(body):
        canonical = _ROA_MAP.get(m.group(0).lower())
        if canonical:
            found.add(canonical)
    return sorted(found)


def parse_doselog(body: str) -> dict:
    """
    Full parse of a trip report body. Returns:
      doselog     - timestamped log entries (all times as T+ relative)
      doses       - flat list of all dose mentions
      time_format - 'tplus' | 'clock' | 'prose' | 'table' | None
      headers     - structured key:value fields
      prep_flags  - preparation/context flags
      routes      - routes of administration mentioned
    """
    # 1. Markdown table
    table_entries = _parse_markdown_table(body)

    # 2. Line-by-line timestamp scan
    raw_entries = []
    all_doses = []
    time_kinds = []

    for line in body.splitlines():
        line = line.strip()
        if not line:
            continue
        ts_result = _parse_raw_timestamp(line)
        line_doses = _parse_doses_in_line(line)
        note = re.sub(r"\*{1,2}|_{1,2}|`", "", line).strip()

        if ts_result:
            kind, ts_str, ts_mins = ts_result
            time_kinds.append(kind)
            entry = {"_kind": kind, "_mins": ts_mins, "time": ts_str, "note": note}
            if line_doses:
                entry["doses"] = line_doses
            raw_entries.append(entry)
        elif line_doses:
            all_doses.extend(line_doses)

    # Prefer table if it produced more entries
    if table_entries and len(table_entries) >= len(raw_entries):
        doselog = table_entries
        fmt = "table"
    elif raw_entries:
        kind_counts = {k: time_kinds.count(k) for k in set(time_kinds)}
        dominant = max(kind_counts, key=kind_counts.get)

        # ── Normalise all entries to T+ relative ──────────────────────────
        #
        # Strategy depends on what mix of timestamp kinds we have:
        #
        # Pure T+/rel  → already relative, use as-is
        # Pure clock   → first clock entry = T+0, derive offsets
        # Pure prose   → already relative offsets, use as-is
        # Mixed        → find the best anchor:
        #   - If T+ entries exist, use the T+0:00 entry as anchor and
        #     convert any clock entries by finding the clock time that
        #     best aligns with T+0:00 (i.e. the clock time of the first
        #     T+0 entry, if present on the same line, else the first clock)
        #   - If no T+ but clock+prose mixed, use first clock as T+0

        is_mixed = len(kind_counts) > 1

        if dominant in ("tplus", "rel") and not is_mixed:
            fmt = "tplus"
            # already relative — no conversion needed

        elif dominant == "clock" and not is_mixed:
            fmt = "clock"
            clock_entries = [e for e in raw_entries if e["_kind"] == "clock"]
            origin = clock_entries[0]["_mins"]
            for entry in raw_entries:
                delta = entry["_mins"] - origin
                if delta < -30:
                    delta += 24 * 60
                entry["time"] = _mins_to_relative(delta)

        elif is_mixed:
            fmt = "mixed"
            # Find anchor: prefer explicit T+0:00 entry, else first tplus,
            # else first clock, else 0
            tplus_entries = [e for e in raw_entries if e["_kind"] in ("tplus", "rel")]
            clock_entries = [e for e in raw_entries if e["_kind"] == "clock"]

            if tplus_entries:
                # T+ entries are already relative — keep them.
                # For clock entries: find the clock time that best aligns with
                # T+0. We look for a clock entry that appears near the first
                # T+0:00 entry in the text, or fall back to the first clock
                # entry and assume it happened at the same wall time as T+0.
                #
                # Concretely: clock_origin = (wall time of first clock entry)
                #             minus (T+ value of first tplus entry at that point)
                # This lets us convert any clock time to T+ via:
                #   T+ = clock_mins - clock_origin
                first_tplus_mins = tplus_entries[0]["_mins"]

                if clock_entries:
                    # Find the clock entry closest in document order to the
                    # first tplus entry
                    first_tplus_idx = raw_entries.index(tplus_entries[0])
                    closest_clock = min(
                        clock_entries,
                        key=lambda e: abs(raw_entries.index(e) - first_tplus_idx)
                    )
                    clock_origin = closest_clock["_mins"] - first_tplus_mins
                    for entry in raw_entries:
                        if entry["_kind"] == "clock":
                            delta = entry["_mins"] - clock_origin
                            if delta < -30:
                                delta += 24 * 60
                            entry["time"] = _mins_to_relative(delta)

            elif clock_entries:
                # No T+ — use first clock as origin, convert prose too
                origin = clock_entries[0]["_mins"]
                for entry in raw_entries:
                    if entry["_kind"] == "clock":
                        delta = entry["_mins"] - origin
                        if delta < -30:
                            delta += 24 * 60
                        entry["time"] = _mins_to_relative(delta)
                    # prose entries already have relative times — keep them

        else:
            fmt = "prose"
            # prose/hour-N entries already carry relative offsets

        doselog = []
        for entry in raw_entries:
            clean = {k: v for k, v in entry.items() if not k.startswith("_")}
            doselog.append(clean)
            all_doses.extend(entry.get("doses", []))

        # Re-anchor: if any entry has a dose, shift all times so the first
        # dosed entry becomes T+0:00. This handles posts where the log starts
        # with pre-trip narrative before the actual dose event.
        first_dosed = next(
            (e for e in raw_entries if e.get("doses")), None
        )
        if first_dosed and first_dosed["_mins"] != 0:
            anchor = first_dosed["_mins"]
            for i, entry in enumerate(raw_entries):
                delta = entry["_mins"] - anchor
                # Midnight wraparound: only apply when gap is large enough
                # to plausibly be a date crossing (> 6 hours back)
                if delta < -(6 * 60):
                    delta += 24 * 60
                doselog[i]["time"] = _mins_to_relative(delta)
    else:
        doselog = None
        fmt = None
        for line in body.splitlines():
            all_doses.extend(_parse_doses_in_line(line.strip()))

    # 3. Inline structured dose lines (higher confidence, prepend)
    #    Only apply when substance starts with uppercase (filtered by regex)
    #    Deduplicate against line-scan doses by (amount, unit, substance) key
    inline = _parse_inline_dose_lines(body)
    if inline:
        existing_keys = {
            (round(d.get("amount", 0), 4), d.get("unit"), d.get("substance"))
            for d in all_doses
        }
        deduped_inline = [
            d for d in inline
            if (round(d.get("amount", 0), 4), d.get("unit"), d.get("substance"))
            not in existing_keys
        ]
        all_doses = deduped_inline + all_doses

    # Deduplicate all_doses — collapse entries with same (amount, unit),
    # keeping the one with the most informative substance name (longest).
    qty_best: dict = {}
    for d in all_doses:
        key = (round(d.get("amount", 0), 4), d.get("unit"))
        if key not in qty_best:
            qty_best[key] = d
        else:
            # Prefer entry with a substance; if both have one, prefer longer
            existing_sub = qty_best[key].get("substance") or ""
            new_sub = d.get("substance") or ""
            if len(new_sub) > len(existing_sub):
                qty_best[key] = d
    all_doses = list(qty_best.values())

    # 4. Structured headers
    headers = _parse_headers(body)

    # 5. Prep flags + routes
    prep_flags = _parse_prep_flags(body)
    routes = _parse_roa_from_body(body)

    # 6. Dose quality notes — post-level summary of what's missing
    dose_notes = []
    if all_doses:
        vague   = [d for d in all_doses if d.get("quality") == "vague"]
        partial = [d for d in all_doses if d.get("quality") == "partial"]
        precise = [d for d in all_doses if d.get("quality") == "precise"]
        if vague and not precise:
            dose_notes.append(
                "only count-based doses found (e.g. pills/tabs) — no weight or substance"
            )
        elif vague:
            for d in vague:
                dose_notes.append(
                    f"vague dose: {d['amount']} {d['unit']} — no substance or weight specified"
                )
        if partial:
            for d in partial:
                if d.get("unit") not in {"mg", "µg", "g", "mL"}:
                    dose_notes.append(
                        f"partial dose: {d['amount']} {d['unit']} {d.get('substance', '')} — no weight unit"
                    )
                elif not d.get("substance"):
                    dose_notes.append(
                        f"partial dose: {d['amount']} {d['unit']} — substance not identified"
                    )
    else:
        dose_notes.append("no dose information found")

    return {
        "doselog":     doselog or None,
        "doses":       all_doses or None,
        "time_format": fmt,
        "headers":     headers or None,
        "prep_flags":  prep_flags or None,
        "routes":      routes or None,
        "dose_notes":  dose_notes or None,
    }


# ---------------------------------------------------------------------------
# Public scrape() — called by the pipeline with a list of substance aliases
# ---------------------------------------------------------------------------

def scrape(aliases: list[str]) -> str:
    """
    Read all posts from the local JSONL archive and filter to those that:
      - have a body >= MIN_BODY_LENGTH characters (not deleted/removed)
      - mention at least one of the requested aliases

    Returns a JSON string in the same envelope format as erowid.py.
    """
    erowid_map = load_erowid_substances(EROWID_FILE)

    candidates: list[dict] = []
    with open(POSTS_FILE, "r", encoding="utf-8") as f:
        for line in f:
            post = json.loads(line)
            body = post.get("selftext") or ""
            if body in ("[deleted]", "[removed]") or len(body) < MIN_BODY_LENGTH:
                continue
            candidates.append(parse_post(post, erowid_map))

    output: dict = {}
    for alias in aliases:
        alias_lower = alias.lower()
        matching = [
            r for r in candidates
            if any(s.lower() == alias_lower or alias_lower in s.lower()
                   for s in r["substances"])
            or alias_lower in r["title"].lower()
            or alias_lower in r["body"].lower()
        ]
        output[alias] = {
            "found":         len(matching) > 0,
            "total_reports": len(matching),
            "reports":       matching,
        }

    return json.dumps(output)


def scrape_all() -> list[dict]:
    """
    Extract every qualifying post from the archive regardless of substance.
    Returns a list of parsed report dicts, each with a 'substances' field.
    """
    erowid_map = load_erowid_substances(EROWID_FILE)

    # Count total lines first for the progress meter
    total = 0
    with open(POSTS_FILE, "r", encoding="utf-8") as f:
        for _ in f:
            total += 1

    results: list[dict] = []
    processed = 0
    kept = 0

    with open(POSTS_FILE, "r", encoding="utf-8") as f:
        for line in f:
            processed += 1
            post = json.loads(line)
            body = post.get("selftext") or ""

            if body not in ("[deleted]", "[removed]") and len(body) >= MIN_BODY_LENGTH:
                results.append(parse_post(post, erowid_map))
                kept += 1

            # Progress meter — overwrite same line
            pct = processed * 100 // total
            bar = "#" * (pct // 2) + "-" * (50 - pct // 2)
            sys.stdout.write(f"\r  [{bar}] {pct:3d}%  {processed}/{total} posts  ({kept} kept)")
            sys.stdout.flush()

    sys.stdout.write("\n")
    return results


# ---------------------------------------------------------------------------
# Standalone usage
# ---------------------------------------------------------------------------

OUTPUT_FILE = "reddit_test.json"

if __name__ == "__main__":
    if "--reparse" in sys.argv:
        # Re-run parsing on existing reddit_test.json without re-scraping
        print(f"Reparsing {OUTPUT_FILE}...")
        with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
            posts = json.load(f)
        total = len(posts)
        for i, post in enumerate(posts):
            parsed = parse_doselog(post.get("body", ""))
            post["doselog"]     = parsed["doselog"]
            post["doses"]       = parsed["doses"]
            post["time_format"] = parsed["time_format"]
            post["headers"]     = parsed["headers"]
            post["prep_flags"]  = parsed["prep_flags"]
            post["routes"]      = parsed["routes"]
            post["dose_notes"]  = parsed["dose_notes"]
            pct = (i + 1) * 100 // total
            bar = "#" * (pct // 2) + "-" * (50 - pct // 2)
            sys.stdout.write(f"\r  [{bar}] {pct:3d}%  {i+1}/{total}")
            sys.stdout.flush()
        sys.stdout.write("\n")
        with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
            json.dump(posts, f, indent=2, ensure_ascii=False)
        print(f"Done. {total} posts reparsed and written to {OUTPUT_FILE}")
    elif "--all" in sys.argv:
        print(f"Extracting all qualifying posts from {POSTS_FILE}...")
        reports = scrape_all()
        with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
            json.dump(reports, f, indent=2, ensure_ascii=False)
        print(f"Done. {len(reports)} reports written to {OUTPUT_FILE}")
    else:
        aliases = [a for a in sys.argv[1:] if not a.startswith("--")] or ["LSD", "MDMA", "Psilocybin"]
        print(f"Reading {POSTS_FILE} for: {aliases}")
        result = scrape(aliases)
        data = json.loads(result)
        with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print(f"\nFull output written to {OUTPUT_FILE}")
        for alias, info in data.items():
            print(f"\n=== {alias} ===")
            print(f"  Found: {info['found']}  |  Reports: {info['total_reports']}")
            for r in info["reports"][:3]:
                print(f"  - [{r['pubdate']}] {r['title']}")
                print(f"    Substances: {r['substances']}")
                print(f"    URL: {r['url']}")
