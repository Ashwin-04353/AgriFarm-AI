from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import text
from ..database import get_db
from ..auth.utils import get_current_user

router = APIRouter(prefix="/alerts", tags=["alerts"])

@router.get("/")
def get_alerts(db: Session = Depends(get_db),
               user=Depends(get_current_user)):
    rows = db.execute(
        text("SELECT TOP 50 * FROM vw_alerts_feed "
             "WHERE user_id=:uid ORDER BY created_at DESC"),
        {"uid": user["id"]}
    ).fetchall()
    return [dict(r._mapping) for r in rows]

@router.put("/{alert_id}/resolve")
def resolve(alert_id: int, db: Session = Depends(get_db),
            user=Depends(get_current_user)):
    db.execute(
        text("UPDATE alerts SET is_resolved=1 WHERE id=:id"),
        {"id": alert_id}
    )
    db.commit()
    return {"message": "Alert resolved"}