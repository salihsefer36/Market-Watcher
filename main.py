import os
import asyncio
from datetime import datetime
from typing import Optional, List, Dict

from fastapi import FastAPI, HTTPException, Query, Path
from fastapi.middleware.cors import CORSMiddleware
import httpx
from sqlmodel import SQLModel, Field, create_engine, Session, select, delete
import yfinance as yf

import firebase_admin
from firebase_admin import credentials, messaging
from dotenv import load_dotenv
import json

# ----------------------
# .env ve Firebase
# ----------------------
load_dotenv()
FINNHUB_API_KEY = os.getenv("FINNHUB_API_KEY")
FINNHUB_BASE = "https://finnhub.io/api/v1"

# Firebase initialization using FIREBASE_JSON
firebase_json_str = os.getenv("FIREBASE_JSON")
if not firebase_json_str:
    raise ValueError("FIREBASE_JSON ortam değişkeni bulunamadı!")

cred_dict = json.loads(firebase_json_str)
cred_dict["private_key"] = cred_dict["private_key"].replace("\\n", "\n").replace("\r", "")

if not firebase_admin._apps:
    cred = credentials.Certificate(cred_dict)
    firebase_admin.initialize_app(cred)

# ----------------------
# Config ve DB
# ----------------------

DB_URL = os.getenv("DATABASE_URL")
if not DB_URL:
    raise RuntimeError("DATABASE_URL bulunamadı! Railway'de Postgres URL tanımlı mı kontrol et.")

if DB_URL.startswith("postgres://"):
    DB_URL = DB_URL.replace("postgres://", "postgresql://", 1)

CHECK_INTERVAL = int(os.getenv("CHECK_INTERVAL", "60")) # API limitlerini zorlamamak için 60 saniyeye çekmek mantıklı olabilir

engine = create_engine(DB_URL, echo=False)
app = FastAPI(title="MarketWatcher Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ----------------------------
# DB Model (GÜNCELLENDİ)
# ----------------------------
class Alert(SQLModel, table=True):
    __table_args__ = {"extend_existing": True}
    id: Optional[int] = Field(default=None, primary_key=True)
    market: str
    symbol: str
    percentage: float
    base_price: float
    upper_limit: float
    lower_limit: float
    created_at: datetime = Field(default_factory=datetime.utcnow)
    user_token: Optional[str] = None  # FCM Cihaz Token'ı
    user_uid: Optional[str] = Field(default=None, index=True) # Firebase Auth UID'si

class AlertCreate(SQLModel):
    market: str
    symbol: str
    percentage: float
    user_token: Optional[str] = None  # FCM Cihaz Token'ı
    user_uid: Optional[str] = None    # Firebase Auth UID'si

class UserSettings(SQLModel):
    notifications_enabled: bool
    language_code: str = Field(default="en") # Default language is english (en)

class User(UserSettings, table=True):
    uid: str = Field(primary_key=True)

# ----------------------------
# DB ve tablo oluşturma
# ----------------------------
def create_db_and_tables():
    SQLModel.metadata.create_all(engine)

# ----------------------------
# CRUD for Alerts and Settings
# ----------------------------
@app.post("/alerts", response_model=Alert)
async def create_alert(alert_in: AlertCreate):
    try:
        current_price = await fetch_price(alert_in.symbol)
        if current_price is None:
            raise HTTPException(status_code=400, detail=f"Price not found for symbol: {alert_in.symbol}")

        perc = float(alert_in.percentage)
        upper = current_price * (1 + perc / 100)
        lower = current_price * (1 - perc / 100)

        alert = Alert(
            market=alert_in.market,
            symbol=alert_in.symbol.upper(),
            percentage=perc,
            base_price=current_price,
            upper_limit=upper,
            lower_limit=lower,
            user_token=alert_in.user_token,
            user_uid=alert_in.user_uid
        )

        with Session(engine) as session:
            session.add(alert)
            session.commit()
            session.refresh(alert)
        return alert
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/alerts", response_model=List[Alert])
def list_alerts(user_uid: Optional[str] = Query(None)):
      with Session(engine) as session:
        query = select(Alert)
        if user_uid:
            query = query.where(Alert.user_uid == user_uid)
        alerts = session.exec(query).all()
      return alerts

@app.delete("/alerts/{alert_id}")
def delete_alert(alert_id: int, user_uid: str = Query(..., description="The UID of the user deleting the alert")):
    with Session(engine) as session:
        alert = session.get(Alert, alert_id)
        if not alert or alert.user_uid != user_uid:
            raise HTTPException(status_code=404, detail="Alert not found or permission denied")
        session.delete(alert)
        session.commit()
    return {"ok": True}

@app.put("/alerts/{alert_id}", response_model=Alert)
async def edit_alert(alert_id: int, alert_in: AlertCreate): 
    try:
        with Session(engine) as session:
            alert = session.get(Alert, alert_id)
            
            if not alert or alert.user_uid != alert_in.user_uid:
                raise HTTPException(status_code=404, detail="Alert not found or permission denied")

            alert.market = alert_in.market
            alert.symbol = alert_in.symbol.upper()
            alert.percentage = float(alert_in.percentage)
            alert.user_token = alert_in.user_token
            alert.user_uid = alert_in.user_uid

            current_price = await fetch_price(alert.symbol)
            if current_price is not None:
                alert.base_price = current_price
                alert.upper_limit = current_price * (1 + alert.percentage / 100)
                alert.lower_limit = current_price * (1 - alert.percentage / 100)

            session.add(alert)
            session.commit()
            session.refresh(alert)
            return alert
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))
    
