import os
import asyncio
from datetime import datetime, timedelta
import traceback
from typing import Optional, List, Dict
import json

from pydantic import BaseModel, Field as PydanticField
from fastapi import FastAPI, HTTPException, Query, Path, BackgroundTasks, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
import httpx
from sqlmodel import SQLModel, Field, create_engine, Session, select, delete
import yfinance as yf

import firebase_admin
from firebase_admin import credentials, messaging
from dotenv import load_dotenv

# ----------------------
# .env, Config ve Firebase
# ----------------------
load_dotenv()

# --- YENİ GEREKLİ ORTAM DEĞİŞKENİ ---
# Cron job'unuzun endpoint'i çağırmak için kullanacağı gizli anahtar.
# Örnek: "my_super_secret_cron_key_123"
# Bu anahtarı hem hosting platformunuza hem de cron job servisinize eklemelisiniz.
CRON_SECRET_KEY = os.getenv("CRON_SECRET_KEY")
if not CRON_SECRET_KEY:
    raise ValueError("CRON_SECRET_KEY ortam değişkeni bulunamadı! Bu, cron job güvenliği için zorunludur.")

FINNHUB_API_KEY = os.getenv("FINNHUB_API_KEY")
FINNHUB_BASE = "https://finnhub.io/api/v1"

# Firebase initialization
firebase_json_str = os.getenv("FIREBASE_JSON")
if not firebase_json_str:
    raise ValueError("FIREBASE_JSON ortam değişkeni bulunamadı!")

cred_dict = json.loads(firebase_json_str)
cred_dict["private_key"] = cred_dict["private_key"].replace("\\n", "\n").replace("\r", "")

if not firebase_admin._apps:
    cred = credentials.Certificate(cred_dict)
    firebase_admin.initialize_app(cred)

# ----------------------
# DB Yapılandırması
# ----------------------
DB_URL = os.getenv("DATABASE_URL")
if not DB_URL:
    raise RuntimeError("DATABASE_URL bulunamadı! Railway'de Postgres URL tanımlı mı kontrol et.")

if DB_URL.startswith("postgres://"):
    DB_URL = DB_URL.replace("postgres://", "postgresql://", 1)

engine = create_engine(DB_URL, echo=False)

# ----------------------
# --- YENİ CACHE MEKANİZMASI ---
# /prices endpoint'i için basit bir in-memory cache
# ----------------------
_prices_cache: Dict = {
    "base_data": {"timestamp": None, "data": None},
    "metals_data": {}  
}
_prices_cache_lock = asyncio.Lock()
CACHE_DURATION = timedelta(seconds=30) # Cache'in 30 saniye geçerli olmasını sağlar

