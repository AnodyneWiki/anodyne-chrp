#!/usr/bin/env python3
"""
SIDER scraper - fetches drug side effects and indications from sideeffects.embl.de
uses a local index for fast offline drug alias resolution
"""
import sys
import os
import argparse
import json
import re
import requests
from bs4 import BeautifulSoup

BASE_URL = "http://sideeffects.embl.de"

class SIDERScraper:
    """resolves drug aliases and fetches side effects/indications from SIDER"""
    def __init__(self, use_pt=False):
        """initialize scraper and load local index. use_pt: fetch preferred terms if true."""
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        })
        self.use_pt = use_pt
        self.confidence_logs = []
        
        # load precompiled index
        self._load_local_index()

    def _load_local_index(self):
        """load precompiled sider_index.json and build lookup maps"""
        self.alias_map = {}
        self.sider_drugs = {}
        self.psychoactive_names = set()
        self.slang_map = {}
        
        script_dir = os.path.dirname(os.path.abspath(__file__))
        index_path = os.path.join(script_dir, "sider_index.json")
        if os.path.exists(index_path):
            try:
                with open(index_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    self.alias_map = data.get("alias_map", {})
                    self.sider_drugs = data.get("sider_drugs", {})
                
                # build psychoactive names and slang mappings from index
                for alias, entry in self.alias_map.items():
                    if entry.get("is_psychoactive"):
                        self.psychoactive_names.add(alias.lower())
                        canonical = entry.get("canonical_name")
                        if canonical:
                            self.psychoactive_names.add(canonical.lower())
                    
                    sider_name = entry.get("sider_name")
                    if sider_name and alias != sider_name:
                        self.slang_map[alias] = sider_name
            except Exception as e:
                print(f"Warning: Failed to load SIDER index file '{index_path}': {e}", file=sys.stderr)
        else:
            print(f"Warning: SIDER index file '{index_path}' not found. Falling back to live resolution only.", file=sys.stderr)

    def get_candidate_labels(self, soup):
        """extract label names from h4 tags in drug page html"""
        labels = []
        for h4 in soup.find_all('h4'):
            text = h4.get_text(strip=True)
            if text and text.lower() != "color scheme:":
                labels.append(text)
        return labels

    def calculate_confidence(self, alias, drug_name, label_names=[]):
        """score how well a candidate drug matches the query alias (0-100)"""
        alias_lower = alias.lower()
        target_substance = self.slang_map.get(alias_lower, alias_lower)
        
        drug_name_lower = drug_name.lower()
        labels_lower = [l.lower() for l in label_names]
        
        score = 0
        match_reasons = []

        # exact match to target substance or query alias
        if drug_name_lower == target_substance:
            score += 80
            match_reasons.append("Exact match to target substance")
        elif drug_name_lower == alias_lower:
            score += 75
            match_reasons.append("Exact match to query alias")
        # 2. Substring/word overlap with target substance
        elif target_substance in drug_name_lower or drug_name_lower in target_substance:
            score += 55
            match_reasons.append("Substring/word overlap with target substance")
            
        # 3. Label name matches (for brand names / aliases like Desoxyn)
        label_exact = False
        label_substring = False
        for l in labels_lower:
            sub_names = [part.strip() for part in re.split(r'[/,]', l)]
            if alias_lower in sub_names or target_substance in sub_names:
                label_exact = True
            elif alias_lower in l or target_substance in l:
                label_substring = True

        if label_exact:
            score = max(score, 80)
            match_reasons.append("Exact match to product label name component")
        elif label_substring:
            score = max(score, 55)
            match_reasons.append("Substring match in product label name")

        # psychoactive bonus if drug or labels match our index
        is_psychoactive = False
        if drug_name_lower in self.psychoactive_names:
            is_psychoactive = True
        else:
            for l in labels_lower:
                words = re.findall(r'[a-zA-Z0-9\-]+', l)
                if any(w in self.psychoactive_names for w in words):
                    is_psychoactive = True
                    break
        
        if is_psychoactive:
            score += 20
            match_reasons.append("Psychoactive drug index bonus (+20)")
            
        score = min(score, 100)
        
        if not match_reasons:
            score = 0
            match_reasons.append("No match")
            
        return score, "; ".join(match_reasons)

    def resolve_drug_url(self, alias):
        """resolve drug alias to SIDER url with confidence score, using local index first"""
        alias_lower = alias.lower()
        self.confidence_logs = []

        # check local alias map for exact match
        if alias_lower in self.alias_map:
            entry = self.alias_map[alias_lower]
            sider_id = entry["sider_id"]
            url = f"{BASE_URL}/drugs/{sider_id}/"
            score = 100 if entry.get("is_psychoactive") else 95
            reason = f"Exact match found in offline index (is_psychoactive={entry.get('is_psychoactive')})"
            
            self.confidence_logs.append({
                "name": entry["sider_name"],
                "url": url,
                "score": score,
                "reason": reason,
                "method": "Offline Index (exact)"
            })
            return url, score

        # look for prefix/substring matches in alias map
        candidates = []
        for name, entry in self.alias_map.items():
            if name.startswith(alias_lower) or alias_lower in name:
                sider_id = entry["sider_id"]
                url = f"{BASE_URL}/drugs/{sider_id}/"
                
                score = 0
                reasons = []
                if name.startswith(alias_lower):
                    score += 65
                    reasons.append("Prefix match in offline index")
                else:
                    score += 45
                    reasons.append("Substring match in offline index")
                    
                if entry.get("is_psychoactive"):
                    score += 20
                    reasons.append("Psychoactive drug bonus (+20)")
                    
                score = min(score, 100)
                candidates.append({
                    "name": entry["sider_name"],
                    "url": url,
                    "score": score,
                    "reason": "; ".join(reasons),
                    "method": "Offline Index (partial)"
                })

        # pick best offline match if score is high enough
        if candidates:
            candidates.sort(key=lambda x: x["score"], reverse=True)
            self.confidence_logs = candidates
            top_cand = candidates[0]
            if top_cand["score"] >= 70:
                return top_cand["url"], top_cand["score"]

        # try direct post search as fallback
        redirect_url = None
        try:
            r = self.session.post(f"{BASE_URL}/", data={"q": alias}, allow_redirects=True, timeout=10)
            if "/drugs/" in r.url:
                url = r.url
                if not url.endswith("/"):
                    url += "/"
                redirect_url = url
        except requests.RequestException:
            pass

        # fetch page and validate if redirected
        if redirect_url:
            try:
                sider_id_match = re.search(r'/drugs/(\d+)', redirect_url)
                if sider_id_match:
                    sider_id = sider_id_match.group(1)
                    if sider_id in self.sider_drugs:
                        drug_info = self.sider_drugs[sider_id]
                        score = 80 + (20 if drug_info.get("is_psychoactive") else 0)
                        self.confidence_logs.append({
                            "name": drug_info["sider_name"],
                            "url": redirect_url,
                            "score": score,
                            "reason": f"Direct redirect validated via local drug database (is_psychoactive={drug_info.get('is_psychoactive')})",
                            "method": "Direct Redirect + Local Verify"
                        })
                        if score >= 80:
                            return redirect_url, score
                
                # fetch page and check labels if not in local db
                r_page = self.session.get(redirect_url, timeout=10)
                if r_page.status_code == 200:
                    soup = BeautifulSoup(r_page.text, 'html.parser')
                    h1 = soup.find('h1')
                    drug_name = h1.get_text(strip=True) if h1 else "Unknown"
                    labels = self.get_candidate_labels(soup)
                    score, reason = self.calculate_confidence(alias, drug_name, labels)
                    self.confidence_logs.append({
                        "name": drug_name,
                        "url": redirect_url,
                        "score": score,
                        "reason": reason,
                        "method": "Direct Redirect + Page Verify"
                    })
                    if score >= 80:
                        return redirect_url, score
            except Exception:
                pass

        # query searchBox live autocomplete as last fallback
        live_candidates = []
        try:
            r = self.session.get(f"{BASE_URL}/searchBox/", params={"q": alias}, timeout=10)
            if r.status_code == 200:
                soup = BeautifulSoup(r.text, 'html.parser')
                drug_list = soup.find('ul', class_='drugList')
                if drug_list:
                    for li in drug_list.find_all('li'):
                        a = li.find('a')
                        if a:
                            name = a.get_text(strip=True)
                            href = a.get('href')
                            if href:
                                live_candidates.append({
                                    "name": name,
                                    "url": f"{BASE_URL}{href}" if href.startswith('/') else href
                                })
        except requests.RequestException:
            pass

        if not live_candidates:
            if redirect_url and self.confidence_logs:
                return redirect_url, self.confidence_logs[0]["score"]
            return None, 0

        # evaluate candidates from search box results
        evaluated_candidates = []
        for cand in live_candidates:
            existing = [x for x in self.confidence_logs if x["url"] == cand["url"]]
            if existing:
                evaluated_candidates.append(existing[0])
                continue
            
            # check if candidate is in local sider_drugs
            cand_id_match = re.search(r'/drugs/(\d+)', cand["url"])
            if cand_id_match:
                cand_id = cand_id_match.group(1)
                if cand_id in self.sider_drugs:
                    drug_info = self.sider_drugs[cand_id]
                    score = 0
                    reasons = []
                    if drug_info["sider_name"] == alias_lower:
                        score += 80
                        reasons.append("Exact name match in local verify")
                    elif drug_info["sider_name"].startswith(alias_lower):
                        score += 60
                        reasons.append("Prefix name match in local verify")
                    
                    if drug_info.get("is_psychoactive"):
                        score += 20
                        reasons.append("Psychoactive drug bonus (+20)")
                        
                    score = min(score, 100)
                    evaluated_candidates.append({
                        "name": drug_info["sider_name"],
                        "url": cand["url"],
                        "score": score,
                        "reason": "; ".join(reasons),
                        "method": "Search Box + Local Verify"
                    })
                    continue

            prelim_score, reason = self.calculate_confidence(alias, cand["name"])
            evaluated_candidates.append({
                "name": cand["name"],
                "url": cand["url"],
                "score": prelim_score,
                "reason": reason,
                "method": "Search Box (preliminary)"
            })

        # sort by score descending
        evaluated_candidates.sort(key=lambda x: x["score"], reverse=True)

        # refine top 3 candidates by fetching their page labels
        for i in range(min(3, len(evaluated_candidates))):
            cand = evaluated_candidates[i]
            if "Verify" in cand["method"] or cand["score"] == 100:
                continue
            
            try:
                r_cand = self.session.get(cand["url"], timeout=10)
                if r_cand.status_code == 200:
                    soup_cand = BeautifulSoup(r_cand.text, 'html.parser')
                    labels = self.get_candidate_labels(soup_cand)
                    score, reason = self.calculate_confidence(alias, cand["name"], labels)
                    cand["score"] = score
                    cand["reason"] = reason
                    cand["method"] = "Search Box (refined with labels)"
            except Exception:
                pass

        # re-sort by refined scores
        evaluated_candidates.sort(key=lambda x: x["score"], reverse=True)
        self.confidence_logs = evaluated_candidates

        # return top result if acceptable confidence
        if evaluated_candidates:
            top_cand = evaluated_candidates[0]
            if top_cand["score"] >= 50:
                return top_cand["url"], top_cand["score"]

        return None, 0

    def scrape_drug_data(self, url):
        """scrape side effects and indications from sider drug page"""
        if self.use_pt:
            parts = url.rstrip("/").split("/")
            if parts[-1] != "pt":
                url = "/".join(parts) + "/pt"

        r = self.session.get(url, timeout=15)
        if r.status_code != 200:
            raise Exception(f"Failed to fetch page: {url} (status code {r.status_code})")
        
        soup = BeautifulSoup(r.text, 'html.parser')
        
        # get drug name from title
        h1 = soup.find('h1')
        drug_name = h1.get_text(strip=True) if h1 else "Unknown Drug"

        side_effects = []
        indications = []

        # find boxDiv sections with side effects and indications tables
        for div in soup.find_all('div', class_='boxDiv'):
            h3 = div.find('h3')
            if not h3:
                continue
            
            h3_text = h3.get_text()
            is_side_effects = 'Side effects' in h3_text
            is_indications = 'Indications' in h3_text

            if is_side_effects or is_indications:
                table = div.find('table')
                if not table:
                    continue
                for tr in table.find_all('tr'):
                    classes = tr.get('class', [])
                    if any(c in classes for c in ['bg1', 'bg2']):
                        tds = tr.find_all('td')
                        if not tds:
                            continue
                        a_tag = tds[0].find('a')
                        if not a_tag:
                            continue
                        
                        # parse effect/indication name and extract UMLS CUI
                        clean_a = BeautifulSoup(str(a_tag), 'html.parser')
                        small = clean_a.find('small')
                        if small:
                            small.decompose()
                        name = clean_a.get_text(strip=True)
                        
                        href = a_tag.get('href', '')
                        match = re.search(r'C\d{7}', href)
                        cui = match.group(0) if match else ''
                        
                        entry = {
                            "name": name,
                            "umls_cui": cui
                        }
                        
                        if is_side_effects:
                            side_effects.append(entry)
                        else:
                            indications.append(entry)

        return {
            "drug_name": drug_name,
            "url": url,
            "side_effects": side_effects,
            "indications": indications
        }

    def scrape_by_aliases(self, aliases):
        """try each alias and scrape data from the first successful resolve"""
        for alias in aliases:
            url, score = self.resolve_drug_url(alias)
            if url:
                try:
                    data = self.scrape_drug_data(url)
                    data["resolved_alias"] = alias
                    data["confidence_score"] = score
                    data["confidence_logs"] = self.confidence_logs
                    
                    # extract sider id from url and lookup metadata
                    sider_id_match = re.search(r'/drugs/(\d+)', url)
                    if sider_id_match:
                        sider_id = sider_id_match.group(1)
                        # lookup atc codes and canonical name from local index
                        if sider_id in self.sider_drugs:
                            drug_info = self.sider_drugs[sider_id]
                            data["atc_codes"] = drug_info.get("atc_codes", [])
                            data["canonical_name"] = drug_info.get("canonical_name") or drug_info["sider_name"].capitalize()
                            data["is_psychoactive"] = drug_info.get("is_psychoactive", False)
                        else:
                            data["atc_codes"] = []
                            data["canonical_name"] = data["drug_name"]
                            data["is_psychoactive"] = False
                    
                    return data
                except Exception as e:
                    print(f"Warning: Failed to scrape resolved URL {url} for alias '{alias}': {e}", file=sys.stderr)
                    pass
        return None


def main():
    parser = argparse.ArgumentParser(description="Scrape drug side effects and indications from SIDER database.")
    parser.add_argument("aliases", nargs="+", help="One or more aliases/names for the drug to search.")
    parser.add_argument("--pt", action="store_true", help="Scrape MedDRA Preferred Terms (PT) instead of Lowest Level Terms.")
    parser.add_argument("--json", action="store_true", help="Output results in JSON format.")
    parser.add_argument("--debug", action="store_true", help="Print debug info and truncate the side effects and indications lists for a quick preview.")
    
    args = parser.parse_args()

    scraper = SIDERScraper(use_pt=args.pt)
    data = scraper.scrape_by_aliases(args.aliases)

    if not data:
        print(f"Error: Could not resolve any of the aliases: {args.aliases}", file=sys.stderr)
        if scraper.confidence_logs:
            print("\nResolution Diagnostics (Top evaluated candidates):", file=sys.stderr)
            for c in scraper.confidence_logs[:5]:
                print(f"  - {c['name']} ({c['url']}): Score {c['score']}/100 - {c['reason']} [{c['method']}]", file=sys.stderr)
        sys.exit(1)

    if args.json:
        if args.debug:
            orig_se_len = len(data["side_effects"])
            orig_ind_len = len(data["indications"])
            data["side_effects"] = data["side_effects"][:5]
            data["indications"] = data["indications"][:5]
            data["truncated_counts"] = {
                "side_effects_omitted": max(0, orig_se_len - 5),
                "indications_omitted": max(0, orig_ind_len - 5)
            }
            # Add database stats and alternate matches
            data["db_statistics"] = {
                "total_sider_drugs": len(scraper.sider_drugs),
                "total_alias_mappings": len(scraper.alias_map)
            }
            data["other_matches"] = data["confidence_logs"][1:4]
        print(json.dumps(data, indent=2))
    else:
        # Diagnostic outputs to stderr
        if args.debug:
            print("[SIDER Index Statistics]", file=sys.stderr)
            print(f"  - Total SIDER Drugs: {len(scraper.sider_drugs)}", file=sys.stderr)
            print(f"  - Total Alias Mappings: {len(scraper.alias_map)}", file=sys.stderr)
            print(file=sys.stderr)

        print(f"[Confidence Report for alias '{data['resolved_alias']}']", file=sys.stderr)
        logs = data['confidence_logs']
        if logs:
            chosen = logs[0]
            print(f"  - Chosen: {chosen['name']} (Score: {chosen['score']}/100, Reason: {chosen['reason']})", file=sys.stderr)
            
            # Show up to 3 other lower confidence matches
            others = logs[1:4]
            if others:
                print("  - Other matches:", file=sys.stderr)
                for c in others:
                    print(f"    * {c['name']} (Score: {c['score']}/100, Reason: {c['reason']})", file=sys.stderr)
        print(f"Resolved '{data['resolved_alias']}' to '{data['drug_name']}' (Confidence: {data['confidence_score']}/100)\n", file=sys.stderr)
        
        # Primary output on stdout
        print(f"Drug Name: {data['drug_name']}")
        print(f"Canonical Name: {data['canonical_name']}")
        print(f"Resolved via Alias: {data['resolved_alias']}")
        print(f"SIDER Page URL: {data['url']}")
        print(f"ATC Codes: {', '.join(data['atc_codes']) if data['atc_codes'] else 'None'}")
        
        # Print side effects
        print("\n--- Side Effects ---")
        se_list = data['side_effects']
        if args.debug and len(se_list) > 5:
            for se in se_list[:5]:
                print(f"- {se['name']} (UMLS: {se['umls_cui']})")
            print(f"- ... (and {len(se_list) - 5} more side effects)")
        else:
            for se in se_list:
                print(f"- {se['name']} (UMLS: {se['umls_cui']})")
                
        # Print indications
        print("\n--- Indications ---")
        ind_list = data['indications']
        if args.debug and len(ind_list) > 5:
            for ind in ind_list[:5]:
                print(f"- {ind['name']} (UMLS: {ind['umls_cui']})")
            print(f"- ... (and {len(ind_list) - 5} more indications)")
        else:
            for ind in ind_list:
                print(f"- {ind['name']} (UMLS: {ind['umls_cui']})")

if __name__ == "__main__":
    main()