@app.get("/user/settings/{user_uid}", response_model=UserSettings)
def get_user_settings(user_uid: str):
    with Session(engine) as session:
        user = session.get(User, user_uid)
        if not user:
            # If user has no settings saved yet, return default values
            return UserSettings(notifications_enabled=True)
        return user

@app.post("/user/settings/{user_uid}", response_model=User)
def update_user_settings(user_uid: str, settings: UserSettings):
    with Session(engine) as session:
        user = session.get(User, user_uid)
        if not user:
            # If user doesn't exist, create them with ALL settings
            user = User(
                uid=user_uid, 
                notifications_enabled=settings.notifications_enabled,
                language_code=settings.language_code 
            )
            session.add(user)
        else:
            # If user exists, update their settings
            user.notifications_enabled = settings.notifications_enabled
            user.language_code = settings.language_code
            session.add(user)
        
        session.commit()
        session.refresh(user)
        return user

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
        print(f"Push notification sent successfully: {response}")
    except Exception as e:
        print(f"Error sending FCM notification: {e}")

# ----------------------------
# Price Fetch
# ----------------------------

async def fetch_price(symbol: str):
    symbol = symbol.upper()
    metals_yf = {"ALTIN": "GC=F", "GÜMÜŞ": "SI=F", "BAKIR": "HG=F"}
    if symbol in metals_yf:
        try:
            loop = asyncio.get_event_loop()
            usdtry = await loop.run_in_executor(None, lambda: yf.Ticker("TRY=X").history(period="1d")['Close'].iloc[-1])
            price_usd = await loop.run_in_executor(None, lambda: yf.Ticker(metals_yf[symbol]).history(period="1d")['Close'].iloc[-1])
            return round((price_usd * usdtry) / 31.1035, 2)
        except:
            return None
        
    if symbol.endswith(".IS") or symbol in BIST_FALLBACK_NAMES:
        try:
            yf_symbol = symbol if symbol.endswith(".IS") else f"{symbol}.IS"
            loop = asyncio.get_event_loop()
            price = await loop.run_in_executor(None, lambda: yf.Ticker(yf_symbol).history(period="1d")['Close'].iloc[-1])
            return round(float(price), 2)
        except:
            return None
    async with httpx.AsyncClient(timeout=10) as client:
        if symbol in POPULAR_NASDAQ:
            try:
                r = await client.get(f"{FINNHUB_BASE}/quote", params={"symbol": symbol, "token": FINNHUB_API_KEY})
                if r.status_code == 200:
                    price = r.json().get("c")
                    if price:
                        return round(float(price), 2)
            except:
                return None

        if symbol.endswith("USDT"):
            try:
                r = await client.get("https://api.binance.com/api/v3/ticker/price", params={"symbol": symbol})
                if r.status_code == 200:
                    price = float(r.json().get("price", 0))
                    if price > 0:
                        return round(price, 2)
            except Exception as e:
                print(f"Crypto fetch error for {symbol}: {e}")
                return None

        return None