# ----------------------
# FastAPI Uygulaması
# ----------------------
app = FastAPI(title="MarketWatcher Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ----------------------------
# DB Modelleri
# ----------------------------
class Alert(SQLModel, table=True):
    __table_args__ = {"extend_existing": True}
    id: Optional[int] = Field(default=None, primary_key=True)
    user_uid: str = Field(foreign_key="user.uid", index=True)
    market: str
    symbol: str
    percentage: float
    base_price: float
    upper_limit: float
    lower_limit: float
    created_at: datetime = Field(default_factory=datetime.utcnow)

class AlertCreate(SQLModel):
    market: str
    symbol: str
    percentage: float
    user_uid: Optional[str] = None    

class UserSettings(SQLModel):
    notifications_enabled: bool
    language_code: str = Field(default="en") 

class User(UserSettings, table=True):
    uid: str = Field(primary_key=True)
    fcm_token: Optional[str] = Field(default=None, index=True)
    plan: str = Field(default="free", index=True) # free, pro, ultra
    last_checked_at: Optional[datetime] = Field(default=None)

# ----------------------------
# DB ve tablo oluşturma
# ----------------------------
def create_db_and_tables():
    SQLModel.metadata.create_all(engine)

@app.on_event("startup")
def on_startup():
    create_db_and_tables()

class RevenueCatEvent(BaseModel):
    app_user_id: str = PydanticField(..., alias="app_user_id")
    entitlements: List[str] = PydanticField(..., alias="entitlements")

class RevenueCatWebhookPayload(BaseModel):
    event: RevenueCatEvent
    api_version: str

# Yeni ortam değişkenini kodun en üstünde diğerleri gibi okuyun
REVENUECAT_WEBHOOK_TOKEN = os.getenv("REVENUECAT_WEBHOOK_TOKEN")

@app.post("/webhooks/revenuecat")
async def handle_revenuecat_webhook(
    payload: RevenueCatWebhookPayload, 
    authorization: str = Header(None)
):
    """
    RevenueCat'ten gelen abonelik durumu değişikliklerini dinler ve
    veritabanındaki kullanıcı planını günceller.
    """
    # 1. Adım: İsteğin gerçekten RevenueCat'ten geldiğini doğrula
    if not REVENUECAT_WEBHOOK_TOKEN or authorization != f"Bearer {REVENUECAT_WEBHOOK_TOKEN}":
        print("KRİTİK GÜVENLİK UYARISI: Geçersiz RevenueCat webhook token'ı!")
        raise HTTPException(status_code=403, detail="Geçersiz Yetkilendirme")

    # 2. Adım: Gelen veriden kullanıcı ID'sini ve yetkilerini al
    user_uid = payload.event.app_user_id
    entitlements = payload.event.entitlements
    
    # 3. Adım: Yetkilere göre yeni planı belirle
    new_plan = "free" # Varsayılan olarak free
    if "ultra_access" in entitlements:
        new_plan = "ultra"
    elif "pro_access" in entitlements:
        new_plan = "pro"

    # 4. Adım: Veritabanındaki kullanıcıyı güncelle
    try:
        with Session(engine) as session:
            user = session.get(User, user_uid)
            if user:
                if user.plan != new_plan:
                    user.plan = new_plan
                    session.add(user)
                    session.commit()
                    print(f"Kullanıcı {user_uid} planı '{new_plan}' olarak güncellendi.")
                else:
                    print(f"Kullanıcı {user_uid} zaten '{new_plan}' planında. Değişiklik yapılmadı.")
            else:
                print(f"Webhook uyarısı: {user_uid} ID'li kullanıcı veritabanında bulunamadı.")
                # İsteğe bağlı: Bu durumda yeni bir kullanıcı da oluşturabilirsiniz.
                # Şimdilik sadece logluyoruz.
    
    except Exception as e:
        print(f"RevenueCat webhook işlenirken veritabanı hatası: {e}")
        # Hata durumunda RevenueCat'e başarısız olduğumuzu bildirmeyelim ki
        # webhook'u tekrar göndermeye çalışsın. Bu yüzden 500 hatası fırlatıyoruz.
        raise HTTPException(status_code=500, detail="Veritabanı güncelleme hatası.")

    # 5. Adım: RevenueCat'e her şeyin yolunda olduğunu bildir
    return {"status": "ok"}
# ----------------------------
# --- YENİ CRON JOB ENDPOINT'i ve MANTIĞI ---
# ----------------------------
# --- run_price_checks fonksiyonunu bu yeni versiyonla değiştirin ---

# Bu yardımcı fonksiyon, kodu daha temiz tutmak için
async def check_alerts_for_user(user: User, session: Session, prices: Dict):
    user_alerts = session.exec(select(Alert).where(Alert.user_uid == user.uid)).all()
    if not user_alerts:
        return []

    alerts_to_delete_ids = []
    for alert in user_alerts:
        # Dil ve bildirim şablonu ayarları
        lang_code = user.language_code if user.language_code in NOTIFICATION_TEMPLATES else "en"
        template = NOTIFICATION_TEMPLATES[lang_code]
        localized_symbol = METAL_LOCALIZATION_MAP.get(alert.symbol, {}).get(lang_code, alert.symbol)
        
        current_price = prices.get(alert.symbol)
        if current_price is None:
            continue

        if current_price >= alert.upper_limit or current_price <= alert.lower_limit:
            if user.notifications_enabled and user.fcm_token:
                is_increase = current_price >= alert.upper_limit
                direction_text = template["increased"] if is_increase else template["decreased"]
                
                title = template["title"].format(symbol=localized_symbol)
                body = template["body"].format(
                    symbol=localized_symbol,
                    percentage=alert.percentage,
                    direction=direction_text,
                    price=current_price
                )
                send_push_notification(token=user.fcm_token, title=title, body=body)
            
            alerts_to_delete_ids.append(alert.id)
    return alerts_to_delete_ids

async def run_price_checks():
    print("Arka plan fiyat kontrolü başladı...")
    now = datetime.utcnow()
    try:
        with Session(engine) as session:
            all_users = session.exec(select(User)).all()
            if not all_users:
                print("Kontrol edilecek kullanıcı bulunamadı.")
                return

            # Kontrol zamanı gelen kullanıcıları ve onların alarmlarını topla
            users_to_check = []
            symbols_to_fetch = set()

            for user in all_users:
                plan = user.plan
                last_checked = user.last_checked_at or datetime.min
                
                should_check = False
                if plan == 'ultra':
                    should_check = True # Her dakika kontrol
                elif plan == 'pro' and (now - last_checked) >= timedelta(minutes=3):
                    should_check = True
                elif plan == 'free' and (now - last_checked) >= timedelta(minutes=10):
                    should_check = True

                if should_check:
                    users_to_check.append(user)
                    user_alerts = session.exec(select(Alert.symbol).where(Alert.user_uid == user.uid)).all()
                    for symbol in user_alerts:
                        symbols_to_fetch.add(symbol)

            if not users_to_check:
                print("Kontrol zamanı gelen kullanıcı yok. Görev sonlandırıldı.")
                return

            # Gerekli tüm sembollerin fiyatlarını tek seferde çek
            prices = {}
            if symbols_to_fetch:
                price_tasks = [fetch_price(symbol) for symbol in symbols_to_fetch]
                price_results = await asyncio.gather(*price_tasks)
                for symbol, price in zip(symbols_to_fetch, price_results):
                    if price is not None:
                        prices[symbol] = price
            
            # Her uygun kullanıcı için alarmları kontrol et
            total_deleted_alerts = []
            for user in users_to_check:
                deleted_ids = await check_alerts_for_user(user, session, prices)
                total_deleted_alerts.extend(deleted_ids)
                user.last_checked_at = now # Son kontrol zamanını güncelle
                session.add(user)

            # Tetiklenen tüm alarmları sil ve kullanıcıları güncelle
            if total_deleted_alerts:
                delete_stmt = delete(Alert).where(Alert.id.in_(total_deleted_alerts))
                session.exec(delete_stmt)
            
            session.commit()
            if total_deleted_alerts:
                print(f"{len(total_deleted_alerts)} adet tetiklenen alarm silindi.")
            print(f"{len(users_to_check)} kullanıcının alarmları kontrol edildi.")

    except Exception as e:
        print(f"KRİTİK HATA (run_price_checks): {e}")
        traceback.print_exc()
    
    print("Arka plan fiyat kontrolü tamamlandı.")

def verify_cron_secret(secret: str = Query(...)):
    """Dependency to verify the cron job secret key."""
    if secret != CRON_SECRET_KEY:
        raise HTTPException(status_code=403, detail="Geçersiz veya eksik gizli anahtar.")
    return True

@app.post("/run-checks", status_code=202)
async def trigger_price_checks(
    background_tasks: BackgroundTasks, 
    is_secret_valid: bool = Depends(verify_cron_secret)
):
    """
    Bu endpoint, bir cron job tarafından çağrılmak üzere tasarlanmıştır.
    Fiyat kontrol işlemini arka planda başlatır ve hemen yanıt döner.
    """
    background_tasks.add_task(run_price_checks)
    return {"message": "Fiyat kontrol görevi arka planda başlatıldı."}

# ----------------------------
# CRUD for Alerts and Settings
# ----------------------------
@app.post("/user/register_token", status_code=200)
def register_token(user_uid: str = Query(...), token: str = Query(...)):
    """Kullanıcının FCM cihaz token'ını veritabanına kaydeder veya günceller."""
    with Session(engine) as session:
        user = session.get(User, user_uid)
        if not user:
            # Kullanıcı yoksa, yeni bir kullanıcı oluştur ve token'ı ata.
            user = User(uid=user_uid, fcm_token=token, notifications_enabled=True, language_code='en')
        else:
            # Kullanıcı varsa, sadece token'ını güncelle.
            user.fcm_token = token
        session.add(user)
        session.commit()
    return {"status": "token registered successfully"}

@app.post("/alerts", response_model=Alert)
async def create_alert(alert_in: AlertCreate):
    try:
        current_price_raw = await fetch_price(alert_in.symbol)
        if current_price_raw is None:
            raise HTTPException(status_code=400, detail=f"Price not found for symbol: {alert_in.symbol}")

        current_price = float(current_price_raw)
        perc = float(alert_in.percentage)

        alert = Alert(
            market=alert_in.market,
            symbol=alert_in.symbol.upper(),
            percentage=perc,
            base_price=current_price,
            upper_limit=current_price * (1 + perc / 100),
            lower_limit=current_price * (1 - perc / 100),
            user_uid=alert_in.user_uid
        )

        with Session(engine) as session:
            session.add(alert)
            session.commit()
            session.refresh(alert)
        return alert
    except Exception as e:
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
            alert.user_uid = alert_in.user_uid

            current_price_raw = await fetch_price(alert.symbol)
            if current_price_raw is not None:
                current_price = float(current_price_raw)
                alert.base_price = current_price
                alert.upper_limit = current_price * (1 + alert.percentage / 100)
                alert.lower_limit = current_price * (1 - alert.percentage / 100)

            session.add(alert)
            session.commit()
            session.refresh(alert)
            return alert
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))
    
