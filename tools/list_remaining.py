from pathlib import Path
import re

t = Path(r'C:\Users\rekar\Desktop\project\subtitle\lib\features\montage\feature_catalog.dart').read_text(encoding='utf-8')
pat = re.compile(
    r"_f\(\s*(\d+)\s*,\s*'([^']+)'\s*,\s*'([^']*)'\s*,\s*'([^']*)'\s*,"
    r"\s*FeatureCategory\.(\w+)\s*,\s*Icons\.\w+\s*,\s*FeatureStatus\.(\w+)"
)
for n, fid, ku, en, cat, st in pat.findall(t):
    if st != 'ready':
        print(f'{n}|{st}|{en}')