# ----------------------------
# --- YENİ ÇEVİRİ SÖZLÜĞÜ ---
# Bu yapıyı dosyanın üst kısımlarına veya price_check_loop'un hemen öncesine ekleyebilirsiniz.
NOTIFICATION_TEMPLATES = {
    "en": {
        "title": "{symbol} Price Alert",
        "body": "The price of {symbol} has {direction} by {percentage}% and is now {price:.2f}.",
        "increased": "increased",
        "decreased": "decreased"
    },
    "tr": {
        "title": "{symbol} Fiyat Alarmı",
        "body": "{symbol} fiyatı %{percentage} {direction} ve {price:.2f} oldu.",
        "increased": "yükseldi",
        "decreased": "düştü"
    },
    "de": {
        "title": "{symbol} Preisalarm",
        "body": "Der Preis von {symbol} ist um {percentage}% {direction} und beträgt jetzt {price:.2f}.",
        "increased": "gestiegen",
        "decreased": "gefallen"
    },
    "fr": {
        "title": "Alerte de Prix {symbol}",
        "body": "Le prix de {symbol} a {direction} de {percentage}% et est maintenant de {price:.2f}.",
        "increased": "augmenté",
        "decreased": "baissé"
    },
    "es": {
        "title": "Alerta de Precio de {symbol}",
        "body": "El precio de {symbol} ha {direction} un {percentage}% y ahora es de {price:.2f}.",
        "increased": "subido",
        "decreased": "bajado"
    },
    "it": {
        "title": "Allarme Prezzo {symbol}",
        "body": "Il prezzo di {symbol} è {direction} del {percentage}% ed è ora di {price:.2f}.",
        "increased": "aumentato",
        "decreased": "diminuito"
    },
    "ru": {
        "title": "Ценовое Оповещение: {symbol}",
        "body": "Цена на {symbol} {direction} на {percentage}% и теперь составляет {price:.2f}.",
        "increased": "выросла",
        "decreased": "упала"
    },
    "zh": {
        "title": "{symbol} 价格提醒",
        "body": "{symbol} 的价格已{direction}{percentage}%，现为 {price:.2f}。",
        "increased": "上涨",
        "decreased": "下跌"
    },
    "hi": {
        "title": "{symbol} मूल्य चेतावनी",
        "body": "{symbol} की कीमत {percentage}% {direction} है और अब {price:.2f} है।",
        "increased": "बढ़ गई",
        "decreased": "घट गई"
    },
    "ja": {
        "title": "{symbol} 価格アラート",
        "body": "{symbol}の価格が{percentage}%{direction}し、現在{price:.2f}です。",
        "increased": "上昇",
        "decreased": "下落"
    },
    "ar": {
        "title": "تنبيه سعر {symbol}",
        "body": "لقد {direction} سعر {symbol} بنسبة {percentage}% وهو الآن {price:.2f}.",
        "increased": "ارتفع",
        "decreased": "انخفض"
    }
}
# ----------------------------
# Price Check Loop 
# ----------------------------
async def price_check_loop():
    while True:
        try:
            with Session(engine) as session:
                all_alerts = session.exec(select(Alert)).all()
                all_users = session.exec(select(User)).all()
                user_preferences = {user.uid: user for user in all_users}

            if not all_alerts:
                await asyncio.sleep(CHECK_INTERVAL)
                continue

            unique_symbols = {alert.symbol for alert in all_alerts}
            
            prices = {}
            for symbol in unique_symbols:
                price = await fetch_price(symbol)
                if price is not None:
                    prices[symbol] = price
            
            alerts_to_delete_ids = []
            for alert in all_alerts:
                user_settings = user_preferences.get(alert.user_uid)
                notifications_on = user_settings.notifications_enabled if user_settings else True
                
                # 1. Kullanıcının dilini al, eğer ayarı yoksa veya dil desteklenmiyorsa varsayılan olarak 'en' kullan.
                lang_code = user_settings.language_code if user_settings and user_settings.language_code in NOTIFICATION_TEMPLATES else "en"
                
                # 2. Seçilen dile göre metin şablonunu al.
                template = NOTIFICATION_TEMPLATES[lang_code]

                current_price = prices.get(alert.symbol)
                if current_price is None:
                    continue

                if current_price >= alert.upper_limit or current_price <= alert.lower_limit:
                    if alert.user_token and notifications_on:
                        # 3. Yön (arttı/azaldı) metnini de şablondan al.
                        is_increase = current_price >= alert.upper_limit
                        direction_text = template["increased"] if is_increase else template["decreased"]
                        
                        # 4. Başlık ve gövde metinlerini seçilen dilde formatla.
                        title = template["title"].format(symbol=alert.symbol)
                        body = template["body"].format(
                            symbol=alert.symbol,
                            percentage=alert.percentage,
                            direction=direction_text,
                            price=current_price
                        )
                        send_push_notification(token=alert.user_token, title=title, body=body)
                    
                    alerts_to_delete_ids.append(alert.id)

            if alerts_to_delete_ids:
                with Session(engine) as session:
                    delete_stmt = delete(Alert).where(Alert.id.in_(alerts_to_delete_ids))
                    session.exec(delete_stmt)
                    session.commit()
                    print(f"Deleted {len(alerts_to_delete_ids)} triggered alerts.")

        except Exception as e:
            print(f"CRITICAL ERROR in price_check_loop: {e}")
        
        print(f"Price check loop finished. Waiting for {CHECK_INTERVAL} seconds.")
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

