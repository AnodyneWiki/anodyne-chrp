from bs4 import BeautifulSoup
import requests
import re
import json

BASE_URL = "https://www.erowid.org/experiences/"
SUBSTANCES_FILE = "erowid_substances.json"

headers = {
    "User-Agent": "Mozilla/5.0",
    "Host": "www.erowid.org",
    "Accept": "*/*"
}


def clean_text(el):
    if not el:
        return None

    text = el.get_text(" ", strip=True)
    text = text.replace("\xa0", " ")
    text = re.sub(r"\s+", " ", text)
    return text.strip() or None


def normalize_name(name):
    return re.sub(r"\s+", " ", name.strip().lower())


def load_substances():
    with open(SUBSTANCES_FILE, "r", encoding="utf-8") as f:
        substances = json.load(f)

    return {
        normalize_name(item["name"]): item
        for item in substances
    }


def parse_dosechart(dose_table):
    if not dose_table:
        return []

    doses = []

    for tr in dose_table.select("tr"):
        doses.append({
            "time": clean_text(tr.select_one(".dosechart-time")),
            "amount": clean_text(tr.select_one(".dosechart-amount")),
            "method": clean_text(tr.select_one(".dosechart-method")),
            "substance": clean_text(tr.select_one(".dosechart-substance")),
            "form": clean_text(tr.select_one(".dosechart-form")),
        })

    return doses


def parse_intensity(details_row):
    if not details_row:
        return None

    text = details_row.get_text(" ", strip=True)
    match = re.search(r"Intensity:\s*([A-Za-z]+)", text)

    return match.group(1) if match else None


def scrape_erowid_results(substance_id):
    url = f"https://www.erowid.org/experiences/exp.cgi?Max=999999999&OldSort=RA_PDD&NewSort=&Start=0&ShowViews=1&S1={substance_id}&Cellar=1&ShowViews=1&SP=1"

    r = requests.get(url, headers=headers)

    soup = BeautifulSoup(r.text, "html.parser")
    results = []

    for row in soup.select("tr.exp-list-row"):
        title_cell = row.select_one("td.exp-title a")
        rating_img = row.select_one("td.exp-rating img")
        author_cell = row.select_one("td.exp-author")
        substance_cell = row.select_one("td.exp-substance")
        pubdate_cell = row.select_one("td.exp-pubdate")

        href = title_cell.get("href", "") if title_cell else ""
        match = re.search(r"[?&]ID=(\d+)", href)

        details_row = row.find_next_sibling("tr")
        dose_table = details_row.select_one("table.dosechart") if details_row else None

        results.append({
            "id": int(match.group(1)) if match else None,
            "title": clean_text(title_cell),
            "experience_link": BASE_URL + href if href else None,
            "rating": rating_img.get("alt") if rating_img else None,
            "author": clean_text(author_cell),
            "substance": clean_text(substance_cell),
            "pubdate": clean_text(pubdate_cell),
            "intensity": parse_intensity(details_row),
            "dosechart": parse_dosechart(dose_table),
        })

    return results


def scrape(aliases):
    substances_by_name = load_substances()
    output = {}

    for alias in aliases:
        key = normalize_name(alias)
        substance = substances_by_name.get(key)

        if not substance:
            continue
        
        reports = scrape_erowid_results(substance["id"])

        output[alias] = {
            "found": True,
            "id": substance["id"],
            "total_reports": len(reports),
            "name": substance["name"],
            "reports": reports
        }

    return json.dumps(output)