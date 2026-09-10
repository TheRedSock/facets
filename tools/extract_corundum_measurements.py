"""Extract visible numeric measurements from the pinned GIA supplement.
No spreadsheet runtime or network is needed; XML is read as data, never executed.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile

SHA256 = "26f9c90a90abba463478b44d390f2a725ec78a9c891a1ca1267f865a2f27a9da"
URL = "https://origin.prod.gia.edu/dam/jcr:6ec3f5fc-4c0c-4276-a81b-a9534b88d50b/sp20-corundum-chromophores-absorption-cross-section-data.xlsx"
ARTICLE = "https://www.gia.edu/gems-gemology/spring-2020-corundum-chromophores"
COLUMNS = {"chromium": ("B", "C"), "vanadium": ("D", "E"), "iron_titanium": ("F", "G"), "hole_iron": ("H", "I"), "hole_chromium": ("J", "K"), "iron": ("M", "N")}
NS = {"s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}

def extract(workbook, output):
    raw = workbook.read_bytes()
    if hashlib.sha256(raw).hexdigest() != SHA256:
        raise ValueError("Unexpected source workbook; review a new edition before changing the pinned hash")
    with zipfile.ZipFile(workbook) as archive:
        document = ET.fromstring(archive.read("xl/worksheets/sheet1.xml"))
        rows = {}
        for row in document.findall("s:sheetData/s:row", NS):
            if int(row.attrib["r"]) < 11:
                continue
            cells = {c.attrib["r"].rstrip("0123456789"): c.find("s:v", NS) for c in row.findall("s:c", NS)}
            if cells.get("A") is None:
                continue
            wavelength = float(cells["A"].text)
            if 380 <= wavelength <= 780:
                if wavelength != int(wavelength) or int(wavelength) in rows:
                    raise ValueError("Unexpected wavelength grid")
                rows[int(wavelength)] = {key: value.text for key, value in cells.items() if value is not None}
    if sorted(rows) != list(range(380, 781)):
        raise ValueError("Incomplete visible data")
    output.mkdir(parents=True, exist_ok=True)
    records = {}
    for name, columns in COLUMNS.items():
        target = output / (name + ".csv")
        with target.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.writer(stream, lineterminator="\n")
            writer.writerow(["wavelength_nm", "ordinary", "extraordinary"])
            for wavelength, values in sorted(rows.items()):
                writer.writerow([wavelength, *(values[column] for column in columns)])
        records[name] = {"file": target.name, "sha256": hashlib.sha256(target.read_bytes()).hexdigest(), "columns": list(columns)}
    metadata = {"source_url": URL, "workbook_sha256": SHA256, "citation": ARTICLE,
                "quantity": "cross_section_cm2", "optical_basis": "ordinary_extraordinary",
                "host_species_id": "corundum", "wavelength_nm": [380, 780, 1],
                "instrument_resolution_nm": 1.5, "source_sheet": "Sheet1", "source_rows": [331, 731],
                "spectra": records,
                "review": {"examples": ["chromium", "iron_titanium"],
                           "deferred": {"iron": "Concentration-dependent clustering; one constant cross section cannot define a general concentration law.",
                                        "vanadium": "Workbook 580nm ordinary value differs from the article peak statement; normalization requires further review.",
                                        "hole_iron": "No independent numeric calibration completed.",
                                        "hole_chromium": "No independent numeric calibration completed."},
                           "color_appendix": "Concentration labels and stored multipliers do not consistently reproduce the listed Lab coordinates. Do not fit coefficient scales to those colors."}}
    (output / "source.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output), "spectra": len(records), "samples_per_axis": len(rows), "workbook_sha256": SHA256}))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("workbook", type=Path)
    parser.add_argument("--output", type=Path, default=Path("data/lapidary/measurements/gia_corundum_2020"))
    args = parser.parse_args()
    extract(args.workbook, args.output)
