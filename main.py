import os
import asyncio
from datetime import datetime
from typing import Optional, List, Dict

from fastapi import FastAPI, HTTPException
import httpx
from sqlmodel import SQLModel, Field, create_engine, Session, select

import firebase_admin
from firebase_admin import credentials, messaging
from dotenv import load_dotenv

# .env dosyasını yükle
load_dotenv()

# Firebase
cred = credentials.Certificate("market-watcher-14891-firebase-adminsdk-fbsvc-66f5a6893b.json")
firebase_admin.initialize_app(cred)

# Config
DB_URL = os.getenv("DATABASE_URL", "sqlite:///./alerts.db")
CHECK_INTERVAL = int(os.getenv("CHECK_INTERVAL", "30"))        # saniye
NOTIFY_COOLDOWN = int(os.getenv("NOTIFY_COOLDOWN", "3600"))    # saniye
CACHE_TTL = int(os.getenv("CACHE_TTL", "3600"))                # saniye
FINNHUB_API_KEY = os.getenv("FINNHUB_API_KEY")   # ✅ Artık .env'den alıyor
FINNHUB_BASE = "https://finnhub.io/api/v1"

engine = create_engine(DB_URL, echo=False)
app = FastAPI(title="MarketWatcher Backend")

# Cache
cache: Dict[str, dict] = {}

# ----------------------------
# DB Model
# ----------------------------
class Alert(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    symbol: str = "CUSTOM"
    threshold: float = 0
    direction: str = "above"
    message: Optional[str] = None
    active: bool = True
    last_notified_at: Optional[datetime] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
    user_token: Optional[str] = None

class AlertCreate(SQLModel):
    symbol: str
    threshold: float
    direction: Optional[str] = "above"
    user_token: Optional[str] = None
    message: Optional[str] = None

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

# ----------------------------
# Alerts CRUD
# ----------------------------
@app.post("/alerts", response_model=Alert)
def create_alert(alert_in: AlertCreate):
    direction = alert_in.direction.lower() if alert_in.direction else "above"
    if direction not in ["above", "below"]:
        raise HTTPException(status_code=400, detail="Direction must be 'above' or 'below'")
    alert = Alert(
        symbol=alert_in.symbol.upper() if alert_in.symbol else "CUSTOM",
        threshold=alert_in.threshold,
        direction=direction,
        message=alert_in.message,
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

# ----------------------------
# Finnhub Price Fetch
# ----------------------------
async def fetch_price(symbol: str):
    url = f"{FINNHUB_BASE}/quote"
    params = {"symbol": symbol, "token": FINNHUB_API_KEY}
    async with httpx.AsyncClient(timeout=10) as client:
        r = await client.get(url, params=params)
        if r.status_code == 200:
            data = r.json()
            if "c" in data:
                return float(data["c"])
    return None

@app.get("/price/{symbol}")
async def get_price_endpoint(symbol: str):
    price = await fetch_price(symbol.upper())
    if price is None:
        raise HTTPException(status_code=404, detail="Price not found")
    return {"symbol": symbol.upper(), "price": price}

# ----------------------------
# Finnhub Symbol Lists
# ----------------------------
async def fetch_symbols(exchange: str):
    url = f"{FINNHUB_BASE}/stock/symbol"
    params = {"exchange": exchange, "token": FINNHUB_API_KEY}
    async with httpx.AsyncClient(timeout=20) as client:
        r = await client.get(url, params=params)
        if r.status_code == 200:
            return r.json()
    return []

@app.get("/bist_companies")
async def get_bist_companies():
    now = datetime.utcnow()
    if "bist" in cache and (now - cache["bist"]["time"]).total_seconds() < CACHE_TTL:
        return cache["bist"]["data"]

    symbols = await fetch_symbols("IS")   # BIST (Istanbul)
    data = [{"symbol": s["symbol"], "name": s.get("description", s["symbol"])} for s in symbols]
    cache["bist"] = {"data": data, "time": now}
    return data

@app.get("/nasdaq_companies")
async def get_nasdaq_companies():
    now = datetime.utcnow()
    if "nasdaq" in cache and (now - cache["nasdaq"]["time"]).total_seconds() < CACHE_TTL:
        return cache["nasdaq"]["data"]

    symbols = await fetch_symbols("US")
    nasdaq = [s for s in symbols if s.get("mic") == "XNAS"][:50]  # İlk 50
    data = [{"symbol": s["symbol"], "name": s.get("description", s["symbol"])} for s in nasdaq]
    cache["nasdaq"] = {"data": data, "time": now}
    return data

@app.get("/crypto_list")
async def get_crypto_list():
    now = datetime.utcnow()
    if "crypto" in cache and (now - cache["crypto"]["time"]).total_seconds() < CACHE_TTL:
        return cache["crypto"]["data"]

    url = f"{FINNHUB_BASE}/crypto/symbol"
    params = {"exchange": "BINANCE", "token": FINNHUB_API_KEY}
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.get(url, params=params)
        data = []
        if r.status_code == 200:
            symbols = r.json()
            data = [{"symbol": s["symbol"], "name": s["displaySymbol"]} for s in symbols]
    cache["crypto"] = {"data": data, "time": now}
    return data

# ----------------------------
# Notifications
# ----------------------------
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

async def price_check_loop():
    while True:
        try:
            with Session(engine) as session:
                alerts = session.exec(select(Alert).where(Alert.active == True)).all()
            for alert in alerts:
                # Eğer mesaj varsa direkt gönder
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
                else:
                    price = await fetch_price(alert.symbol)
                    if price is not None:
                        trigger = (alert.direction=="above" and price>=alert.threshold) or \
                                  (alert.direction=="below" and price<=alert.threshold)
                        if trigger and alert.user_token:
                            send_push_notification(
                                token=alert.user_token,
                                title=f"{alert.symbol} Alarm",
                                body=f"Fiyat {price} {alert.direction} {alert.threshold}"
                            )
                            alert.last_notified_at = datetime.utcnow()
                            with Session(engine) as session:
                                session.add(alert)
                                session.commit()
        except Exception as e:
            print("Error in price_check_loop:", e)
        await asyncio.sleep(CHECK_INTERVAL)