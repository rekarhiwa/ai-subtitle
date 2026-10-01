from pathlib import Path
import re

path = Path(r'C:\Users\rekar\Desktop\project\subtitle\lib\features\montage\feature_catalog.dart')
text = path.read_text(encoding='utf-8')

# Features completed in this batch → ready
ready_ids = {
    9,14,15,21,22,29,30,34,39,50,51,52,54,57,62,67,68,69,72,75,77,81,85,90,91,109,116,118,127,131
}

def repl(m):
    n = int(m.group(1))
    whole = m.group(0)
    if n in ready_ids:
        whole = whole.replace('FeatureStatus.partial', 'FeatureStatus.ready')
        whole = whole.replace('FeatureStatus.planned', 'FeatureStatus.ready')
    return whole

# Match each _f(...) call spanning lines until closing );
pattern = re.compile(r"_f\(\s*(\d+),[\s\S]*?\),", re.M)
new_text, count = pattern.subn(repl, text)
path.write_text(new_text, encoding='utf-8')
print('patched features', count)
# verify
ready = len(re.findall(r'FeatureStatus\.ready', new_text))
partial = len(re.findall(r'FeatureStatus\.partial', new_text))
planned = len(re.findall(r'FeatureStatus\.planned', new_text))
print(f'ready={ready} partial={partial} planned={planned}')