LANGUAGE_CURRENCY_MAP = {
    'tr': 'TRY',
    'de': 'EUR',
    'fr': 'EUR',
    'es': 'EUR',
    'it': 'EUR',
    'ru': 'RUB',
    'hi': 'INR', 
    'zh': 'CNY', 
    'ja': 'JPY', 
    'ar': 'SAR',
    'en': 'USD', 
}

CURRENCY_TICKERS = {
    "TRY": "TRY=X", 
    "USD": "USD=X",
    "EUR": "EURUSD=X", 
    "RUB": "RUB=X",  
    "JPY": "JPY=X",  
    "CNY": "CNY=X",  
    "INR": "INR=X",  
    "SAR": "SAR=X",  
}
# ----------------------------
# METALS
# ----------------------------
@app.get("/metals")
def get_metals(user_uid: str): 
    with Session(engine) as session:
        user = session.get(User, user_uid)
        language_code = user.language_code if user and user.language_code else 'en'
        
    target_currency = LANGUAGE_CURRENCY_MAP.get(language_code, 'USD')

    metals = {
        "Altın": "GC=F",
        "Gümüş": "SI=F",
        "Bakır": "HG=F"
    }
    
    currency_ticker = CURRENCY_TICKERS.get(target_currency)
    usd_to_target = None

    if target_currency == "USD":
        usd_to_target = 1.0
    elif currency_ticker:
        try:
            if target_currency == "EUR":
                 exchange_rate_raw = yf.Ticker(currency_ticker).history(period="1d")['Close'].iloc[-1]
                 usd_to_target = 1.0 / exchange_rate_raw
            else:
                 usd_to_target = yf.Ticker(currency_ticker).history(period="1d")['Close'].iloc[-1]

        except Exception as e:
            print(f"Error fetching exchange rate for {target_currency}: {e}")
            usd_to_target = None
    
    if usd_to_target is None and target_currency != "USD":
        usd_to_target = 1.0
        print(f"Failed to get {target_currency} rate. Defaulting to USD.")


    result = {}
    for name, ticker_symbol in metals.items():
        try:
            price_usd = yf.Ticker(ticker_symbol).history(period="1d")['Close'].iloc[-1]
            
            if usd_to_target is not None:
                price_target = price_usd * usd_to_target
                gram_price = price_target / 31.1035
                
                result[name] = round(gram_price, 2)
            else:
                result[name] = None
        except Exception as e:
            print(f"Error fetching metal {name}: {e}")
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
    "FENER": "Fenerbahçe Futbol",
    "KARSN": "Karsan",
    "NTHOL": "Netaş",
    "SNGYO": "Sinpas GYO",
    "TAVHL": "TAV Havalimanları",
    "TKNSA": "Teknosa",
    "TRGYO": "Torunlar GYO",
    "TSPOR": "Trabzonspor",
    "TTRAK": "Tümosan Traktör",
    "VAKBN": "Vakıfbank",
    "YATAS": "Yataş",
    "ZOREN": "Zorlu Enerji",
    "AKGRT": "Ak Gıda",
    "BJKAS": "Beşiktaş Futbol",
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
    # We only use the fallback names for simplicity, not API calls
    return [{"symbol": s.split(".")[0], "name": BIST_FALLBACK_NAMES.get(s.split(".")[0], s.split(".")[0])}
            for s in BIST100_SYMBOLS]

