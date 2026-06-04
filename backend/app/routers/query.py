from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text
from pydantic import BaseModel
from ..database import get_db
from ..auth.utils import get_current_user
from ..agents.nl_to_sql import natural_language_to_sql

router = APIRouter(prefix="/query", tags=["query"])

class NLQueryIn(BaseModel):
    question: str

@router.post("/ask")
def ask(data: NLQueryIn,
        db: Session = Depends(get_db),
        user=Depends(get_current_user)):
    
    try:
        result = natural_language_to_sql(db, user["id"], data.question)
        return result
    except ValueError as e:
        raise HTTPException(422, str(e))

@router.get("/history")
def history(db: Session = Depends(get_db),
            user=Depends(get_current_user)):
    rows = db.execute(
        text("SELECT TOP 20 natural_query, generated_sql, "
             "executed, result_rows, error_message, created_at "
             "FROM nl_query_log WHERE user_id=:uid "
             "ORDER BY created_at DESC"),
        {"uid": user["id"]}
    ).fetchall()
    return [dict(r._mapping) for r in rows]