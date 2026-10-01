import re
from pathlib import Path

path = Path(r'C:\Users\rekar\Desktop\project\subtitle\lib\features\montage\feature_catalog.dart')
text = path.read_text(encoding='utf-8')
pat = re.compile(
    r"_f\(\s*(\d+)\s*,\s*'([^']+)'\s*,\s*'([^']*)'\s*,\s*'([^']*)'\s*,"
    r"\s*FeatureCategory\.(\w+)\s*,\s*Icons\.\w+\s*,\s*FeatureStatus\.(\w+)\s*,\s*'([^']+)'"
)
rows = pat.findall(text)
out = Path(r'C:\Users\rekar\Desktop\project\subtitle\test\_feature_meta.csv')
lines = ['number|id|status|action|en']
for n, fid, ku, en, cat, st, act in rows:
    lines.append(f'{n}|{fid}|{st}|{act}|{en}')
out.write_text('\n'.join(lines), encoding='utf-8')
print(f'count={len(rows)} written={out}')
