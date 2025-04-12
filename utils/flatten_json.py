import pandas as pd

def flatten_json(data, parent_key='', sep='_'):
    """
    Recursively flattens a nested JSON structure into a flat dictionary.
    """
    items = []
    for key, value in data.items():
        new_key = f"{parent_key}{sep}{key}" if parent_key else key
        if isinstance(value, dict):
            items.extend(flatten_json(value, new_key, sep=sep).items())
        else:
            items.append((new_key, value))
    return dict(items)