async def get_bist_prices():
    try:
        data = yf.download(BIST100_SYMBOLS, period="1d")['Close']
    except:
        data = None

    results = []
    for symbol in BIST100_SYMBOLS:
        short_symbol = symbol.split(".")[0]
        price = None
        if data is not None:
            try:
                price = round(float(data[symbol].iloc[-1]), 2)
            except:
                price = None
        results.append({"symbol": short_symbol, "price": price})
    return results

# ----------------------------
# NASDAQ Symbols & Prices
# ----------------------------

POPULAR_NASDAQ = [
    "AAPL", "TSLA", "MSFT", "AMZN", "GOOGL", "META", "NVDA", "NFLX", "INTC", "AMD",
    "ADBE", "CSCO", "CMCSA", "PEP", "QCOM", "AVGO", "TXN", "COST", "AMGN", "SBUX",
    "ISRG", "GILD", "MDLZ", "BIIB", "ZM", "SNPS", "LRCX", "MU", "BKNG", "ADSK",
    "REGN", "VRTX", "EA", "IDXX", "MAR", "CTSH", "KLAC", "ILMN", "ADP", "ROST",
    "ASML", "DOCU", "MELI", "EXC", "ALGN", "FAST", "WDAY", "NTES", "SWKS", "KDP"
]

async def get_nasdaq_symbols_with_name(n=50):
    symbols = POPULAR_NASDAQ[:n]
    results = []

    async with httpx.AsyncClient(timeout=5) as client:
        tasks = []
        for sym in symbols:
            url = f"{FINNHUB_BASE}/stock/profile2"
            params = {"symbol": sym, "token": FINNHUB_API_KEY}
            tasks.append(client.get(url, params=params))
        responses = await asyncio.gather(*tasks, return_exceptions=True)

    for sym, r in zip(symbols, responses):
        name = sym
        try:
            if not isinstance(r, Exception) and r.status_code == 200:
                data = r.json()
                name = data.get("name") or sym
        except:
            pass
        results.append({"symbol": sym, "name": name})

    return results


async def fetch_nasdaq_prices(symbols: list[str]):
    async def fetch(symbol: str):
        url = f"{FINNHUB_BASE}/quote"
        params = {"symbol": symbol, "token": FINNHUB_API_KEY}
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                r = await client.get(url, params=params)
                if r.status_code == 200:
                    price = r.json().get("c")
                    return {"symbol": symbol, "price": round(price, 2) if price else None}
        except:
            pass
        return {"symbol": symbol, "price": None}

    tasks = [fetch(sym) for sym in symbols]
    return await asyncio.gather(*tasks)

async def get_nasdaq_prices(n=50):
    symbols_with_name = await get_nasdaq_symbols_with_name(n)
    symbols = [item["symbol"] for item in symbols_with_name]
    results = await fetch_nasdaq_prices(symbols)

    final = []
    for item, price_data in zip(symbols_with_name, results):
        final.append({
            "symbol": item["symbol"],
            "name": item["name"],
            "price": price_data["price"]
        })
    return final
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
                    price = round(float(data["price"]), 2)
                    if price > 0:
                        return {"symbol": symbol[:-1], "price": price}
            return None 
        tasks.append(fetch())
    results = await asyncio.gather(*tasks)
    return [r for r in results if r is not None]

# ----------------------------
# Combined Prices Endpoint 
# ----------------------------
@app.get("/prices")
async def get_all_prices(user_uid: Optional[str] = Query(None)): 
    
    bist_task = get_bist_prices()
    nasdaq_task = get_nasdaq_prices()
    crypto_task = get_crypto_prices()

    if user_uid is None:
        raise HTTPException(status_code=400, detail="User UID is required for price fetching.")
        
    bist, nasdaq, crypto = await asyncio.gather(bist_task, nasdaq_task, crypto_task)
    
    metals_dict = get_metals(user_uid=user_uid) 
    
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

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)