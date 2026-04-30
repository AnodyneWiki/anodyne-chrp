from rdkit import Chem
from rdkit.Chem.EnumerateStereoisomers import EnumerateStereoisomers, StereoEnumerationOptions
from rdkit.Chem.rdmolops import SANITIZE_ALL
from rdkit.Chem import rdCIPLabeler
from rdkit.Chem import AllChem
import sys
import json

def get_stereoisomers(smiles):
    mol = Chem.MolFromSmiles(smiles)
    Chem.SanitizeMol(mol, sanitizeOps=SANITIZE_ALL)
    Chem.AssignCIPLabels(mol)
    Chem.CanonicalizeStereoGroups(mol)
    if not mol:
        return []

    result = []
    opts = StereoEnumerationOptions(tryEmbedding=True, onlyUnassigned=True, unique=True)
    isomers = list(EnumerateStereoisomers(mol, options=opts))
    for isomer in isomers:
        label = ""
        centers = Chem.FindMolChiralCenters(isomer, includeUnassigned=True, useLegacyImplementation=False,force=True)
        
        for ct in centers:
            if label == "":
                if len(centers) == 1:
                    label += "(" + ct[1] + ")-" 
                else:
                    label += "(" + str(ct[0]) + ct[1] + "," 
            else:
                label += str(ct[0]) + ct[1] + ")-"
        smiles_iso = Chem.MolToSmiles(isomer, kekuleSmiles=True, isomericSmiles=True, canonical=True)
        result.append((label, smiles_iso))
    
    return result

if __name__ == "__main__":
    smiles_input = sys.argv[1]
    isomers = get_stereoisomers(smiles_input)
    print(json.dumps(isomers))
