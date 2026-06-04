from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text
from ..database import get_db, call_procedure
from ..auth.utils import get_current_user
from ..agents.reasoning import run_reasoning_agent

router = APIRouter(prefix="/analytics", tags=["analytics"])

@router.get("/dashboard")
def dashboard(db: Session = Depends(get_db),
              user=Depends(get_current_user)):
    rows = db.execute(
        text("SELECT * FROM vw_dashboard_overview WHERE user_id=:uid"),
        {"uid": user["id"]}
    ).fetchall()
    return [dict(r._mapping) for r in rows]

@router.get("/field/{field_id}/trends")
def trends(field_id: int, db: Session = Depends(get_db),
           user=Depends(get_current_user)):
    rows = db.execute(
        text("SELECT TOP 30 * FROM vw_field_trends "
             "WHERE field_id=:fid ORDER BY recorded_at DESC"),
        {"fid": field_id}
    ).fetchall()
    return [dict(r._mapping) for r in rows]

@router.get("/field/{field_id}/anomalies")
def anomalies(field_id: int, db: Session = Depends(get_db),
              user=Depends(get_current_user)):
    return call_procedure(db, "sp_classify_anomalies",
                          {"field_id": field_id})

@router.get("/field/{field_id}/rotation")
def rotation(field_id: int, db: Session = Depends(get_db),
             user=Depends(get_current_user)):
    return call_procedure(db, "sp_crop_rotation_advisor",
                          {"field_id": field_id})

@router.post("/field/{field_id}/run-agent")
def run_agent(field_id: int, db: Session = Depends(get_db),
              user=Depends(get_current_user)):
    try:
        result = run_reasoning_agent(db, field_id)
        return {"status": "success", "advisory": result}
    except ValueError as e:
        raise HTTPException(422, str(e))

@router.get("/farm/{farm_id}/irrigation-plan")
def irrigation(farm_id: int, db: Session = Depends(get_db),
               user=Depends(get_current_user)):
    return call_procedure(db, "sp_optimize_irrigation",
                          {"farm_id": farm_id})

@router.get("/regional-benchmark")
def benchmark(db: Session = Depends(get_db),
              user=Depends(get_current_user)):
    rows = db.execute(
        text("SELECT * FROM vw_regional_benchmark")
    ).fetchall()
    return [dict(r._mapping) for r in rows]