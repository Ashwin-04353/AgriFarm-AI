from groq import Groq
import json
from loguru import logger
from sqlalchemy.orm import Session
from sqlalchemy import text
from ..config import get_settings
from decimal import Decimal

settings = get_settings()
client = Groq(api_key=settings.groq_api_key)

def get_field_context(db: Session, field_id: int) -> dict:
    row = db.execute(
        text("SELECT * FROM vw_field_agent_context WHERE field_id=:fid"),
        {"fid": field_id}
    ).fetchone()
    if not row:
        raise ValueError(f"No context for field {field_id}")
    return {
    k: float(v) if isinstance(v, Decimal) else v
    for k, v in dict(row._mapping).items()
}

def get_field_memory(db: Session, field_id: int) -> list:
    rows = db.execute(
        text("SELECT memory_type,content,confidence_score "
             "FROM agent_memory WHERE field_id=:fid "
             "ORDER BY confidence_score DESC"),
        {"fid": field_id}
    ).fetchall()
    return [
    {
        k: float(v) if isinstance(v, Decimal) else v
        for k, v in dict(r._mapping).items()
    }
    for r in rows
]

def run_reasoning_agent(db: Session, field_id: int) -> dict:
    try:
        ctx = get_field_context(db, field_id)
        mem = get_field_memory(db, field_id)

        prompt = f"""Analyze this real farmer field data and return advisory.

FIELD: {ctx.get('field_name')} | FARM: {ctx.get('farm_name')}
CROP: {ctx.get('crop_name')} | STAGE: {ctx.get('crop_stage')}
DAYS SINCE SOWING: {ctx.get('days_since_sowing')} of {ctx.get('total_growth_days')}
SOIL TYPE: {ctx.get('soil_type')}

LATEST READINGS:
pH: {ctx.get('ph')} (optimal {ctx.get('optimal_ph_min')}–{ctx.get('optimal_ph_max')})
Moisture: {ctx.get('moisture_pct')}%
Temperature: {ctx.get('temperature_c')}C
Nitrogen: {ctx.get('nitrogen_ppm')} ppm
Phosphorus: {ctx.get('phosphorus_ppm')} ppm
Potassium: {ctx.get('potassium_ppm')} ppm

7-DAY SQL AVERAGES:
Avg moisture: {ctx.get('avg_moisture_7d')}%
Avg pH: {ctx.get('avg_ph_7d')}
Active alerts: {ctx.get('active_alerts')}

PAST MEMORY: {json.dumps(mem)}

Reply ONLY with this JSON, no other text:
{{
  "action": "irrigate|fertilize|monitor|treat_soil|harvest_prep",
  "urgency": "immediate|within_2_days|this_week|routine",
  "primary_issue": "one sentence",
  "recommendation": "2-3 sentences of specific advice",
  "nutrient_advisory": "fertilizer suggestion or null",
  "next_check_days": 3
}}"""

        response = client.chat.completions.create(
            model="llama-3.3-70b-versatile",
            messages=[
                {"role": "system",
                 "content": "You are AgriAI, an agricultural intelligence agent. "
                            "Return valid JSON only. No markdown, no explanation."},
                {"role": "user", "content": prompt}
            ],
            max_tokens=500,
            temperature=0.2
        )

        raw = response.choices[0].message.content.strip()
        clean = raw.replace("```json","").replace("```","").strip()
        result = json.loads(clean)

        db.execute(
            text("INSERT INTO alerts "
                 "(field_id,alert_type,severity,message) "
                 "VALUES (:fid,'agent_advisory',:sev,:msg)"),
            {"fid": field_id,
             "sev": "high" if result["urgency"]=="immediate" else "medium",
             "msg": f"[AgriAI] {result['recommendation']}"}
        )
        db.execute(
            text("INSERT INTO agent_memory "
                 "(field_id,memory_type,content,confidence_score) "
                 "VALUES (:fid,'soil_pattern',:c,1.0)"),
            {"fid": field_id,
             "c": f"action:{result['action']} issue:{result['primary_issue']}"}
        )
        db.commit()
        return result

    except json.JSONDecodeError as e:
        logger.error(f"JSON parse error: {e}")
        raise ValueError("Agent returned invalid format")
    except Exception as e:
        logger.error(f"Agent error: {e}")
        raise