@app.get("/user/settings/{user_uid}", response_model=UserSettings)
def get_user_settings(user_uid: str):
    with Session(engine) as session:
        user = session.get(User, user_uid)
        if not user:
            # If user has no settings saved yet, return default values
            return UserSettings(notifications_enabled=True, language_code="en")
        return UserSettings(notifications_enabled=user.notifications_enabled, language_code=user.language_code)

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
            
            data={
                "title": title,
                "body": body,
                "click_action": "FLUTTER_NOTIFICATION_CLICK", 
            },
            
            android=messaging.AndroidConfig(
                priority="high",
            ),
            
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(
                        content_available=True,
                    )
                )
            ),
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
            usdtry_ticker = await loop.run_in_executor(None, lambda: yf.Ticker("TRY=X"))
            usdtry = usdtry_ticker.history(period="1d")['Close'].iloc[-1]
            
            metal_ticker = await loop.run_in_executor(None, lambda: yf.Ticker(metals_yf[symbol]))
            price_usd = metal_ticker.history(period="1d")['Close'].iloc[-1]
            
            return round((price_usd * usdtry) / 31.1035, 2)
        except Exception as e:
            print(f"Error fetching metal {symbol} with yfinance: {e}")
            return None
        
    if symbol.endswith(".IS") or symbol in BIST_FALLBACK_NAMES:
        try:
            yf_symbol = symbol if symbol.endswith(".IS") else f"{symbol}.IS"
            loop = asyncio.get_event_loop()
            ticker_obj = await loop.run_in_executor(None, lambda: yf.Ticker(yf_symbol))
            price = ticker_obj.history(period="1d")['Close'].iloc[-1]
            return round(float(price), 2)
        except Exception as e:
            print(f"Error fetching BIST {symbol} with yfinance: {e}")
            return None

    async with httpx.AsyncClient(timeout=10) as client:
        if symbol in POPULAR_NASDAQ:
            try:
                r = await client.get(f"{FINNHUB_BASE}/quote", params={"symbol": symbol, "token": FINNHUB_API_KEY})
                r.raise_for_status()
                price = r.json().get("c")
                if price:
                    return round(float(price), 2)
            except Exception as e:
                print(f"Error fetching NASDAQ {symbol} from Finnhub: {e}")
                return None

        if symbol.endswith("USDT"):
            try:
                r = await client.get("https://api.binance.com/api/v3/ticker/price", params={"symbol": symbol})
                r.raise_for_status()
                price = float(r.json().get("price", 0))
                if price > 0:
                    return round(price, 2)
            except Exception as e:
                print(f"Error fetching Crypto {symbol} from Binance: {e}")
                return None
        return None
