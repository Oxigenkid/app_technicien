import json

with open('assets/inventaires/inventaire_camions.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

ids = {}
total = 0
for k, v in data.items():
    c_num = "".join(filter(str.isdigit, v['camion']))
    for art in v['articles']:
        total += 1
        ref = art['ref']
        item_id = f"{c_num}_{ref}"
        if item_id in ids:
            ids[item_id].append((v['camion'], art))
        else:
            ids[item_id] = [(v['camion'], art)]

dups = {k: v for k, v in ids.items() if len(v) > 1}
print(f"Total: {total}")
print(f"Unique: {len(ids)}")
print(f"Duplicates: {len(dups)}")
for k, v in dups.items():
    print(f"\nDuplicate ID: {k} (appears {len(v)} times)")
    for truck, item in v:
        print(f"  {truck}: nom='{item.get('nom')}', qte={item.get('quantite')}, cout={item.get('cout')}")
