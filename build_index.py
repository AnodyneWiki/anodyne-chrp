import os
import json
import re

def build_index():
    print("Building SIDER index...")
    
    # 1. Load SIDER drugs from drug_names.tsv
    sider_drugs = {}  # id (int) -> dict
    sider_name_to_id = {}  # lowercase name -> id
    
    if os.path.exists("drug_names.tsv"):
        with open("drug_names.tsv", "r", encoding="utf-8") as f:
            for line in f:
                parts = line.strip().split("\t")
                if len(parts) == 2:
                    cid, name = parts
                    sider_id = int(cid[4:])
                    name_lower = name.strip().lower()
                    sider_drugs[sider_id] = {
                        "sider_id": sider_id,
                        "sider_name": name_lower,
                        "atc_codes": [],
                        "canonical_name": None,
                        "is_psychoactive": False
                    }
                    sider_name_to_id[name_lower] = sider_id
    else:
        print("Error: drug_names.tsv not found!", file=sys.stderr)
        return

    # 2. Load ATC codes from drug_atc.tsv
    if os.path.exists("drug_atc.tsv"):
        with open("drug_atc.tsv", "r", encoding="utf-8") as f:
            for line in f:
                parts = line.strip().split("\t")
                if len(parts) == 2:
                    cid, atc = parts
                    sider_id = int(cid[4:])
                    if sider_id in sider_drugs:
                        if atc not in sider_drugs[sider_id]["atc_codes"]:
                            sider_drugs[sider_id]["atc_codes"].append(atc)

    # 3. Load slang map (psychoactive slang from reddit.py)
    slang_map = {
        "acid":          "lsd",
        "lsd":           "lsd",
        "tabs":          "lsd",
        "blotter":       "lsd",
        "shrooms":       "psilocybin mushrooms",
        "mushrooms":     "psilocybin mushrooms",
        "mush":          "psilocybin mushrooms",
        "psilocybin":    "psilocybin",
        "psilocin":      "psilocin",
        "dmt":           "dmt",
        "ayahuasca":     "ayahuasca",
        "salvia":        "salvia divinorum",
        "mescaline":     "mescaline",
        "peyote":        "peyote",
        "ibogaine":      "ibogaine",
        "iboga":         "ibogaine",
        "2cb":           "2c-b",
        "2c-b":          "2c-b",
        "nbome":         "nbome",
        "25i":           "25i-nbome",
        "25b":           "25b-nbome",
        "25c":           "25c-nbome",
        "ketamine":      "ketamine",
        "ket":           "ketamine",
        "special k":     "ketamine",
        "dxm":           "dxm",
        "robo":          "dxm",
        "pcp":           "pcp",
        "mxe":           "methoxetamine",
        "nitrous":       "nitrous oxide",
        "nos":           "nitrous oxide",
        "whippets":      "nitrous oxide",
        "mdma":          "mdma",
        "molly":         "mdma",
        "ecstasy":       "mdma",
        "mda":           "mda",
        "5mapb":         "5-mapb",
        "6apb":          "6-apb",
        "cocaine":       "cocaine",
        "coke":          "cocaine",
        "crack":         "crack cocaine",
        "meth":          "methamphetamine",
        "crystal":       "methamphetamine",
        "ice":           "methamphetamine",
        "amphetamine":   "amphetamine",
        "adderall":      "amphetamine",
        "speed":         "amphetamine",
        "vyvanse":       "lisdexamfetamine",
        "ritalin":       "methylphenidate",
        "caffeine":      "caffeine",
        "heroin":        "heroin",
        "dope":          "heroin",
        "fentanyl":      "fentanyl",
        "oxycodone":     "oxycodone",
        "oxy":           "oxycodone",
        "percocet":      "oxycodone",
        "hydrocodone":   "hydrocodone",
        "vicodin":       "hydrocodone",
        "codeine":       "codeine",
        "tramadol":      "tramadol",
        "morphine":      "morphine",
        "methadone":     "methadone",
        "buprenorphine": "buprenorphine",
        "suboxone":      "buprenorphine",
        "kratom":        "kratom",
        "alcohol":       "alcohol",
        "ethanol":       "alcohol",
        "booze":         "alcohol",
        "beer":          "alcohol",
        "wine":          "alcohol",
        "vodka":         "alcohol",
        "whiskey":       "alcohol",
        "xanax":         "alprazolam",
        "alprazolam":    "alprazolam",
        "xans":          "alprazolam",
        "valium":        "diazepam",
        "diazepam":      "diazepam",
        "klonopin":      "clonazepam",
        "clonazepam":    "clonazepam",
        "ativan":        "lorazepam",
        "lorazepam":     "lorazepam",
        "weed":          "cannabis",
        "cannabis":      "cannabis",
        "marijuana":     "cannabis",
        "thc":           "cannabis",
        "cbd":           "cbd",
        "dabs":          "cannabis",
        "edibles":       "cannabis"
    }

    # 4. Parse substance_index.txt
    psychoactive_list = []  # list of dicts: {"canonical": str, "aliases": list}
    
    if os.path.exists("substance_index.txt"):
        with open("substance_index.txt", "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("Substance Index"):
                    continue
                # Match canonical name and optional parenthesis content
                match = re.match(r'^([^(]+)(?:\(([^)]+)\))?', line)
                if match:
                    canonical = match.group(1).strip()
                    aliases = [canonical]
                    if match.group(2):
                        # Split aliases by comma
                        parts = [p.strip() for p in match.group(2).split(",")]
                        aliases.extend(parts)
                    psychoactive_list.append({
                        "canonical": canonical,
                        "aliases": aliases
                    })

    # 5. Load erowid_substances.json
    if os.path.exists("erowid_substances.json"):
        try:
            with open("erowid_substances.json", "r", encoding="utf-8") as f:
                data = json.load(f)
                for item in data:
                    name = item.get("name")
                    if name:
                        # Add to list if not already present
                        exists = False
                        for p in psychoactive_list:
                            if p["canonical"].lower() == name.lower():
                                exists = True
                                break
                        if not exists:
                            psychoactive_list.append({
                                "canonical": name,
                                "aliases": [name]
                            })
        except Exception as e:
            print(f"Warning: Failed to parse erowid_substances.json: {e}")

    # Helper function to find SIDER ID by name
    def find_sider_id(name):
        n_lower = name.lower()
        # Direct match
        if n_lower in sider_name_to_id:
            return sider_name_to_id[n_lower]
        # Check slang map
        if n_lower in slang_map:
            target = slang_map[n_lower]
            if target in sider_name_to_id:
                return sider_name_to_id[target]
        # Substring search in SIDER names
        for sider_name, sider_id in sider_name_to_id.items():
            if n_lower == sider_name or n_lower in sider_name.split() or sider_name in n_lower.split():
                return sider_id
        return None

    # 6. Map psychoactive substances to SIDER drugs
    alias_map = {}  # lowercase alias -> dict (sider_id, canonical, atc_codes, is_psychoactive)
    
    # Pre-populate alias_map with all standard SIDER drugs as a baseline
    for sider_id, drug in sider_drugs.items():
        name = drug["sider_name"]
        alias_map[name] = {
            "sider_id": sider_id,
            "sider_name": name,
            "canonical_name": name.capitalize(),
            "atc_codes": drug["atc_codes"],
            "is_psychoactive": False
        }

    matched_count = 0
    for entry in psychoactive_list:
        canonical = entry["canonical"]
        aliases = entry["aliases"]
        
        # Try to find a matching SIDER drug for any of the aliases
        target_sider_id = None
        for alias in aliases:
            target_sider_id = find_sider_id(alias)
            if target_sider_id:
                break
                
        if target_sider_id:
            matched_count += 1
            # Mark SIDER drug as psychoactive
            sider_drugs[target_sider_id]["is_psychoactive"] = True
            sider_drugs[target_sider_id]["canonical_name"] = canonical
            
            # Map all aliases of this substance to the SIDER drug
            drug_info = sider_drugs[target_sider_id]
            for alias in aliases:
                alias_lower = alias.lower()
                alias_map[alias_lower] = {
                    "sider_id": target_sider_id,
                    "sider_name": drug_info["sider_name"],
                    "canonical_name": canonical,
                    "atc_codes": drug_info["atc_codes"],
                    "is_psychoactive": True
                }

    # 7. Map the slang_map entries explicitly to ensure they are captured
    for slang, target in slang_map.items():
        target_id = find_sider_id(target)
        if target_id:
            drug_info = sider_drugs[target_id]
            alias_map[slang.lower()] = {
                "sider_id": target_id,
                "sider_name": drug_info["sider_name"],
                "canonical_name": drug_info["canonical_name"] or target,
                "atc_codes": drug_info["atc_codes"],
                "is_psychoactive": True
            }

    # 8. Clean up sider_drugs keys for JSON output (convert int keys to str)
    sider_drugs_json = {str(k): v for k, v in sider_drugs.items()}

    # 9. Save to sider_index.json
    output_data = {
        "alias_map": alias_map,
        "sider_drugs": sider_drugs_json
    }
    
    with open("sider_index.json", "w", encoding="utf-8") as f:
        json.dump(output_data, f, indent=2)
        
    print(f"Index built successfully! Matched {matched_count} psychoactive substances to SIDER.")
    print(f"Total SIDER drugs indexed: {len(sider_drugs)}")
    print(f"Total alias mappings: {len(alias_map)}")

if __name__ == "__main__":
    build_index()
