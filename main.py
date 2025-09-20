import os
import asyncio
from datetime import datetime
from typing import Optional, List, Dict

from fastapi import FastAPI, HTTPException
import httpx
from sqlmodel import SQLModel, Field, create_engine, Session, select
import yfinance as yf

import firebase_admin
from firebase_admin import credentials, messaging
from dotenv import load_dotenv

# ----------------------
# .env ve Firebase
# ----------------------
load_dotenv()
FINNHUB_API_KEY = os.getenv("FINNHUB_API_KEY")
FINNHUB_BASE = "https://finnhub.io/api/v1"

cred = credentials.Certificate("market-watcher-14891-firebase-adminsdk-fbsvc-66f5a6893b.json")
if not firebase_admin._apps:  # Firebase initialize hatasını önler
    firebase_admin.initialize_app(cred)

# ----------------------
# Config ve DB
# ----------------------
DB_URL = os.getenv("DATABASE_URL", "sqlite:///./alerts.db")
CHECK_INTERVAL = int(os.getenv("CHECK_INTERVAL", "30"))
NOTIFY_COOLDOWN = int(os.getenv("NOTIFY_COOLDOWN", "3600"))
CACHE_TTL = int(os.getenv("CACHE_TTL", "3600"))

engine = create_engine(DB_URL, echo=False)
app = FastAPI(title="MarketWatcher Backend")

# Cache
cache: Dict[str, dict] = {}

# ----------------------------
# DB Model
# ----------------------------
class Alert(SQLModel, table=True):
    __table_args__ = {"extend_existing": True}  # <- Bu satır eklendi
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
# Push Notification
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
                print(f"[Finnhub] {symbol} price: {data['c']}")
                return float(data["c"])
    return None

# ----------------------------
# Price Check Loop
# ----------------------------
async def price_check_loop():
    while True:
        try:
            with Session(engine) as session:
                alerts = session.exec(select(Alert).where(Alert.active == True)).all()
            for alert in alerts:
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

# ----------------------------
# METALLER (GRAM TL)
# ----------------------------
@app.get("/metals")
def get_metals():
    metals = {
        "Altın": "GC=F",
        "Gümüş": "SI=F",
        "Bakır": "HG=F"
    }
    try:
        usdtry = yf.Ticker("TRY=X").history(period="1d")['Close'].iloc[-1]
    except:
        usdtry = None

    result = {}
    for name, ticker_symbol in metals.items():
        try:
            price_usd = yf.Ticker(ticker_symbol).history(period="1d")['Close'].iloc[-1]
            if usdtry is not None:
                gram_price = (price_usd * usdtry) / 31.1035
                result[name] = round(gram_price, 2)
                print(f"[Metals] {name} price: {result[name]} TL/gram")
            else:
                result[name] = None
        except:
            result[name] = None
    return result

# ----------------------------
# BIST100 SYMBOLS & PRICES
# ----------------------------
BIST100_SYMBOLS = [
    "ASELS.IS","GARAN.IS","THYAO.IS","AKBNK.IS","ISCTR.IS",
    "VESTL.IS","KOZAL.IS","BIMAS.IS","EREGL.IS","PETKM.IS",
    # ... ilk 100 BIST sembolünü ekle
][:100]

async def fetch_bist_price(symbol: str):
    try:
        ticker = yf.Ticker(symbol)
        data = ticker.history(period="1d")
        if not data.empty:
            price = data['Close'].iloc[-1]
            print(f"[BIST] {symbol}: {price}")
            return {"symbol": symbol, "price": round(price, 2)}
    except Exception as e:
        print(f"[BIST] Error {symbol}: {e}")
    return {"symbol": symbol, "price": None}

@app.get("/bist_prices")
async def get_bist_prices():
    tasks = [fetch_bist_price(s) for s in BIST100_SYMBOLS]
    results = await asyncio.gather(*tasks)
    return results

# ----------------------------
# NASDAQ PRICES
# ----------------------------
async def fetch_nasdaq_price(symbol: str):
    try:
        url = f"{FINNHUB_BASE}/quote"
        params = {"symbol": symbol, "token": FINNHUB_API_KEY}
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.get(url, params=params)
            if r.status_code == 200:
                data = r.json()
                price = data.get("c", None)
                if price is not None:
                    print(f"[NASDAQ] {symbol}: {price}")
                    return {"symbol": symbol, "price": round(price, 2)}
    except Exception as e:
        print(f"[NASDAQ] Error {symbol}: {e}")
    return {"symbol": symbol, "price": None}

async def get_top_nasdaq_symbols(n=10):
    url = f"{FINNHUB_BASE}/stock/symbol"
    params = {"exchange": "US", "token": FINNHUB_API_KEY}
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.get(url, params=params)
        if r.status_code == 200:
            symbols = r.json()
            nasdaq_symbols = [s["symbol"] for s in symbols if s.get("mic")=="XNAS"]
            return nasdaq_symbols[:n]
    return []

@app.get("/nasdaq_prices")
async def get_nasdaq_prices(n: int = 10):
    symbols = await get_top_nasdaq_symbols(n)
    tasks = [fetch_nasdaq_price(s) for s in symbols]
    results = await asyncio.gather(*tasks)
    return results

# ----------------------------
# CRYPTO PRICES
# ----------------------------
async def fetch_crypto_price(symbol: str):
    try:
        url = "https://api.binance.com/api/v3/ticker/price"
        params = {"symbol": symbol}
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.get(url, params=params)
            if r.status_code == 200:
                data = r.json()
                print(f"[CRYPTO] {symbol}: {data['price']}")
                return {"symbol": symbol, "price": round(float(data["price"]), 2)}
    except Exception as e:
        print(f"[CRYPTO] Error {symbol}: {e}")
    return {"symbol": symbol, "price": None}

async def get_top_crypto_symbols(n=10):
    url = "https://api.binance.com/api/v3/ticker/price"
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.get(url)
        if r.status_code == 200:
            data = r.json()
            symbols = [d["symbol"] for d in data if d["symbol"].endswith("USDT")]
            return symbols[:n]
    return []

@app.get("/crypto_prices")
async def get_crypto_prices(n: int = 10):
    symbols = await get_top_crypto_symbols(n)
    tasks = [fetch_crypto_price(s) for s in symbols]
    results = await asyncio.gather(*tasks)
    return results

# ----------------------------
# Eğer doğrudan main.py ile çalıştırılırsa
# ----------------------------
if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)