# ----------------------------
# --- YENİ ÇEVİRİ SÖZLÜĞÜ (Metal İsimleri) ---
# ALTIN, GÜMÜŞ, BAKIR sembollerinin farklı dillerdeki karşılıkları.
METAL_LOCALIZATION_MAP = {
    "ALTIN": {
        "tr": "Altın", "en": "Gold", "de": "Gold", "fr": "Or", "es": "Oro",
        "it": "Oro", "ru": "Золото", "zh": "黄金", "hi": "सोना", "ja": "金",
        "ar": "الذهب"
    },
    "GÜMÜŞ": {
        "tr": "Gümüş", "en": "Silver", "de": "Silber", "fr": "Argent", "es": "Plata",
        "it": "Argento", "ru": "Серебро", "zh": "白银", "hi": "चांदी", "ja": "銀",
        "ar": "الفضة"
    },
    "BAKIR": {
        "tr": "Bakır", "en": "Copper", "de": "Kupfer", "fr": "Cuivre", "es": "Cobre",
        "it": "Rame", "ru": "Медь", "zh": "铜", "hi": "तांबा", "ja": "銅",
        "ar": "النحاس"
    }
}
# ----------------------------
# --- YENİ ÇEVİRİ SÖZLÜĞÜ (Şablonlar) ---
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
async def get_metals(user_uid: str) -> Dict[str, Optional[float]]:
    try:
        with Session(engine) as session:
            user = session.get(User, user_uid)
            language_code = user.language_code if user and user.language_code else 'en'

        target_currency = LANGUAGE_CURRENCY_MAP.get(language_code, 'USD')

        metal_tickers = {"ALTIN": "GC=F", "GÜMÜŞ": "SI=F", "BAKIR": "HG=F"}
        required_tickers = list(metal_tickers.values())
        
        usd_to_target_rate = 1.0 # Default to USD

        if target_currency != "USD":
            currency_yf_ticker = CURRENCY_TICKERS.get(target_currency)
            if currency_yf_ticker:
                required_tickers.append(currency_yf_ticker)
        
        loop = asyncio.get_event_loop()
        data = await loop.run_in_executor(None, 
            lambda: yf.download(required_tickers, period="1d", progress=False, auto_adjust=True)['Close']
        )

        if data is None or data.empty:
            raise ValueError("yfinance'dan veri alınamadı.")

        # Döviz kurunu al
        if target_currency != "USD" and currency_yf_ticker in data:
            rate = data[currency_yf_ticker].iloc[-1]
            if target_currency == "EUR": # EURUSD=X kuru EUR/USD'dir, bize USD/EUR lazım
                usd_to_target_rate = 1.0 / rate if rate != 0 else 0
            else: # Diğerleri (TRY=X vb.) zaten USD/CURRENCY şeklindedir
                usd_to_target_rate = rate
        
        result = {}
        for name, ticker in metal_tickers.items():
            if ticker in data and not data[ticker].dropna().empty:
                price_usd_ounce = data[ticker].iloc[-1]
                price_target_ounce = price_usd_ounce * usd_to_target_rate
                price_target_gram = price_target_ounce / 31.1035
                result[name] = round(price_target_gram, 2)
            else:
                result[name] = None
        
        return result

    except Exception as e:
        print(f"KRİTİK HATA (get_metals): {e}")
        traceback.print_exc()
        return {"Altın": None, "Gümüş": None, "Bakır": None}

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
    return [{"symbol": s.split(".")[0], "name": BIST_FALLBACK_NAMES.get(s.split(".")[0], s.split(".")[0])}
            for s in BIST100_SYMBOLS]

