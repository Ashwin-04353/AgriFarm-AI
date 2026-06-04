from fastapi import APIRouter, Depends, HTTPException, Response, Cookie
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from sqlalchemy import text
from datetime import datetime, timedelta, timezone
import hashlib
from pydantic import BaseModel, EmailStr
from ..database import get_db
from ..config import get_settings
from .utils import (hash_password, verify_password,
                    create_access_token, create_refresh_token,
                    get_current_user)

settings = get_settings()
router = APIRouter(prefix="/auth", tags=["auth"])

class RegisterIn(BaseModel):
    full_name: str
    email: EmailStr
    password: str
    role: str = "farmer"

class LoginIn(BaseModel):
    email: EmailStr
    password: str

@router.post("/register", status_code=201)
def register(data: RegisterIn, db: Session = Depends(get_db)):
    if len(data.password) < 8:
        raise HTTPException(422, "Password must be at least 8 characters")
    if db.execute(text("SELECT id FROM users WHERE email=:e"),
                  {"e": data.email}).fetchone():
        raise HTTPException(409, "Email already registered")
    db.execute(
        text("INSERT INTO users (full_name,email,password_hash,role) "
             "VALUES (:n,:e,:p,:r)"),
        {"n": data.full_name, "e": data.email,
         "p": hash_password(data.password), "r": data.role}
    )
    db.commit()
    return {"message": "Registration successful"}

@router.post("/login")
def login(
    form_data: OAuth2PasswordRequestForm = Depends(),
    response: Response = None,
    db: Session = Depends(get_db)
):
    user = db.execute(
        text("SELECT id,uuid,password_hash,role,is_active "
             "FROM users WHERE email=:e"), {"e": form_data.username}
    ).fetchone()
    if not user or not verify_password(form_data.password, user.password_hash):
        raise HTTPException(401, "Invalid credentials")
    if not user.is_active:
        raise HTTPException(403, "Account inactive")

    access = create_access_token({"sub": str(user.uuid), "role": user.role})
    raw, hashed = create_refresh_token()
    exp = datetime.now(timezone.utc) + timedelta(
        days=settings.refresh_token_expire_days)

    db.execute(
        text("INSERT INTO refresh_tokens (user_id,token_hash,expires_at) "
             "VALUES (:uid,:th,:exp)"),
        {"uid": user.id, "th": hashed, "exp": exp}
    )
    db.execute(text("UPDATE users SET last_login=SYSDATETIME() WHERE id=:id"),
               {"id": user.id})
    db.commit()

    response.set_cookie(
        key="refresh_token", value=raw, httponly=True,
        secure=settings.app_env == "production",
        samesite="lax",
        max_age=settings.refresh_token_expire_days * 86400
    )
    return {"access_token": access, "token_type": "bearer", "role": user.role}

@router.post("/logout")
def logout(response: Response,
           refresh_token: str = Cookie(None),
           db: Session = Depends(get_db)):
    if refresh_token:
        h = hashlib.sha256(refresh_token.encode()).hexdigest()
        db.execute(
            text("UPDATE refresh_tokens SET revoked=1 WHERE token_hash=:th"),
            {"th": h})
        db.commit()
    response.delete_cookie("refresh_token")
    return {"message": "Logged out"}

@router.get("/me")
def me(user=Depends(get_current_user)):
    return user