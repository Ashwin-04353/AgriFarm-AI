import pandas as pd, io
from fastapi import UploadFile, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text
from loguru import logger
from ..config import get_settings

settings = get_settings()
REQUIRED = {"field_id","ph","moisture_pct","temperature_c"}

async def process_soil_csv(
    file: UploadFile, user_id: int, db: Session
) -> dict:
    if not file.filename.endswith(".csv"):
        raise HTTPException(400, "Only CSV files accepted")

    contents = await file.read()
    try:
        df = pd.read_csv(io.BytesIO(contents))
    except Exception:
        raise HTTPException(400, "Cannot parse CSV")

    df.columns = df.columns.str.lower().str.strip()
    missing = REQUIRED - set(df.columns)
    if missing:
        raise HTTPException(422, f"Missing columns: {missing}")

    df = df.dropna(subset=["field_id","ph","moisture_pct"])
    df["ph"]          = df["ph"].clip(0, 14)
    df["moisture_pct"]= df["moisture_pct"].clip(0, 100)
    df["temperature_c"]= df.get("temperature_c",
                                pd.Series([25]*len(df))).fillna(25).clip(-10,60)

    imported, errors = 0, []

    for idx, row in df.iterrows():
        try:
            print("CSV field_id =", row["field_id"])
            print("USER ID =", user_id)
            field = db.execute(
                text("SELECT f.id FROM fields f "
                     "JOIN farms fa ON fa.id=f.farm_id "
                     "WHERE f.id=:fid AND fa.user_id=:uid"),
                {"fid": int(row["field_id"]), "uid": user_id}
            ).fetchone()

            if not field:
                errors.append(f"Row {idx+1}: field not found or unauthorized")
                continue

            db.execute(
                text("INSERT INTO soil_readings "
                     "(field_id,ph,moisture_pct,nitrogen_ppm,"
                     "phosphorus_ppm,potassium_ppm,temperature_c,source) "
                     "VALUES (:fid,:ph,:m,:n,:p,:k,:t,'csv_import')"),
                {"fid": int(row["field_id"]),
                 "ph":  float(row["ph"]),
                 "m":   float(row["moisture_pct"]),
                 "n":   float(row.get("nitrogen_ppm") or 0),
                 "p":   float(row.get("phosphorus_ppm") or 0),
                 "k":   float(row.get("potassium_ppm") or 0),
                 "t":   float(row["temperature_c"])}
            )
            imported += 1
        except Exception as e:
            errors.append(f"Row {idx+1}: {e}")

    db.execute(
        text("INSERT INTO csv_imports "
             "(user_id,filename,rows_imported,status,error_log) "
             "VALUES (:uid,:fn,:rows,:status,:err)"),
        {"uid": user_id, "fn": file.filename, "rows": imported,
         "status": "success" if imported > 0 else "failed",
         "err": "\n".join(errors) or None}
    )
    db.commit()
    return {"imported": imported, "errors": errors, "total_rows": len(df)}