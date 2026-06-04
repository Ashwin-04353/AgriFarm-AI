from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, DeclarativeBase
from sqlalchemy.pool import QueuePool
from urllib.parse import quote_plus
from loguru import logger
from .config import get_settings

settings = get_settings()

if settings.db_trusted_connection.lower() == "yes":
    conn_str = (
        f"DRIVER={{{settings.db_driver}}};"
        f"SERVER={settings.db_server};"
        f"DATABASE={settings.db_name};"
        f"Trusted_Connection=yes;"
        f"TrustServerCertificate=yes;"
    )
else:
    conn_str = (
        f"DRIVER={{{settings.db_driver}}};"
        f"SERVER={settings.db_server};"
        f"DATABASE={settings.db_name};"
        f"UID={settings.db_user};"
        f"PWD={settings.db_password};"
        f"TrustServerCertificate=yes;"
    )

DATABASE_URL = f"mssql+pyodbc:///?odbc_connect={quote_plus(conn_str)}"

engine = create_engine(
    DATABASE_URL,
    poolclass=QueuePool,
    pool_size=10, max_overflow=20,
    pool_pre_ping=True, pool_recycle=3600,
    echo=settings.app_env == "development"
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

class Base(DeclarativeBase):
    pass

def get_db():
    db = SessionLocal()
    try:
        yield db
    except Exception as e:
        logger.error(f"DB error: {e}")
        db.rollback()
        raise
    finally:
        db.close()

def call_procedure(db, name: str, params: dict = {}):
    param_str = ", ".join([f"@{k}=:{k}" for k in params])
    result = db.execute(text(f"EXEC {name} {param_str}"), params)
    try:
        rows = result.fetchall()
        return [dict(r._mapping) for r in rows]
    except Exception:
        return []