async def get_bist_prices():
    try:
        data = yf.download(BIST100_SYMBOLS, period="1d", progress=False, auto_adjust=True)['Close']
    except Exception as e:
        print(f"Error downloading BIST data: {e}")
        data = None

    results = []
    for symbol in BIST100_SYMBOLS:
        short_symbol = symbol.split(".")[0]
        price = None
        if data is not None and not data.empty:
            try:
                price_series = data[symbol]
                if not price_series.dropna().empty:
                    price = round(float(price_series.dropna().iloc[-1]), 2)
            except (KeyError, IndexError):
                price = None
        results.append({"symbol": short_symbol, "price": price})
    return results

POPULAR_NASDAQ = [
    "AAPL", "TSLA", "MSFT", "AMZN", "GOOGL", "META", "NVDA", "NFLX", "INTC", "AMD", "ADBE", "CSCO", "CMCSA", "PEP",
    "QCOM", "AVGO", "TXN", "COST", "AMGN", "SBUX", "ISRG", "GILD", "MDLZ", "BIIB", "ZM", "SNPS", "LRCX", "MU",
    "BKNG", "ADSK", "REGN", "VRTX", "EA", "IDXX", "MAR", "CTSH", "KLAC", "ILMN", "ADP", "ROST", "ASML", "DOCU",
    "MELI", "EXC", "ALGN", "FAST", "WDAY", "NTES", "SWKS", "KDP"
]

