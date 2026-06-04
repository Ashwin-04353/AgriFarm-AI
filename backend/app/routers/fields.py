from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text
from pydantic import BaseModel
from typing import Optional
from ..database import get_db
from ..auth.utils import get_current_user

router = APIRouter(prefix="/fields", tags=["fields"])

class FieldIn(BaseModel):
    farm_id: int
    name: str
    area_hectares: Optional[float] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    soil_type: str = "loam"

@router.get("/")
def list_fields(db: Session = Depends(get_db),
                user=Depends(get_current_user)):
    rows = db.execute(
        text("SELECT f.* FROM fields f "
             "JOIN farms fa ON fa.id=f.farm_id "
             "WHERE fa.user_id=:uid"),
        {"uid": user["id"]}
    ).fetchall()
    return [dict(r._mapping) for r in rows]

@router.post("/", status_code=201)
def create_field(data: FieldIn,
                 db: Session = Depends(get_db),
                 user=Depends(get_current_user)):
    farm = db.execute(
        text("SELECT id FROM farms WHERE id=:fid AND user_id=:uid"),
        {"fid": data.farm_id, "uid": user["id"]}
    ).fetchone()
    if not farm:
        raise HTTPException(403, "Farm not found or unauthorized")
    db.execute(
        text("INSERT INTO fields "
             "(farm_id,name,area_hectares,latitude,longitude,soil_type) "
             "VALUES (:fid,:n,:a,:lat,:lon,:s)"),
        {"fid": data.farm_id, "n": data.name,
         "a": data.area_hectares, "lat": data.latitude,
         "lon": data.longitude,  "s": data.soil_type}
    )
    db.commit()
    return {"message": "Field created"}