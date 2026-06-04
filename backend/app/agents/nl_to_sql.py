from groq import Groq
import re
from loguru import logger
from sqlalchemy.orm import Session
from sqlalchemy import text
from ..config import get_settings

settings = get_settings()
client = Groq(api_key=settings.groq_api_key)

# Exact schema description injected into every prompt
SCHEMA_CONTEXT = """
DATABASE: agri_ai (SQL Server)

TABLES AND COLUMNS:
- users(id, full_name, email, role, is_active, created_at)
- farms(id, user_id, name, region, country)
- fields(id, farm_id, name, area_hectares, latitude, longitude, soil_type)
- crops(id, name, variety, season, optimal_ph_min, optimal_ph_max,
        optimal_temp_min, optimal_temp_max, water_req_mm, growth_days)
- field_crops(id, field_id, crop_id, sown_date, harvest_date, stage, actual_yield)
- soil_readings(id, field_id, ph, moisture_pct, nitrogen_ppm, phosphorus_ppm,
                potassium_ppm, temperature_c, recorded_at, source)
- alerts(id, field_id, alert_type, severity, message, is_resolved, created_at)
- agent_observations(id, field_id, stress_index, observation, observed_at)
- daily_summaries(id, field_id, summary_date, avg_moisture, avg_ph,
                  avg_temp, stress_score, alert_count)

CRITICAL RULES — NEVER VIOLATE:
1. soil_type column EXISTS ONLY in the fields table (f.soil_type).
2. crops table has NO soil_type column. NEVER write c.soil_type or crops.soil_type.
3. soil_readings table has NO soil_type column. NEVER write sr.soil_type.
4. To filter by soil type: JOIN fields f ON f.id = fc.field_id AND f.soil_type = '...'
5. NEVER use semicolons at end of SQL.
6. NEVER use SELECT *. Always name columns explicitly.
7. Generate SELECT queries only. No INSERT/UPDATE/DELETE/DROP/EXEC.
8. When recommending crops or joining field_crops with crops,
   ALWAYS use SELECT DISTINCT to avoid duplicate crop results.
9. If a query returns crop recommendations,
   NEVER return duplicate crop IDs.
10. If using SELECT DISTINCT and ORDER BY,
    the ORDER BY column MUST also be included in the SELECT list.

CORRECT EXAMPLE for soil-type filtering:
  SELECT DISTINCT TOP 10
    c.id,
    c.name,
    c.variety,
    c.growth_days
FROM crops c
JOIN field_crops fc ON fc.crop_id = c.id
JOIN fields f ON f.id = fc.field_id
WHERE f.soil_type = 'loam'
ORDER BY c.growth_days ASC

VIEWS:
- vw_dashboard_overview  — field health status with latest readings
- vw_field_trends        — rolling averages + LAG comparisons
- vw_anomaly_scores      — Z-score based anomaly detection
- vw_regional_benchmark  — region-level crop averages
- vw_alerts_feed         — alerts with field and farm names

EXAMPLE — active alerts:
  SELECT a.id, a.alert_type, a.severity, a.message, a.created_at,
         f.name AS field_name
  FROM alerts a
  JOIN fields f ON f.id = a.field_id
  WHERE a.is_resolved = 0
  ORDER BY a.created_at DESC
"""

# Block any dangerous keywords — security guard
BLOCKED_KEYWORDS = [
    "insert","update","delete","drop","truncate","alter","create",
    "exec","execute","xp_","sp_","grant","revoke","shutdown",
    "--","/*","*/","';","union select"
]

def is_safe_sql(sql: str) -> bool:
    lowered = sql.lower()
    for kw in BLOCKED_KEYWORDS:
        if kw in lowered:
            return False
    if not lowered.strip().startswith("select"):
        return False
    return True

def natural_language_to_sql(
    db: Session,
    user_id: int,
    natural_query: str
) -> dict:
    if len(natural_query.strip()) < 5:
        raise ValueError("Query too short")

    prompt = f"""{SCHEMA_CONTEXT}

Convert this natural language question to a T-SQL SELECT query:
"{natural_query}"

Rules:
- Return ONLY the SQL query
- No explanation, no markdown, no backticks
- Must be a SELECT statement only
- Use TOP 100 to limit results
- Use proper T-SQL syntax for SQL Server
- Never use = (SELECT ...)
- If multiple rows are possible use IN (SELECT ...)"""

    try:
        response = client.chat.completions.create(
            model="llama-3.3-70b-versatile",
            messages=[
                {"role": "system",
                 "content": "You are a T-SQL expert. Convert natural language "
                            "to SQL Server SELECT queries only. "
                            "Return only the raw SQL, nothing else."},
                {"role": "user", "content": prompt}
            ],
            max_tokens=400,
            temperature=0.1   # very low — deterministic SQL
        )

        generated_sql = response.choices[0].message.content.strip()
        generated_sql = re.sub(r"```sql|```","", generated_sql).strip()
        generated_sql = generated_sql.rstrip(";")  # strip trailing semicolon
        

        # Security check
        if not is_safe_sql(generated_sql):
            db.execute(
                text("INSERT INTO nl_query_log "
                     "(user_id,natural_query,generated_sql,executed,error_message) "
                     "VALUES (:uid,:nq,:sql,0,:err)"),
                {"uid": user_id, "nq": natural_query,
                 "sql": generated_sql,
                 "err": "Blocked: unsafe SQL detected"}
            )
            db.commit()
            raise ValueError("Generated SQL failed safety check")

        # Execute safely
        result = db.execute(text(generated_sql))
        rows = result.fetchall()
        columns = list(result.keys())
        data = [dict(zip(columns, row)) for row in rows]

        # Log successful query
        db.execute(
            text("INSERT INTO nl_query_log "
                 "(user_id,natural_query,generated_sql,executed,result_rows) "
                 "VALUES (:uid,:nq,:sql,1,:rows)"),
            {"uid": user_id, "nq": natural_query,
             "sql": generated_sql, "rows": len(data)}
        )
        db.commit()

        return {
            "natural_query": natural_query,
            "generated_sql": generated_sql,
            "columns": columns,
            "rows": data,
            "total_rows": len(data)
        }

    except ValueError:
        raise
    except Exception as e:
        logger.error(f"NL→SQL error: {e}")
        db.execute(
            text("INSERT INTO nl_query_log "
                 "(user_id,natural_query,executed,error_message) "
                 "VALUES (:uid,:nq,0,:err)"),
            {"uid": user_id, "nq": natural_query, "err": str(e)}
        )
        db.commit()
        raise ValueError(f"Query failed: {str(e)}")