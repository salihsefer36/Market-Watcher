import os
import asyncio
from datetime import datetime
from typing import Optional, List, Dict

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
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
if not firebase_admin._apps:  
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

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

cache: Dict[str, dict] = {}

# ----------------------------
# DB Model
# ----------------------------
class Alert(SQLModel, table=True):
    __table_args__ = {"extend_existing": True}
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
# METALS
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
            else:
                result[name] = None
        except:
            result[name] = None
    return result

# ----------------------------
# BIST Symbols & Prices
# ----------------------------
BIST100_SYMBOLS = [
    "ASELS.IS","GARAN.IS","THYAO.IS","AKBNK.IS","ISCTR.IS",
    "VESTL.IS","KOZAL.IS","BIMAS.IS","EREGL.IS","PETKM.IS",
    "SISE.IS","KRDMD.IS","YKBNK.IS","FROTO.IS","TOASO.IS",
    "ARCLK.IS","TUPRS.IS","ALARK.IS","MGROS.IS","PGSUS.IS",
    "ENJSA.IS","TCELL.IS","TTKOM.IS","AYGAZ.IS","CCOLA.IS",
    "ODAS.IS","HEKTS.IS","SAHOL.IS","KCHOL.IS","BRSAN.IS",
    "BAGFS.IS","TKFEN.IS","AKSA.IS","BRISA.IS","DOHOL.IS",
    "DOAS.IS","FENER.IS","KARSN.IS","NTHOL.IS","SNGYO.IS",
    "TAVHL.IS","TKNSA.IS","TRGYO.IS","TSPOR.IS","TTRAK.IS",
    "VAKBN.IS","YATAS.IS","ZOREN.IS","AKGRT.IS","BJKAS.IS",
    "NETAS.IS","KOZAA.IS","GOZDE.IS","ALCTL.IS","DMSAS.IS",
    "HALKB.IS","ISGYO.IS","ISDMR.IS","KONYA.IS","LOGO.IS",
    "MAVI.IS","MEPET.IS","OZKGY.IS","PRKME.IS","SASA.IS",
    "SEKUR.IS","SOKM.IS","TMSN.IS","ULKER.IS","YUNSA.IS",
    "ASUZU.IS","EKGYO.IS","KORDS.IS","AKCNS.IS"
][:100]

BIST_FALLBACK_NAMES = {
    "ASELS": "Aselsan",
    "GARAN": "Garanti Bankası",
    "THYAO": "Türk Hava Yolları",
    "AKBNK": "Akbank",
    "ISCTR": "İş Bankası",
    "VESTL": "Vestel",
    "KOZAL": "Koza Altın",
    "BIMAS": "BİM Mağazacılık",
    "EREGL": "Ereğli Demir Çelik",
    "PETKM": "Petkim",
    "SISE": "Şişecam",
    "KRDMD": "Kardemir",
    "YKBNK": "Yapı Kredi Bankası",
    "FROTO": "Ford Otosan",
    "TOASO": "Tofaş",
    "ARCLK": "Arçelik",
    "TUPRS": "Tüpraş",
    "ALARK": "Alarko Holding",
    "MGROS": "Migros",
    "PGSUS": "Pegasus",
    "ENJSA": "Enka İnşaat",
    "TCELL": "Türkcell",
    "TTKOM": "Türk Telekom",
    "AYGAZ": "Aygaz",
    "CCOLA": "Coca Cola İçecek",
    "ODAS": "Odaş Elektrik",
    "HEKTS": "Hektaş",
    "SAHOL": "Sabancı Holding",
    "KCHOL": "Koç Holding",
    "BRSAN": "Brisa",
    "BAGFS": "Bagfas",
    "TKFEN": "Tekfen Holding",
    "AKSA": "Aksa",
    "DOHOL": "Doğan Holding",
    "DOAS": "Doğuş Otomotiv",
    "FENER": "Fenerbahçe Futbol A.Ş.",
    "KARSN": "Karsan",
    "NTHOL": "Netaş",
    "SNGYO": "Sinpas GYO",
    "TAVHL": "TAV Havalimanları",
    "TKNSA": "Teknosa",
    "TRGYO": "Torunlar GYO",
    "TSPOR": "Trabzonspor A.Ş.",
    "TTRAK": "Tümosan Traktör",
    "VAKBN": "Vakıfbank",
    "YATAS": "Yataş",
    "ZOREN": "Zorlu Enerji",
    "AKGRT": "Ak Gıda",
    "BJKAS": "Beşiktaş Futbol A.Ş.",
    "NETAS": "Netaş",
    "KOZAA": "Koza Altın",
    "GOZDE": "Gözde Girişim",
    "ALCTL": "Alcatel-Lucent",
    "DMSAS": "Dimes",
    "HALKB": "Halkbank",
    "ISGYO": "İş GYO",
    "ISDMR": "İş Demir Çelik",
    "KONYA": "Konya Çimento",
    "LOGO": "Logo Yazılım",
    "MAVI": "Mavi Giyim",
    "MEPET": "Mepet",
    "OZKGY": "Özak GYO",
    "PRKME": "Park Elek. Madencilik",
    "SASA": "SASA Polyester",
    "SEKUR": "Sekuro",
    "SOKM": "Şok Marketler",
    "TMSN": "Temsan",
    "ULKER": "Ülker",
    "YUNSA": "Yünsa",
    "ASUZU": "Asuzu",
    "EKGYO": "Emlak Konut GYO",
    "KORDS": "Kordsa",
    "AKCNS": "Akçansa"
}

