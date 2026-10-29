import json
import math
import re
import sys
import time
from urllib.parse import parse_qs, urlparse

import requests
from bs4 import BeautifulSoup, NavigableString


class BindingDBScraper:
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update(
            {
                "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
                "accept-language": "en-US,en;q=0.9",
                "content-type": "application/x-www-form-urlencoded",
                "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                "upgrade-insecure-requests": "1",
            }
        )

    def search_by_smiles(
        self,
        smiles,
        search_type=4,
        similarity=0.10,
        column="KI",
        energy_term="kJ/mole",
        increment=50,
    ):
        if not isinstance(smiles, str):
            raise ValueError("SMILES must be a string.")
        if not smiles.strip():
            raise ValueError("SMILES cannot be empty.")

        first_page_html = self._make_request(
            smiles=smiles,
            start_pg=0,
            search_type=search_type,
            similarity=similarity,
            column=column,
            energy_term=energy_term,
            increment=increment,
        )

        total_hits = self._get_total_hits(first_page_html)
        results = self._parse_results(first_page_html)

        total_pages = math.ceil(total_hits / increment)
        for page_num in range(1, total_pages):
            start_pg = page_num * increment
            page_html = self._make_request(
                smiles=smiles,
                start_pg=start_pg,
                search_type=search_type,
                similarity=similarity,
                column=column,
                energy_term=energy_term,
                increment=increment,
            )
            page_results = self._parse_results(page_html)
            results.extend(page_results)

        return {
            "query": {
                "smiles": smiles,
                "search_type": search_type,
                "similarity": similarity,
                "column": column,
                "energy_term": energy_term,
                "increment": increment,
            },
            "total_hits": total_hits,
            "results": results,
        }

    def _make_request(
        self,
        smiles,
        start_pg,
        search_type,
        similarity,
        column,
        energy_term,
        increment,
    ):
        url = "https://bindingdb.org/rwd/bind/searchby_smiles.jsp"
        payload = {
            "smilesStr": smiles,
            "SearchType": search_type,
            "submit": "Search",
            "startPg": start_pg,
            "Increment": increment,
            "column": column,
            "energyterm": energy_term,
        }
        if similarity is not None:
            payload["Similarity"] = similarity

        max_attempts = 3
        for attempt in range(max_attempts):
            try:
                response = self.session.post(
                    url,
                    data=payload,
                    timeout=60,
                )
                response.raise_for_status()
                return response.text
            except requests.RequestException as exc:
                if attempt == max_attempts - 1:
                    raise RuntimeError(
                        f"Failed to fetch BindingDB results after {max_attempts} attempts: {exc}"
                    )
                sleep_seconds = 2 ** attempt
                time.sleep(sleep_seconds)

    @staticmethod
    def _get_total_hits(html):
        match = re.search(
            r"Found\s+<span[^>]*>\s*(\d+)\s*</span>\s+hits",
            html,
        )
        if match:
            return int(match.group(1))

        match = re.search(
            r"Filter\s+my\s+<span[^>]*>\s*(\d+)\s*</span>\s+hits",
            html,
        )
        if match:
            return int(match.group(1))

        return 0

    @staticmethod
    def _parse_results(html):
        soup = BeautifulSoup(html, "html.parser")
        table = soup.find("div", class_="index_table")
        if not table:
            return []

        results = []
        for child in table.find_all("div", recursive=False):
            try:
                entry = BindingDBScraper._parse_entry(child)
                results.append(entry)
            except Exception as exc:
                print(f"  [Warning] Skipping malformed entry: {exc}")
        return results

    @staticmethod
    def _parse_entry(div):
        section_map = {
            "Target": ("target", BindingDBScraper._parse_target),
            "Ligand": ("ligand", BindingDBScraper._parse_ligand),
            "Affinity Data": ("affinity", BindingDBScraper._parse_affinity),
            "Target Info": ("target_info", BindingDBScraper._parse_target_info),
            "Ligand Info": ("ligand_info", BindingDBScraper._parse_ligand_info),
            "In Depth": ("in_depth", BindingDBScraper._parse_in_depth),
        }

        sections = {}
        for child in div.find_all("div", recursive=False):
            header_span = child.find("span", class_="header")
            if not header_span:
                continue
            key = header_span.get_text(strip=True).replace("\xa0", " ")
            if key in section_map:
                field_name, parser = section_map[key]
                sections[field_name] = parser(child)

        return sections

    @staticmethod
    def _parse_target(div):
        target_name = None
        organism = None
        institution = None
        curated_by = None

        big_link = div.find("a", class_="big")
        if big_link:
            target_name = big_link.get_text(strip=True)

        for span in div.find_all("span"):
            text = span.get_text(strip=True)
            if text.startswith("(") and text.endswith(")"):
                organism = text[1:-1]
                break

        first_br = div.find("br")
        if first_br:
            next_sibling = first_br.next_sibling
            if isinstance(next_sibling, NavigableString):
                candidate = str(next_sibling).strip()
                if candidate and "Curated" not in candidate:
                    institution = candidate

        chembl_link = div.find("a", href=re.compile(r"ebi\.ac\.uk/chembl"))
        if chembl_link:
            curated_by = chembl_link.get_text(strip=True)

        result = {}
        if target_name:
            result["name"] = target_name
        if organism:
            result["organism"] = organism
        if institution:
            result["institution"] = institution
        if curated_by:
            result["curated_by"] = curated_by
        return result

    @staticmethod
    def _parse_ligand(div):
        bdbm_id = None
        name = None
        smiles = None
        inchi = None

        big_link = div.find("a", class_="big")
        if big_link:
            bdbm_id = big_link.get_text(strip=True)
            full_text = big_link.parent.get_text(strip=True)
            match = re.search(rf"{re.escape(bdbm_id)}\s*\(([^)]+)\)", full_text)
            if match:
                name = match.group(1).strip()

        for button in div.find_all("button"):
            onclick = button.get("onclick", "")
            if "setClipboard" in onclick:
                clipboard_match = re.search(r"setClipboard\('([^']+)'\)", onclick)
                if clipboard_match:
                    value = clipboard_match.group(1)
                    button_text = button.get_text()
                    if "InChI" in onclick or "InChI" in button_text:
                        inchi = value
                    else:
                        smiles = value

        result = {}
        if bdbm_id:
            result["bdbm_id"] = bdbm_id
        if name:
            result["name"] = name
        if smiles:
            result["smiles"] = smiles
        if inchi:
            result["inchi"] = inchi
        return result

    @staticmethod
    def _parse_affinity(div):
        affinity_type = None
        value = None
        unit = None
        assay_description = None

        big_span = div.find("span", class_="big")
        if big_span:
            text = big_span.get_text(strip=True)
            match = re.search(
                r"(Ki|IC50|Kd|EC50|Kon|Koff)\s*:\s*([\d.E+\-]+)\s*(nM|µM|uM|mM|pM)",
                text,
            )
            if match:
                affinity_type = match.group(1)
                value = match.group(2)
                unit = match.group(3)

        ay_span = div.find("span", class_="ay")
        if ay_span:
            next_span = ay_span.find_next_sibling("span")
            if next_span:
                assay_description = next_span.get_text(strip=True)

        result = {}
        if affinity_type:
            result["type"] = affinity_type
        if value:
            result["value"] = value
        if unit:
            result["unit"] = unit
        if assay_description:
            result["assay_description"] = assay_description
        return result

    @staticmethod
    def _parse_target_info(div):
        pdb_ids = []
        kegg = None
        uniprot_ids = []

        pdb_link = div.find("a", string=re.compile(r"\bPDB\b", re.I))
        if pdb_link:
            href = pdb_link.get("href", "")
            match = re.search(r'"value"\s*:\s*"([^"]+)"', href)
            if match:
                pdb_ids = [id.strip() for id in match.group(1).split(",") if id.strip()]

        kegg_link = div.find("a", href=re.compile("KEGG"))
        if kegg_link:
            href = kegg_link.get("href", "")
            parsed = urlparse(href)
            ids = parse_qs(parsed.query).get("ids")
            if ids:
                kegg = ids[0]

        uniprot_link = div.find("a", href=re.compile("UniProt"))
        if uniprot_link:
            href = uniprot_link.get("href", "")
            parsed = urlparse(href)
            ids = parse_qs(parsed.query).get("ids")
            if ids:
                uniprot_ids = [
                    id.strip() for id in ids[0].split(",") if id.strip()
                ]

        result = {}
        if pdb_ids:
            result["pdb_ids"] = pdb_ids
        if kegg:
            result["kegg"] = kegg
        if uniprot_ids:
            result["uniprot_ids"] = uniprot_ids
        return result

    @staticmethod
    def _parse_ligand_info(div):
        chembl_id = None
        pubchem_cid = None
        pubchem_sid = None

        chembl_link = div.find("a", href=re.compile("chembl"))
        if chembl_link:
            href = chembl_link.get("href", "")
            match = re.search(r"CHEMBL\d+", href)
            if match:
                chembl_id = match.group(0)

        cid_pattern = re.compile(r"PC\s*cid", re.I)
        cid_link = div.find("a", text=cid_pattern)
        if not cid_link:
            cid_link = div.find("a", string=cid_pattern)
        if cid_link:
            href = cid_link.get("href", "")
            match = re.search(r"cid=(\d+)", href)
            if match:
                pubchem_cid = match.group(1)

        sid_pattern = re.compile(r"PC\s*sid", re.I)
        sid_link = div.find("a", text=sid_pattern)
        if not sid_link:
            sid_link = div.find("a", string=sid_pattern)
        if sid_link:
            href = sid_link.get("href", "")
            match = re.search(r"sid=(\d+)", href)
            if match:
                pubchem_sid = match.group(1)

        result = {}
        if chembl_id:
            result["chembl_id"] = chembl_id
        if pubchem_cid:
            result["pubchem_cid"] = pubchem_cid
        if pubchem_sid:
            result["pubchem_sid"] = pubchem_sid
        return result

    @staticmethod
    def _parse_in_depth(div):
        date = None
        entry_id = None
        ki_result_id = None
        reactant_set_id = None
        article_doi = None
        pubmed_id = None
        bdb_doi = None
        reaction_url = None

        div_text = str(div)
        date_match = re.search(
            r"Date in BDB:\s*<br[^>]*>\s*([\d/]+)",
            div_text,
        )
        if date_match:
            date = date_match.group(1)

        entry_link = div.find("a", text=re.compile("Entry Details"))
        if not entry_link:
            entry_link = div.find("a", string=re.compile("Entry Details"))
        if entry_link:
            href = entry_link.get("href", "")
            parsed = urlparse(href)
            params = parse_qs(parsed.query)
            entry_id_list = params.get("entryid")
            ki_result_id_list = params.get("ki_result_id")
            reactant_set_id_list = params.get("reactant_set_id")
            if entry_id_list:
                entry_id = entry_id_list[0]
            if ki_result_id_list:
                ki_result_id = ki_result_id_list[0]
            if reactant_set_id_list:
                reactant_set_id = reactant_set_id_list[0]

        doi_link = div.find("a", href=re.compile(r"dx\.doi\.org"))
        if doi_link:
            href = doi_link.get("href", "")
            article_doi = re.sub(r"https?://dx\.doi\.org/", "", href)

        pubmed_link = div.find("a", text=re.compile("PubMed"))
        if not pubmed_link:
            pubmed_link = div.find("a", string=re.compile("PubMed"))
        if pubmed_link:
            href = pubmed_link.get("href", "")
            parsed = urlparse(href)
            ids = parse_qs(parsed.query).get("ids")
            if ids:
                pubmed_id = ids[0]

        for button in div.find_all("button"):
            button_text = button.get_text(strip=True)
            onclick = button.get("onclick", "")
            if "BDB" in button_text and "DOI" in button_text:
                match = re.search(r"setClipboard\('([^']+)'\)", onclick)
                if match:
                    bdb_doi = match.group(1)
            if "reaction" in button_text.lower() or "URL" in button_text:
                match = re.search(r"setClipboard\('([^']+)'\)", onclick)
                if match:
                    reaction_url = match.group(1)

        result = {}
        if date:
            result["date"] = date
        if entry_id:
            result["entry_id"] = entry_id
        if ki_result_id:
            result["ki_result_id"] = ki_result_id
        if reactant_set_id:
            result["reactant_set_id"] = reactant_set_id
        if article_doi:
            result["article_doi"] = article_doi
        if pubmed_id:
            result["pubmed_id"] = pubmed_id
        if bdb_doi:
            result["bdb_doi"] = bdb_doi
        if reaction_url:
            result["reaction_url"] = reaction_url
        return result

