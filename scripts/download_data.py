import os
import json
import urllib.request
import pandas as pd
import numpy as np

DATA_DIR = "data"
CSV_PATH = os.path.join(DATA_DIR, "XAUUSD_M5_2019_2024.csv")
PARQUET_PATH = os.path.join(DATA_DIR, "XAUUSD_M5_2019_2024.parquet")

def download_xauusd_m5():
    os.makedirs(DATA_DIR, exist_ok=True)
    if os.path.exists(PARQUET_PATH):
        print(f"Dataset already exists at {PARQUET_PATH}")
        return

    print("Downloading XAUUSD M5 data from HuggingFace dataset (ZombitX64/xauusd-gold-price-historical-data-2004-2025)...")
    url = "https://huggingface.co/datasets/ZombitX64/xauusd-gold-price-historical-data-2004-2025/resolve/main/XAU_5m_data.jsonl"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})

    records = []
    # Filter 2019-01-01 to 2024-12-31
    start_str = "2019.01.01"
    end_str = "2024.12.31 23:59"

    with urllib.request.urlopen(req) as resp:
        for line in resp:
            data = json.loads(line.decode("utf-8"))
            date_str = data["Date"]
            if date_str >= start_str and date_str <= end_str:
                records.append(data)

    print(f"Downloaded {len(records)} bars. Converting to DataFrame...")
    df = pd.DataFrame(records)
    df["Date"] = pd.to_datetime(df["Date"], format="%Y.%m.%d %H:%M")
    df.set_index("Date", inplace=True)
    df.sort_index(inplace=True)

    # Save to parquet for fast reading
    df.to_parquet(PARQUET_PATH)
    df.to_csv(CSV_PATH)
    print(f"Saved {len(df)} rows to {PARQUET_PATH} and {CSV_PATH}")

if __name__ == "__main__":
    download_xauusd_m5()