async def get_bist_symbols_with_name():
    results = []
    for symbol in BIST100_SYMBOLS:
        short_symbol = symbol.split(".")[0]
        name = None
        try:
            info = yf.Ticker(symbol).info
            name = info.get("shortName") or info.get("longName")
        except:
            pass
        if not name:
            name = BIST_FALLBACK_NAMES.get(short_symbol, short_symbol)
        results.append({"symbol": short_symbol, "name": name})
    return results

async def fetch_bist_price(symbol: str):
    try:
        ticker = yf.Ticker(symbol)
        data = ticker.history(period="1d")
        if not data.empty:
            price = data['Close'].iloc[-1]
            return {"symbol": symbol.split(".")[0], "price": round(price, 2)}
    except:
        pass
    return {"symbol": symbol.split(".")[0], "price": None}

async def get_bist_prices():
    tasks = [fetch_bist_price(s) for s in BIST100_SYMBOLS]
    results = await asyncio.gather(*tasks)
    return results

# ----------------------------
# NASDAQ Symbols & Prices
# ----------------------------
async def get_top_nasdaq_symbols(n=50):
    url = f"{FINNHUB_BASE}/stock/symbol"
    params = {"exchange": "US", "token": FINNHUB_API_KEY}
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.get(url, params=params)
        if r.status_code == 200:
            symbols = r.json()
            nasdaq_symbols = [s["symbol"] for s in symbols if s.get("mic")=="XNAS"]
            return nasdaq_symbols[:n]
    return []

async def get_nasdaq_symbols_with_name(n=50):
    results = []
    symbols = await get_top_nasdaq_symbols(n)
    async with httpx.AsyncClient(timeout=10) as client:
        for sym in symbols:
            name = None
            try:
                url = f"{FINNHUB_BASE}/stock/profile2"
                params = {"symbol": sym, "token": FINNHUB_API_KEY}
                r = await client.get(url, params=params)
                if r.status_code == 200:
                    data = r.json()
                    name = data.get("name")
            except:
                pass
            if not name:
                name = sym
            results.append({"symbol": sym, "name": name})
    return results

async def fetch_nasdaq_price(symbol: str):
    try:
        url = f"{FINNHUB_BASE}/quote"
        params = {"symbol": symbol, "token": FINNHUB_API_KEY}
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.get(url, params=params)
            if r.status_code == 200:
                data = r.json()
                price = data.get("c")
                return {"symbol": symbol, "price": round(price, 2) if price else None}
    except:
        pass
    return {"symbol": symbol, "price": None}

async def get_nasdaq_prices(n=50):
    symbols = await get_top_nasdaq_symbols(n)
    tasks = [fetch_nasdaq_price(s) for s in symbols]
    results = await asyncio.gather(*tasks)
    return results

# ----------------------------
# Crypto Prices
# ----------------------------
async def get_top_crypto_symbols(n=50):
    url = "https://api.binance.com/api/v3/ticker/price"
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.get(url)
        if r.status_code == 200:
            data = r.json()
            symbols = [d["symbol"] for d in data if d["symbol"].endswith("USDT")]
            return symbols[:n]
    return []

async def get_crypto_prices(n=50):
    symbols = await get_top_crypto_symbols(n)
    tasks = []
    for s in symbols:
        async def fetch(symbol=s):
            url = "https://api.binance.com/api/v3/ticker/price"
            async with httpx.AsyncClient(timeout=10) as client:
                r = await client.get(url, params={"symbol": symbol})
                if r.status_code == 200:
                    data = r.json()
                    return {"symbol": symbol[:-1], "price": round(float(data["price"]), 2)}
            return {"symbol": symbol[:-1], "price": None}
        tasks.append(fetch())
    results = await asyncio.gather(*tasks)
    return results

# ----------------------------
# Combined Prices Endpoint
# ----------------------------
@app.get("/prices")
async def get_all_prices():
    bist = await get_bist_prices()
    nasdaq = await get_nasdaq_prices()
    crypto = await get_crypto_prices()
    metals_dict = get_metals()
    metals = [{"market": "METALS", "symbol": k, "price": v} for k, v in metals_dict.items()]
    bist = [{"market": "BIST", **item} for item in bist]
    nasdaq = [{"market": "NASDAQ", **item} for item in nasdaq]
    crypto = [{"market": "CRYPTO", **item} for item in crypto]
    all_data = bist + nasdaq + crypto + metals
    return all_data

# ----------------------------
# Symbols with Name Endpoint
# ----------------------------
@app.get("/symbols_with_name")
async def symbols_with_name(market: str, n: int = 50):
    market = market.upper()
    if market == "BIST":
        return await get_bist_symbols_with_name()
    elif market == "NASDAQ":
        return await get_nasdaq_symbols_with_name(n)
    elif market == "CRYPTO":
        symbols = await get_top_crypto_symbols(n)
        return [{"symbol": s[:-1], "name": s[:-1]} for s in symbols]
    elif market == "METALS":
        metals_dict = get_metals()
        return [{"symbol": k, "name": k} for k in metals_dict.keys()]
    return []

# ----------------------------
# Run
# ----------------------------
if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)