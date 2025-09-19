# MarketWatcher - Backend (main.py)
# ---------------------------------
# Basit MVP backend. Özeti:
# - FastAPI ile REST API
# - SQLite (SQLModel) ile Alert tablosu
# - Binance + Yahoo fallback ile fiyat çekme
# - Arka planda çalışan döngü ile aktif alarm kontrolleri (console'a bildirim basılıyor)
#
# Gereksinimler:
# pip install fastapi uvicorn sqlmodel httpx
#
# Çalıştırma:
# export CHECK_INTERVAL=30      # (opsiyonel) kontrol aralığı saniye
# export NOTIFY_COOLDOWN=3600   # (opsiyonel) aynı alarm için cooldown saniye
# uvicorn main:app --reload
#
# Test örnekleri:
# GET price:   curl http://127.0.0.1:8000/price/BTCUSDT
# POST alert:  curl -X POST "http://127.0.0.1:8000/alerts" -H "Content-Type: application/json" -d '{"symbol":"BTCUSDT","threshold":70000,"direction":"above"}'
# GET alerts:  curl http://127.0.0.1:8000/alerts

import asyncio
import os
from datetime import datetime
from typing import Optional, List

from fastapi import FastAPI, HTTPException
import httpx
from sqlmodel import SQLModel, Field, create_engine, Session, select

import firebase_admin
from firebase_admin import credentials, messaging

# Firebase initialization
cred = credentials.Certificate("market-watcher-14891-firebase-adminsdk-fbsvc-66f5a6893b.json")
firebase_admin.initialize_app(cred)

# Config
DB_URL = os.getenv("DATABASE_URL", "sqlite:///./alerts.db")
CHECK_INTERVAL = int(os.getenv("CHECK_INTERVAL", "30"))        # saniye
NOTIFY_COOLDOWN = int(os.getenv("NOTIFY_COOLDOWN", "3600"))    # saniye

# DB setup
engine = create_engine(DB_URL, echo=False)

class Alert(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    symbol: str = "CUSTOM"  # Opsiyonel sembol, Flutter verisi için CUSTOM
    threshold: float = 0     # Opsiyonel, fiyat alarmı için kullanılabilir
    direction: str = "above"
    message: Optional[str] = None  # Flutter’dan gelen özgün veri
    active: bool = True
    last_notified_at: Optional[datetime] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
    user_token: Optional[str] = None # FCM token

class AlertCreate(SQLModel):
    symbol: str
    threshold: float
    direction: Optional[str] = "above"
    user_token: Optional[str] = None  # FCM token

app = FastAPI(title="MarketWatcher Backend")

def create_db_and_tables():
    SQLModel.metadata.create_all(engine)

@app.on_event("startup")
async def on_startup():
    create_db_and_tables()
    app.state._task = asyncio.create_task(price_check_loop())

@app.on_event("shutdown")
async def on_shutdown():
    task = getattr(app.state, "_task", None)
    if task:
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass

@app.post("/alerts", response_model=Alert)
def create_alert(alert_in: AlertCreate):
    direction = alert_in.direction.lower() if alert_in.direction else "above"
    if direction not in ["above", "below"]:
        raise HTTPException(status_code=400, detail="Direction must be 'above' or 'below'")
    
    alert = Alert(
        symbol=alert_in.symbol.upper() if alert_in.symbol else "CUSTOM",
        threshold=alert_in.threshold if alert_in.threshold else 0,
        direction=direction,
        message=getattr(alert_in, "message", None),
        user_token=alert_in.user_token
    )
    
    with Session(engine) as session:
        session.add(alert)
        session.commit()
        session.refresh(alert)
    return alert

@app.get("/alerts", response_model=List[Alert])
def list_alerts():
    with Session(engine) as session:
        alerts = session.exec(select(Alert)).all()
    return alerts

@app.delete("/alerts/{alert_id}")
def delete_alert(alert_id: int):
    with Session(engine) as session:
        alert = session.get(Alert, alert_id)
        if not alert:
            raise HTTPException(status_code=404, detail="Alert not found")
        session.delete(alert)
        session.commit()
    return {"ok": True}

def send_push_notification(token: str, title: str, body: str):
    try:
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            token=token
        )
        response = messaging.send(message)
        print(f"Push sent: {response}")
    except Exception as e:
        print("FCM send error:", e)

@app.get("/price/{symbol}")
async def get_price_endpoint(symbol: str):
    price = await fetch_price(symbol.upper())
    if price is None:
        raise HTTPException(status_code=404, detail="Price not found")
    return {"symbol": symbol.upper(), "price": price}

async def fetch_price(symbol: str) -> Optional[float]:
    """First Binance (crypto pairs), if not Yahoo Finance fallback"""
    async with httpx.AsyncClient(timeout=10) as client:
        # Binance
        try:
            r = await client.get("https://api.binance.com/api/v3/ticker/price", params={"symbol": symbol})
            if r.status_code == 200:
                data = r.json()
                if "price" in data:
                    return float(data["price"])
        except Exception:
            pass
        # Yahoo Finance fallback
        try:
            r = await client.get("https://query1.finance.yahoo.com/v7/finance/quote", params={"symbols": symbol})
            if r.status_code == 200:
                data = r.json()
                result = data.get("quoteResponse", {}).get("result", [])
                if result and "regularMarketPrice" in result[0] and result[0]["regularMarketPrice"] is not None:
                    return float(result[0]["regularMarketPrice"])
        except Exception:
            pass
    return None

async def price_check_loop():
    while True:
        try:
            with Session(engine) as session:
                alerts = session.exec(select(Alert).where(Alert.active == True)).all()
            for alert in alerts:
                # Flutter'dan gelen mesaj varsa push anında
                if alert.message and alert.user_token:
                    now = datetime.utcnow()
                    if not alert.last_notified_at or (now - alert.last_notified_at).total_seconds() > NOTIFY_COOLDOWN:
                        send_push_notification(
                            token=alert.user_token,
                            title="Yeni veri eklendi!",
                            body=alert.message
                        )
                        alert.last_notified_at = now
                        with Session(engine) as session:
                            session.add(alert)
                            session.commit()
                # Fiyat alarmı varsa mevcut logic çalışır (symbol/threshold)
        except Exception as e:
            print("Error in price_check_loop:", e)
        await asyncio.sleep(CHECK_INTERVAL)