async def get_nasdaq_symbols_with_name(n=50):
    symbols = POPULAR_NASDAQ[:n]
    results = []
    async with httpx.AsyncClient(timeout=10) as client:
        tasks = [client.get(f"{FINNHUB_BASE}/stock/profile2", params={"symbol": sym, "token": FINNHUB_API_KEY}) for sym in symbols]
        responses = await asyncio.gather(*tasks, return_exceptions=True)

    for sym, r in zip(symbols, responses):
        name = sym
        if not isinstance(r, Exception) and r.status_code == 200:
            data = r.json()
            name = data.get("name") or sym
        results.append({"symbol": sym, "name": name})
    return results

async def get_nasdaq_prices(n=50):
    symbols = POPULAR_NASDAQ[:n]
    async with httpx.AsyncClient(timeout=10) as client:
        tasks = [client.get(f"{FINNHUB_BASE}/quote", params={"symbol": sym, "token": FINNHUB_API_KEY}) for sym in symbols]
        responses = await asyncio.gather(*tasks, return_exceptions=True)
    
    results = []
    for sym, r in zip(symbols, responses):
        price = None
        if not isinstance(r, Exception) and r.status_code == 200:
            price_val = r.json().get("c")
            if price_val:
                price = round(price_val, 2)
        results.append({"symbol": sym, "price": price})
    return results

async def get_top_crypto_symbols(n=50):
    url = "https://api.binance.com/api/v3/ticker/price"
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            r = await client.get(url)
            r.raise_for_status()
            data = r.json()
            symbols = [d["symbol"] for d in data if d["symbol"].endswith("USDT")]
            return symbols[:n]
    except Exception as e:
        print(f"Error fetching crypto symbols: {e}")
        return []

async def get_crypto_prices(n=50):
    symbols = await get_top_crypto_symbols(n)
    async with httpx.AsyncClient(timeout=10) as client:
        tasks = [client.get("https://api.binance.com/api/v3/ticker/price", params={"symbol": s}) for s in symbols]
        responses = await asyncio.gather(*tasks, return_exceptions=True)
    
    results = []
    for sym, r in zip(symbols, responses):
        if not isinstance(r, Exception) and r.status_code == 200:
            data = r.json()
            price = round(float(data["price"]), 2)
            if price > 0:
                results.append({"symbol": sym[:-4], "price": price}) # USDT son ekini kaldır
    return results

