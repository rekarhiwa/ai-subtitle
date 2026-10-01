from pathlib import Path
import re

path = Path(r'C:\Users\rekar\Desktop\project\subtitle\lib\features\montage\feature_catalog.dart')
text = path.read_text(encoding='utf-8')

ready_ids = {
    24,25,26,27,28,31,44,47,58,65,66,70,79,80,82,83,84,
    86,87,88,112,113,115,117,119,120,125,128,132,133
}
assert len(ready_ids) == 30

def repl(m):
    n = int(m.group(1))
    whole = m.group(0)
    if n in ready_ids:
        whole = whole.replace('FeatureStatus.partial', 'FeatureStatus.ready')
        whole = whole.replace('FeatureStatus.planned', 'FeatureStatus.ready')
    return whole

pattern = re.compile(r"_f\(\s*(\d+),[\s\S]*?\),", re.M)
new_text, count = pattern.subn(repl, text)

# Fix action ids for newly ready features that still point to ai_soon
replacements = {
    "('autocut'": None,
}
# Simple line-based action fixes
new_text = new_text.replace(
    "_f(86, 'autocut', 'AutoCut', 'AutoCut',\n        FeatureCategory.ai, Icons.content_cut, FeatureStatus.ready, 'ai_soon'),",
    "_f(86, 'autocut', 'AutoCut', 'AutoCut',\n        FeatureCategory.ai, Icons.content_cut, FeatureStatus.ready, 'effects'),",
)
new_text = new_text.replace(
    "_f(87, 'ai_clipper', 'AI Clipper', 'AI Clipper best moments',\n        FeatureCategory.ai, Icons.movie_filter, FeatureStatus.ready, 'ai_soon'),",
    "_f(87, 'ai_clipper', 'AI Clipper', 'AI Clipper best moments',\n        FeatureCategory.ai, Icons.movie_filter, FeatureStatus.ready, 'effects'),",
)
new_text = new_text.replace(
    "_f(88, 'long_to_short', 'Long → Shorts', 'Long video to Shorts',\n        FeatureCategory.ai, Icons.smartphone, FeatureStatus.ready, 'ai_soon'),",
    "_f(88, 'long_to_short', 'Long → Shorts', 'Long video to Shorts',\n        FeatureCategory.ai, Icons.smartphone, FeatureStatus.ready, 'aspect_ratio'),",
)
new_text = new_text.replace(
    "_f(112, 'beat_edit', 'مۆنتاژی بیت-ئاگاه', 'Beat-aware auto edit',\n        FeatureCategory.ai, Icons.music_video, FeatureStatus.ready, 'ai_soon'),",
    "_f(112, 'beat_edit', 'مۆنتاژی بیت-ئاگاه', 'Beat-aware auto edit',\n        FeatureCategory.ai, Icons.music_video, FeatureStatus.ready, 'effects'),",
)
new_text = new_text.replace(
    "_f(115, 'ai_credits', 'کریدیتی AI', 'Cloud AI credits',\n        FeatureCategory.ai, Icons.stars_outlined, FeatureStatus.ready, 'ai_soon'),",
    "_f(115, 'ai_credits', 'کریدیتی AI', 'Cloud AI credits',\n        FeatureCategory.ai, Icons.stars_outlined, FeatureStatus.ready, 'open_export'),",
)

path.write_text(new_text, encoding='utf-8')
ready = len(re.findall(r'FeatureStatus\.ready', new_text))
partial = len(re.findall(r'FeatureStatus\.partial', new_text))
planned = len(re.findall(r'FeatureStatus\.planned', new_text))
print(f'ready={ready} partial={partial} planned={planned}')
