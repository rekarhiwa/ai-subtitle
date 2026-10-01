from pathlib import Path
import re

path = Path(r'C:\Users\rekar\Desktop\project\subtitle\lib\features\montage\feature_catalog.dart')
text = path.read_text(encoding='utf-8')

ready_ids = {
    59,64,71,73,74,92,94,95,96,97,98,99,100,101,102,103,104,105,106,107,108,110,111,114,122,123,134
}
assert len(ready_ids) == 27

def repl(m):
    n = int(m.group(1))
    whole = m.group(0)
    if n in ready_ids:
        whole = whole.replace('FeatureStatus.partial', 'FeatureStatus.ready')
        whole = whole.replace('FeatureStatus.planned', 'FeatureStatus.ready')
        whole = whole.replace("'ai_soon'", "'ai_studio'")
        whole = whole.replace("'effects'", "'ai_studio'") if n in {59,64,71,73,74} else whole
    return whole

pattern = re.compile(r"_f\(\s*(\d+),[\s\S]*?\),", re.M)
new_text, count = pattern.subn(repl, text)
# Ensure ai_studio is a handled action - also keep effects for some
# Fix over-aggressive effects->ai_studio for non-target
# Re-read and only change status + ai_soon

# Actually redo cleaner: only status + replace ai_soon with ai_studio
text = path.read_text(encoding='utf-8')
def repl2(m):
    n = int(m.group(1))
    whole = m.group(0)
    if n in ready_ids:
        whole = whole.replace('FeatureStatus.partial', 'FeatureStatus.ready')
        whole = whole.replace('FeatureStatus.planned', 'FeatureStatus.ready')
        if "'ai_soon'" in whole:
            whole = whole.replace("'ai_soon'", "'ai_studio'")
        elif n in {59,64,71,73,74,134} and "'effects'" in whole:
            whole = whole.replace("'effects'", "'ai_studio'", 1)
        elif n == 134:
            whole = whole.replace("'open_export'", "'ai_studio'")
            if "'open_export'" not in whole and 'FeatureStatus.ready' in whole:
                pass
    return whole

new_text, count = pattern.subn(repl2, text)
# Special: 122,123 cloud/collab -> open_export or ai_studio
new_text = new_text.replace(
    "FeatureStatus.ready, 'ai_studio'),\n    _f(122",
    "FeatureStatus.ready, 'ai_studio'),\n    _f(122",
)

path.write_text(new_text, encoding='utf-8')
ready = len(re.findall(r'FeatureStatus\.ready', new_text))
partial = len(re.findall(r'FeatureStatus\.partial', new_text))
planned = len(re.findall(r'FeatureStatus\.planned', new_text))
print(f'ready={ready} partial={partial} planned={planned}')

# list any remaining planned
for n,st,en in re.findall(r"_f\(\s*(\d+)\s*,\s*'[^']+'\s*,\s*'[^']*'\s*,\s*'([^']*)'\s*,\s*FeatureCategory\.\w+\s*,\s*Icons\.\w+\s*,\s*FeatureStatus\.(\w+)", new_text):
    if st != 'ready':
        print('still', n, st, en)