@app.get("/prices")
async def get_all_prices(user_uid: Optional[str] = Query(None)):
    global _prices_cache
    
    if user_uid is None:
        raise HTTPException(status_code=400, detail="Fiyatları çekmek için Kullanıcı ID'si gereklidir.")

    try:
        with Session(engine) as session:
            user = session.get(User, user_uid)
            language_code = user.language_code if user and user.language_code else 'en'
        target_currency = LANGUAGE_CURRENCY_MAP.get(language_code, 'USD')
    except Exception as e:
        print(f"Kullanıcı ayarları alınırken hata: {e}")
        target_currency = 'USD'

    async with _prices_cache_lock:
        base_data_to_fetch = False
        metals_data_to_fetch = False
        
        # 1. Sabit veriler (BIST, NASDAQ, CRYPTO) için ana cache'i kontrol et
        base_cache = _prices_cache["base_data"]
        if not base_cache.get("timestamp") or (datetime.utcnow() - base_cache["timestamp"]) >= CACHE_DURATION:
            print("Ana cache (BIST, NASDAQ, CRYPTO) süresi geçmiş. API'ler çağrılacak.")
            base_data_to_fetch = True
        else:
            print("Ana cache (BIST, NASDAQ, CRYPTO) kullanılıyor.")
            bist, nasdaq, crypto = base_cache["data"]

        # 2. Metaller için para birimine özel cache'i kontrol et
        metals_cache = _prices_cache["metals_data"].get(target_currency, {})
        if not metals_cache.get("timestamp") or (datetime.utcnow() - metals_cache["timestamp"]) >= CACHE_DURATION:
            print(f"Metaller için '{target_currency}' cache'i süresi geçmiş. Hesaplama yapılacak.")
            metals_data_to_fetch = True
        else:
            print(f"Metaller için '{target_currency}' cache'i kullanılıyor.")
            metals = metals_cache["data"]

        # 3. Sadece cache'de olmayan verileri API'lerden çek
        tasks_to_run = []
        if base_data_to_fetch:
            tasks_to_run.extend([get_bist_prices(), get_nasdaq_prices(), get_crypto_prices()])
        if metals_data_to_fetch:
            tasks_to_run.append(get_metals(user_uid=user_uid))

        if tasks_to_run:
            results = await asyncio.gather(*tasks_to_run)
            
            result_index = 0
            if base_data_to_fetch:
                bist, nasdaq, crypto = results[result_index:result_index+3]
                result_index += 3
                # Ana cache'i güncelle
                _prices_cache["base_data"] = {
                    "data": (bist, nasdaq, crypto),
                    "timestamp": datetime.utcnow()
                }

            if metals_data_to_fetch:
                metals_dict = results[result_index]
                metals = [{"market": "METALS", "symbol": k, "price": v} for k, v in metals_dict.items()]
                # Para birimine özel metal cache'ini güncelle
                _prices_cache["metals_data"][target_currency] = {
                    "data": metals,
                    "timestamp": datetime.utcnow()
                }
        
        # Sonuçları formatla ve birleştir
        bist_formatted = [{"market": "BIST", **item} for item in bist]
        nasdaq_formatted = [{"market": "NASDAQ", **item} for item in nasdaq]
        crypto_formatted = [{"market": "CRYPTO", **item} for item in crypto]
        
        all_data = bist_formatted + nasdaq_formatted + crypto_formatted + metals
        
        return all_data
    
@app.get("/symbols_with_name")
async def symbols_with_name(market: str, n: int = 50):
    market = market.upper()
    if market == "BIST":
        return await get_bist_symbols_with_name()
    elif market == "NASDAQ":
        return await get_nasdaq_symbols_with_name(n)
    elif market == "CRYPTO":
        symbols = await get_top_crypto_symbols(n)
        return [{"symbol": s[:-4], "name": s[:-4]} for s in symbols]
    elif market == "METALS":
        return [{"symbol": name, "name": name} for name in ["Altın", "Gümüş", "Bakır"]]
    raise HTTPException(status_code=400, detail="Invalid market specified")