from fastapi import APIRouter, Depends, UploadFile, File
from sqlalchemy.orm import Session
from ..database import get_db
from ..auth.utils import get_current_user
from ..utils.csv_processor import process_soil_csv

router = APIRouter(prefix="/upload", tags=["upload"])

@router.post("/soil-readings")
async def upload_csv(file: UploadFile = File(...),
                     db: Session = Depends(get_db),
                     user=Depends(get_current_user)):
    return await process_soil_csv(file, user["id"], db)