
import json

def load_cross_sections(path):
    with open(path) as f:
        return json.load(f)
